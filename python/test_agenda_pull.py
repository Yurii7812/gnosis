#!/usr/bin/env python3
import contextlib
import datetime as dt
import io
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import agenda_pull as pl
import agenda_push as ap

TODAY = dt.date(2026, 10, 21)


def note(root, name, title, body):
    (root / name).write_text(f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class PullTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        base = self.base = Path(self.tmp.name)
        r = self.root = base / "v"
        r.mkdir()
        note(r, "a.md", "家", "- [ ] ゴミ出し 📅 2026-10-21\n- [ ] 電球 📅 2026-10-19\n- [ ] 週次 🔁 weekly 📅 2026-10-21\n- [x] 終えた ✅ 2026-10-01")
        note(r, "b.md", "仕事", "- [ ] ゴミ出し 📅 2026-10-22\n本文")
        self.k = lambda f, t: ap.task_key(f, t)

    def done(self, *keys):
        return "\n".join(f"done\t{k}\t2026-10-21T09:12" for k in keys) + "\n"

    def test_parse_ignores_bad_lines_and_duplicates(self):
        k = self.k("a.md", "ゴミ出し")
        txt = f"# comment\ndone\t{k}\t2026-10-21T09:00\ndone\t{k}\t2026-10-21T09:05\ndone\tZZZZ\tx\nfoo\t{k}\ndone\n\ndone\t{self.k('a.md', '電球')}\r\n"
        got = pl.parse(txt)
        self.assertEqual([g["key"] for g in got], [k, self.k("a.md", "電球")])                    # 重複・不正な形は捨てる
        self.assertEqual(got[0]["at"], "2026-10-21T09:00")

    def test_apply_completes_only_matching_open_tasks(self):
        res = pl.apply_text(self.root, self.done(self.k("a.md", "ゴミ出し")), TODAY)
        self.assertEqual([x["text"] for x in res["applied"]], ["ゴミ出し"])
        a = (self.root / "a.md").read_text(encoding="utf-8")
        self.assertIn("- [x] ゴミ出し 📅 2026-10-21 ✅ 2026-10-21", a)
        self.assertIn("- [ ] 電球", a)                                                              # ほかのタスクは触らない
        b = (self.root / "b.md").read_text(encoding="utf-8")
        self.assertIn("- [ ] ゴミ出し 📅 2026-10-22", b)                                           # 別のノートの同じ文面は触らない(キーが違う)

    def test_idempotent_and_missing(self):
        k = self.k("a.md", "ゴミ出し")
        pl.apply_text(self.root, self.done(k), TODAY)
        before = (self.root / "a.md").read_text(encoding="utf-8")
        again = pl.apply_text(self.root, self.done(k, "0123456789"), TODAY)
        self.assertEqual(again["applied"], [])
        self.assertEqual(sorted(again["missing"]), sorted([k, "0123456789"]))                       # すでに完了・存在しないキーは「見つからない」
        self.assertEqual((self.root / "a.md").read_text(encoding="utf-8"), before)                  # 二重に完了しない・何も書かない

    def test_repeating_task_makes_next_occurrence(self):
        res = pl.apply_text(self.root, self.done(self.k("a.md", "週次")), TODAY)
        self.assertIn("2026-10-28", res["applied"][0]["next"])
        a = (self.root / "a.md").read_text(encoding="utf-8")
        self.assertIn("- [x] 週次", a)
        self.assertIn("- [ ] 週次 🔁 weekly 📅 2026-10-28", a)

    def test_edited_task_is_reported_not_guessed(self):
        k = self.k("a.md", "ゴミ出し")
        note(self.root, "a.md", "家", "- [ ] ゴミ出し(書き換えた) 📅 2026-10-21")
        res = pl.apply_text(self.root, self.done(k), TODAY)
        self.assertEqual((res["applied"], res["missing"]), ([], [k]))                               # 本文が変わっていたら、推測して別のタスクを完了にしない
        self.assertIn("- [ ] ゴミ出し(書き換えた)", (self.root / "a.md").read_text(encoding="utf-8"))

    def test_empty_input(self):
        self.assertEqual(pl.apply_text(self.root, "", TODAY), {"applied": [], "missing": [], "total": 0})
        self.assertEqual(pl.apply_text(self.root, "garbage\n", TODAY)["total"], 0)

    def fake_adb(self, phone: Path, fail_rm=False):
        """アプリの files/ を phone フォルダで模す偽の adb（mv / cat / rm だけ）。"""
        d = self.base / "bin"
        d.mkdir(exist_ok=True)
        script = d / "adb"
        script.write_text(f"""#!/bin/sh
# adb exec-out run-as PKG CMD files/NAME ...
shift 3   # exec-out run-as PKG
cmd=$1; shift
rel() {{ echo "{phone}/$(basename "$1")"; }}
case "$cmd" in
  mv) src=$(rel "$1"); dst=$(rel "$2"); [ -f "$src" ] && mv "$src" "$dst" || exit 1 ;;
  cat) f=$(rel "$1"); [ -f "$f" ] && cat "$f" || exit 1 ;;
  rm) {'exit 1' if fail_rm else 'shift; rm -f "$(rel "$1")"'} ;;
  tee) cat > "$(rel "$1")" ;;
esac
""", encoding="utf-8")
        script.chmod(script.stat().st_mode | stat.S_IEXEC)
        return d

    def with_adb(self, d, fn):
        old = os.environ["PATH"]
        os.environ["PATH"] = f"{d}:{old}"
        try:
            return fn()
        finally:
            os.environ["PATH"] = old

    def test_pull_moves_then_reads_then_deletes_phone_file(self):
        phone = self.base / "phone"; phone.mkdir()
        (phone / "agenda-done.tsv").write_text(self.done(self.k("a.md", "ゴミ出し")), encoding="utf-8")
        d = self.fake_adb(phone)
        res = self.with_adb(d, lambda: pl.pull(self.root, TODAY))
        self.assertEqual(len(res["applied"]), 1)
        self.assertEqual(sorted(p.name for p in phone.iterdir() if p.name.startswith("agenda-done")), [])      # 反映できたら、スマホ側の記録は消える
        sent = (phone / "agenda.tsv").read_text(encoding="utf-8")                                     # 反映後の最新の予定を送り直す(完了済みは含まれない)
        self.assertEqual(res["refreshed"], sum(1 for ln in sent.split("\n") if ln.startswith("task\t")))
        self.assertNotIn(self.k("a.md", "ゴミ出し"), sent)                                              # 完了にした a.md のゴミ出し(別のノートの同名のタスクは残る)
        self.assertIn(self.k("a.md", "電球"), sent)
        again = self.with_adb(d, lambda: pl.pull(self.root, TODAY))                                 # もう一度は何もない
        self.assertEqual((again["total"], again["applied"]), (0, []))

    def test_pull_resumes_from_processing_after_interruption(self):
        phone = self.base / "phone"; phone.mkdir()
        (phone / "agenda-done.processing").write_text(self.done(self.k("a.md", "電球")), encoding="utf-8")     # 前回、反映の途中で止まった分
        (phone / "agenda-done.tsv").write_text(self.done(self.k("a.md", "ゴミ出し")), encoding="utf-8")       # そのあと増えた分
        d = self.fake_adb(phone)
        res = self.with_adb(d, lambda: pl.pull(self.root, TODAY))
        # 実際の mv は processing を上書きする。止まった分を先に反映して消してから移すので、前回の分は失われない
        texts = sorted(x["text"] for x in res["applied"])
        self.assertIn("ゴミ出し", texts)
        self.assertIn("電球", texts)                                                                  # 前回の分も失われない

    def test_pull_failure_to_delete_is_reported(self):
        phone = self.base / "phone"; phone.mkdir()
        (phone / "agenda-done.tsv").write_text(self.done(self.k("a.md", "ゴミ出し")), encoding="utf-8")
        d = self.fake_adb(phone, fail_rm=True)
        with self.assertRaises(ValueError) as cm:
            self.with_adb(d, lambda: pl.pull(self.root, TODAY))
        self.assertIn("消せませんでした", str(cm.exception))
        self.assertIn("- [x] ゴミ出し", (self.root / "a.md").read_text(encoding="utf-8"))            # 反映自体は済んでいる

    def test_refresh_failure_is_reported_not_fatal_and_can_be_skipped(self):
        phone = self.base / "phone"; phone.mkdir()
        (phone / "agenda-done.tsv").write_text(self.done(self.k("a.md", "ゴミ出し")), encoding="utf-8")
        d = self.fake_adb(phone)
        (d / "adb").write_text((d / "adb").read_text(encoding="utf-8").replace("  tee)", "  tee) exit 1 ;;\n  tee_unused)"), encoding="utf-8")   # 送り直しだけ失敗する
        res = self.with_adb(d, lambda: pl.pull(self.root, TODAY))
        self.assertEqual(len(res["applied"]), 1)                                                      # 反映は済んでいる
        self.assertIn("スマホへ送れませんでした", res["refresh_error"])
        self.assertIn("- [x] ゴミ出し", (self.root / "a.md").read_text(encoding="utf-8"))
        (phone / "agenda-done.tsv").write_text(self.done(self.k("a.md", "電球")), encoding="utf-8")
        d2 = self.fake_adb(phone)
        res2 = self.with_adb(d2, lambda: pl.pull(self.root, TODAY, refresh=False))
        self.assertNotIn("refreshed", res2)

    # ---- 編集(日時・所要時間・通知・繰り返し・優先度) ----
    def edit(self, key, due="", time="", dur="", rem="", rep="", prio=""):
        return f"edit\t{key}\t{due}\t{time}\t{dur}\t{rem}\t{rep}\t{prio}\n"

    def a(self):
        return (self.root / "a.md").read_text(encoding="utf-8")

    def test_edit_rewrites_only_marks_of_the_matching_open_task(self):
        r = pl.apply_edits_text(self.root, self.edit(self.k("a.md", "ゴミ出し"), "2026-10-23", "08:30", "15", "1d,10m", "daily", "high"))
        self.assertEqual([x["text"] for x in r["edited"]], ["ゴミ出し"])
        self.assertIn("- [ ] ゴミ出し 📅 2026-10-23 08:30 ⌛ 15m 🔔 1d,10m 🔁 daily ⏫", self.a())
        self.assertIn("- [ ] 電球 📅 2026-10-19", self.a())                                 # ほかのタスクは変わらない
        self.assertIn("- [ ] ゴミ出し 📅 2026-10-22", (self.root / "b.md").read_text(encoding="utf-8"))   # 別のノートの同名のタスクも変わらない
        self.assertTrue(self.a().startswith("---\ntime: 2026-01-01 00:00:00\ntitle: 家\n---\n"))     # 本文・front matter はそのまま

    def test_edit_is_idempotent_last_wins_and_can_clear(self):
        k = self.k("a.md", "電球")
        q = self.edit(k, "2026-10-25", "09:00") + self.edit(k, "2026-10-26", "10:00", "30", "none", "", "low")
        r = pl.apply_edits_text(self.root, q)
        self.assertEqual(len(r["edited"]), 1)                                                # 同じキーは最後の 1 つだけ
        once = self.a()
        self.assertIn("- [ ] 電球 📅 2026-10-26 10:00 ⌛ 30m 🔔 none 🔽", once)
        pl.apply_edits_text(self.root, q)
        self.assertEqual(self.a(), once)                                                     # もう一度反映しても同じ(冪等)
        pl.apply_edits_text(self.root, self.edit(k))                                         # すべて空 = 期限・所要時間・通知・繰り返し・優先度を消す
        self.assertIn("- [ ] 電球\n", self.a())

    def test_edit_missing_rejected_done_and_crlf(self):
        r = pl.apply_edits_text(self.root, self.edit("0123456789", "2026-10-25"))
        self.assertEqual((r["edited"], r["edit_missing"]), ([], ["0123456789"]))               # 見つからない
        done_key = self.k("a.md", "終えた")
        self.assertEqual(pl.apply_edits_text(self.root, self.edit(done_key, "2026-10-25"))["edit_missing"], [done_key])    # 完了済みは変えない
        bad = self.k("a.md", "ゴミ出し")
        for q in (self.edit(bad, "2026-13-45"), self.edit(bad, "2026-10-25", "25:00"), self.edit(bad, "2026-10-25", "", "abc"), self.edit(bad, "2026-10-25", "", "", "10x"),
                  self.edit(bad, "2026-10-25", "", "", "", "sometimes"), self.edit(bad, "2026-10-25", "", "", "", "", "urgent"), self.edit(bad, "2026-10-25", "", "999999")):
            rr = pl.apply_edits_text(self.root, q)
            self.assertEqual((rr["edited"], rr["edit_rejected"]), ([], [bad]), q)                # 正しくない値は反映しない
        self.assertIn("- [ ] ゴミ出し 📅 2026-10-21\n", self.a())
        (self.root / "c.md").write_bytes("- [ ] 改行 📅 2026-10-21\r\n- [ ] 別 📅 2026-10-21\r\n".encode("utf-8"))
        pl.apply_edits_text(self.root, self.edit(self.k("c.md", "改行"), "2026-10-22", "07:00"))
        self.assertEqual((self.root / "c.md").read_bytes().decode("utf-8"), "- [ ] 改行 📅 2026-10-22 07:00\r\n- [ ] 別 📅 2026-10-21\r\n")   # CRLF を保つ
        self.assertEqual(pl.apply_edits_text(self.root, "")["edit_total"], 0)

    def test_edit_without_date_drops_time_and_repeat_task_keeps_edit_after_complete(self):
        k = self.k("a.md", "週次")
        pl.apply_edits_text(self.root, self.edit(k, "2026-10-21", "09:00", "45", "10m", "weekly"))
        res = pl.apply_text(self.root, self.done(k), TODAY)
        self.assertEqual(len(res["applied"]), 1)
        self.assertIn("- [ ] 週次 📅 2026-10-28 09:00 ⌛ 45m 🔔 10m 🔁 weekly", self.a())        # 次の回は編集した時刻・所要時間・通知を引き継ぐ
        pl.apply_edits_text(self.root, self.edit(k, "", "09:00"))
        self.assertIn("- [ ] 週次\n", self.a())                                                # 日付が空なら時刻も消える(完了済みの元の行は残る)

    def test_pull_applies_edits_before_done_and_reports(self):
        phone = self.base / "phone"; phone.mkdir()
        k = self.k("a.md", "週次")
        (phone / "agenda-edit.tsv").write_text(self.edit(k, "2026-10-21", "09:00", "", "5m", "weekly"), encoding="utf-8")
        (phone / "agenda-done.tsv").write_text(self.done(k), encoding="utf-8")
        d = self.fake_adb(phone)
        res = self.with_adb(d, lambda: pl.pull(self.root, TODAY))
        self.assertEqual((len(res["edited"]), len(res["applied"])), (1, 1))
        self.assertIn("- [ ] 週次 📅 2026-10-28 09:00 🔔 5m 🔁 weekly", self.a())              # 編集 → 完了の順
        self.assertEqual(sorted(p.name for p in phone.iterdir() if p.name.startswith(("agenda-edit", "agenda-done"))), [])
        again = self.with_adb(d, lambda: pl.pull(self.root, TODAY))
        self.assertEqual((again["edited"], again["applied"]), ([], []))

    def test_pull_resumes_edit_processing_after_interruption(self):
        phone = self.base / "phone"; phone.mkdir()
        (phone / "agenda-edit.processing").write_text(self.edit(self.k("a.md", "電球"), "2026-10-30"), encoding="utf-8")      # 前回、反映の途中で止まった分
        (phone / "agenda-edit.tsv").write_text(self.edit(self.k("a.md", "ゴミ出し"), "2026-10-31"), encoding="utf-8")        # そのあと増えた分
        d = self.fake_adb(phone)
        res = self.with_adb(d, lambda: pl.pull(self.root, TODAY))
        self.assertEqual(sorted(x["text"] for x in res["edited"]), ["ゴミ出し", "電球"])
        self.assertIn("電球 📅 2026-10-30", self.a())

    def test_no_adb(self):
        old = os.environ["PATH"]
        os.environ["PATH"] = "/nonexistent"
        try:
            with self.assertRaises(ValueError):
                pl.pull(self.root)
        finally:
            os.environ["PATH"] = old

    def test_cli(self):
        f = self.base / "done.tsv"
        f.write_text(self.done(self.k("a.md", "電球")), encoding="utf-8")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = pl.main([str(self.root), "apply", str(f)])
        self.assertEqual(rc, 0)
        self.assertIn("電球", buf.getvalue())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(pl.main([str(self.root), "apply", str(self.base / "none.tsv")]), 1)
            self.assertEqual(pl.main([str(self.root), "bogus"]), 2)


if __name__ == "__main__":
    unittest.main()
