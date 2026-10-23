package com.z4yed.typed

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * "Voice memo" quick-settings tile: one swipe and a tap from anywhere opens
 * Typed straight into recording. A button, not a toggle, so it always reads
 * as inactive. On a locked phone the user unlocks first; memos are never
 * recorded over the lock screen.
 */
class VoiceMemoTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        if (isLocked) unlockAndRun { openRecorder() } else openRecorder()
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun openRecorder() {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = WidgetHelper.ACTION_VOICE
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                PendingIntent.getActivity(
                    this, 9, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
