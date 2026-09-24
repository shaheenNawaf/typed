package com.z4yed.typed

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import org.json.JSONObject

class StreakWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        updateWidget(context, manager, appWidgetId)
    }

    companion object {
        fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = context.getSharedPreferences(WidgetHelper.PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.widget_streak_v1", null)
            val data = try { JSONObject(raw ?: "{}") } catch (_: Exception) { JSONObject() }
            val streak = data.optInt("streak", 0)
            val writtenToday = data.optBoolean("writtenToday", false)
            val views = RemoteViews(context.packageName, R.layout.widget_streak).apply {
                setOnClickPendingIntent(R.id.widget_streak_root, WidgetHelper.newNoteIntent(context))
                setOnClickPendingIntent(R.id.widget_streak_action, WidgetHelper.newNoteIntent(context))
                setTextViewText(
                    R.id.widget_streak_days,
                    context.resources.getQuantityString(
                        R.plurals.widget_streak_days_count,
                        streak,
                        streak,
                    ),
                )
                setTextViewText(
                    R.id.widget_streak_message,
                    if (writtenToday) context.getString(R.string.widget_streak_written)
                    else if (streak > 0) context.getString(R.string.widget_streak_today)
                    else context.getString(R.string.widget_streak_started),
                )
                setViewVisibility(R.id.widget_streak_action, if (writtenToday) android.view.View.GONE else android.view.View.VISIBLE)
            }
            manager.updateAppWidget(id, views)
        }
    }
}
