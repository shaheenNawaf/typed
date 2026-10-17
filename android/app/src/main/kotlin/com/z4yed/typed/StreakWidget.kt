package com.z4yed.typed

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

class StreakWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, manager, it) }
        WidgetHelper.scheduleDayRollover(context)
    }

    override fun onEnabled(context: Context) {
        WidgetHelper.scheduleDayRollover(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        updateWidget(context, manager, appWidgetId)
    }

    companion object {
        /**
         * The payload is a snapshot from the last app save. Once that day is
         * over it is re-read against today: a streak that included its day
         * survives one more day (not yet written), anything older is broken.
         */
        fun currentStreak(
            streakAsOf: Int,
            writtenAsOf: Boolean,
            asOfDay: Long?,
            today: Long,
        ): Pair<Int, Boolean> {
            if (asOfDay == null || today <= asOfDay) return streakAsOf to writtenAsOf
            val alive = today - asOfDay == 1L && writtenAsOf
            return (if (alive) streakAsOf else 0) to false
        }

        /** Below this the 7-day dots are dropped so the button never clips. */
        private const val COMPACT_HEIGHT_DP = 170

        private val DOT_IDS = intArrayOf(
            R.id.widget_streak_dot_0,
            R.id.widget_streak_dot_1,
            R.id.widget_streak_dot_2,
            R.id.widget_streak_dot_3,
            R.id.widget_streak_dot_4,
            R.id.widget_streak_dot_5,
            R.id.widget_streak_dot_6,
        )

        /**
         * The payload's last-7-days flags (oldest first, ending on its asOf
         * day) slid forward to end today; days since then had no writing.
         */
        fun currentWeek(week: List<Boolean>, asOfDay: Long?, today: Long): List<Boolean> {
            val padded = List(maxOf(0, 7 - week.size)) { false } + week.takeLast(7)
            val shift = if (asOfDay == null) 0 else (today - asOfDay).coerceIn(0L, 7L).toInt()
            return padded.drop(shift) + List(shift) { false }
        }

        fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = context.getSharedPreferences(WidgetHelper.PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.widget_streak_v1", null)
            val data = try { JSONObject(raw ?: "{}") } catch (_: Exception) { JSONObject() }
            val today = WidgetHelper.localEpochDay()
            val asOfDay = if (data.has("asOfDay")) data.optLong("asOfDay") else null
            val (streak, writtenToday) = currentStreak(
                streakAsOf = data.optInt("streak", 0),
                writtenAsOf = data.optBoolean("writtenToday", false),
                asOfDay = asOfDay,
                today = today,
            )
            val weekJson = data.optJSONArray("week")
            val week = currentWeek(
                if (weekJson == null) emptyList()
                else List(weekJson.length()) { weekJson.optBoolean(it, false) },
                asOfDay,
                today,
            )
            val height = WidgetHelper.heightDp(context, manager, id)
            val compact = height != null && height < COMPACT_HEIGHT_DP

            val views = RemoteViews(context.packageName, R.layout.widget_streak).apply {
                setOnClickPendingIntent(R.id.widget_streak_root, WidgetHelper.newNoteIntent(context))
                setOnClickPendingIntent(R.id.widget_streak_action, WidgetHelper.newNoteIntent(context))
                setTextViewText(R.id.widget_streak_count, streak.toString())
                setTextViewText(
                    R.id.widget_streak_unit,
                    context.resources.getQuantityString(R.plurals.widget_streak_unit, streak),
                )
                setContentDescription(
                    R.id.widget_streak_count,
                    context.getString(R.string.widget_streak_description_a11y, streak),
                )
                DOT_IDS.forEachIndexed { index, dot ->
                    setImageViewResource(
                        dot,
                        if (week[index]) R.drawable.widget_dot_on else R.drawable.widget_dot_off,
                    )
                }
                setViewVisibility(
                    R.id.widget_streak_week,
                    if (compact || weekJson == null) View.GONE else View.VISIBLE,
                )
                setTextViewText(
                    R.id.widget_streak_message,
                    if (writtenToday) context.getString(R.string.widget_streak_written)
                    else if (streak > 0) context.getString(R.string.widget_streak_today)
                    else context.getString(R.string.widget_streak_started),
                )
                setViewVisibility(
                    R.id.widget_streak_action,
                    if (writtenToday) View.GONE else View.VISIBLE,
                )
            }
            manager.updateAppWidget(id, views)
        }
    }
}
