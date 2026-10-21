package net.gnosis.capture

import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime

class AgendaTest {
    private val today = LocalDate.of(2026, 10, 21)
    private val now = LocalDateTime.of(2026, 10, 21, 7, 0)
    private fun t(key: String, due: String, time: String = "", text: String = "x", prio: String = "") = AgendaTask(key, due, time, prio, "ノート", text)

    private val sample = """# gnosis-agenda v1
generated	2026-10-21T07:00
task	0123456789	2026-10-19			家	電球を替える
task	00ff4958bf	2026-10-21	09:30	high	家	ゴミ出し
task	abcdef0123	2026-10-28			仕事	来週の資料
task	aaaaaaaaaa				仕事	いつか
"""

    @Test fun parseReadsTasksAndGenerated() {
        val d = Agenda.parse(sample)!!
        assertEquals("2026-10-21T07:00", d.generated)
        assertEquals(4, d.tasks.size)
        assertEquals(AgendaTask("00ff4958bf", "2026-10-21", "09:30", "high", "家", "ゴミ出し"), d.tasks[1])
        assertEquals("", d.tasks[3].due)
    }

    @Test fun parseRejectsWrongHeaderAndSkipsBrokenLines() {
        assertNull(Agenda.parse(""))
        assertNull(Agenda.parse("# gnosis-agenda v2\ngenerated\t2026-10-21T07:00\n"))
        assertNull(Agenda.parse("task\t0123456789\t\t\t\tA\tB\n"))
        val broken = Agenda.HEADER + "\n" + listOf(
            "task\tZZZZZZZZZZ\t\t\t\tA\t本文",            // キーの形が違う
            "task\t0123456789\t2026-13-45\t\t\tA\t本文",   // 存在しない日付
            "task\t0123456789\tふつう\t\t\tA\t本文",       // 日付の形が違う
            "task\t0123456789\t2026-10-21\t25:00\t\tA\t本文", // 時刻の形が違う
            "task\t0123456789\t\t\t\tA",                   // 列が足りない
            "task\t0123456789\t\t\t\tA\t   ",              // 本文が空
            "garbage",
            "task\t1111111111\t2026-10-21\t08:00\t\tA\t読める行"
        ).joinToString("\n") + "\n"
        val d = Agenda.parse(broken)!!
        assertEquals(listOf("読める行"), d.tasks.map { it.text })                                         // 壊れた行だけ捨てる
        assertEquals(Agenda.parse(Agenda.HEADER + "\r\ngenerated\t2026-10-21T07:00\r\ntask\t1111111111\t\t\t\tA\tcrlf\r\n")!!.tasks.size, 1)   // CRLF
    }

    @Test fun bucketBoundaries() {
        val tasks = listOf(t("1111111111", "2026-10-20"), t("2222222222", "2026-10-21"), t("3333333333", "2026-10-22"), t("4444444444", "2026-10-28"),
            t("5555555555", "2026-10-29"), t("6666666666", ""), t("7777777777", "2026-12-31"))
        val b = Agenda.bucket(tasks, today)
        assertEquals(listOf("1111111111"), b.overdue.map { it.key })
        assertEquals(listOf("2222222222"), b.today.map { it.key })
        assertEquals(listOf("3333333333", "4444444444"), b.soon.map { it.key })        // 7 日後(10-28)まで含む
        assertEquals(listOf("5555555555", "7777777777"), b.later.map { it.key })        // 8 日後からは「それ以降」
        assertEquals(listOf("6666666666"), b.undated.map { it.key })
        assertEquals(7, b.all.size)
        assertEquals(2, b.urgent)
        // 月末・年末をまたぐ
        val ny = Agenda.bucket(listOf(t("1111111111", "2027-01-04"), t("2222222222", "2027-01-05")), LocalDate.of(2026, 12, 28))   // 7 日後(1/4)は「7 日以内」・8 日後は「それ以降」
        assertEquals(listOf("1111111111"), ny.soon.map { it.key })
        assertEquals(listOf("2222222222"), ny.later.map { it.key })
        assertEquals(1, Agenda.bucket(listOf(t("1111111111", "2028-02-29")), LocalDate.of(2028, 2, 28)).soon.size)   // うるう日
        assertTrue(Agenda.bucket(emptyList(), today).all.isEmpty())
    }

