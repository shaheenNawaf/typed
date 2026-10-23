import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/budget.dart';
import '../models/note.dart';
import 'markdown_display.dart';
import 'streak.dart';

const _pendingActionKey = 'pending_intent';

class ReminderSettings {
  final bool eveningEnabled;
  final bool streakEnabled;
  final bool budgetEnabled;
  final int eveningHour;
  final int eveningMinute;
  final int streakHour;
  final int streakMinute;

  const ReminderSettings({
    this.eveningEnabled = false,
    this.streakEnabled = false,
    this.budgetEnabled = false,
    this.eveningHour = 19,
    this.eveningMinute = 0,
    this.streakHour = 20,
    this.streakMinute = 30,
  });

  ReminderSettings copyWith({
    bool? eveningEnabled,
    bool? streakEnabled,
    bool? budgetEnabled,
    int? eveningHour,
    int? eveningMinute,
    int? streakHour,
    int? streakMinute,
  }) {
    return ReminderSettings(
      eveningEnabled: eveningEnabled ?? this.eveningEnabled,
      streakEnabled: streakEnabled ?? this.streakEnabled,
      budgetEnabled: budgetEnabled ?? this.budgetEnabled,
      eveningHour: eveningHour ?? this.eveningHour,
      eveningMinute: eveningMinute ?? this.eveningMinute,
      streakHour: streakHour ?? this.streakHour,
      streakMinute: streakMinute ?? this.streakMinute,
    );
  }
}

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();
  static const _eveningId = 4101;
  static const _streakId = 4102;
  static const _budgetBaseId = 4200;

  /// One-off reminders for dated voice-memo tasks: ids 5000..904999, one
  /// record each in prefs so they can be cancelled when the task goes.
  static const _taskBaseId = 5000;
  static const _taskKey = 'task_reminders_v1';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  DateTime? _lastBudgetAlertCheck;

  static Future<void> initialize() => instance._initialize();

  Future<void> _initialize() async {
    if (_initialized || kIsWeb) return;
    try {
      tz.initializeTimeZones();
      try {
        final zone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(zone));
      } catch (_) {
        // An unmapped or unavailable zone id must not disable reminders:
        // fall back to UTC so scheduling keeps working (times shift, they
        // do not silently stop).
        try {
          tz.setLocalLocation(tz.getLocation('UTC'));
        } catch (_) {
          rethrow;
        }
      }
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      // Desktop platforms: the plugin throws ArgumentError when the running
      // platform's settings are null, and the catch below would silently
      // disable every reminder. macOS defers its permission prompt to
      // requestPermission() (fired by the settings toggle); Windows
      // self-registers its AUMID + activation GUID in HKCU on initialize.
      const macOS = DarwinInitializationSettings(requestAlertPermission: false);
      const linux = LinuxInitializationSettings(
        defaultActionName: 'Open Typed',
      );
      const windows = WindowsInitializationSettings(
        appName: 'Typed',
        appUserModelId: 'com.z4yed.typed',
        guid: '3f7c2a1e-8d4b-4f6a-9c2e-1a5b7d3e9f04',
      );
      await _plugin.initialize(
        const InitializationSettings(
          android: android,
          iOS: ios,
          macOS: macOS,
          linux: linux,
          windows: windows,
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        await _storePendingAction(response);
      }
      _initialized = true;
    } catch (_) {
      // Notifications are optional and must never prevent the editor loading.
    }
  }

  Future<bool> requestPermission() async {
    await _initialize();
    if (kIsWeb) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              sound: true,
              badge: true,
            ) ??
            false;
      }
      final macos = _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
          >();
      if (macos != null) {
        return await macos.requestPermissions(
              alert: true,
              sound: true,
              badge: true,
            ) ??
            false;
      }
      // Windows and Linux need no runtime permission.
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<ReminderSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return ReminderSettings(
      eveningEnabled: prefs.getBool('reminder_evening_enabled') ?? false,
      streakEnabled: prefs.getBool('reminder_streak_enabled') ?? false,
      budgetEnabled: prefs.getBool('reminder_budget_enabled') ?? false,
      eveningHour: prefs.getInt('reminder_evening_hour') ?? 19,
      eveningMinute: prefs.getInt('reminder_evening_minute') ?? 0,
      streakHour: prefs.getInt('reminder_streak_hour') ?? 20,
      streakMinute: prefs.getInt('reminder_streak_minute') ?? 30,
    );
  }

  Future<void> saveSettings(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('reminder_evening_enabled', settings.eveningEnabled),
      prefs.setBool('reminder_streak_enabled', settings.streakEnabled),
      prefs.setBool('reminder_budget_enabled', settings.budgetEnabled),
      prefs.setInt('reminder_evening_hour', settings.eveningHour),
      prefs.setInt('reminder_evening_minute', settings.eveningMinute),
      prefs.setInt('reminder_streak_hour', settings.streakHour),
      prefs.setInt('reminder_streak_minute', settings.streakMinute),
    ]);
  }

  /// Reminds about [line] (a checklist line in note [noteId]) at [at].
  /// Returns false when it could not be scheduled (past time, no
  /// permission, unsupported platform).
  Future<bool> scheduleTaskReminder({
    required String noteId,
    required String noteTitle,
    required String line,
    required DateTime at,
  }) async {
    await _initialize();
    if (!_initialized || !at.isAfter(DateTime.now())) return false;
    if (defaultTargetPlatform == TargetPlatform.linux) return false;
    await requestPermission();
    final id = _taskId(noteId, line);
    // "Call the dentist — Tue, Oct 20, 3 PM" → "Call the dentist".
    final task = line.split(' — ').first.trim();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final exact = await android?.canScheduleExactNotifications() ?? false;
      await _plugin.zonedSchedule(
        id,
        task,
        noteTitle.isEmpty ? 'Reminder' : 'From $noteTitle',
        tz.TZDateTime.from(at, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'typed_task_reminders',
            'Task reminders',
            channelDescription: 'Reminders for tasks with a time',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
        // Exact when the user allows it (Settings → Alarms & reminders);
        // otherwise Android's slightly flexible timing.
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'open:$noteId',
      );
    } catch (_) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final all = _loadTaskReminders(prefs)
      ..removeWhere((r) => r['id'] == id)
      ..add({'id': id, 'noteId': noteId, 'line': line, 'at': at.toIso8601String()});
    await prefs.setString(_taskKey, jsonEncode(all));
    return true;
  }

  static int _taskId(String noteId, String line) =>
      _taskBaseId + ('$noteId|$line'.hashCode & 0x7fffffff) % 900000;

  List<Map<String, dynamic>> _loadTaskReminders(SharedPreferences prefs) {
    try {
      return (jsonDecode(prefs.getString(_taskKey) ?? '[]') as List)
          .cast<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Cancels reminders whose task was ticked, edited away, deleted, or
  /// whose note is gone; forgets ones already past.
  Future<void> _reconcileTaskReminders(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final all = _loadTaskReminders(prefs);
    if (all.isEmpty) return;
    final now = DateTime.now();
    final keep = <Map<String, dynamic>>[];
    for (final r in all) {
      final note = notes.where((n) => n.id == r['noteId']).firstOrNull;
      final open = note != null &&
          !note.isDeleted &&
          !note.isArchived &&
          note.content.split('\n').any((l) => l.trim() == '- [ ] ${r['line']}');
      final at = DateTime.tryParse(r['at'] as String? ?? '');
      if (!open) {
        try {
          await _plugin.cancel(r['id'] as int);
        } catch (_) {}
      } else if (at != null && at.isAfter(now)) {
        keep.add(r);
      }
    }
    await prefs.setString(_taskKey, jsonEncode(keep));
  }

  Future<void> sync({
    required List<Note> notes,
    required List<Budget> budgets,
    bool checkBudgets = false,
  }) async {
    await _initialize();
    if (!_initialized) return;
    try {
      await _reconcileTaskReminders(notes);
    } catch (_) {}
    final settings = await loadSettings();
    try {
      await _plugin.cancel(_eveningId);
      await _plugin.cancel(_streakId);
      // Linux has no zonedSchedule in the plugin (UnimplementedError); without
      // this guard the throw would kill the whole sync, budget alerts included.
      final supportsScheduling =
          defaultTargetPlatform != TargetPlatform.linux;
      if (settings.eveningEnabled && supportsScheduling) {
        await _scheduleDaily(
          id: _eveningId,
          hour: settings.eveningHour,
          minute: settings.eveningMinute,
          title: 'Your Typed recap',
          body: _recap(notes),
          payload: 'finance',
        );
      }
      final streak = computeWritingStreak(notes);
      if (settings.streakEnabled && !streak.writtenToday && supportsScheduling) {
        await _scheduleDaily(
          id: _streakId,
          hour: settings.streakHour,
          minute: settings.streakMinute,
          title: streak.days > 0
              ? 'Keep your ${streak.days}-day streak'
              : 'Make time to write',
          body: streak.days > 0
              ? 'Write for five minutes to keep it going.'
              : 'Open Typed and capture one thought today.',
          payload: 'new',
        );
      }
      if (settings.budgetEnabled) {
        // Alerts used to run inside every save, popping "over budget"
        // notifications while the user was still mid-entry. Throttle to one
        // check per ten minutes unless a budget itself changed.
        final now = DateTime.now();
        final stale = _lastBudgetAlertCheck == null ||
            now.difference(_lastBudgetAlertCheck!) >
                const Duration(minutes: 10);
        if (checkBudgets || stale) {
          _lastBudgetAlertCheck = now;
          await _showBudgetAlerts(notes, budgets);
        }
      }
    } catch (_) {
      // A device may revoke scheduling permission or restrict exact alarms.
    }
  }

  Future<void> _scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    required String payload,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    // Windows ignores matchDateTimeComponents (no repeating notifications):
    // the daily re-arm happens because sync() runs at every launch and save.
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'typed_reminders',
        'Typed reminders',
        channelDescription: 'Helpful reminders from Typed',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  String _recap(List<Note> notes) {
    final today = DateTime.now();
    bool sameDay(DateTime date) =>
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final active = notes.where((note) => !note.isArchived && !note.isDeleted);
    final written = active.where((note) => sameDay(note.updatedAt)).length;
    final tasks = openTaskCount(active);
    var expenses = 0;
    for (final note in active) {
      expenses += note.amounts
          .where(
            (entry) =>
                !entry.isDemo &&
                (entry.type ?? note.type) == 'expense' &&
                sameDay(entry.date),
          )
          .length;
    }
    return '$written note${written == 1 ? '' : 's'} written · '
        '$tasks task${tasks == 1 ? '' : 's'} left · '
        '$expenses expense${expenses == 1 ? '' : 's'} logged';
  }

  Future<void> _showBudgetAlerts(List<Note> notes, List<Budget> budgets) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final spent = <String, int>{};
    for (final note in notes.where(
      (note) => !note.isArchived && !note.isDeleted,
    )) {
      for (final entry in note.amounts) {
        if (entry.isDemo) continue;
        if ((entry.type ?? note.type) != 'expense' ||
            entry.date.isBefore(monthStart) ||
            !entry.date.isBefore(nextMonth)) {
          continue;
        }
        // Same fallback chain the dashboard uses, otherwise a null-currency
        // entry never reaches its budget's alert.
        final key = '${entry.currency ?? note.currency ?? 'PHP'}:${entry.category}';
        spent[key] = (spent[key] ?? 0) + entry.amount;
      }
    }
    for (final budget in budgets.where(
      (budget) =>
          !budget.isDemo && budget.period == 'month' && budget.limit > 0,
    )) {
      final value = spent['${budget.currency}:${budget.category}'] ?? 0;
      final ratio = value / budget.limit;
      if (ratio < .8) continue;
      final level = ratio >= 1 ? 'over' : 'near';
      final key = 'budget_alert_${budget.id}_${now.year}_${now.month}_$level';
      if (prefs.getBool(key) == true) {
        continue;
      }
      await _plugin.show(
        // 31-bit mask keeps ids positive and collision-light without the
        // earlier `% 1000` window where different budgets clobbered
        // each other's alerts.
        _budgetBaseId + (budget.id.hashCode & 0x3FFFFFFF),
        ratio >= 1 ? 'Budget exceeded' : 'Budget is nearly full',
        '${budget.category}: ${ratio >= 1 ? 'over your limit' : '80% of your limit used'}',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'typed_budget',
            'Budget alerts',
            channelDescription: 'Alerts when a budget is nearly used',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
        payload: 'finance',
      );
      await prefs.setBool(key, true);
    }
  }

  static Future<String?> consumePendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    final action = prefs.getString(_pendingActionKey);
    if (action != null) await prefs.remove(_pendingActionKey);
    return action;
  }

  static Future<void> _onResponse(NotificationResponse response) async {
    final payload = response.payload;
    if (payload != null) await _storePendingAction(payload);
  }

  static Future<void> _storePendingAction(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingActionKey, action);
  }
}
