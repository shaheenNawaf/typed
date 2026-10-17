package com.z4yed.typed

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class FinanceWidget : AppWidgetProvider() {
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
        /** Below this the budget meter is dropped so the buttons never clip. */
        private const val COMPACT_HEIGHT_DP = 170

        fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = context.getSharedPreferences(WidgetHelper.PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.widget_finance_v1", null)
            val data = try { JSONObject(raw ?: "{}") } catch (_: Exception) { JSONObject() }
            // Amounts arrive pre-formatted from Dart (single source of money
            // formatting); older payloads without the text fields render blank
            // until the next app save refreshes them.
            val now = Calendar.getInstance()
            val currentMonth = now.get(Calendar.YEAR) * 12 + now.get(Calendar.MONTH)
            // Totals from a month that has ended are not this month's: show a
            // fresh-month state until the app next saves, rather than last
            // month's numbers under a stale label.
            val stale = data.has("monthIndex") && data.optInt("monthIndex") != currentMonth
            val balanceText = if (stale) "" else data.optString("balanceText")
            val empty = stale || data.optBoolean("empty", balanceText.isEmpty())
            val hasBudget = !stale && data.optBoolean("hasBudget", false)
            val progress = data.optInt("budgetPercent", 0).coerceIn(0, 100)
            val budgetOver = data.optBoolean("budgetOver", false)
            val month = if (stale) {
                SimpleDateFormat("MMM yyyy", Locale.getDefault()).format(now.time)
            } else {
                data.optString("month")
            }
            val currency = data.optString("currency")
            val monthLabel = when {
                month.isBlank() -> ""
                !stale && data.optInt("currencyCount", 1) > 1 && currency.isNotBlank() ->
                    context.getString(R.string.widget_finance_month_currency, month, currency)
                else -> context.getString(R.string.widget_finance_month_net, month)
            }
            val height = WidgetHelper.heightDp(context, manager, id)
            val compact = height != null && height < COMPACT_HEIGHT_DP

            val views = RemoteViews(context.packageName, R.layout.widget_finance).apply {
                setOnClickPendingIntent(R.id.widget_finance_root, WidgetHelper.financeIntent(context))
                setOnClickPendingIntent(R.id.widget_finance_expense, WidgetHelper.expenseIntent(context))
                setOnClickPendingIntent(R.id.widget_finance_income, WidgetHelper.incomeIntent(context))
                setTextViewText(R.id.widget_finance_month, monthLabel)
                setTextViewText(R.id.widget_finance_balance, balanceText)
                setViewVisibility(
                    R.id.widget_finance_totals,
                    if (stale) View.GONE else View.VISIBLE,
                )
                setTextViewText(
                    R.id.widget_finance_income_value,
                    context.getString(R.string.widget_income_value, data.optString("incomeText")),
                )
                setTextViewText(
                    R.id.widget_finance_expense_value,
                    context.getString(R.string.widget_expense_value, data.optString("expenseText")),
                )
                val category = data.optString("budgetCategory")
                setTextViewText(
                    R.id.widget_finance_budget_label,
                    when {
                        // Android and iOS return the empty string (not null) for a
                        // missing key; isNullOrBlank covers both plus blank data.
                        category.isNullOrBlank() -> context.getString(R.string.widget_budget_default)
                        budgetOver -> context.getString(R.string.widget_budget_over, category)
                        else -> category
                    },
                )
                // Always set: hosts reapply RemoteViews onto the existing view
                // tree, so a color set only in the over-budget branch stayed
                // red after spending dropped back under the limit.
                setTextColor(
                    R.id.widget_finance_budget_label,
                    ContextCompat.getColor(
                        context,
                        if (budgetOver) R.color.widget_accent else R.color.widget_muted,
                    ),
                )
                val spent = data.optString("budgetSpentText")
                val limit = data.optString("budgetLimitText")
                setTextViewText(
                    R.id.widget_finance_budget_amount,
                    if (spent.isNotBlank() && limit.isNotBlank()) {
                        context.getString(R.string.widget_budget_amount, spent, limit)
                    } else {
                        ""
                    },
                )
                setProgressBar(R.id.widget_finance_budget_progress, 100, progress, false)
                setViewVisibility(
                    R.id.widget_finance_budget_group,
                    if (hasBudget && !compact) View.VISIBLE else View.GONE,
                )
                setTextViewText(
                    R.id.widget_finance_empty,
                    when {
                        stale -> context.getString(R.string.widget_finance_new_month)
                        empty -> context.getString(R.string.widget_finance_empty)
                        else -> ""
                    },
                )
            }
            manager.updateAppWidget(id, views)
        }
    }
}
