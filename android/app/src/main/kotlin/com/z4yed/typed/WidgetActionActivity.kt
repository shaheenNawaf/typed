package com.z4yed.typed

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import org.json.JSONArray
import org.json.JSONObject

/**
 * Invisible target of the collection widgets' PendingIntent template.
 *
 * A collection gets exactly one template, so open and toggle taps share it.
 * Opening a note forwards to [MainActivity]; ticking a to-do is applied right
 * here, on the home screen, instead of launching the whole app for a
 * checkbox. The widget's own payload flips immediately and the toggle is
 * queued for Dart, which applies it to the note on its next load or resume
 * (see HomeScreen._drainWidgetToggles) — Dart stays the only writer of
 * note content.
 */
class WidgetActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val source = intent
        if (source?.getStringExtra(WidgetHelper.EXTRA_VERB) == WidgetHelper.VERB_TOGGLE) {
            val id = source.getStringExtra(WidgetHelper.EXTRA_NOTE_ID)
            val text = source.getStringExtra(WidgetHelper.EXTRA_TODO_TEXT)
            if (id != null && text != null) {
                WidgetTodoStore.toggle(
                    applicationContext,
                    id,
                    text,
                    source.getBooleanExtra(WidgetHelper.EXTRA_TODO_DONE, false),
                )
            }
        } else if (source != null) {
            startActivity(
                Intent(source)
                    .setClass(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            )
        }
        // Theme.NoDisplay: must finish before onResume.
        finish()
    }
}

object WidgetTodoStore {
    private const val TODO_KEY = "flutter.widget_todo_v1"
    private const val TODAY_KEY = TodayRemoteViewsService.ITEMS_KEY

    /** Read (and cleared) by Dart; keep in sync with HomeScreen. */
    private const val PENDING_KEY = "flutter.widget_pending_toggles_v1"

    fun toggle(context: Context, noteId: String, text: String, doneAtTap: Boolean) {
        val prefs = context.getSharedPreferences(WidgetHelper.PREFS_NAME, Context.MODE_PRIVATE)
        // The same task may show in both the To-do and Today widgets; it
        // flips in each so neither shows a stale state.
        val items = parseArray(prefs.getString(TODO_KEY, null))
        val today = parseArray(prefs.getString(TODAY_KEY, null))
        val flippedTodo = flip(items, noteId, text, doneAtTap)
        val flippedToday = flip(today, noteId, text, doneAtTap)
        // No row in the tapped state: a launcher replaying a stale click.
        if (!flippedTodo && !flippedToday) return

        val pending = parseArray(prefs.getString(PENDING_KEY, null)).put(
            JSONObject()
                .put("id", noteId)
                .put("text", text)
                .put("done", doneAtTap),
        )
        // commit, not apply: the process may die right after finish().
        prefs.edit()
            .putString(TODO_KEY, items.toString())
            .putString(TODAY_KEY, today.toString())
            .putString(PENDING_KEY, pending.toString())
            .commit()

        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, TodoListWidget::class.java))
        if (ids.isNotEmpty()) manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_todo_list)
        val todayIds = manager.getAppWidgetIds(ComponentName(context, TodayWidget::class.java))
        if (todayIds.isNotEmpty()) {
            manager.notifyAppWidgetViewDataChanged(todayIds, R.id.widget_today_list)
        }
    }

    private fun flip(items: JSONArray, noteId: String, text: String, doneAtTap: Boolean): Boolean {
        for (i in 0 until items.length()) {
            val item = items.optJSONObject(i) ?: continue
            if (item.optString("id") == noteId &&
                item.optString("text") == text &&
                item.optBoolean("done", false) == doneAtTap
            ) {
                item.put("done", !doneAtTap)
                return true
            }
        }
        return false
    }

    private fun parseArray(raw: String?): JSONArray =
        try { JSONArray(raw ?: "[]") } catch (_: Exception) { JSONArray() }
}
