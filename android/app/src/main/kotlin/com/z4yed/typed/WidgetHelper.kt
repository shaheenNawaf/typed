package com.z4yed.typed

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build

object WidgetHelper {
    const val ACTION_NEW = "com.z4yed.typed.ACTION_NEW"
    const val ACTION_OPEN = "com.z4yed.typed.ACTION_OPEN"
    const val EXTRA_NOTE_ID = "noteId"
    const val PREFS_NAME = "FlutterSharedPreferences"
    const val KEY_PENDING_INTENT = "flutter.pending_intent"

    val PENDING_INTENT_FLAGS = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    else
        PendingIntent.FLAG_UPDATE_CURRENT

    fun openNoteIntent(context: Context, noteId: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = ACTION_OPEN
            putExtra(EXTRA_NOTE_ID, noteId)
        }
        return PendingIntent.getActivity(
            context, noteId.hashCode(), intent, PENDING_INTENT_FLAGS
        )
    }

    fun newNoteIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = ACTION_NEW
        }
        return PendingIntent.getActivity(
            context, 0, intent, PENDING_INTENT_FLAGS
        )
    }

    fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        return PendingIntent.getActivity(
            context, 1, intent, PENDING_INTENT_FLAGS
        )
    }

    fun refreshAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val providerClasses = listOf(
            QuickCaptureWidget::class.java,
            RecentNotesWidget::class.java,
            TodoListWidget::class.java,
        )
        for (cls in providerClasses) {
            val name = ComponentName(context, cls)
            val ids = mgr.getAppWidgetIds(name)
            if (ids.isNotEmpty()) {
                val updateIntent = Intent(context, cls).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(updateIntent)
            }
        }
    }
}
