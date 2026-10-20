#!/usr/bin/env python3
import contextlib
import datetime as dt
import hashlib
import io
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nav

TODAY = dt.date(2026, 10, 21)
NOW = dt.datetime(2026, 10, 21, 9, 0, 0)


def note(root, name, title, body="", tm="2026-01-01 00:00:00"):
    (root / name).write_text(f"---\ntime: {tm}\ntitle: {title}\n---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class NavTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        note(r, "a.md", "甲", "? これは本当にそうなのか調べる\n? 解決した問い ✅\n仮説: 睡眠は記憶に効く\n❓ 2026-10-01 半年後の自分は\n❓ 2027-04-01 まだ先の問い")
        note(r, "b.md", "乙", "🕰 2026-10-15\n普通の文。\n🕰 2027-01-01")
        note(r, "c.md", "丙", "```\n? コードの中の問い\n仮説: コード内\n```\n[リンク](a.md)? これは問いではない")
        note(r, "new.md", "新しい", "", "2026-10-20 08:00:00")
        old = time.time() - 400 * 86400
        os.utime(r / "a.md", (old, old))
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in r.glob("*.md")}

    def same(self):
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md") if p.name in self.before})

    def test_bookmarks_add_slot_remove(self):
        nav.bookmark_add(self.root, "a.md")
        nav.bookmark_add(self.root, "乙", 3)
        nav.bookmark_add(self.root, "c.md", 3)                                  # スロットはあとから付けたほうが勝つ
        b = {x["path"]: x for x in nav.bookmark_list(self.root)["bookmarks"]}
        self.assertEqual(b["c.md"]["slot"], 3)
        self.assertNotIn("slot", b["b.md"])
        self.assertEqual(nav.bookmark_slot(self.root, 3)["path"], "c.md")
        nav.bookmark_add(self.root, "a.md", 1)                                  # 同じノートは 1 件のまま付け替え
        self.assertEqual(len(nav.bookmark_list(self.root)["bookmarks"]), 3)
        self.assertEqual([x.get("slot") for x in nav.bookmark_list(self.root)["bookmarks"]], [1, 3, None])   # スロット順→なし
        for bad in (0, 10):
            with self.assertRaises(ValueError):
                nav.bookmark_add(self.root, "a.md", bad)
        with self.assertRaises(ValueError):
            nav.bookmark_slot(self.root, 7)
        nav.bookmark_remove(self.root, "a.md")
        with self.assertRaises(ValueError):
            nav.bookmark_remove(self.root, "a.md")
        self.same()

    def test_bookmark_of_vanished_note_is_kept_and_marked(self):
        nav.bookmark_add(self.root, "c.md", 2)
        (self.root / "c.md").unlink()
        b = nav.bookmark_list(self.root)["bookmarks"][0]
        self.assertFalse(b["exists"])
        with self.assertRaises(ValueError) as cm:
            nav.bookmark_slot(self.root, 2)
        self.assertIn("見つかりません", str(cm.exception))
        nav.bookmark_remove(self.root, "c.md")                                  # 消えたノートでも外せる
        self.assertEqual(nav.bookmark_list(self.root)["bookmarks"], [])

    def test_bookmark_file_corruption_recovers(self):
        nav.bookmark_add(self.root, "a.md")
        (self.root / ".gnosis" / "bookmarks.json").write_text("{bad", encoding="utf-8")
        self.assertEqual(nav.bookmark_list(self.root)["bookmarks"], [])
        nav.bookmark_add(self.root, "b.md")
        self.assertEqual(len(nav.bookmark_list(self.root)["bookmarks"]), 1)

    def test_recent_orders_and_limits(self):
        c = nav.recent(self.root, "created", 3)["notes"]
        self.assertEqual(c[0]["path"], "new.md")                                 # 2026-10-20 が最新
        self.assertEqual(len(c), 3)
        m = nav.recent(self.root, "modified")["notes"]
        self.assertEqual(m[-1]["path"], "a.md")                                  # 400 日前に触ったものは最後
        with self.assertRaises(ValueError):
            nav.recent(self.root, "bogus")

    def test_recent_viewed_and_imported(self):
        (self.root / ".state").mkdir(exist_ok=True)
        (self.root / ".state" / "history.json").write_text(json.dumps({"list": ["a.md", "b.md", "gone.md", "../x.md", "a.md", "/etc/passwd", 3]}), encoding="utf-8")
        v = nav.recent(self.root, "viewed")["notes"]
        self.assertEqual([x["path"] for x in v], ["a.md", "b.md"])                 # 新しい順・重複と無いファイルと外のパスは除く
        self.assertEqual(nav.recent(self.root, "viewed", 1)["notes"][0]["path"], "a.md")
        self.assertEqual(nav.recent(Path(tempfile.mkdtemp(dir=str(Path.home() / "Desktop" / "test"))), "viewed")["notes"], [])
        (self.root / "ph.md").write_text("---\ntime: 2026-10-19 09:00:00\ntitle: 電話\ncapture_id: 261019090000\n---\n\n# 電話\n", encoding="utf-8")
        (self.root / "ph2.md").write_text("---\ntime: 2026-10-20 09:00:00\ntitle: 電話2\ncapture_id: 261020090000\n---\n\n# 電話2\n", encoding="utf-8")
        self.assertEqual([x["path"] for x in nav.recent(self.root, "imported")["notes"]], ["ph2.md", "ph.md"])
        self.assertIn("スマホから取り込んだ", nav.to_md("recent", nav.recent(self.root, "imported")))
        self.assertIn("なし", nav.to_md("recent", {"by": "imported", "notes": []}))

    def test_reminders_questions_hypotheses_future_capsules(self):
        r = nav.reminders(self.root, TODAY, 90)
        self.assertEqual([x["text"] for x in r["questions"]], ["これは本当にそうなのか調べる"])       # ✅・コード内・リンク内は除く
        self.assertGreaterEqual(r["questions"][0]["age_days"], 399)
        self.assertEqual([x["text"] for x in r["old_hypotheses"]], ["睡眠は記憶に効く"])           # 90 日以上たったものだけ
        self.assertEqual([x["text"] for x in r["future_due"]], ["半年後の自分は"])
        self.assertEqual([x["date"] for x in r["future_waiting"]], ["2027-04-01"])
        self.assertEqual([x["date"] for x in r["capsules_due"]], ["2026-10-15"])
        self.assertEqual([x["date"] for x in r["capsules_waiting"]], ["2027-01-01"])
        self.assertEqual(nav.reminders(self.root, TODAY, 1000)["old_hypotheses"], [])             # 基準を上げれば出ない
        # 未来の日付に動かすと、待っていたものが今日のものになる
        later = nav.reminders(self.root, dt.date(2027, 5, 1), 90)
        self.assertEqual(len(later["future_due"]), 2)
        self.assertEqual(len(later["capsules_due"]), 2)
        self.assertEqual(later["future_waiting"], [])
        md = nav.to_md("reminders", r)
        self.assertIn("## 今日の問い（未来への質問）（1）", md)
        self.assertIn("半年後の自分は", md)
        self.same()

    def test_trails_save_add_show_export(self):
        nav.trail(self.root, "save", "読み筋", ["a.md", "b.md", "b.md", "乙", "c.md"])   # 連続する同じノートは 1 歩
        s = nav.trail(self.root, "show", "読み筋")
        self.assertEqual([x["path"] for x in s["steps"]], ["a.md", "b.md", "c.md"])
        nav.trail(self.root, "add", "読み筋", ["new.md"])
        nav.trail(self.root, "add", "読み筋", ["new.md"])
        self.assertEqual(len(nav.trail(self.root, "show", "読み筋")["steps"]), 4)
        self.assertEqual(nav.trail(self.root, "list")["trails"], [{"name": "読み筋", "steps": 4}])
        w = nav.trail_export(self.root, "読み筋", "trails/read.md", NOW)
        text = (self.root / "trails" / "read.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\ntime: 2026-10-21 09:00:00\ntitle: トレイル: 読み筋\n---\n"))
        self.assertIn("1. [甲](../a.md)", text)                                    # 書き出し先のフォルダからの相対リンク
        self.assertEqual(w["steps"], 4)
        for bad, msg in (("trails/read.md", "上書きしません"), ("../x.md", "vault の外"), (".s/x.md", "ドット始まり"), ("", "--write")):
            with self.assertRaises(ValueError) as cm:
                nav.trail_export(self.root, "読み筋", bad)
            self.assertIn(msg, str(cm.exception))
        for bad in (("save", "x", []), ("show", "ない", None), ("remove", "ない", None), ("add", "ない", ["a.md"]), ("zzz", "x", None), ("save", "", ["a.md"])):
            with self.assertRaises(ValueError):
                nav.trail(self.root, bad[0], bad[1], bad[2])
        nav.trail(self.root, "remove", "読み筋")
        self.assertEqual(nav.trail(self.root, "list")["trails"], [])
        self.same()

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = nav.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertEqual(run("bookmark", "add", "a.md", "2")[0], 0)
        self.assertIn("[2]", run("bookmark", "list", "--md")[1])
        self.assertIn('"path": "a.md"', run("bookmark", "slot", "2")[1])
        self.assertEqual(run("bookmark", "slot", "9")[0], 1)
        self.assertIn("最近作った", run("recent", "created", "5", "--md")[1])
        self.assertIn("# 知識リマインダー（2026-10-21）", run("reminders", "2026-10-21", "--md")[1])
        self.assertEqual(run("trail", "save", "t", "a.md", "b.md")[0], 0)
        self.assertIn("1. [甲](a.md)", run("trail", "show", "t", "--md")[1])
        self.assertEqual(run("trail-export", "t", "--write", "te.md")[0], 0)
        self.assertEqual(run("trail-export", "t", "--write", "te.md")[0], 1)
        self.assertEqual(run("bookmark", "bogus")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