    @Test fun summaryText() {
        val b = Agenda.bucket(listOf(t("1111111111", "2026-10-19"), t("2222222222", "2026-10-21"), t("3333333333", "2026-10-21"), t("4444444444", "2026-10-25")), today)
        assertEquals("期限切れ 1・今日 2・7 日以内 1", Agenda.summary(b))
        assertEquals("予定はありません", Agenda.summary(Agenda.bucket(emptyList(), today)))
        assertEquals("今日 1", Agenda.summary(Agenda.bucket(listOf(t("1111111111", "2026-10-21")), today)))
        assertEquals("予定はありません", Agenda.summary(Agenda.bucket(listOf(t("1111111111", "2027-05-01")), today)))   // 遠い先だけなら出さない
    }

    @Test fun morningMessageOnlyWhenSomethingIsUrgent() {
        val none = AgendaData("g", listOf(t("1111111111", "2026-10-25"), t("2222222222", "")))
        assertNull(Agenda.morningMessage(none, today))                                                    // 今日・期限切れが無ければ通知しない
        val m = Agenda.morningMessage(AgendaData("g", listOf(t("1111111111", "2026-10-19", text = "電球"), t("2222222222", "2026-10-21", text = "ゴミ出し"))), today)!!
        assertEquals("今日の予定 1 件・期限切れ 1 件", m.first)
        assertEquals("⚠ 電球\n・ゴミ出し", m.second)
        val many = AgendaData("g", (1..6).map { t("%010d".format(it), "2026-10-21", text = "t$it") })
        val mm = Agenda.morningMessage(many, today)!!
        assertEquals("今日の予定 6 件", mm.first)
        assertEquals("・t1\n・t2\n・t3\nほか 3 件", mm.second)                                              // 本文は上位 3 件・残りは件数
        val only = Agenda.morningMessage(AgendaData("g", listOf(t("1111111111", "2026-10-19", text = "遅れ"))), today)!!
        assertEquals("今日の予定 0 件・期限切れ 1 件", only.first)
    }

    @Test fun staleDays() {
        assertEquals(0L, Agenda.staleDays(AgendaData("2026-10-21T00:00", emptyList()), now))
        assertEquals(3L, Agenda.staleDays(AgendaData("2026-10-18T07:00", emptyList()), now))
        assertEquals(0L, Agenda.staleDays(AgendaData("2026-10-22T07:00", emptyList()), now))             // 未来の日付でも負にならない
        assertNull(Agenda.staleDays(AgendaData("壊れた", emptyList()), now))
        assertNull(Agenda.staleDays(AgendaData("", emptyList()), now))
    }

    @Test fun quickTaskLine() {
        assertEquals("- [ ] 牛乳を買う", Agenda.quickTaskLine("牛乳を買う", null))
        assertEquals("- [ ] 牛乳を買う 📅 2026-10-22", Agenda.quickTaskLine("  牛乳を買う \n", LocalDate.of(2026, 10, 22)))
        assertEquals("- [ ] 急ぎ 📅 2026-10-21 ⏫", Agenda.quickTaskLine("急ぎ", today, high = true))
        assertEquals("- [ ] 二行 にする", Agenda.quickTaskLine("二行\tにする", null))                        // タブ・改行は空白に(1 行のタスクにする)
        assertEquals("- [ ] 二行 目", Agenda.quickTaskLine("二行\n目", null))
        assertEquals("- [ ] すでに印あり", Agenda.quickTaskLine("- [ ] すでに印あり", null))                // 二重に印を付けない
        assertNull(Agenda.quickTaskLine("   ", today))
        assertNull(Agenda.quickTaskLine("", null))
        assertNull(Agenda.quickTaskLine("- [ ]", null))
    }

    @Test fun doneLine() {
        assertEquals("done\t00ff4958bf\t2026-10-21T09:12", Agenda.doneLine("00ff4958bf", LocalDateTime.of(2026, 10, 21, 9, 12, 59)))
        assertNull(Agenda.doneLine("short", now))
        assertNull(Agenda.doneLine("ZZZZZZZZZZ", now))
        assertNull(Agenda.doneLine("0123456789\tinject", now))                                             // タブ・改行で行を壊せない
    }

