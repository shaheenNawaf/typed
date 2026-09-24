package com.z4yed.typed

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build

object WidgetHelper {
    const val ACTION_NEW = "com.z4yed.typed.ACTION_NEW"
    const val ACTION_EXPENSE = "com.z4yed.typed.ACTION_EXPENSE"
    const val ACTION_INCOME = "com.z4yed.typed.ACTION_INCOME"
    const val ACTION_FINANCE = "com.z4yed.typed.ACTION_FINANCE"
    const val ACTION_TOGGLE = "com.z4yed.typed.ACTION_TOGGLE"

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
     * so MainActivity can route on the verb extra.
     */
    fun widgetDispatchTemplateIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
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
