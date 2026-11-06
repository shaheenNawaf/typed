package com.z4yed.typed

import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.text.NumberFormat
import java.util.Calendar
import java.util.Locale

class TodayRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        TodayFactory(applicationContext)

    companion object {
        /** Written by Dart (NoteStorage._writeWidgetPayload). */
        const val ITEMS_KEY = "flutter.widget_today_items_v1"
        const val MONEY_KEY = "flutter.widget_today_money_v1"

        /** Tapping the money row opens Finance (see HomeScreen's intents). */
        const val FINANCE_TARGET = "__finance__"
    }
}

/**
 * Rows: a summary ("Friday · 3 for today"), the tasks, then money until
 * payday. Dates arrive absolute (local epoch days) and are judged here,
 * against today, so the list stays right after midnight with the app shut.
 */
private class TodayFactory(
    private val context: Context,
) : RemoteViewsService.RemoteViewsFactory {
    private data class Item(
        val id: String,
        val text: String,
        val title: String,
        val done: Boolean,
        val day: Long,
        val hour: Int,
        val minute: Int,
        val part: String,
    ) {
        val hasTime get() = hour >= 0 || part.isNotEmpty()
        val minutes get() = when {
            hour >= 0 -> hour * 60 + minute
            part == "morning" -> 9 * 60
            part == "afternoon" -> 14 * 60
            part == "evening" -> 18 * 60
            part == "tonight" -> 20 * 60
            else -> 0
        }
    }

    private data class Money(
        val symbol: String,
        val decimals: Int,
        val budget: Long,
        val spent: Long,
        val start: Long,
        val next: Long,
        val nextDay: Int,
        val startLabel: String,
    )

    private var items = emptyList<Item>()
    private var money: Money? = null
    private var today = 0L

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val prefs = context.getSharedPreferences(WidgetHelper.PREFS_NAME, Context.MODE_PRIVATE)
        today = WidgetHelper.localEpochDay()
        val json = try {
            JSONArray(prefs.getString(TodayRemoteViewsService.ITEMS_KEY, null) ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        val all = (0 until json.length()).mapNotNull { i ->
            val o = json.optJSONObject(i) ?: return@mapNotNull null
            Item(
                id = o.optString("id"),
                text = o.optString("text"),
                title = o.optString("title", o.optString("text")),
                done = o.optBoolean("done", false),
                day = o.optLong("day", -1L),
                hour = o.optInt("hour", -1),
                minute = o.optInt("minute", 0),
                part = o.optString("part", ""),
            )
        }
        // Home's order: overdue (oldest first), timed today, today, undated.
        // Tomorrow's tasks ride along and join once their day comes.
        items = all.filter { it.day <= today }.sortedWith(
            compareBy<Item>(
                { rank(it) },
                { if (it.day >= 0) it.day else Long.MAX_VALUE },
                { it.minutes },
            ),
        )
        money = parseMoney(prefs.getString(TodayRemoteViewsService.MONEY_KEY, null))
    }

    private fun rank(item: Item): Int = when {
        item.day in 0 until today -> 0
        item.day == today && item.hasTime -> 1
        item.day == today -> 2
        else -> 3
    }

    private fun parseMoney(raw: String?): Money? = try {
        val o = JSONObject(raw ?: return null)
        if (!o.has("spent")) {
            null
        } else {
            Money(
                symbol = o.optString("symbol", "₱"),
                decimals = o.optInt("decimals", 2),
                budget = o.optLong("budget", -1L),
                spent = o.optLong("spent", 0L),
                start = o.optLong("start", 0L),
                next = o.optLong("next", 0L),
                nextDay = o.optInt("nextDay", 15),
                startLabel = o.optString("startLabel", ""),
            )
        }
    } catch (_: Exception) {
        null
    }

    override fun onDestroy() {
        items = emptyList()
    }

    /** A cutoff that ended while the app was closed is no longer shown. */
    private fun liveMoney(): Money? = money?.takeIf { today < it.next }

    override fun getCount(): Int {
        if (items.isEmpty() && liveMoney() == null) return 0
        return 1 + items.size + (if (liveMoney() != null) 1 else 0)
    }

    override fun getViewTypeCount(): Int = 3

    override fun getViewAt(position: Int): RemoteViews {
        if (position == 0) return summaryRow()
        val item = items.getOrNull(position - 1)
        if (item != null) return taskRow(item)
        return moneyRow(liveMoney())
    }

    private fun summaryRow(): RemoteViews {
        val weekday = Calendar.getInstance()
            .getDisplayName(Calendar.DAY_OF_WEEK, Calendar.LONG, Locale.ENGLISH) ?: ""
        val open = items.filter { !it.done }
        val overdue = open.count { it.day in 0 until today }
        val forToday = open.size - overdue
        val text = when {
            open.isEmpty() && items.isNotEmpty() -> "$weekday · all done"
            open.isEmpty() -> "$weekday · nothing due today"
            overdue == 0 -> "$weekday · $forToday for today"
            forToday == 0 -> "$weekday · $overdue overdue"
            else -> "$weekday · $forToday for today, $overdue overdue"
        }
        return RemoteViews(context.packageName, R.layout.widget_today_summary_row).apply {
            setTextViewText(R.id.widget_today_summary, text)
        }
    }

    private fun taskRow(item: Item): RemoteViews {
        val overdue = item.day in 0 until today
        val whenText = when {
            overdue -> dueLabel(item.day)
            item.day == today && item.hour >= 0 -> clock(item.hour, item.minute)
            item.day == today && item.part.isNotEmpty() ->
                item.part.replaceFirstChar { it.uppercase() }
            else -> ""
        }
        return RemoteViews(context.packageName, R.layout.widget_today_item).apply {
            setTextViewText(R.id.today_item_text, item.title)
            setTextViewText(R.id.today_item_when, whenText)
            // Rows are recycled: always set every state both ways.
            setInt(
                R.id.today_item_text,
                "setPaintFlags",
                if (item.done) Paint.STRIKE_THRU_TEXT_FLAG or Paint.ANTI_ALIAS_FLAG
                else Paint.ANTI_ALIAS_FLAG,
            )
            setTextColor(
                R.id.today_item_text,
                ContextCompat.getColor(
                    context,
                    if (item.done) R.color.widget_muted else R.color.widget_fg,
                ),
            )
            setTextColor(
                R.id.today_item_when,
                ContextCompat.getColor(
                    context,
                    if (overdue && !item.done) R.color.widget_warning else R.color.widget_muted,
                ),
            )
            setImageViewResource(
                R.id.today_item_check,
                if (item.done) R.drawable.ic_check_filled else R.drawable.ic_check_empty,
            )
            setContentDescription(
                R.id.today_item_check,
                context.getString(
                    if (item.done) R.string.widget_completed else R.string.widget_incomplete,
                ),
            )
            setOnClickFillInIntent(
                R.id.today_item_check,
                WidgetHelper.toggleRowFillInIntent(item.id, item.text, item.done),
            )
            setOnClickFillInIntent(
                R.id.today_item_root,
                WidgetHelper.openRowFillInIntent().putExtra(WidgetHelper.EXTRA_NOTE_ID, item.id),
            )
        }
    }

    private fun moneyRow(m: Money?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today_money_row)
        if (m == null) return views
        val daysLeft = (m.next - today).coerceAtLeast(1)
        val payday = ordinal(m.nextDay)
        if (m.budget > 0) {
            val left = m.budget - m.spent
            if (left >= 0) {
                views.setTextViewText(R.id.today_money_text, "${whole(left, m)} until the $payday")
                views.setTextViewText(
                    R.id.today_money_sub,
                    "About ${whole(left / daysLeft, m)} a day for $daysLeft " +
                        if (daysLeft == 1L) "day" else "days",
                )
            } else {
                views.setTextViewText(R.id.today_money_text, "${whole(-left, m)} over budget")
                views.setTextViewText(R.id.today_money_sub, "Payday on the $payday")
            }
            val fill = (m.spent * 1000 / m.budget).coerceIn(0, 1000).toInt()
            views.setProgressBar(R.id.today_money_bar, 1000, fill, false)
            views.setViewVisibility(R.id.today_money_bar, android.view.View.VISIBLE)
        } else {
            views.setTextViewText(R.id.today_money_text, "${whole(m.spent, m)} spent since ${m.startLabel}")
            views.setTextViewText(R.id.today_money_sub, "Payday on the $payday")
            views.setViewVisibility(R.id.today_money_bar, android.view.View.GONE)
        }
        views.setOnClickFillInIntent(
            R.id.today_money_root,
            WidgetHelper.openRowFillInIntent().putExtra(WidgetHelper.EXTRA_NOTE_ID, TodayRemoteViewsService.FINANCE_TARGET),
        )
        return views
    }

    private fun whole(minor: Long, m: Money): String {
        var scale = 1L
        repeat(m.decimals) { scale *= 10 }
        val major = (minor + scale / 2) / scale
        return m.symbol + NumberFormat.getIntegerInstance(Locale.US).format(major)
    }

    private fun clock(hour: Int, minute: Int): String {
        val h = if (hour % 12 == 0) 12 else hour % 12
        return "$h:${minute.toString().padStart(2, '0')} ${if (hour < 12) "AM" else "PM"}"
    }

    private fun dueLabel(day: Long): String {
        val ago = today - day
        if (ago == 1L) return "Yesterday"
        val cal = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -ago.toInt()) }
        return if (ago < 7) {
            cal.getDisplayName(Calendar.DAY_OF_WEEK, Calendar.SHORT, Locale.ENGLISH) ?: ""
        } else {
            "${cal.getDisplayName(Calendar.MONTH, Calendar.SHORT, Locale.ENGLISH)} " +
                "${cal.get(Calendar.DAY_OF_MONTH)}"
        }
    }

    private fun ordinal(n: Int): String {
        val teen = n % 100 in 11..13
        val suffix = if (teen) "th" else when (n % 10) {
            1 -> "st"
            2 -> "nd"
            3 -> "rd"
            else -> "th"
        }
        return "$n$suffix"
    }

    override fun getLoadingView(): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_today_item)

    override fun getItemId(position: Int): Long {
        if (position == 0) return -1L
        val item = items.getOrNull(position - 1) ?: return -2L
        val occurrence = items.subList(0, position - 1)
            .count { it.id == item.id && it.text == item.text }
        return "${item.id}:${item.text}:$occurrence".hashCode().toLong()
    }

    override fun hasStableIds(): Boolean = true

}
