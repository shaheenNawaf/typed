package com.z4yed.typed

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

class FinanceWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, manager, it) }
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
        fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = context.getSharedPreferences(WidgetHelper.PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.widget_finance_v1", null)
            val data = try { JSONObject(raw ?: "{}") } catch (_: Exception) { JSONObject() }
        // Amounts arrive pre-formatted from Dart (single source of money
        // formatting); older payloads without the text fields render blank
        // until the next app save refreshes them.
        val balanceText = data.optString("balanceText")
        val incomeText = data.optString("incomeText")
        val expenseText = data.optString("expenseText")
        val empty = data.optBoolean("empty", balanceText.isEmpty())
        val hasBudget = data.optBoolean("hasBudget", false)
        val progress = data.optInt("budgetPercent", 0).coerceIn(0, 100)
        val budgetOver = data.optBoolean("budgetOver", false)

        val views = RemoteViews(context.packageName, R.layout.widget_finance).apply {
            setOnClickPendingIntent(R.id.widget_finance_root, WidgetHelper.financeIntent(context))
            setOnClickPendingIntent(R.id.widget_finance_expense, WidgetHelper.expenseIntent(context))
            setOnClickPendingIntent(R.id.widget_finance_income, WidgetHelper.incomeIntent(context))
            setTextViewText(R.id.widget_finance_month, data.optString("month"))
            setTextViewText(R.id.widget_finance_balance, balanceText)
            setTextViewText(
                R.id.widget_finance_income_value,
                context.getString(R.string.widget_income_value, incomeText),
            )
            setTextViewText(
                R.id.widget_finance_expense_value,
                context.getString(R.string.widget_expense_value, expenseText),
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
            if (budgetOver) {
                setTextColor(
                    R.id.widget_finance_budget_label,
                    androidx.core.content.ContextCompat.getColor(context, R.color.widget_accent),
                )
            }
            setProgressBar(R.id.widget_finance_budget_progress, 100, progress, false)
            setViewVisibility(
                R.id.widget_finance_budget_group,
                if (hasBudget) View.VISIBLE else View.GONE,
            )
            setTextViewText(
                R.id.widget_finance_empty,
                if (empty) context.getString(R.string.widget_finance_empty) else "",
            )
        }
            manager.updateAppWidget(id, views)
        }
    }
}
