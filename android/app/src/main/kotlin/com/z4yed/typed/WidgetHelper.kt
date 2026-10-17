package com.z4yed.typed

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar
import java.util.TimeZone

object WidgetHelper {
    const val ACTION_NEW = "com.z4yed.typed.ACTION_NEW"
    const val ACTION_EXPENSE = "com.z4yed.typed.ACTION_EXPENSE"
    const val ACTION_INCOME = "com.z4yed.typed.ACTION_INCOME"
    const val ACTION_FINANCE = "com.z4yed.typed.ACTION_FINANCE"
    const val ACTION_TOGGLE = "com.z4yed.typed.ACTION_TOGGLE"
    const val ACTION_DAY_ROLLOVER = "com.z4yed.typed.ACTION_DAY_ROLLOVER"

    /**
     * Collection rows cannot carry their own PendingIntent (setOnClickPendingIntent
     * is ignored for children of a RemoteViews ListView), so every tap inside a
     * collection resolves through one template intent whose action is fixed at
     * creation time. Rows specialize themselves with a fill-in extra ([EXTRA_VERB])
     * instead — a fill-in intent can add extras but cannot override the template's
     * action, which is why the verb lives in an extra and not in the action.
     */
    const val ACTION_WIDGET_DISPATCH = "com.z4yed.typed.ACTION_WIDGET_DISPATCH"
    const val VERB_OPEN = "open"
    const val VERB_TOGGLE = "toggle"
    const val EXTRA_VERB = "verb"
    const val EXTRA_NOTE_ID = "noteId"
    const val EXTRA_TODO_TEXT = "todoText"

    /// The item's done state at tap time. Dart skips a toggle whose target
    /// line is already in the post-toggle state, so a launcher replaying a
    /// stale collection click cannot double-toggle an item.
    const val EXTRA_TODO_DONE = "todoDone"
    const val PREFS_NAME = "FlutterSharedPreferences"

    val PENDING_INTENT_FLAGS = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    else
        PendingIntent.FLAG_UPDATE_CURRENT

    val PENDING_INTENT_TEMPLATE_FLAGS = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
    else
        PendingIntent.FLAG_UPDATE_CURRENT

