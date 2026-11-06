import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/voice/when_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.z4yed.typed/widget'),
    (call) async => null,
  );

  String label(int addDays, {int? hour}) {
    final n = DateTime.now();
    return SpokenWhen(DateTime(n.year, n.month, n.day + addDays), hour: hour)
        .label;
  }

  test('the Today widget gets absolute dates, tomorrow included', () async {
    SharedPreferences.setMockInitialValues({
      'cutoff_budget_v1': '{"amount":1000000,"currency":"PHP"}',
    });
    final now = DateTime.now();
    await NoteStorage().save([
      Note(
        id: 'l',
        title: 'Errands',
        content: '- [ ] Pay **Meralco** — ${label(-1)}\n'
            '- [ ] Call — ${label(0, hour: 14)}\n'
            '- [ ] Slides — ${label(1)}\n'
            '- [ ] Far — ${label(9)}\n'
            '- [ ] Buy eggs\n'
            '- [x] Done — ${label(0)}\n',
        tags: const ['todo'],
        type: 'todo',
      ),
      Note(
        id: 'f',
        title: 'Money',
        content: '',
        tags: const [],
        type: 'expense',
        currency: 'PHP',
        amounts: [
          MoneyEntry(
            id: 'e',
            amount: 25000,
            category: 'Food',
            date: now,
            type: 'expense',
          ),
        ],
      ),
    ]);
    final prefs = await SharedPreferences.getInstance();
    final items = (jsonDecode(prefs.getString('widget_today_items_v1')!) as List)
        .cast<Map<String, dynamic>>();
    expect(items.map((i) => i['title']), ['Pay Meralco', 'Call', 'Slides', 'Buy eggs']);
    final today = localEpochDay(now);
    expect(items.map((i) => i['day']), [today - 1, today, today + 1, -1]);
    expect(items[1]['hour'], 14);
    // Ticking matches the stored line, markdown stripped.
    expect(items[0]['text'], 'Pay Meralco — ${label(-1)}');

    final money =
        jsonDecode(prefs.getString('widget_today_money_v1')!) as Map<String, dynamic>;
    expect(money['symbol'], '₱');
    expect(money['budget'], 1000000);
    expect(money['spent'], 25000);
    expect(money['next'], greaterThan(today));
  });

  test('no money and no budget: no money row', () async {
    SharedPreferences.setMockInitialValues({});
    await NoteStorage().save([
      Note(id: 'n', title: 'Plain', content: 'words', tags: const []),
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('widget_today_money_v1'), '{}');
    expect(prefs.getString('widget_today_items_v1'), '[]');
  });
}
