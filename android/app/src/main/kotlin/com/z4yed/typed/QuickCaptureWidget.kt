package com.z4yed.typed

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

class QuickCaptureWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            updateWidget(context, appWidgetManager, id)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    companion object {
        /** Below this the invitation text is dropped so the buttons fit. */
        private const val COMPACT_HEIGHT_DP = 170

        fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_quick_capture)
            val newNote = WidgetHelper.newNoteIntent(context)
            views.setOnClickPendingIntent(R.id.widget_quick_capture, newNote)
            views.setOnClickPendingIntent(R.id.widget_quick_body, newNote)
            views.setOnClickPendingIntent(
                R.id.widget_quick_root,
                WidgetHelper.openAppIntent(context)
            )
            views.setOnClickPendingIntent(
                R.id.widget_quick_voice,
                WidgetHelper.voiceIntent(context)
            )
            views.setOnClickPendingIntent(
                R.id.widget_quick_expense,
                WidgetHelper.expenseIntent(context)
            )
            views.setOnClickPendingIntent(
                R.id.widget_quick_income,
                WidgetHelper.incomeIntent(context)
            )
            val height = WidgetHelper.heightDp(context, appWidgetManager, id)
            views.setViewVisibility(
                R.id.widget_quick_body,
                if (height != null && height < COMPACT_HEIGHT_DP) View.GONE else View.VISIBLE,
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
