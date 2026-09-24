package com.z4yed.typed

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

class TodoRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        TodoFactory(applicationContext)
}

private class TodoFactory(
    private val context: Context,
) : RemoteViewsService.RemoteViewsFactory {
    private data class Item(val id: String, val done: Boolean, val text: String)

    private var items = emptyList<Item>()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val prefs = context.getSharedPreferences(WidgetHelper.PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.widget_todo_v1", null)
        val json = try { JSONArray(raw ?: "[]") } catch (_: Exception) { JSONArray() }
        // Unfinished first, then done.
        items = (0 until json.length()).mapNotNull { index ->
            val item = json.optJSONObject(index) ?: return@mapNotNull null
            Item(
                id = item.optString("id"),
                done = item.optBoolean("done", false),
                text = item.optString("text"),
            )
        }.sortedBy { it.done }
    }

    override fun onDestroy() {
        items = emptyList()
    }

    // Position 0 is the live progress row ("x/y done"); the rest are tasks.
    override fun getCount(): Int = if (items.isEmpty()) 0 else items.size + 1

    override fun getViewTypeCount(): Int = 2

    override fun getViewAt(position: Int): RemoteViews {
        if (position == 0) {
            val done = items.count { it.done }
            return RemoteViews(context.packageName, R.layout.widget_todo_progress_row).apply {
                setTextViewText(
                    R.id.widget_todo_progress_text,
                    context.getString(R.string.widget_todo_progress, done, items.size),
                )
            }
        }
        val item = items.getOrNull(position - 1)
            ?: return RemoteViews(context.packageName, R.layout.widget_todo_item)
        return RemoteViews(context.packageName, R.layout.widget_todo_item).apply {
            setTextViewText(R.id.todo_item_text, item.text)
            setImageViewResource(
                R.id.todo_item_check,
                if (item.done) R.drawable.ic_check_filled else R.drawable.ic_check_empty,
            )
            setContentDescription(
                R.id.todo_item_check,
                if (item.done) context.getString(R.string.widget_completed)
                else context.getString(R.string.widget_incomplete),
            )
            // Children of a collection may only use fill-in intents; a
            // setOnClickPendingIntent here would be silently ignored. The
            // checkbox fills in verb=toggle, the rest of the row verb=open —
            // MainActivity routes on the verb through the collection's
            // PendingIntent template.
            setOnClickFillInIntent(
                R.id.todo_item_check,
                WidgetHelper.toggleRowFillInIntent(item.id, item.text, item.done),
            )
            setOnClickFillInIntent(
                R.id.todo_item_root,
                WidgetHelper.openRowFillInIntent().putExtra(WidgetHelper.EXTRA_NOTE_ID, item.id),
            )
        }
    }

    override fun getLoadingView(): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_todo_item)

    override fun getItemId(position: Int): Long {
        if (position == 0) return -1L
        val item = items.getOrNull(position - 1) ?: return position.toLong()
        return "${item.id}:${item.text}".hashCode().toLong()
    }

    override fun hasStableIds(): Boolean = true
}
