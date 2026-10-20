#!/usr/bin/env python3
import contextlib
import datetime as dt
import hashlib
import io
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import agenda_push as ap

TODAY = dt.date(2026, 10, 21)
NOW = dt.datetime(2026, 10, 21, 7, 0)


def note(root, name, title, body):
    (root / name).write_text(f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class AgendaPushTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name) / "v"
        r.mkdir()
        note(r, "a.md", "家のこと", "- [ ] 電球を替える 📅 2026-10-19\n- [ ] ゴミ出し 📅 2026-10-21 09:30 ⏫\n- [x] 終えたもの 📅 2026-10-20 ✅ 2026-10-20\n- [ ] いつか\n- [ ] 来月 📅 2026-11-20")
        note(r, "b.md", "仕事\tのタブ", "- [ ] 資料\tを送る 📅 2026-10-21\n- [ ] 開始前 🛫 2027-01-01 📅 2027-01-02\n- [ ] 待ち id:x1\n- [ ] 依存 after:x1\n- [ ] 予定日だけ ⏳ 2026-10-22")
        self.before = {str(p.relative_to(r)): hashlib.md5(p.read_bytes()).hexdigest() for p in r.rglob("*") if p.is_file()}

    def test_snapshot_filters_and_orders(self):
        s = ap.snapshot(self.root, TODAY, NOW)
        texts = [(t["due"], t["time"], t["priority"], t["text"]) for t in s["tasks"]]
        self.assertEqual(texts, [("2026-10-19", "", "", "電球を替える"), ("2026-10-21", "09:30", "high", "ゴミ出し"), ("2026-10-21", "", "", "資料 を送る"),
                                  ("2026-10-22", "", "", "予定日だけ"), ("2026-11-20", "", "", "来月"), ("", "", "", "待ち"), ("", "", "", "いつか")])   # 期限なしは、ノートの題の順（仕事… が 家のこと より先）
        # 除くもの: 完了済み・開始日前・他のタスクを待っている(依存)
        flat = " ".join(t["text"] for t in s["tasks"])
        for gone in ("終えたもの", "開始前", "依存"):
            self.assertNotIn(gone, flat)
        self.assertEqual(s["generated"], "2026-10-21T07:00")
        self.assertEqual(s["total_open"], 7)

    def test_tsv_is_one_line_per_task_without_stray_tabs(self):
        tsv = ap.to_tsv(ap.snapshot(self.root, TODAY, NOW))
        lines = tsv.rstrip("\n").split("\n")
        self.assertEqual(lines[0], "# gnosis-agenda v1")
        self.assertEqual(lines[1], "generated\t2026-10-21T07:00")
        for ln in lines[2:]:
            f = ln.split("\t")
            self.assertEqual((len(f), f[0]), (7, "task"), ln)                               # 本文・題にタブがあっても列がずれない
        self.assertRegex(tsv, r"task\t[0-9a-f]{10}\t2026-10-21\t\t\t仕事 のタブ\t資料 を送る")      # タブは空白に・キーは 10 桁

    def test_task_key_is_stable_and_distinct(self):
        k = ap.task_key("a.md", "ゴミ出し")
        self.assertEqual(k, ap.task_key("a.md", "ゴミ出し"))
        self.assertEqual(len(k), 10)
        self.assertNotEqual(k, ap.task_key("b.md", "ゴミ出し"))                                  # 別のノートの同じ文面は別のキー
        self.assertNotEqual(k, ap.task_key("a.md", "ゴミ出し2"))
        self.assertEqual(ap.task_key("a.md", "ゴミ\t出し"), ap.task_key("a.md", "ゴミ 出し"))     # タブは空白と同じ扱い(送るときの整形と一致)
        self.assertEqual(ap.task_key("a.md", "ゴミ出し"), "00ff4958bf")                          # Kotlin 側の単体試験と共有する固定の値
        # 行が動いてもキーは変わらない
        s1 = {t["text"]: t["key"] for t in ap.snapshot(self.root, TODAY, NOW)["tasks"]}
        note(self.root, "a.md", "家のこと", "追加の行\n\n- [ ] 電球を替える 📅 2026-10-19\n- [ ] ゴミ出し 📅 2026-10-21 09:30 ⏫")
        s2 = {t["text"]: t["key"] for t in ap.snapshot(self.root, TODAY, NOW)["tasks"]}
        self.assertEqual(s1["ゴミ出し"], s2["ゴミ出し"])

    def test_limit_and_empty(self):
        many = "\n".join(f"- [ ] t{i} 📅 2026-12-{(i % 28) + 1:02d}" for i in range(250))
        note(self.root, "many.md", "多い", many)
        s = ap.snapshot(self.root, TODAY, NOW)
        self.assertEqual((len(s["tasks"]), s["total_open"]), (200, 257))
        empty = Path(self.tmp.name) / "empty"
        empty.mkdir()
        e = ap.snapshot(empty, TODAY, NOW)
        self.assertEqual((e["tasks"], e["total_open"]), ([], 0))
        self.assertEqual(ap.to_tsv(e), "# gnosis-agenda v1\ngenerated\t" + e["generated"] + "\n")

    def test_write_never_overwrites_and_vault_is_read_only(self):
        out = Path(self.tmp.name) / "agenda.tsv"
        r = ap.write(self.root, out, TODAY)
        self.assertEqual(r["tasks"], 7)
        self.assertTrue(out.read_text(encoding="utf-8").startswith("# gnosis-agenda v1\n"))
        with self.assertRaises(ValueError):
            ap.write(self.root, out, TODAY)
        self.assertEqual(self.before, {str(p.relative_to(self.root)): hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.rglob("*") if p.is_file()})

    def fake_adb(self, fail_at=None):
        d = Path(self.tmp.name) / "bin"
        d.mkdir(exist_ok=True)
        log = Path(self.tmp.name) / "adb.log"
        script = d / "adb"
        script.write_text(f"""#!/bin/sh
echo "$@" >> "{log}"
case "$*" in
  *tee*) cat > "{Path(self.tmp.name)}/pushed.tsv"; [ "{fail_at}" = "tee" ] && exit 1; exit 0 ;;
  *mv*) [ "{fail_at}" = "mv" ] && exit 1; exit 0 ;;
esac
exit 0
""", encoding="utf-8")
        script.chmod(script.stat().st_mode | stat.S_IEXEC)
        return d, log

    def test_push_uses_tee_then_mv_into_app_files_only(self):
        d, log = self.fake_adb()
        old = os.environ["PATH"]
        os.environ["PATH"] = f"{d}:{old}"
        try:
            r = ap.push(self.root, TODAY)
        finally:
            os.environ["PATH"] = old
        self.assertEqual((r["pushed"], r["total_open"]), (7, 7))
        calls = log.read_text(encoding="utf-8").strip().split("\n")
        self.assertEqual(calls, ["exec-in run-as net.gnosis.capture tee files/agenda.tsv.tmp", "exec-out run-as net.gnosis.capture mv files/agenda.tsv.tmp files/agenda.tsv"])   # 書き込み先はアプリの files/agenda.tsv だけ
        self.assertTrue((Path(self.tmp.name) / "pushed.tsv").read_text(encoding="utf-8").startswith("# gnosis-agenda v1"))

    def test_push_failures_are_reported(self):
        for stage in ("tee", "mv"):
            d, _ = self.fake_adb(stage)
            old = os.environ["PATH"]
            os.environ["PATH"] = f"{d}:{old}"
            try:
                with self.assertRaises(ValueError, msg=stage):
                    ap.push(self.root, TODAY)
            finally:
                os.environ["PATH"] = old
        old = os.environ["PATH"]
        os.environ["PATH"] = "/nonexistent"
        try:
            with self.assertRaises(ValueError) as cm:
                ap.push(self.root, TODAY)
            self.assertIn("adb が見つかりません", str(cm.exception))
        finally:
            os.environ["PATH"] = old

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = ap.main([str(self.root), *a])
            return rc, buf.getvalue()
        rc, out = run("show", "2026-10-21")
        self.assertEqual(rc, 0)
        self.assertRegex(out, r"task\t[0-9a-f]{10}\t2026-10-19")
        self.assertEqual(run("write", str(Path(self.tmp.name) / "x.tsv"), "2026-10-21")[0], 0)
        self.assertEqual(run("write", str(Path(self.tmp.name) / "x.tsv"))[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
