#!/usr/bin/env python3
import datetime as dt
import hashlib
import io
import contextlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chrono as ch

NOW = dt.datetime(2026, 10, 21, 8, 0, 0)


def note(root, name, title, time_, body=""):
    (root / name).write_text(f"---\ntime: {time_}\ntitle: {title}\n---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class ChronoTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        note(r, "a.md", "十月の一", "2026-10-05 09:00:00", "- [ ] 提出 📅 2026-10-25\n- [x] 買い物 ✅ 2026-10-06")
        note(r, "b.md", "十月の二", "2026-10-05 20:00:00")
        note(r, "c.md", "去年の今日", "2025-10-21 10:00:00", "- [x] 去年の終えた ✅ 2025-10-21")
        note(r, "d.md", "三年前の今日", "2023-10-21 10:00:00")
        note(r, "e.md", "来週に期限", "2026-09-01 10:00:00", "- [ ] 来週の締切 📅 2026-10-27\n- [ ] 持ち越し 📅 2026-09-30")
        note(r, "f.md", "九月", "2026-09-10 10:00:00")
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in r.glob("*.md")}

    def same(self):
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md")})

    def test_calendar_counts_and_grid(self):
        c = ch.calendar(self.root, 2026, 10)
        self.assertEqual(len(c["days"]), 31)
        self.assertEqual(c["days"]["2026-10-05"]["created"], 2)
        self.assertEqual(c["days"]["2026-10-25"]["due"], 1)
        self.assertEqual(c["days"]["2026-10-06"]["done"], 1)
        self.assertEqual(c["days"]["2026-10-01"], {"created": 0, "due": 0, "done": 0})
        md = ch.calendar_md(c)
        self.assertIn("# 2026年10月", md)
        self.assertIn("| 月 | 火 | 水 | 木 | 金 | 土 | 日 |", md)
        self.assertIn("5<br>📝2", md)
        rows = [r for r in md.split("\n") if r.startswith("| ") and "<br>" in r or r.startswith("| ") and r[2:3].isdigit() or r.startswith("|  ")]
        self.assertTrue(all(r.count("|") == 8 for r in rows))                 # 7 列
        # 10/1 は木曜日: 最初の週の木曜の位置に 1
        first = [r for r in md.split("\n") if r.startswith("| ") and "| 1" in r][0]
        self.assertEqual([x.strip() for x in first.strip("|").split("|")][3], "1")
        self.same()

    def test_calendar_february_leap(self):
        self.assertEqual(len(ch.calendar(self.root, 2028, 2)["days"]), 29)
        self.assertEqual(len(ch.calendar(self.root, 2026, 2)["days"]), 28)

    def test_day(self):
        d = ch.day(self.root, dt.date(2026, 10, 5))
        self.assertEqual({x["path"] for x in d["created"]}, {"a.md", "b.md"})
        self.assertEqual(ch.day(self.root, dt.date(2026, 10, 25))["due"][0]["text"], "提出")
        self.assertEqual(ch.day(self.root, dt.date(2026, 10, 6))["done"][0]["text"], "買い物")
        self.assertIn("## 作ったノート", ch.day_md(d))
        self.same()

    def test_on_this_day_only_past_years(self):
        o = ch.on_this_day(self.root, dt.date(2026, 10, 21))
        self.assertEqual([(y["year"], y["years_ago"]) for y in o["years"]], [(2025, 1), (2023, 3)])      # 新しい年が先
        self.assertEqual(o["years"][0]["notes"][0]["path"], "c.md")
        self.assertEqual(o["years"][0]["done"][0]["text"], "去年の終えた")
        note(self.root, "now.md", "今年の今日", "2026-10-21 07:00:00")                                    # 今年は含めない
        self.assertNotIn(2026, [y["year"] for y in ch.on_this_day(self.root, dt.date(2026, 10, 21))["years"]])
        self.assertEqual(ch.on_this_day(self.root, dt.date(2026, 3, 3))["years"], [])
        self.assertIn("過去に作ったノートはありません", ch.onthisday_md(ch.on_this_day(self.root, dt.date(2026, 3, 3))))
        self.assertIn("1 年前", ch.onthisday_md(o))

    def test_review_week_month_year_day(self):
        w = ch.review(self.root, "週", dt.date(2026, 10, 5))           # 月曜 10/5〜日曜 10/11
        self.assertEqual((w["from"], w["to"]), ("2026-10-05", "2026-10-11"))
        self.assertEqual({x["path"] for x in w["created"]}, {"a.md", "b.md"})
        self.assertEqual([x["text"] for x in w["done"]], ["買い物"])
        m = ch.review(self.root, "month", dt.date(2026, 10, 21))
        self.assertEqual((m["from"], m["to"]), ("2026-10-01", "2026-10-31"))
        self.assertEqual([x["text"] for x in m["open_in_period"]], ["提出", "来週の締切"])
        self.assertEqual([x["text"] for x in m["carried_over"]], ["持ち越し"])                      # 期間より前の期限で未完了
        w2 = ch.review(self.root, "週", dt.date(2026, 10, 21))         # 10/19〜10/25 → 次の週は 10/26〜11/1
        self.assertEqual([x["text"] for x in w2["next_due"]], ["来週の締切"])
        y = ch.review(self.root, "年", dt.date(2026, 6, 1))
        self.assertEqual((y["from"], y["to"]), ("2026-01-01", "2026-12-31"))
        self.assertEqual(len(y["created"]), 4)
        self.assertEqual(ch.review(self.root, "日", dt.date(2026, 10, 5))["from"], "2026-10-05")
        with self.assertRaises(ValueError):
            ch.review(self.root, "十年", dt.date(2026, 1, 1))
        md = ch.review_md(w)
        self.assertIn("# 週のレビュー 2026-10-05〜2026-10-11", md)
        self.assertIn("(a.md)", md)
        self.assertIn("## 振り返り（自分の言葉で）", md)
        self.same()

    def test_year_boundary_week(self):
        w = ch.review(self.root, "week", dt.date(2026, 1, 1))          # 2025-12-29（月）〜 2026-01-04
        self.assertEqual((w["from"], w["to"]), ("2025-12-29", "2026-01-04"))

    def test_write_review_new_note_only(self):
        r = ch.write_review(self.root, "週", dt.date(2026, 10, 5), "reviews/2026-W41.md", NOW)
        p = self.root / "reviews" / "2026-W41.md"
        self.assertEqual(r["path"], "reviews/2026-W41.md")
        text = p.read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\ntime: 2026-10-21 08:00:00\ntitle: 週のレビュー 2026-10-05〜2026-10-11\n---\n"))
        self.assertIn("(a.md)", text)
        for bad, msg in (("reviews/2026-W41.md", "上書きしません"), ("../x.md", "vault の外"), (".state/x.md", "ドット始まり")):
            with self.assertRaises(ValueError, msg=bad) as cm:
                ch.write_review(self.root, "週", dt.date(2026, 10, 5), bad, NOW)
            self.assertIn(msg, str(cm.exception))
        self.assertFalse((self.root.parent / "x.md").exists())
        self.assertEqual(p.read_text(encoding="utf-8"), text)           # 上書きされていない
        self.assertEqual(self.before, {q.name: hashlib.md5(q.read_bytes()).hexdigest() for q in self.root.glob("*.md")})   # 既存ノートは不変

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = ch.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertEqual(run("calendar", "2026-10")[0], 0)
        self.assertIn("📝", run("calendar", "2026-10", "--md")[1])
        self.assertEqual(run("onthisday", "2026-10-21")[0], 0)
        self.assertEqual(run("review", "週", "2026-10-05")[0], 0)
        self.assertEqual(run("day", "2026-10-05", "--md")[0], 0)
        self.assertEqual(run("day", "not-a-date")[0], 1)
        self.assertEqual(run("review", "十年")[0], 1)
        self.assertEqual(run("bogus")[0], 2)
        rc, out = run("write-review", "週", "2026-10-05", "r.md")
        self.assertEqual(rc, 0)
        self.assertEqual(run("write-review", "週", "2026-10-05", "r.md")[0], 1)


if __name__ == "__main__":
    unittest.main()
