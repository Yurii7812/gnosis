#!/usr/bin/env python3
import datetime as dt
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tasks as tk

D = dt.date


class TasksTest(unittest.TestCase):
    def test_parse(self):
        t = tk.parse_line("  - [ ] 提出する 📅 2026-10-25 09:30 🔁 weekly ⏫ id:a1 after:b2", "a.md", 7)
        self.assertEqual((t.text, t.due, t.due_time, t.repeat, t.priority, t.tid, t.after, t.done, t.line),
                         ("提出する", "2026-10-25", "09:30", "weekly", "high", "a1", ["b2"], False, 7))
        t = tk.parse_line("- [x] 済み due:2026-10-01 done:2026-10-02")
        self.assertTrue(t.done)
        self.assertEqual((t.due, t.done_date), ("2026-10-01", "2026-10-02"))
        self.assertIsNone(tk.parse_line("- 普通の箇条書き"))
        self.assertIsNone(tk.parse_line("[ ] 先頭が箇条書きでない"))
        self.assertEqual(tk.parse_line("- [ ]").text, "")  # 空のタスクも読める

    def test_code_fence_is_not_task(self):
        text = "- [ ] 本物\n```\n- [ ] コード内\n```\n~~~\n- [ ] これも\n~~~\n- [ ] もう一つ\n"
        self.assertEqual([t.text for t in tk.parse_text(text)], ["本物", "もう一つ"])

    def test_next_occurrence(self):
        self.assertEqual(tk.next_occurrence(D(2026, 1, 31), "monthly"), D(2026, 2, 28))   # 月末に丸める
        self.assertEqual(tk.next_occurrence(D(2024, 2, 29), "yearly"), D(2025, 2, 28))
        self.assertEqual(tk.next_occurrence(D(2026, 10, 23), "weekday"), D(2026, 10, 26))  # 金 → 月
        self.assertEqual(tk.next_occurrence(D(2026, 10, 1), "every 3 days"), D(2026, 10, 4))
        self.assertEqual(tk.next_occurrence(D(2026, 10, 31), "every 2 weeks"), D(2026, 11, 14))
        with self.assertRaises(ValueError):
            tk.next_occurrence(D(2026, 1, 1), "sometimes")

    def test_agenda_grouping(self):
        ts = tk.parse_text("\n".join([
            "- [ ] 過去 📅 2026-10-10", "- [ ] 今日 📅 2026-10-20 08:00", "- [ ] 今日の優先 📅 2026-10-20 ⏫",
            "- [ ] 近日 📅 2026-10-25", "- [ ] 先 📅 2026-12-01", "- [ ] 期限なし", "- [x] 済 📅 2026-10-01",
            "- [ ] 開始前 🛫 2026-11-01 📅 2026-11-02", "- [ ] 親 id:p", "- [ ] 子 after:p 📅 2026-10-20"]), "n.md")
        open_ids = {t.tid for t in ts if t.tid and not t.done}
        for t in ts:
            t.blocked = (not t.done) and any(a in open_ids for a in t.after)
        a = tk.agenda(ts, D(2026, 10, 20))
        names = {k: [t.text for t in v] for k, v in a.items()}
        self.assertEqual(names["overdue"], ["過去"])
        self.assertEqual(names["today"], ["今日", "今日の優先"])    # 並びは 日付 → 時刻（時刻ありが先）→ 優先度
        self.assertEqual(names["soon"], ["近日"])
        self.assertEqual(names["later"], ["先"])
        self.assertEqual(sorted(names["undated"]), ["期限なし", "親"])
        self.assertEqual(names["blocked"], ["子"])
        self.assertEqual(names["not_started"], ["開始前"])

    def test_complete_plain_and_repeat(self):
        with tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test")) as d:
            p = Path(d) / "n.md"
            p.write_text("# n\n\n- [ ] 単発 📅 2026-10-20\n- [ ] 毎週 📅 2026-10-20 🔁 weekly\n- 箇条書き\n- [ ] 期限なしの繰り返し 🔁 daily\n", encoding="utf-8")
            r = tk.complete(p, 3, D(2026, 10, 20))
            self.assertTrue(r["changed"])
            self.assertEqual(p.read_text(encoding="utf-8").split("\n")[2], "- [x] 単発 📅 2026-10-20 ✅ 2026-10-20")
            r = tk.complete(p, 4, D(2026, 10, 21))
            lines = p.read_text(encoding="utf-8").split("\n")
            self.assertEqual(lines[3], "- [x] 毎週 📅 2026-10-20 🔁 weekly ✅ 2026-10-21")
            self.assertEqual(lines[4], "- [ ] 毎週 📅 2026-10-27 🔁 weekly")           # 次の回は期限の次の週
            self.assertEqual(r["next"], lines[4])
            r = tk.complete(p, 7, D(2026, 10, 21))                                      # 期限なし: 今日を基準に
            self.assertEqual(p.read_text(encoding="utf-8").split("\n")[7], "- [ ] 期限なしの繰り返し 🔁 daily 📅 2026-10-22")
            # 完了済み・タスクでない行・範囲外は何も書かない
            before = p.read_text(encoding="utf-8")
            self.assertFalse(tk.complete(p, 3, D(2026, 10, 22))["changed"])
            self.assertFalse(tk.complete(p, 6, D(2026, 10, 22))["ok"])                  # 行 6 は通常の箇条書き（行 4 の完了で次の回が 5 に入った）
            self.assertFalse(tk.complete(p, 1, D(2026, 10, 22))["ok"])
            with self.assertRaises(ValueError):
                tk.complete(p, 99, D(2026, 10, 22))
            self.assertEqual(before, p.read_text(encoding="utf-8"))
            self.assertEqual([x.name for x in Path(d).iterdir()], ["n.md"])

    def test_collect_skips_hidden_dirs(self):
        with tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test")) as d:
            r = Path(d)
            (r / "a.md").write_text("- [ ] A\n", encoding="utf-8")
            (r / ".trash").mkdir()
            (r / ".trash" / "b.md").write_text("- [ ] B\n", encoding="utf-8")
            (r / "sub").mkdir()
            (r / "sub" / "c.md").write_text("- [ ] C after:z\n- [ ] Z id:z\n", encoding="utf-8")
            ts = tk.collect(r)
            self.assertEqual(sorted(t.text for t in ts), ["A", "C", "Z"])
            self.assertTrue(next(t for t in ts if t.text == "C").blocked)
            self.assertEqual(next(t for t in ts if t.text == "C").file, "sub/c.md")


if __name__ == "__main__":
    unittest.main()
