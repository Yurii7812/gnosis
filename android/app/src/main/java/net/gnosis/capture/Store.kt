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
    val topics: List<String> = listOf(DIARY),
    val lastTopic: String = ALL,
    val topicModes: Map<String, TopicMode> = emptyMap(),
)

/**
 * トピックの取り込み方（日記以外）。single = PC に取り込むとこのトピックの 1 つのノートに追記する
 * （1 件 = 1 ノートにしない）。stamp = 追記するとき時刻を付け、日が替わったら日付の見出しを入れる。
 * record = 時系列記録（PC の :GnosisRecordNew と同じ。日記のように、その日のノート「2026-10-19-MO-夢」に時刻つきで入る）。
 * single と record は同時に使わない（record が優先）。
 */
data class TopicMode(val single: Boolean = false, val stamp: Boolean = true, val record: Boolean = false)

const val DIARY = "日記"
const val ALL = "__all__"
const val UNASSIGNED = ""
fun normalizedTopic(topic: String) = if (topic == "メモ") UNASSIGNED else topic
fun topicLabel(topic: String) = when (topic) {
    ALL -> "全部"
    UNASSIGNED -> "未所属"
    else -> topic
}
fun visibleEntries(entries: List<Entry>, topic: String) = entries.filter { topic == ALL || it.topic == topic }
fun writingTopic(topic: String) = if (topic == ALL) UNASSIGNED else topic

/** 検索用に揃える: 全角・半角（NFKC）、大文字・小文字、カタカナ→ひらがな。 */
fun searchKey(s: String): String {
    val n = java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFKC).lowercase()
    val b = StringBuilder(n.length)
    for (c in n) b.append(if (c in 'ァ'..'ヶ') c - 0x60 else c)
    return b.toString()
}

/** 空白（全角・半角）で区切った語をすべて含むか（順番は問わない）。空の検索はすべてに当たる。 */
fun matchesQuery(text: String, query: String): Boolean {
    val terms = searchKey(query).split(Regex("\\s+")).filter { it.isNotEmpty() }
    if (terms.isEmpty()) return true
    val t = searchKey(text)
    return terms.all { it in t }
}

/**
 * データはアプリの中だけ（entries.json と images/）。共有フォルダには置かない。
 * PC の Gnosis が USB（adb の run-as）で直接読み、取り込んだ id を imported.json に書き戻す。
 */
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
        check(tmp.renameTo(file)) { "メモを保存できませんでした" }
    }

    /** PC の Gnosis が取り込んだ id（PC が書き戻す）。 */
    fun importedIds(): Set<String> {
        val f = File(ctx.filesDir, "imported.json")
        if (!f.exists()) return emptySet()
        return try {
            val imported = JSONObject(f.readText()).optJSONArray("entries") ?: return emptySet()
            val current = load().associateBy { it.id }
            (0 until imported.length()).mapNotNull { i ->
                val old = fromJson(imported.getJSONObject(i))
                val now = current[old.id]
                if (now != null && old.copy(edited = 0, exported = false) == now.copy(edited = 0, exported = false)) old.id else null
            }.toSet()
        } catch (e: Exception) { emptySet() }
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
            topics = (listOf(DIARY) + (topics ?: emptyList()).map(::normalizedTopic)).filter { it.isNotEmpty() && it != ALL }.distinct(),
            lastTopic = o.optString("lastTopic", ALL).let { if (it == ALL) ALL else normalizedTopic(it) },
            topicModes = o.optJSONObject("topicModes")?.let { m ->
                m.keys().asSequence().filter { it.isNotEmpty() && it != DIARY }.associateWith { k ->
                    val t = m.getJSONObject(k); TopicMode(t.optBoolean("single", false), t.optBoolean("stamp", true), t.optBoolean("record", false))
                }
            } ?: emptyMap(),
        )
    }

    fun saveSettings(s: Settings) {
        val o = JSONObject()
        o.put("alarmOn", s.alarmOn); o.put("alarmMinutes", s.alarmMinutes)
        o.put("fromHour", s.fromHour); o.put("toHour", s.toHour)
        o.put("topics", JSONArray(s.topics)); o.put("lastTopic", s.lastTopic)
        // PC の取り込み（\M）もこのファイルを読む（topicModes）
        val modes = JSONObject()
        s.topicModes.forEach { (k, v) -> modes.put(k, JSONObject().put("single", v.single).put("stamp", v.stamp).put("record", v.record)) }
        o.put("topicModes", modes)
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
                id = o.getString("id"), created = o.getLong("created"), topic = normalizedTopic(o.optString("topic", UNASSIGNED)),
                text = o.optString("text", ""), images = strs("images"),
                parent = if (o.isNull("parent")) null else o.optString("parent").ifEmpty { null },
                contexts = strs("contexts"), exported = o.optBoolean("exported", false), edited = o.optLong("edited", 0),
            )
        }
    }
}
