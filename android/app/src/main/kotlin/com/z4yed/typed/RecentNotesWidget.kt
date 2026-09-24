package com.z4yed.typed

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class RecentNotesWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
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
            val views = RemoteViews(context.packageName, R.layout.widget_recent_notes).apply {
                setOnClickPendingIntent(R.id.widget_recent_root, WidgetHelper.openAppIntent(context))
                setOnClickPendingIntent(R.id.widget_recent_empty, WidgetHelper.newNoteIntent(context))
                setEmptyView(R.id.widget_recent_list, R.id.widget_recent_empty)
                setPendingIntentTemplate(
                    R.id.widget_recent_list,
                    WidgetHelper.widgetDispatchTemplateIntent(context),
                )
                setRemoteAdapter(
                    R.id.widget_recent_list,
                    Intent(context, RecentNotesRemoteViewsService::class.java).apply {
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                    },
                )
            }
            manager.updateAppWidget(id, views)
            manager.notifyAppWidgetViewDataChanged(intArrayOf(id), R.id.widget_recent_list)
        }
    }
}
