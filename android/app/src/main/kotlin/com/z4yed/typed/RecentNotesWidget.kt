package com.z4yed.typed

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

class RecentNotesWidget : AppWidgetProvider() {
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
        val raw = prefs.getString("flutter.widget_recent_v1", null)

        val root = RemoteViews(context.packageName, R.layout.widget_recent_notes)
        root.setOnClickPendingIntent(
            R.id.widget_recent_root,
            WidgetHelper.openAppIntent(context)
        )
        root.setOnClickPendingIntent(
            R.id.widget_recent_empty,
            WidgetHelper.openAppIntent(context)
        )

        if (raw.isNullOrEmpty()) {
            root.removeAllViews(R.id.widget_recent_list)
            root.setViewVisibility(R.id.widget_recent_list, View.GONE)
            root.setViewVisibility(R.id.widget_recent_empty, View.VISIBLE)
            mgr.updateAppWidget(widgetId, root)
            return
        }

        val items = try { JSONArray(raw) } catch (_: Exception) { JSONArray() }

        root.removeAllViews(R.id.widget_recent_list)

        if (items.length() == 0) {
            root.setViewVisibility(R.id.widget_recent_list, View.GONE)
            root.setViewVisibility(R.id.widget_recent_empty, View.VISIBLE)
        } else {
            root.setViewVisibility(R.id.widget_recent_empty, View.GONE)
            root.setViewVisibility(R.id.widget_recent_list, View.VISIBLE)
            val maxItems = minOf(items.length(), 5)
            for (i in 0 until maxItems) {
                val obj = items.getJSONObject(i)
                val id = obj.optString("id", "")
                val title = obj.optString("title", "Untitled")
                val preview = obj.optString("preview", "")

                val item = RemoteViews(context.packageName, R.layout.widget_recent_item)
                item.setTextViewText(R.id.recent_item_title, title)
                item.setTextViewText(R.id.recent_item_preview, preview)
                item.setOnClickPendingIntent(
                    R.id.recent_item_root,
                    WidgetHelper.openNoteIntent(context, id)
                )
                root.addView(R.id.widget_recent_list, item)
            }
        }

        mgr.updateAppWidget(widgetId, root)
    }
}
