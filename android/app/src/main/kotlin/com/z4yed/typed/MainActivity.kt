package com.z4yed.typed

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.z4yed.typed/widget"
    private var pendingIntent: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        handleIntent(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getIntent" -> {
                        result.success(pendingIntent)
                        pendingIntent = null
                    }
                    "refreshWidgets" -> {
                        WidgetHelper.refreshAll(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleIntent(intent: Intent?) {
        intent ?: return
        when (intent.action) {
            WidgetHelper.ACTION_NEW -> pendingIntent = "new"
            WidgetHelper.ACTION_OPEN -> {
                val id = intent.getStringExtra(WidgetHelper.EXTRA_NOTE_ID)
                if (id != null) pendingIntent = "open:$id"
            }
        }
    }
}
