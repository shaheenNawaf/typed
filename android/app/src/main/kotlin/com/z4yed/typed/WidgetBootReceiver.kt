package com.z4yed.typed

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class WidgetBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Date/timezone rollovers must refresh the date-sensitive widgets
        // (streak "wrote today", finance month) even when the app is closed.
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            intent.action == Intent.ACTION_DATE_CHANGED ||
            intent.action == Intent.ACTION_TIME_CHANGED ||
            intent.action == Intent.ACTION_TIMEZONE_CHANGED
        ) {
            WidgetHelper.refreshAll(context)
        }
    }
}
