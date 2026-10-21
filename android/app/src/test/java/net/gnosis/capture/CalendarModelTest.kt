package net.gnosis.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

class CalendarModelTest {
    private val tokyo = ZoneId.of("Asia/Tokyo")
    private fun at(s: String) = java.time.LocalDateTime.parse(s).atZone(tokyo).toInstant().toEpochMilli()
    private fun task(due: String, time: String = "", text: String = "t") = AgendaTask("0123456789", due, time, "", "ノート", text)

    @Test fun cellsStartOnMonday() {
        val c = CalendarModel.cells(YearMonth.of(2026, 10))   // 2026-10-01 は木曜
        assertEquals(0, c.size % 7)
        assertNull(c[0]); assertNull(c[2])
        assertEquals(LocalDate.of(2026, 10, 1), c[3])
        assertEquals(LocalDate.of(2026, 10, 31), c.filterNotNull().last())
        assertEquals(31, c.filterNotNull().size)
        // 月曜はじまりの月は前の空きが無い
        assertEquals(LocalDate.of(2026, 6, 1), CalendarModel.cells(YearMonth.of(2026, 6))[0])
    }

    @Test fun countsMemosAndTasksPerDay() {
        val es = listOf(
            Entry("a", at("2026-10-19T07:00"), DIARY, "起きた"),
            Entry("b", at("2026-10-19T23:59"), "仕事", "メモ"),
            Entry("c", at("2026-10-20T00:01"), "", "次の日"),
            Entry("d", at("2026-09-30T12:00"), "", "前の月"),
        )
        val ts = listOf(task("2026-10-19", "09:30"), task("2026-10-25"), task(""), task("2026-11-01"))
        val m = CalendarModel.month(YearMonth.of(2026, 10), es, ts, tokyo)
        assertEquals(CalendarModel.Day(memos = 2, diary = 1, tasks = 1), m[LocalDate.of(2026, 10, 19)])
        assertEquals(CalendarModel.Day(memos = 1), m[LocalDate.of(2026, 10, 20)])
        assertEquals(CalendarModel.Day(tasks = 1), m[LocalDate.of(2026, 10, 25)])
        assertNull(m[LocalDate.of(2026, 9, 30)])
        assertEquals(3, m.size)
    }

    @Test fun dayLists() {
        val es = listOf(Entry("b", at("2026-10-19T20:00"), "", "夜"), Entry("a", at("2026-10-19T08:00"), "", "朝"), Entry("c", at("2026-10-18T08:00"), "", "前の日"))
        assertEquals(listOf("a", "b"), CalendarModel.memosOn(es, LocalDate.of(2026, 10, 19), tokyo).map { it.id })
        val ts = listOf(task("2026-10-19", "", "終日"), task("2026-10-19", "18:00", "夕方"), task("2026-10-19", "09:00", "朝"), task("2026-10-20"))
        assertEquals(listOf("朝", "夕方", "終日"), CalendarModel.tasksOn(ts, LocalDate.of(2026, 10, 19)).map { it.text })
        assertEquals(at("2026-10-19T00:00"), CalendarModel.startOfDay(LocalDate.of(2026, 10, 19), tokyo))
    }
}
