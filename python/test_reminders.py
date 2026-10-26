#!/usr/bin/env python3
import contextlib
import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import reminders as rm


def note(root, name, body):
    (root / name).write_text(f"---\ntime: 2026-10-01 09:00:00\ntitle: {name}\n---\n\n# {name}\n\n{body}\n", encoding="utf-8")


class RemindersTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        note(r, "a.md", "- [ ] 薬を飲む ⏰ 2026-10-25 09:30\n- [x] 終えたもの ⏰ 2026-10-25 08:00\n歯医者の予約 ⏰ 2026-10-26\n```\n- [ ] コード内 ⏰ 2026-10-25 07:00\n```\nremind:2026-10-27T18:00 英語の書き方")
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in r.glob("*.md")}
        self.id = next(x["id"] for x in rm.scan(r) if x["text"].startswith("薬"))

    def same(self):
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md")})

    def test_scan_formats_and_ignored(self):
        s = {x["text"]: x for x in rm.scan(self.root)}
        self.assertEqual(s["薬を飲む"]["at"], "2026-10-25T09:30")
        self.assertEqual(s["歯医者の予約"]["at"], "2026-10-26T09:00")           # 時刻を省くと 09:00
        self.assertTrue(any(x["at"] == "2026-10-27T18:00" for x in s.values()))
        self.assertNotIn("コード内", s)                                          # コードブロックの中は無視
        self.assertTrue(s["終えたもの"]["task_done"])
        self.assertEqual(s["薬を飲む"]["line"], 8)
        self.same()

    def test_id_stable_when_line_moves(self):
        note(self.root, "a.md", "追加行\n追加行2\n- [ ] 薬を飲む ⏰ 2026-10-25 09:30")
        self.assertEqual(next(x["id"] for x in rm.scan(self.root) if x["text"] == "薬を飲む"), self.id)

    def test_fire_once_then_renotify_then_cap(self):
        self.assertEqual(rm.fire(self.root, "2026-10-25T09:29")["fired"], [])        # まだ
        f = rm.fire(self.root, "2026-10-25T09:30")["fired"]
        self.assertEqual([x["text"] for x in f], ["薬を飲む"])                          # 完了済みは鳴らない
        self.assertEqual(rm.fire(self.root, "2026-10-25T09:31")["fired"], [])        # 二重に鳴らさない
        self.assertEqual(rm.fire(self.root, "2026-10-25T09:59")["fired"], [])        # 再通知の間隔(30 分)前
        r2 = rm.fire(self.root, "2026-10-25T10:00")["fired"]
        self.assertEqual((r2[0]["status"], r2[0]["fire_no"]), ("renotify", 2))
        rm.fire(self.root, "2026-10-25T10:30")
        rm.fire(self.root, "2026-10-25T11:00")                                        # 4 回目
        self.assertEqual(rm.fire(self.root, "2026-10-25T12:00")["fired"], [])        # 使い切ったら鳴らさない
        lst = {x["text"]: x for x in rm.list_reminders(self.root, "2026-10-25T12:00")["reminders"]}
        self.assertEqual(lst["薬を飲む"]["status"], "exhausted")
        self.assertEqual(len(rm.history(self.root, now="2026-10-25T12:00")["unhandled"]), 1)   # 未処理として残る
        self.same()

    def test_ack_stops_everything(self):
        rm.fire(self.root, "2026-10-25T09:30")
        rm.ack(self.root, self.id, "2026-10-25T09:40")
        self.assertEqual(rm.fire(self.root, "2026-10-25T10:30")["fired"], [])
        self.assertNotIn("薬を飲む", [x["text"] for x in rm.list_reminders(self.root, "2026-10-25T10:30")["reminders"]])
        self.assertEqual(rm.history(self.root, now="2026-10-25T10:30")["unhandled"], [])
        self.assertEqual(rm.history(self.root)["history"][0]["kind"], "扱い済み")
        with self.assertRaises(ValueError):
            rm.ack(self.root, "nothing")

    def test_snooze_resets_and_hides(self):
        rm.fire(self.root, "2026-10-25T09:30")
        s = rm.snooze(self.root, self.id, 20, "2026-10-25T09:35")
        self.assertEqual(s["snooze_until"], "2026-10-25T09:55")
        self.assertEqual(rm.fire(self.root, "2026-10-25T09:50")["fired"], [])        # スヌーズ中は鳴らない
        st = {x["text"]: x["status"] for x in rm.list_reminders(self.root, "2026-10-25T09:50")["reminders"]}
        self.assertEqual(st["薬を飲む"], "snoozed")
        f = rm.fire(self.root, "2026-10-25T09:55")["fired"]                           # 明けたらもう一度
        self.assertEqual((f[0]["text"], f[0]["fire_no"]), ("薬を飲む", 1))
        for bad in (0, -5, 60 * 24 * 15):
            with self.assertRaises(ValueError):
                rm.snooze(self.root, self.id, bad)

    def test_notify_failure_is_recorded_but_does_not_lose_state(self):
        calls = []
        def boom(r):
            calls.append(r["text"])
            raise RuntimeError("no display")
        f = rm.fire(self.root, "2026-10-25T09:30", boom)["fired"]
        self.assertEqual(calls, ["薬を飲む"])
        h = rm.history(self.root)["history"][0]
        self.assertIs(h["delivered"], False)                                           # 届かなかったと分かる
        self.assertEqual(rm.fire(self.root, "2026-10-25T09:31", boom)["fired"], [])    # 記録は残っているので連打しない
        self.assertEqual(len(f), 1)

    def test_state_survives_corruption_and_never_touches_notes(self):
        rm.fire(self.root, "2026-10-25T09:30")
        (self.root / ".state" / "reminders.json").write_text("{broken", encoding="utf-8")
        f = rm.fire(self.root, "2026-10-25T09:31")["fired"]                            # 壊れていたら作り直し、過ぎた未完了を再び知らせる
        self.assertEqual([x["text"] for x in f], ["薬を飲む"])
        self.same()

    def test_cli_and_md(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = rm.main([str(self.root), *a])
            return rc, buf.getvalue()
        rc, out = run("list", "2026-10-25T09:00", "--md")
        self.assertIn("# リマインダー（2026-10-25 09:00 時点）", out)
        self.assertIn(f"ID `{self.id}`", out)
        self.assertIn("薬を飲む（1 回目・[a.md:8](a.md)）", run("fire", "2026-10-25T09:30", "--md")[1])
        self.assertIn("(a.md)", run("history", "--md")[1])
        self.assertEqual(run("snooze", self.id, "15", "2026-10-25T09:40")[0], 0)
        self.assertEqual(run("ack", self.id)[0], 0)
        self.assertEqual(run("ack", "zzz")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
