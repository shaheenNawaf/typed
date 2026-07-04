package com.z4yed.typed

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

class TodoListWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            updateWidget(context, appWidgetManager, id)
        }
    }

    private fun updateWidget(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int
    ) {
        val prefs = context.getSharedPreferences(WidgetHelper.PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.widget_todo_v1", null)

        val root = RemoteViews(context.packageName, R.layout.widget_todo_list)
        root.setOnClickPendingIntent(
            R.id.widget_todo_root,
            WidgetHelper.openAppIntent(context)
        )
        root.setOnClickPendingIntent(
            R.id.widget_todo_empty,
            WidgetHelper.openAppIntent(context)
        )

        if (raw.isNullOrEmpty()) {
            root.removeAllViews(R.id.widget_todo_list)
            root.setViewVisibility(R.id.widget_todo_list, View.GONE)
            root.setViewVisibility(R.id.widget_todo_empty, View.VISIBLE)
            mgr.updateAppWidget(widgetId, root)
            return
        }

        val items = try { JSONArray(raw) } catch (_: Exception) { JSONArray() }

        // Sort: undone first, preserving original order
        val sorted = (0 until items.length())
            .map { items.getJSONObject(it) }
            .sortedWith(compareBy({ it.optBoolean("done", false) }))

        root.removeAllViews(R.id.widget_todo_list)

        if (sorted.isEmpty()) {
            root.setViewVisibility(R.id.widget_todo_list, View.GONE)
            root.setViewVisibility(R.id.widget_todo_empty, View.VISIBLE)
        } else {
            root.setViewVisibility(R.id.widget_todo_empty, View.GONE)
            root.setViewVisibility(R.id.widget_todo_list, View.VISIBLE)
            val maxItems = minOf(sorted.size, 6)
            for (i in 0 until maxItems) {
                val obj = sorted[i]
                val id = obj.optString("id", "")
                val done = obj.optBoolean("done", false)
                val text = obj.optString("text", "")

                val item = RemoteViews(context.packageName, R.layout.widget_todo_item)
                item.setTextViewText(R.id.todo_item_text, text)
                item.setImageViewResource(
                    R.id.todo_item_check,
                    if (done) R.drawable.ic_check_filled else R.drawable.ic_check_empty
                )
                item.setOnClickPendingIntent(
                    R.id.todo_item_root,
                    WidgetHelper.openNoteIntent(context, id)
                )
                root.addView(R.id.widget_todo_list, item)
            }
        }

        mgr.updateAppWidget(widgetId, root)
    }
}
