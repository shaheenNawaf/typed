package com.z4yed.typed

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Today: Home's Today list (overdue first, then by time) with money until
 * payday, on the home screen. Rows tick in place like the To-do widget's;
 * the mic and + start a voice memo or a note.
 */
class TodayWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
        WidgetHelper.scheduleDayRollover(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    companion object {
        fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_today).apply {
                setOnClickPendingIntent(R.id.widget_today_root, WidgetHelper.openAppIntent(context))
                setOnClickPendingIntent(R.id.widget_today_voice, WidgetHelper.voiceIntent(context))
                setOnClickPendingIntent(R.id.widget_today_new, WidgetHelper.newNoteIntent(context))
                setOnClickPendingIntent(R.id.widget_today_empty, WidgetHelper.newNoteIntent(context))
                setEmptyView(R.id.widget_today_list, R.id.widget_today_empty)
                setPendingIntentTemplate(
                    R.id.widget_today_list,
                    WidgetHelper.widgetDispatchTemplateIntent(context),
                )
                setRemoteAdapter(
                    R.id.widget_today_list,
                    Intent(context, TodayRemoteViewsService::class.java).apply {
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                    },
                )
            }
            manager.updateAppWidget(id, views)
            manager.notifyAppWidgetViewDataChanged(intArrayOf(id), R.id.widget_today_list)
        }
    }
}
