package com.z4yed.typed

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.z4yed.typed/widget"

    // Queued rather than a single var: two widget taps in quick succession used
    // to overwrite each other and the first action was silently lost. Dart
    // drains the queue with repeated getIntent calls.
    private val pendingIntents = ArrayDeque<String>()

    private var activityResumed = false
    private var widgetRefreshQueued = false
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        activityResumed = true
    }

    override fun onPause() {
        super.onPause()
        activityResumed = false
    }

    override fun onStop() {
        super.onStop()
        // Collection-widget header pushes made while this activity was
        // foreground are deferred by AppWidgetServiceImpl and the deferred
        // queue does not flush reliably on its own. Deliver them shortly
        // after the activity is fully hidden, once the provider uid is
        // background and delivery goes through immediately.
        if (widgetRefreshQueued) {
            mainHandler.postDelayed({
                if (widgetRefreshQueued) {
                    widgetRefreshQueued = false
                    WidgetHelper.refreshAll(applicationContext)
                }
            }, 1200)
        }
    }

    /// Recreated (config change, process death) or reopened from Recents:
    /// the launch intent is the original widget tap, and replaying it would
    /// reopen the expense sheet / note a second time.
    private var replayedLaunch = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        replayedLaunch = savedInstanceState != null ||
            ((intent?.flags ?: 0) and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!replayedLaunch) handleIntent(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getIntent" -> {
                        result.success(pendingIntents.removeFirstOrNull())
                    }
                    "refreshWidgets" -> {
                        if (activityResumed) {
                            // Lists rebind live; collection headers are held
                            // until the app backgrounds (see onStop).
                            widgetRefreshQueued = true
                            WidgetHelper.refreshWhileForeground(applicationContext)
                        } else {
                            WidgetHelper.refreshAll(applicationContext)
                        }
                        result.success(null)
                    }
                    // Voice memos only run on an on-device recogniser. The
                    // speech plugin silently falls back to the default (often
                    // cloud) recogniser when there is none, so Dart asks first.
                    "onDeviceSpeechAvailable" -> {
                        result.success(
                            android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S &&
                                android.speech.SpeechRecognizer
                                    .isOnDeviceRecognitionAvailable(applicationContext)
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleIntent(intent: Intent?) {
        intent ?: return
        when (intent.action) {
            WidgetHelper.ACTION_NEW -> pendingIntents.addLast("new")
            WidgetHelper.ACTION_VOICE -> pendingIntents.addLast("voice")
            WidgetHelper.ACTION_WIDGET_DISPATCH -> {
                val id = intent.getStringExtra(WidgetHelper.EXTRA_NOTE_ID)
                when (intent.getStringExtra(WidgetHelper.EXTRA_VERB)) {
                    WidgetHelper.VERB_TOGGLE -> {
                        val text = intent.getStringExtra(WidgetHelper.EXTRA_TODO_TEXT)
                        val done = intent.getBooleanExtra(WidgetHelper.EXTRA_TODO_DONE, false)
                        if (id != null && text != null) {
                            pendingIntents.addLast(
                                "toggle:$id:${android.net.Uri.encode(text)}:${if (done) 1 else 0}",
                            )
                        }
                    }
                    else -> {
                        if (id != null) pendingIntents.addLast("open:$id")
                    }
                }
            }
            WidgetHelper.ACTION_EXPENSE -> pendingIntents.addLast("expense")
            WidgetHelper.ACTION_INCOME -> pendingIntents.addLast("income")
            WidgetHelper.ACTION_FINANCE -> pendingIntents.addLast("finance")
            WidgetHelper.ACTION_TOGGLE -> {
                val id = intent.getStringExtra(WidgetHelper.EXTRA_NOTE_ID)
                val text = intent.getStringExtra(WidgetHelper.EXTRA_TODO_TEXT)
                if (id != null && text != null) {
                    pendingIntents.addLast(
                        "toggle:$id:${android.net.Uri.encode(text)}",
                    )
                }
            }
        }
    }
}
