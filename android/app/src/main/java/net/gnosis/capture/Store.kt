package net.gnosis.capture

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** 書いた 1 件。Gnosis では 1 件 = 1 ノート（日記トピックは日記の本文に時刻つきで入る）。 */
data class Entry(
    val id: String,              // Gnosis のファイル名（拡張子なし）。yyMMddHHmmss（重なれば -2, -3 …）
    val created: Long,
    val topic: String,
    val text: String,
    val images: List<String> = emptyList(),   // アプリの images/ の中のファイル名
    val parent: String? = null,  // Branch の親（スマホで書いたものの id）
    val contexts: List<String> = emptyList(), // Context（スマホで書いたものの id）
    val exported: Boolean = false,
    val edited: Long = 0,
)

data class Settings(
    val alarmOn: Boolean = false,
    val alarmMinutes: Int = 60,
    val fromHour: Int = 9,
    val toHour: Int = 23,
    val topics: List<String> = listOf(DIARY, "メモ"),
    val lastTopic: String = DIARY,
)

const val DIARY = "日記"

/** データはアプリの中だけ（entries.json と images/）。書き出すまで外には出さない。 */
class Store(private val ctx: Context) {
    private val file get() = File(ctx.filesDir, "entries.json")
    private val settingsFile get() = File(ctx.filesDir, "settings.json")
    val imageDir: File get() = File(ctx.filesDir, "images").apply { mkdirs() }

    fun load(): List<Entry> {
        if (!file.exists()) return emptyList()
        val arr = JSONArray(file.readText())
        return (0 until arr.length()).map { fromJson(arr.getJSONObject(it)) }
    }

    fun save(list: List<Entry>) {
        val arr = JSONArray()
        list.forEach { arr.put(toJson(it)) }
        val tmp = File(ctx.filesDir, "entries.json.tmp")
        tmp.writeText(arr.toString())
        tmp.renameTo(file)
    }

    fun loadSettings(): Settings {
        if (!settingsFile.exists()) return Settings()
        val o = JSONObject(settingsFile.readText())
        val topics = o.optJSONArray("topics")?.let { a -> (0 until a.length()).map { a.getString(it) } }
        return Settings(
            alarmOn = o.optBoolean("alarmOn", false),
            alarmMinutes = o.optInt("alarmMinutes", 60).coerceAtLeast(1),
            fromHour = o.optInt("fromHour", 9),
            toHour = o.optInt("toHour", 23),
            topics = if (topics.isNullOrEmpty()) Settings().topics else topics,
            lastTopic = o.optString("lastTopic", DIARY),
        )
    }

    fun saveSettings(s: Settings) {
        val o = JSONObject()
        o.put("alarmOn", s.alarmOn); o.put("alarmMinutes", s.alarmMinutes)
        o.put("fromHour", s.fromHour); o.put("toHour", s.toHour)
        o.put("topics", JSONArray(s.topics)); o.put("lastTopic", s.lastTopic)
        settingsFile.writeText(o.toString())
    }

    companion object {
        private val idFmt = SimpleDateFormat("yyMMddHHmmss", Locale.US)

        fun newId(time: Long, existing: Collection<Entry>): String {
            val base = idFmt.format(Date(time))
            val used = existing.map { it.id }.toSet()
            if (base !in used) return base
            var n = 2
            while ("$base-$n" in used) n++
            return "$base-$n"
        }

        fun toJson(e: Entry): JSONObject = JSONObject().apply {
            put("id", e.id); put("created", e.created); put("topic", e.topic); put("text", e.text)
            put("images", JSONArray(e.images)); put("parent", e.parent ?: JSONObject.NULL)
            put("contexts", JSONArray(e.contexts)); put("exported", e.exported); put("edited", e.edited)
        }

        fun fromJson(o: JSONObject): Entry {
            fun strs(k: String) = o.optJSONArray(k)?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
            return Entry(
                id = o.getString("id"), created = o.getLong("created"), topic = o.optString("topic", DIARY),
                text = o.optString("text", ""), images = strs("images"),
                parent = if (o.isNull("parent")) null else o.optString("parent").ifEmpty { null },
                contexts = strs("contexts"), exported = o.optBoolean("exported", false), edited = o.optLong("edited", 0),
            )
        }
    }
}
