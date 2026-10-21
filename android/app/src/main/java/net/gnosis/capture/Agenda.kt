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
data class AgendaTask(val key: String, val due: String, val time: String, val priority: String, val note: String, val text: String,
                      val duration: Int = 0, val reminds: String = "", val repeat: String = "")

/** 1 つのタスクの日時・通知などの設定（Google カレンダーの予定のように）。reminds は "" = 時刻ちょうど・"none" = 通知なし・"1d,10m" = 期限の 1 日前と 10 分前。 */
data class TaskSpec(val due: String = "", val time: String = "", val duration: Int = 0, val reminds: String = "", val repeat: String = "", val priority: String = "")
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
    private val REMINDS = Regex("^\\d+[mhd](,\\d+[mhd])*$")
    private val REPEAT = Regex("^(daily|weekly|monthly|yearly|weekday|every \\d+ (days|weeks|months|years))$")
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
                    // 8 列目以降(所要時間・通知・繰り返し)は無くてもよい(古い PC の送る v1)。読めない値は既定に戻す
                    tasks.add(AgendaTask(f[1], f[2], f[3], f[4], f[5], f[6], f.getOrNull(7)?.toIntOrNull()?.takeIf { it in 0..10080 } ?: 0,
                        f.getOrNull(8)?.takeIf { it == "none" || REMINDS.matches(it) } ?: "", f.getOrNull(9)?.takeIf { REPEAT.matches(it) } ?: ""))
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

    // ---- 日時・所要時間・通知・繰り返し（PC の python/tasks.py と同じ書き方。共通の例は AgendaTest と test_tasks.py） ----
    data class Alarm(val at: LocalDateTime, val task: AgendaTask, val offset: Int)

    fun fmtDuration(m: Int): String = when { m <= 0 -> ""; m % 60 == 0 -> "${m / 60}h"; m > 60 -> "${m / 60}h${m % 60}m"; else -> "${m}m" }
    fun fmtOffset(m: Int): String = when { m > 0 && m % 1440 == 0 -> "${m / 1440}d"; m > 0 && m % 60 == 0 -> "${m / 60}h"; else -> "${m}m" }
    private fun parseOffset(v: String): Int? {
        val n = v.dropLast(1).toIntOrNull() ?: return null
        return when (v.lastOrNull()) { 'm' -> n; 'h' -> n * 60; 'd' -> n * 1440; else -> null }
    }
    /** "1d,10m" → [1440, 10]（大きい順・重複なし）。"" と none は空。正しくなければ null。 */
    fun parseReminds(r: String): List<Int>? {
        if (r.isEmpty() || r == "none") return emptyList()
        if (!REMINDS.matches(r)) return null
        return r.split(",").map { parseOffset(it) ?: return null }.distinct().sortedDescending()
    }
    /** 画面の選択肢から書く形（正規化）。 */
    fun remindsText(offsets: List<Int>): String = offsets.distinct().sortedDescending().joinToString(",") { fmtOffset(it) }

    /** 実際に知らせる、期限の何分前か。"" は時刻ちょうど（0）、none は知らせない。 */
    fun remindOffsets(t: AgendaTask): List<Int> = if (t.reminds.isEmpty()) listOf(0) else parseReminds(t.reminds) ?: listOf(0)

    fun offsetLabel(m: Int): String = when {
        m <= 0 -> "時刻ちょうど"
        m % 1440 == 0 -> "${m / 1440} 日前"
        m % 60 == 0 -> "${m / 60} 時間前"
        else -> "$m 分前"
    }

    private fun validSpec(s: TaskSpec): Boolean =
        (s.due.isEmpty() || date(s.due) != null) && (s.time.isEmpty() || (s.due.isNotEmpty() && TIME.matches(s.time))) && s.duration in 0..10080 &&
            (s.reminds == "none" || s.reminds.isEmpty() || (parseReminds(s.reminds) != null)) && (s.repeat.isEmpty() || REPEAT.matches(s.repeat)) && s.priority in listOf("", "high", "medium", "low")

    /** タスクの行(`- [ ] 本文 📅 日付 時刻 ⌛ 1h 🔔 1d,10m 🔁 weekly ⏫`)。本文が空・設定が正しくなければ null。PC の取り込み(\\M)でそのままタスクになる。 */
    fun taskLine(text: String, spec: TaskSpec): String? {
        val t = text.replace(Regex("[\\t\\r\\n]+"), " ").trim().removePrefix("- [ ]").trim()
        if (t.isEmpty() || !validSpec(spec)) return null
        val sb = StringBuilder("- [ ] ").append(t)
        if (spec.due.isNotEmpty()) sb.append(" 📅 ").append(spec.due).append(if (spec.time.isNotEmpty()) " " + spec.time else "")
        if (spec.duration > 0) sb.append(" ⌛ ").append(fmtDuration(spec.duration))
        if (spec.reminds.isNotEmpty()) sb.append(" 🔔 ").append(if (spec.reminds == "none") "none" else remindsText(parseReminds(spec.reminds)!!))
        if (spec.repeat.isNotEmpty()) sb.append(" 🔁 ").append(spec.repeat)
        when (spec.priority) { "high" -> sb.append(" ⏫"); "medium" -> sb.append(" 🔼"); "low" -> sb.append(" 🔽") }
        return sb.toString()
    }

    /** PC へ渡す編集の 1 行（agenda-edit.tsv）。PC の agenda_pull.py が、キーが一致する未完了のタスクの日時・通知などの印だけを書き換える。 */
    fun editLine(key: String, spec: TaskSpec): String? {
        if (!KEY.matches(key) || !validSpec(spec)) return null
        val rem = if (spec.reminds.isEmpty() || spec.reminds == "none") spec.reminds else remindsText(parseReminds(spec.reminds)!!)
        return listOf("edit", key, spec.due, if (spec.due.isEmpty()) "" else spec.time, if (spec.duration > 0) spec.duration.toString() else "", rem, spec.repeat, spec.priority).joinToString("\t")
    }

    /** 保存した編集を、手元の予定に先に反映する（PC が反映して送り直すまでの間も、画面と通知が新しい設定になる）。 */
    fun applyEdit(tasks: List<AgendaTask>, key: String, spec: TaskSpec): List<AgendaTask> {
        if (!validSpec(spec)) return tasks
        val rem = if (spec.reminds.isEmpty() || spec.reminds == "none") spec.reminds else remindsText(parseReminds(spec.reminds)!!)
        return tasks.map { if (it.key == key) it.copy(due = spec.due, time = if (spec.due.isEmpty()) "" else spec.time, duration = spec.duration, reminds = rem, repeat = spec.repeat, priority = spec.priority) else it }
    }

    fun specOf(t: AgendaTask) = TaskSpec(t.due, t.time, t.duration, t.reminds, t.repeat, t.priority)

    fun toTsv(d: AgendaData): String {
        val sb = StringBuilder(HEADER).append("\ngenerated\t").append(d.generated).append("\n")
        for (t in d.tasks) sb.append(listOf("task", t.key, t.due, t.time, t.priority, t.note, t.text, if (t.duration > 0) t.duration.toString() else "", t.reminds, t.repeat).joinToString("\t")).append("\n")
        return sb.toString()
    }

    /**
     * これから知らせる時刻の一覧（horizonHours 時間先まで・近い順・limit 件）。時刻つきのタスクは、設定した通知（既定は時刻ちょうど）の分だけ。
     * 日付だけのタスクは、通知を指定したときだけ、その日の 9 時を基準にする（指定が無ければ朝のまとめだけ）。
     */
    fun alarmPlan(tasks: List<AgendaTask>, now: LocalDateTime, horizonHours: Long = 48, limit: Int = 20): List<Alarm> {
        val end = now.plusHours(horizonHours)
        val out = ArrayList<Alarm>()
        for (t in tasks) {
            val d = date(t.due) ?: continue
            val base = if (TIME.matches(t.time)) LocalDateTime.of(d, LocalTime.parse(t.time)) else if (t.reminds.isNotEmpty() && t.reminds != "none") d.atTime(9, 0) else continue
            for (off in remindOffsets(t)) {
                val at = base.minusMinutes(off.toLong())
                if (at.isAfter(now) && !at.isAfter(end)) out.add(Alarm(at, t, off))
            }
        }
        return out.sortedBy { it.at }.take(limit)
    }

    val SNOOZE_CHOICES = listOf(5, 10, 30, 60)
}
