package com.z4yed.typed

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

class TodoListWidget : AppWidgetProvider() {
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
            val views = RemoteViews(context.packageName, R.layout.widget_todo_list).apply {
                setOnClickPendingIntent(R.id.widget_todo_root, WidgetHelper.openAppIntent(context))
                setOnClickPendingIntent(R.id.widget_todo_empty, WidgetHelper.newNoteIntent(context))
                setEmptyView(R.id.widget_todo_list, R.id.widget_todo_empty)
                setPendingIntentTemplate(R.id.widget_todo_list, WidgetHelper.widgetDispatchTemplateIntent(context))
                setRemoteAdapter(
                    R.id.widget_todo_list,
                    Intent(context, TodoRemoteViewsService::class.java).apply {
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                    },
                )
                // The "x/y done" counter lives inside the collection (first
                // row, rendered by TodoRemoteViewsService): static-view pushes
                // for collection widgets go through Android 16's deferred
                // host-update path and can stay stale on the launcher.
            }
            manager.updateAppWidget(id, views)
            manager.notifyAppWidgetViewDataChanged(intArrayOf(id), R.id.widget_todo_list)
        }
    }
}
