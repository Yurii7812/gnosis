package net.gnosis.capture

import org.junit.Assert.*
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

class CaptureTest {
    private val entries = listOf(
        Entry("1", 1, UNASSIGNED, "そのまま\n本文"),
        Entry("2", 2, DIARY, "日記"),
        Entry("3", 3, "仕事", "仕事のメモ"),
    )

    @Test fun filterAndComposeDestination() {
        assertEquals(entries, visibleEntries(entries, ALL))
        assertEquals(listOf(entries[0]), visibleEntries(entries, UNASSIGNED))
        assertEquals(listOf(entries[1]), visibleEntries(entries, DIARY))
        assertEquals(listOf(entries[2]), visibleEntries(entries, "仕事"))
        assertEquals(emptyList<Entry>(), visibleEntries(entries, "空のトピック"))
        assertEquals(UNASSIGNED, writingTopic(ALL))
        assertEquals(UNASSIGNED, writingTopic(UNASSIGNED))
        assertEquals("仕事", writingTopic("仕事"))
        assertEquals(UNASSIGNED, normalizedTopic("メモ"))
    }

    private fun at(day: Int, hour: Int, minute: Int = 0): Long = Calendar.getInstance().apply {
        clear(); set(2026, Calendar.OCTOBER, day, hour, minute)
    }.timeInMillis

    @Test fun regularHoursOvernightAndFullDay() {
        val original = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Tokyo"))
        try {
            assertEquals(at(19, 11), AlarmTiming.next(60, 9, 23, at(19, 10)))
            assertEquals(at(20, 9), AlarmTiming.next(60, 9, 23, at(19, 22, 30)))
            assertEquals(at(19, 9), AlarmTiming.next(60, 9, 23, at(19, 6)))
            assertEquals(at(20, 0, 30), AlarmTiming.next(60, 0, 24, at(19, 23, 30)))
            assertEquals(at(19, 13), AlarmTiming.next(60, 1, 1, at(19, 12)))
            assertEquals(at(19, 22), AlarmTiming.next(60, 22, 6, at(19, 12)))
            assertEquals(at(19, 22), AlarmTiming.next(60, 22, 6, at(19, 5, 30)))
            assertEquals(at(20, 1), AlarmTiming.next(60, 22, 6, at(20, 0)))
            assertFalse(AlarmTiming.inside(9, 23, 23))
            assertTrue(AlarmTiming.inside(22, 6, 2))
            assertFalse(AlarmTiming.inside(22, 6, 12))
            assertTrue(AlarmTiming.inside(0, 24, 0))
            assertTrue(AlarmTiming.inside(1, 1, 12))
        } finally { TimeZone.setDefault(original) }
    }
}