    @Test fun nextMorning() {
        assertEquals(LocalDateTime.of(2026, 10, 21, 7, 30), Agenda.nextMorning(7, 30, now))              // 今日のまだ先
        assertEquals(LocalDateTime.of(2026, 10, 22, 7, 30), Agenda.nextMorning(7, 30, LocalDateTime.of(2026, 10, 21, 8, 0)))   // 過ぎていれば明日
        assertEquals(LocalDateTime.of(2026, 10, 22, 7, 0), Agenda.nextMorning(7, 0, now))               // ちょうどのときも明日（二度鳴らさない）
        assertEquals(LocalDateTime.of(2027, 1, 1, 6, 0), Agenda.nextMorning(6, 0, LocalDateTime.of(2026, 12, 31, 23, 59)))       // 年またぎ
        assertEquals(LocalDateTime.of(2026, 10, 21, 23, 59), Agenda.nextMorning(99, 99, LocalDateTime.of(2026, 10, 21, 0, 0)))   // 範囲外は丸める
    }

    @Test fun timedToday() {
        val tasks = listOf(t("1111111111", "2026-10-21", "09:30", "ゴミ"), t("2222222222", "2026-10-21", "06:00", "もう過ぎた"), t("3333333333", "2026-10-22", "08:00", "明日"),
            t("4444444444", "2026-10-21", "", "時刻なし"), t("5555555555", "2026-10-21", "08:15", "朝"))
        val r = Agenda.timedToday(tasks, today, now)
        assertEquals(listOf("朝", "ゴミ"), r.map { it.second.text })                                       // 時刻順・過ぎたもの/明日/時刻なしは除く
        assertEquals(LocalDateTime.of(2026, 10, 21, 8, 15), r[0].first)
        assertEquals(1, Agenda.timedToday(tasks, today, now, limit = 1).size)
        assertTrue(Agenda.timedToday(tasks, today, LocalDateTime.of(2026, 10, 21, 23, 0)).isEmpty())
    }

    @Test fun snooze() {
        assertEquals(LocalDateTime.of(2026, 10, 21, 7, 10), Agenda.snoozeAt(now, 10))
        assertEquals(LocalDateTime.of(2026, 10, 21, 7, 1), Agenda.snoozeAt(now, 0))                       // 0 以下は 1 分
        assertEquals(LocalDateTime.of(2026, 10, 22, 7, 0), Agenda.snoozeAt(now, 99999))                    // 長すぎれば 24 時間
        assertEquals(LocalDateTime.of(2026, 10, 22, 0, 5), Agenda.snoozeAt(LocalDateTime.of(2026, 10, 21, 23, 55), 10))   // 日またぎ
    }

    @Test fun widgetLines() {
        val (none, noTasks) = AgendaWidget.lines(null, today, now)
        assertEquals("PC の予定がまだ届いていません", none)
        assertTrue(noTasks.isEmpty())
        val d = AgendaData("2026-10-21T07:00", listOf(t("1111111111", "2026-10-19", text = "遅れ"), t("2222222222", "2026-10-21", text = "今日1"), t("3333333333", "2026-10-21", text = "今日2"),
            t("4444444444", "2026-10-22", text = "明日"), t("5555555555", "2026-10-23", text = "あさって"), t("6666666666", "", text = "期限なし")))
        val (head, lines) = AgendaWidget.lines(d, today, now)
        assertEquals("期限切れ 1・今日 2・7 日以内 2", head)
        assertEquals(listOf("⚠ 遅れ", "・今日1", "・今日2", "・明日"), lines)                                  // 上位 4 件・期限なしは出さない・期限切れに印
        assertEquals("予定はありません", AgendaWidget.lines(AgendaData("2026-10-21T07:00", emptyList()), today, now).first)
        // PC のデータが古ければ知らせる
        assertTrue(AgendaWidget.lines(d.copy(generated = "2026-10-17T07:00"), today, now).first.endsWith("（4 日前の予定）"))
        assertFalse(AgendaWidget.lines(d.copy(generated = "2026-10-19T07:00"), today, now).first.contains("日前"))   // 2 日前までは表示しない
    }

