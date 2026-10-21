package net.gnosis.capture

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

/**
 * カレンダーの画面の計算（Android に依存しない純粋なロジック。CalendarModelTest で試験する）。
 * 日ごとに、スマホで書いたメモ（日記トピックとそれ以外）と、PC から届いた期限のタスクを数える。
 * 月曜はじまり（PC の Gnosis のカレンダーと同じ）。
 */
object CalendarModel {
    data class Day(val memos: Int = 0, val diary: Int = 0, val tasks: Int = 0)

    /** 月の表のマス。前後の空きは null。7 の倍数の長さ。 */
    fun cells(ym: YearMonth): List<LocalDate?> {
        val first = ym.atDay(1)
        val lead = (first.dayOfWeek.value - DayOfWeek.MONDAY.value + 7) % 7
        val out = ArrayList<LocalDate?>()
        repeat(lead) { out.add(null) }
        for (d in 1..ym.lengthOfMonth()) out.add(ym.atDay(d))
        while (out.size % 7 != 0) out.add(null)
        return out
    }

    fun dateOf(created: Long, zone: ZoneId = ZoneId.systemDefault()): LocalDate = Instant.ofEpochMilli(created).atZone(zone).toLocalDate()

    /** 月の日ごとの数。メモは書いた日（日付を指定して書いたものはその日）、タスクは期限の日。 */
    fun month(ym: YearMonth, entries: List<Entry>, tasks: List<AgendaTask>, zone: ZoneId = ZoneId.systemDefault()): Map<LocalDate, Day> {
        val out = HashMap<LocalDate, Day>()
        for (e in entries) {
            val d = dateOf(e.created, zone)
            if (YearMonth.from(d) != ym) continue
            val c = out[d] ?: Day()
            out[d] = if (e.topic == DIARY) c.copy(memos = c.memos + 1, diary = c.diary + 1) else c.copy(memos = c.memos + 1)
        }
        for (t in tasks) {
            val d = runCatching { LocalDate.parse(t.due) }.getOrNull() ?: continue
            if (YearMonth.from(d) != ym) continue
            val c = out[d] ?: Day()
            out[d] = c.copy(tasks = c.tasks + 1)
        }
        return out
    }

    /** その日に書いたメモ（古い順）。 */
    fun memosOn(entries: List<Entry>, day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): List<Entry> =
        entries.filter { dateOf(it.created, zone) == day }.sortedBy { it.created }

    /** その日が期限のタスク（時刻のあるものは時刻順、無いものは後ろ）。 */
    fun tasksOn(tasks: List<AgendaTask>, day: LocalDate): List<AgendaTask> =
        tasks.filter { it.due == day.toString() }.sortedWith(compareBy({ it.time.isEmpty() }, { it.time }))

    /** その日の 0 時（端末の時刻帯）。メモ帳の「日付を指定して書く」と同じ値。 */
    fun startOfDay(day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): Long = day.atStartOfDay(zone).toInstant().toEpochMilli()
}