    fun newNoteIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = ACTION_NEW
        }
        return PendingIntent.getActivity(
            context, 0, intent, PENDING_INTENT_FLAGS
        )
    }

    fun expenseIntent(context: Context): PendingIntent = actionIntent(
        context,
        ACTION_EXPENSE,
        2,
    )

    fun incomeIntent(context: Context): PendingIntent = actionIntent(
        context,
        ACTION_INCOME,
        3,
    )

    fun financeIntent(context: Context): PendingIntent = actionIntent(
        context,
        ACTION_FINANCE,
        4,
    )

    /**
     * The PendingIntent *template* for both collection widgets (recent notes,
     * todo list). Must stay FLAG_MUTABLE so per-row fill-in intents can merge
     * their extras into it, and its action must be the generic dispatch action
     * so WidgetActionActivity can route on the verb extra (toggles stay on the
     * home screen, opens forward to MainActivity).
     */
    fun widgetDispatchTemplateIntent(context: Context): PendingIntent {
        val intent = Intent(context, WidgetActionActivity::class.java).apply {
            action = ACTION_WIDGET_DISPATCH
        }
        return PendingIntent.getActivity(
            context,
            5,
            intent,
            PENDING_INTENT_TEMPLATE_FLAGS,
        )
    }

    fun openRowFillInIntent(): Intent =
        Intent().putExtra(EXTRA_VERB, VERB_OPEN)

    fun toggleRowFillInIntent(noteId: String, todoText: String, done: Boolean): Intent = Intent()
        .putExtra(EXTRA_VERB, VERB_TOGGLE)
        .putExtra(EXTRA_NOTE_ID, noteId)
        .putExtra(EXTRA_TODO_TEXT, todoText)
        .putExtra(EXTRA_TODO_DONE, done)

    private fun actionIntent(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            this.action = action
        }
        return PendingIntent.getActivity(context, requestCode, intent, PENDING_INTENT_FLAGS)
    }

    fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        return PendingIntent.getActivity(
            context, 1, intent, PENDING_INTENT_FLAGS
        )
    }

    /**
     * Full refresh: pushes fresh static views to every widget and rebinds the
     * collections. Safe to call when the provider app has no foreground
     * activity.
     */
    fun refreshAll(context: Context) {
        scheduleDayRollover(context)
        updateNonCollectionWidgets(context)
        updateCollectionWidgetHeaders(context)
        notifyCollectionDataChanged(context, RecentNotesWidget::class.java, R.id.widget_recent_list)
        notifyCollectionDataChanged(context, TodoListWidget::class.java, R.id.widget_todo_list)
    }

    /**
     * Refresh used while the app's own activity is in the foreground.
     * AppWidgetServiceImpl defers static-view pushes for collection widgets
     * in that state — the lists re-bind but headers stay stale indefinitely —
     * so the collection headers are skipped here and flushed by the activity
     * once it is leaving the foreground (see MainActivity.onPause). The
     * non-collection widgets deliver immediately and stay live, and the
     * collection lists still re-bind on the viewDataChanged call.
     */
    fun refreshWhileForeground(context: Context) {
        updateNonCollectionWidgets(context)
        notifyCollectionDataChanged(context, RecentNotesWidget::class.java, R.id.widget_recent_list)
        notifyCollectionDataChanged(context, TodoListWidget::class.java, R.id.widget_todo_list)
    }

    /**
     * The widget's current height in dp, or null before the host reports it.
     * Portrait cells use the MAX height (MIN is the landscape one).
     */
    fun heightDp(context: Context, manager: AppWidgetManager, id: Int): Int? {
        val options = manager.getAppWidgetOptions(id)
        val landscape = context.resources.configuration.orientation ==
            android.content.res.Configuration.ORIENTATION_LANDSCAPE
        val height = options.getInt(
            if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT
            else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT,
        )
        return height.takeIf { it > 0 }
    }

    /**
     * Days since 1970-01-01 of today's LOCAL calendar date; mirrors Dart's
     * localEpochDay so payload stamps compare exactly.
     */
    fun localEpochDay(now: Calendar = Calendar.getInstance()): Long {
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(now.get(Calendar.YEAR), now.get(Calendar.MONTH), now.get(Calendar.DAY_OF_MONTH))
        }
        return utc.timeInMillis / 86_400_000L
    }

    /**
     * Wakes the date-sensitive widgets (streak, finance month) just after
     * local midnight. ACTION_DATE_CHANGED is no longer delivered to manifest
     * receivers (Android 8+), so without this the streak kept saying "you
     * wrote today" until the 30-minute periodic update, or the next app open.
     * Inexact and non-waking: it lands when the device is next awake.
     */
    fun scheduleDayRollover(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val next = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 1)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val intent = Intent(context, WidgetBootReceiver::class.java).setAction(ACTION_DAY_ROLLOVER)
        val pending = PendingIntent.getBroadcast(context, 6, intent, PENDING_INTENT_FLAGS)
        alarms.set(AlarmManager.RTC, next.timeInMillis, pending)
    }

    private fun updateNonCollectionWidgets(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        for (id in mgr.getAppWidgetIds(ComponentName(context, QuickCaptureWidget::class.java))) {
            QuickCaptureWidget.updateWidget(context, mgr, id)
        }
        for (id in mgr.getAppWidgetIds(ComponentName(context, FinanceWidget::class.java))) {
            FinanceWidget.updateWidget(context, mgr, id)
        }
        for (id in mgr.getAppWidgetIds(ComponentName(context, StreakWidget::class.java))) {
            StreakWidget.updateWidget(context, mgr, id)
        }
    }

    private fun updateCollectionWidgetHeaders(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        for (id in mgr.getAppWidgetIds(ComponentName(context, RecentNotesWidget::class.java))) {
            RecentNotesWidget.updateWidget(context, mgr, id)
        }
        for (id in mgr.getAppWidgetIds(ComponentName(context, TodoListWidget::class.java))) {
            TodoListWidget.updateWidget(context, mgr, id)
        }
    }

    private fun notifyCollectionDataChanged(
        context: Context,
        provider: Class<out AppWidgetProvider>,
        viewId: Int,
    ) {
        val mgr = AppWidgetManager.getInstance(context)
        val ids = mgr.getAppWidgetIds(ComponentName(context, provider))
        if (ids.isNotEmpty()) mgr.notifyAppWidgetViewDataChanged(ids, viewId)
    }
}