    @Test fun parseExtraColumnsAreOptionalAndValidated() {
        val d = Agenda.parse(Agenda.HEADER + "\n" +
            "task\t1111111111\t2026-10-25\t09:30\thigh\t家\t会議\t90\t1d,10m\tweekly\n" +
            "task\t2222222222\t2026-10-25\t\t\t家\t古い形\n" +                         // 7 列(古い PC)
            "task\t3333333333\t\t\t\t家\t壊れた追加列\tabc\t10x\tsometimes\n" +        // 読めない値は既定に戻す
            "task\t4444444444\t\t\t\t家\t通知なし\t\tnone\t\n")!!
        assertEquals(AgendaTask("1111111111", "2026-10-25", "09:30", "high", "家", "会議", 90, "1d,10m", "weekly"), d.tasks[0])
        assertEquals(Triple(0, "", ""), Triple(d.tasks[1].duration, d.tasks[1].reminds, d.tasks[1].repeat))
        assertEquals(Triple(0, "", ""), Triple(d.tasks[2].duration, d.tasks[2].reminds, d.tasks[2].repeat))
        assertEquals("none", d.tasks[3].reminds)
    }

    @Test fun formatsMatchPython() {
        assertEquals(listOf("", "45m", "1h", "1h30m", "2h"), listOf(0, 45, 60, 90, 120).map { Agenda.fmtDuration(it) })
        assertEquals(listOf("5m", "1h", "90m", "1d", "2d"), listOf(5, 60, 90, 1440, 2880).map { Agenda.fmtOffset(it) })
        assertEquals(listOf(1440, 120, 10), Agenda.parseReminds("10m,1d,2h,10m"))
        assertEquals(emptyList<Int>(), Agenda.parseReminds("none"))
        assertNull(Agenda.parseReminds("10x"))
        assertEquals("1d,10m", Agenda.remindsText(listOf(10, 1440, 10)))
        assertEquals(listOf("時刻ちょうど", "10 分前", "1 時間前", "90 分前", "1 日前"), listOf(0, 10, 60, 90, 1440).map { Agenda.offsetLabel(it) })
    }

    @Test fun taskLineSameAsPythonEditLine() {
        val spec = TaskSpec("2026-10-25", "09:30", 90, "10m,1d", "weekly", "high")
        assertEquals("- [ ] 会議 📅 2026-10-25 09:30 ⌛ 1h30m 🔔 1d,10m 🔁 weekly ⏫", Agenda.taskLine("会議", spec))
        assertEquals("- [ ] 買う 📅 2026-10-22 🔔 none", Agenda.taskLine("買う", TaskSpec("2026-10-22", reminds = "none")))
        assertEquals("- [ ] 薬 📅 2026-10-22 10:30 ⌛ 1h 🔔 5m 🔁 daily 🔽", Agenda.taskLine("薬", TaskSpec("2026-10-22", "10:30", 60, "5m", "daily", "low")))
        assertEquals("- [ ] だけ", Agenda.taskLine("だけ", TaskSpec()))
        assertEquals("- [ ] 二行 目", Agenda.taskLine("- [ ] 二行\n目", TaskSpec()))
        assertNull(Agenda.taskLine("  ", TaskSpec()))
        assertNull(Agenda.taskLine("x", TaskSpec("2026-13-45")))                              // 日付が正しくない
        assertNull(Agenda.taskLine("x", TaskSpec("", "09:00")))                               // 日付なしの時刻
        assertNull(Agenda.taskLine("x", TaskSpec("2026-10-22", "25:00")))
        assertNull(Agenda.taskLine("x", TaskSpec(reminds = "abc")))
        assertNull(Agenda.taskLine("x", TaskSpec(repeat = "sometimes")))
        assertNull(Agenda.taskLine("x", TaskSpec(priority = "urgent")))
        assertNull(Agenda.taskLine("x", TaskSpec(duration = 999999)))
    }

