package com.z4yed.typed

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import org.json.JSONObject

class RecentNotesRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        RecentNotesFactory(applicationContext)
}

private class RecentNotesFactory(
    private val context: Context,
) : RemoteViewsService.RemoteViewsFactory {
    private data class Item(val id: String, val title: String, val preview: String)

    private var items = emptyList<Item>()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val prefs = context.getSharedPreferences(WidgetHelper.PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.widget_recent_v1", null)
        val json = try { JSONArray(raw ?: "[]") } catch (_: Exception) { JSONArray() }
        items = (0 until minOf(json.length(), 8)).mapNotNull { index ->
            val item = when {
                json.optJSONObject(index) != null -> json.optJSONObject(index)
                // Heal stale double-encoded payloads written by older builds.
                else -> try {
                    val str = json.optString(index)
                    if (str.isBlank()) null else JSONObject(str)
                } catch (_: Exception) {
                    null
                }
            } ?: return@mapNotNull null
            val title = item.optString("title").ifBlank {
                context.getString(R.string.widget_untitled)
            }
            Item(
                id = item.optString("id"),
                title = title,
                preview = item.optString("preview"),
            )
        }
    }

    override fun onDestroy() {
        items = emptyList()
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        // Returning null violates the RemoteViewsFactory contract; render an
        // empty row instead (unreachable in practice since getCount() and
        // getViewAt() are serialized by the adapter's executor).
        val item = items.getOrNull(position)
            ?: return RemoteViews(context.packageName, R.layout.widget_recent_item)
        return RemoteViews(context.packageName, R.layout.widget_recent_item).apply {
            setTextViewText(R.id.recent_item_title, item.title)
            setTextViewText(R.id.recent_item_preview, item.preview)
            setOnClickFillInIntent(
                R.id.recent_item_root,
                WidgetHelper.openRowFillInIntent().putExtra(WidgetHelper.EXTRA_NOTE_ID, item.id),
            )
        }
    }

    override fun getLoadingView(): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_recent_item)

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        items.getOrNull(position)?.id?.hashCode()?.toLong() ?: position.toLong()

    override fun hasStableIds(): Boolean = true
}
