package com.z4yed.typed

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.widget.RemoteViews

class QuickCaptureWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: android.content.Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            updateWidget(context, appWidgetManager, id)
        }
    }

    companion object {
        fun updateWidget(context: android.content.Context, appWidgetManager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_quick_capture)
            views.setOnClickPendingIntent(
                R.id.widget_quick_capture,
                WidgetHelper.newNoteIntent(context)
            )
            views.setOnClickPendingIntent(
                R.id.widget_quick_root,
                WidgetHelper.openAppIntent(context)
            )
            views.setOnClickPendingIntent(
                R.id.widget_quick_expense,
                WidgetHelper.expenseIntent(context)
            )
            views.setOnClickPendingIntent(
                R.id.widget_quick_income,
                WidgetHelper.incomeIntent(context)
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
