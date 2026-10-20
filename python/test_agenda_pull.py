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
        self.assertEqual(sorted(p.name for p in phone.iterdir()), [])                                # 反映できたら、スマホ側の記録は消える
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
