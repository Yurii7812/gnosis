package net.gnosis.capture

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

/**
 * PC の Gnosis から渡される予定（未完了のタスク）。`files/agenda.tsv`（python/agenda_push.py が USB で書く）を読む。
 * Android のフレームワークに依存しない純粋なロジック（単体試験できる）。通知・ウィジェット・画面はこれを使う。
 *
 *   # gnosis-agenda v1
 *   generated<TAB>2026-10-21T07:00
 *   task<TAB>キー<TAB>期限<TAB>時刻<TAB>優先度<TAB>ノートの題<TAB>本文
 */
data class AgendaTask(val key: String, val due: String, val time: String, val priority: String, val note: String, val text: String)
data class AgendaData(val generated: String, val tasks: List<AgendaTask>)
data class AgendaBuckets(val overdue: List<AgendaTask>, val today: List<AgendaTask>, val soon: List<AgendaTask>, val later: List<AgendaTask>, val undated: List<AgendaTask>) {
    val urgent get() = overdue.size + today.size
    val all get() = overdue + today + soon + later + undated
}

object Agenda {
    const val HEADER = "# gnosis-agenda v1"
    private val KEY = Regex("^[0-9a-f]{10}$")
    private val DATE = Regex("^\\d{4}-\\d{2}-\\d{2}$")
    private val TIME = Regex("^([01]\\d|2[0-3]):[0-5]\\d$")
    private val STAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")

    private fun date(s: String): LocalDate? = if (DATE.matches(s)) try { LocalDate.parse(s) } catch (_: DateTimeParseException) { null } else null

    /** 先頭の印が違う・壊れているファイルは null。壊れた行（列が足りない・キーや日付の形が違う）は捨てて、読める行だけ返す。 */
    fun parse(text: String): AgendaData? {
        val lines = text.replace("\r\n", "\n").split("\n")
        if (lines.firstOrNull() != HEADER) return null
        var generated = ""
        val tasks = ArrayList<AgendaTask>()
        for (ln in lines.drop(1)) {
            val f = ln.split("\t")
            when {
                f[0] == "generated" && f.size >= 2 -> generated = f[1]
                f[0] == "task" && f.size >= 7 && KEY.matches(f[1]) && (f[2].isEmpty() || date(f[2]) != null) && (f[3].isEmpty() || TIME.matches(f[3])) && f[6].isNotBlank() ->
                    tasks.add(AgendaTask(f[1], f[2], f[3], f[4], f[5], f[6]))
            }
        }
        return AgendaData(generated, tasks)
    }

    /** 期限（無ければ予定日）で、期限切れ・今日・soonDays 日以内・それ以降・期限なしに分ける。入力の順序（PC が期限順に並べてある）を保つ。 */
    fun bucket(tasks: List<AgendaTask>, today: LocalDate, soonDays: Long = 7): AgendaBuckets {
        val o = ArrayList<AgendaTask>(); val t = ArrayList<AgendaTask>(); val s = ArrayList<AgendaTask>(); val l = ArrayList<AgendaTask>(); val u = ArrayList<AgendaTask>()
        val soonEnd = today.plusDays(soonDays)
        for (k in tasks) {
            val d = date(k.due)
            when {
                d == null -> u.add(k)
                d.isBefore(today) -> o.add(k)
                d == today -> t.add(k)
                !d.isAfter(soonEnd) -> s.add(k)
                else -> l.add(k)
            }
        }
        return AgendaBuckets(o, t, s, l, u)
    }

    fun summary(b: AgendaBuckets): String {
        val parts = ArrayList<String>()
        if (b.overdue.isNotEmpty()) parts.add("期限切れ ${b.overdue.size}")
        if (b.today.isNotEmpty()) parts.add("今日 ${b.today.size}")
        if (b.soon.isNotEmpty()) parts.add("7 日以内 ${b.soon.size}")
        return if (parts.isEmpty()) "予定はありません" else parts.joinToString("・")
    }

    /** 朝の通知の文面。期限切れと今日が 1 件も無ければ null（通知を出さない）。本文は上位 3 件。 */
    fun morningMessage(data: AgendaData, today: LocalDate): Pair<String, String>? {
        val b = bucket(data.tasks, today)
        if (b.urgent == 0) return null
        val head = (b.overdue + b.today).take(3).joinToString("\n") { (if (it.due < today.toString() && it.due.isNotEmpty()) "⚠ " else "・") + it.text }
        val more = b.urgent - 3
        return "今日の予定 ${b.today.size} 件" + (if (b.overdue.isNotEmpty()) "・期限切れ ${b.overdue.size} 件" else "") to
            (head + if (more > 0) "\nほか $more 件" else "")
    }

    /** PC から届いたデータの古さ（日）。壊れていれば null。長く更新されていなければ画面で知らせる。 */
    fun staleDays(data: AgendaData, now: LocalDateTime): Long? = try {
        java.time.Duration.between(LocalDateTime.parse(data.generated, STAMP), now).toDays().coerceAtLeast(0)
    } catch (_: DateTimeParseException) { null }

    /** ウィジェット・クイック追加から作るタスクの 1 行（PC の取り込みでそのままタスクになる）。空なら null。 */
    fun quickTaskLine(text: String, due: LocalDate?, high: Boolean = false): String? {
        val t = text.replace(Regex("[\\t\\r\\n]+"), " ").trim().removePrefix("- [ ]").trim()
        if (t.isEmpty()) return null
        return "- [ ] $t" + (if (due != null) " 📅 $due" else "") + (if (high) " ⏫" else "")
    }

    /** 「完了」の記録 1 行。PC（agenda_pull.py）が読む。 */
    fun doneLine(key: String, at: LocalDateTime): String? = if (KEY.matches(key)) "done\t$key\t${at.format(STAMP)}" else null

    /** 次の朝の通知の時刻。今がちょうどその時刻なら次の日（同じ時刻に二度鳴らさない）。 */
    fun nextMorning(hour: Int, minute: Int, now: LocalDateTime): LocalDateTime {
        val at = now.toLocalDate().atTime(LocalTime.of(hour.coerceIn(0, 23), minute.coerceIn(0, 59)))
        return if (at.isAfter(now)) at else at.plusDays(1)
    }

    /** 今日の、時刻つきで、まだ先のタスク（時刻順）。時刻の直前に出す通知の予定に使う。 */
    fun timedToday(tasks: List<AgendaTask>, today: LocalDate, now: LocalDateTime, limit: Int = 20): List<Pair<LocalDateTime, AgendaTask>> =
        tasks.filter { it.due == today.toString() && TIME.matches(it.time) }
            .map { LocalDateTime.of(today, LocalTime.parse(it.time)) to it }
            .filter { it.first.isAfter(now) }
            .sortedBy { it.first }.take(limit)

    fun snoozeAt(now: LocalDateTime, minutes: Int): LocalDateTime = now.plusMinutes(minutes.coerceIn(1, 24 * 60).toLong())
}
