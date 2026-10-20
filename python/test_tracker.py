#!/usr/bin/env python3
import contextlib
import datetime as dt
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tracker as tr


class TrackerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "hand.md").write_text("---\ntitle: 手書き\n---\n\n# 手書き\n\n- ⏱ 2026-10-20 22:30-00:15 夜の作業 #仕事\n- 🌱 運動 2026-10-19\n```\n- ⏱ 2026-10-20 01:00-02:00 コード内\n```\n", encoding="utf-8")

    def test_parse_hand_written_and_midnight(self):
        e = tr.entries(self.root)
        self.assertEqual(len(e["times"]), 1)                       # コードブロックの中は数えない
        t = e["times"][0]
        self.assertEqual((t["start"], t["end"], t["minutes"]), ("2026-10-20T22:30", "2026-10-21T00:15", 105))   # 日またぎ
        self.assertEqual((t["label"], t["tags"]), ("夜の作業", ["仕事"]))
        self.assertEqual(e["habits"], {"運動": ["2026-10-19"]})

    def test_timer_start_status_stop_appends_only(self):
        before = (self.root / "hand.md").read_bytes()
        tr.start(self.root, "資料作り", False, "2026-10-21T09:00")
        with self.assertRaises(ValueError):
            tr.start(self.root, "二つ目", False, "2026-10-21T09:01")                   # 二重に動かさない
        s = tr.status(self.root, "2026-10-21T09:42")
        self.assertEqual((s["running"], s["elapsed_min"]), (True, 42))
        r = tr.stop(self.root, "2026-10-21T10:15")
        self.assertEqual((r["logged"], r["minutes"], r["file"]), (True, 75, "記録.md"))
        text = (self.root / "記録.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\ntime: 2026-10-21 10:15:00\ntitle: 記録\n---\n\n# 記録\n\n"))
        self.assertTrue(text.endswith("- ⏱ 2026-10-21 09:00-10:15 資料作り\n"))
        self.assertEqual(tr.status(self.root)["running"], False)
        self.assertEqual((self.root / "hand.md").read_bytes(), before)                   # 他のノートは不変
        self.assertEqual(tr.entries(self.root)["times"][-1]["minutes"], 75)               # 書いた行を読み戻せる
        with self.assertRaises(ValueError):
            tr.stop(self.root)

    def test_stop_under_a_minute_is_not_logged_but_clears(self):
        tr.start(self.root, "うっかり", False, "2026-10-21T09:00")
        r = tr.stop(self.root, "2026-10-21T09:00")
        self.assertFalse(r["logged"])
        self.assertFalse((self.root / "記録.md").exists())
        self.assertFalse(tr.status(self.root)["running"])

    def test_pomodoro_phases(self):
        P = tr._phase
        self.assertEqual((P(0)["phase"], P(0)["left"], P(0)["completed"]), ("work", 25, 0))
        self.assertEqual((P(24)["phase"], P(24)["left"]), ("work", 1))
        self.assertEqual((P(25)["phase"], P(25)["left"], P(25)["completed"]), ("break", 5, 1))
        self.assertEqual((P(29)["phase"], P(29)["left"]), ("break", 1))
        self.assertEqual((P(30)["phase"], P(30)["round"]), ("work", 2))
        # 4 回目の作業が終わると長い休憩(15 分)
        self.assertEqual(P(3 * 30 + 25)["phase"], "break")
        self.assertEqual(P(3 * 30 + 25)["left"], 15)
        self.assertEqual(P(3 * 30 + 25 + 15)["phase"], "work")
        self.assertEqual(P(3 * 30 + 25 + 15)["round"], 5)

    def test_pomodoro_stop_counts_completed_rounds(self):
        tr.start(self.root, "集中", True, "2026-10-21T09:00")
        s = tr.status(self.root, "2026-10-21T09:27")
        self.assertEqual((s["phase"], s["left"], s["completed"]), ("break", 3, 1))
        r = tr.stop(self.root, "2026-10-21T10:05")                                    # 65 分: 作業2回完了(0:00-0:25, 0:30-0:55)
        self.assertEqual(r["pomodoros"], 2)
        self.assertIn("🍅2", r["line"])
        self.assertEqual(tr.entries(self.root)["times"][-1]["pomodoros"], 2)

    def test_report_totals_by_label_and_tag(self):
        for i, (st, en, name) in enumerate((("09:00", "09:30", "A #x"), ("10:00", "10:20", "A #x #y"), ("11:00", "12:00", "B"))):
            tr._append(self.root, "記録.md", f"- ⏱ 2026-10-21 {st}-{en} {name}", dt.datetime(2026, 10, 21))
        r = tr.report(self.root, "日", dt.date(2026, 10, 21))
        self.assertEqual(r["total_min"], 110)
        self.assertEqual(r["by_label"], [("B", 60), ("A", 50)])
        self.assertEqual(dict(r["by_tag"]), {"x": 50, "y": 20})
        w = tr.report(self.root, "週", dt.date(2026, 10, 21))                          # 2026-10-19〜25: 夜の作業(10/20 開始)も入る
        self.assertEqual(w["total_min"], 110 + 105)
        self.assertIn("合計 3 時間 35 分", tr.to_md("report", w))

    def test_habit_check_idempotent_and_streaks(self):
        n = "2026-10-21T08:00"
        self.assertTrue(tr.habit_check(self.root, "運動", "2026-10-20", now=n)["added"])
        self.assertFalse(tr.habit_check(self.root, "運動", "2026-10-20", now=n)["added"])   # 同じ日は 1 回
        self.assertTrue(tr.habit_check(self.root, "運動", None, now=n)["added"])            # 今日
        self.assertEqual((self.root / "記録.md").read_text(encoding="utf-8").count("🌱 運動 2026-10-20"), 1)
        h = tr.habit_stats(self.root, "運動", dt.date(2026, 10, 21))["habits"][0]
        self.assertEqual((h["current_streak"], h["longest_streak"], h["total"]), (3, 3, 3))   # 10/19(手書き)-21
        self.assertTrue(h["done_today"])
        self.assertTrue(h["last28"].endswith("■■■"))
        self.assertEqual(len(h["last28"]), 28)
        # 今日まだなら昨日までの連続を保つ。1 日抜けたら 0
        self.assertEqual(tr.habit_stats(self.root, "運動", dt.date(2026, 10, 22))["habits"][0]["current_streak"], 3)
        self.assertEqual(tr.habit_stats(self.root, "運動", dt.date(2026, 10, 23))["habits"][0]["current_streak"], 0)
        self.assertEqual(tr.habit_stats(self.root, "運動", dt.date(2026, 10, 23))["habits"][0]["longest_streak"], 3)
        self.assertEqual(tr.habit_stats(self.root, "運動", dt.date(2026, 10, 21))["habits"][0]["rate_7"], round(3 / 7, 3))
        for bad in ("", "運動 2026-10-21", "a\nb"):
            with self.assertRaises(ValueError):
                tr.habit_check(self.root, bad, now=n)
        with self.assertRaises(ValueError):
            tr.habit_check(self.root, "運動", "2026-13-40", now=n)
        with self.assertRaises(ValueError):
            tr.habit_stats(self.root, "存在しない")

    def test_lifelog_and_day_summary(self):
        tr.log_add(self.root, "昼食 カレー", "2026-10-21T12:30")
        tr.habit_check(self.root, "読書", "2026-10-21", now="2026-10-21T20:00")
        tr._append(self.root, "記録.md", "- ⏱ 2026-10-21 09:00-09:30 朝の作業", dt.datetime(2026, 10, 21))
        d = tr.day_summary(self.root, "2026-10-21")
        self.assertEqual(d["total_min"], 30)
        self.assertEqual(d["habits"], ["読書"])
        self.assertEqual(d["logs"][0]["text"], "昼食 カレー")
        md = tr.day_md(d)
        self.assertIn("## 2026-10-21 の記録", md)
        self.assertIn("### 時間（合計 30 分）", md)
        self.assertIn("- 12:30 昼食 カレー", md)
        self.assertIn("この日の記録はありません", tr.day_md(tr.day_summary(self.root, "2020-01-01")))
        with self.assertRaises(ValueError):
            tr.log_add(self.root, "  ")

    def test_write_target_is_restricted(self):
        for bad, msg in (("../x.md", "vault の外"), (".state/x.md", "ドット始まり"), ("x.txt", ".md")):
            with self.assertRaises(ValueError) as cm:
                tr.log_add(self.root, "a", "2026-10-21T10:00", bad)
            self.assertIn(msg, str(cm.exception))
        self.assertFalse((self.root.parent / "x.md").exists())

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = tr.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertEqual(run("start", "CLI", "--pomodoro", "--at", "2026-10-21T09:00")[0], 0)
        self.assertIn("ポモドーロ 1 回目・作業中・あと 10 分", run("status", "--at", "2026-10-21T09:15", "--md")[1])
        self.assertEqual(run("stop", "--at", "2026-10-21T09:40")[0], 0)
        self.assertIn("タイマーは動いていません", run("status", "--md")[1])
        self.assertEqual(run("habit", "check", "歩く", "2026-10-21")[0], 0)
        self.assertIn("## 歩く", run("habit", "stats", "2026-10-21", "--md")[1])
        self.assertIn("## 歩く", run("habit", "stats", "歩く", "2026-10-21", "--md")[1])
        self.assertEqual(run("log", "メモ", "--at", "2026-10-21T10:00")[0], 0)
        self.assertIn("メモ", run("day", "2026-10-21", "--md")[1])
        self.assertEqual(run("report", "月", "2026-10-21", "--md")[0], 0)
        self.assertEqual(run("stop")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