    @Test fun editLineAndApplyEdit() {
        val spec = TaskSpec("2026-10-23", "08:30", 15, "10m,1d", "daily", "high")
        assertEquals("edit\t00ff4958bf\t2026-10-23\t08:30\t15\t1d,10m\tdaily\thigh", Agenda.editLine("00ff4958bf", spec))
        assertEquals("edit\t00ff4958bf\t\t\t\t\t\t", Agenda.editLine("00ff4958bf", TaskSpec()))                      // すべて空 = 全部消す
        assertEquals("edit\t00ff4958bf\t2026-10-23\t\t\tnone\t\t", Agenda.editLine("00ff4958bf", TaskSpec("2026-10-23", reminds = "none")))
        assertNull(Agenda.editLine("short", spec))
        assertNull(Agenda.editLine("00ff4958bf", spec.copy(due = "x")))
        assertNull(Agenda.editLine("0123456789\tinject", spec))                                // タブで行を壊せない
        assertNull(Agenda.editLine("00ff4958bf", TaskSpec("", "09:00")))                          // 日付なしの時刻は送らない
        val tasks = listOf(t("00ff4958bf", "2026-10-21", "09:00", "ゴミ"), t("1111111111", "2026-10-21", "10:00", "別"))
        val r = Agenda.applyEdit(tasks, "00ff4958bf", spec)
        assertEquals(AgendaTask("00ff4958bf", "2026-10-23", "08:30", "high", "ノート", "ゴミ", 15, "1d,10m", "daily"), r[0])
        assertEquals(tasks[1], r[1])                                                           // ほかは変わらない
        assertEquals("", Agenda.applyEdit(tasks, "00ff4958bf", TaskSpec())[0].time)            // 日付を消せば時刻も消える
        assertEquals(tasks, Agenda.applyEdit(tasks, "00ff4958bf", spec.copy(due = "x")))        // 正しくない設定は何も変えない
        assertEquals(spec, Agenda.specOf(r[0]).copy(reminds = "10m,1d"))
    }

    @Test fun tsvRoundTrip() {
        val d = AgendaData("2026-10-21T07:00", listOf(AgendaTask("1111111111", "2026-10-25", "09:30", "high", "家", "会議", 90, "1d,10m", "weekly"), t("2222222222", "", text = "いつか")))
        assertEquals(d, Agenda.parse(Agenda.toTsv(d)))
        assertEquals(1, Agenda.toTsv(d).lines().count { it.startsWith("generated") })
    }

    @Test fun alarmPlanCoversRemindersTimesAndHorizon() {
        val tasks = listOf(
            AgendaTask("1111111111", "2026-10-21", "09:30", "", "n", "既定"),                                   // 時刻ちょうど
            AgendaTask("2222222222", "2026-10-21", "09:30", "", "n", "複数", reminds = "10m,1h"),                // 8:30 と 9:20
            AgendaTask("3333333333", "2026-10-21", "09:30", "", "n", "なし", reminds = "none"),
            AgendaTask("4444444444", "2026-10-22", "08:00", "", "n", "明日", reminds = "1d"),                    // 今日の 8:00
            AgendaTask("5555555555", "2026-10-22", "", "", "n", "終日", reminds = "1h"),                         // 9 時基準 → 8:00
            AgendaTask("6666666666", "2026-10-22", "", "", "n", "終日の既定"),                                    // 指定が無ければ朝のまとめだけ
            AgendaTask("7777777777", "2026-10-30", "09:00", "", "n", "遠い"),
            AgendaTask("8888888888", "2026-10-21", "06:00", "", "n", "過去"))
        val p = Agenda.alarmPlan(tasks, now)
        assertEquals(listOf("2026-10-21T08:00" to "明日", "2026-10-21T08:30" to "複数", "2026-10-21T09:20" to "複数", "2026-10-21T09:30" to "既定", "2026-10-22T08:00" to "終日"),
            p.map { it.at.toString().take(16) to it.task.text })
        assertEquals(listOf(1440, 60, 10, 0, 60), p.map { it.offset })                                                   // 時刻順に、期限の何分前の知らせか
        assertEquals(5, p.size)
        assertEquals(2, Agenda.alarmPlan(tasks, now, limit = 2).size)
        assertEquals(listOf("明日"), Agenda.alarmPlan(tasks, now, horizonHours = 1).map { it.task.text })      // 1 時間先(今日の 8:00)まで。終日は明日の 8:00 なので入らない
        assertTrue(Agenda.alarmPlan(tasks, now, horizonHours = 0).isEmpty())
        assertEquals(listOf(0), Agenda.remindOffsets(tasks[0]))
        assertEquals(emptyList<Int>(), Agenda.remindOffsets(tasks[2]))
    }
}
