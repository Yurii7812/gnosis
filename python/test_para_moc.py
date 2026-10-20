#!/usr/bin/env python3
import contextlib
import datetime as dt
import hashlib
import io
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import para_moc as pm


def note(root, name, title, body="", extra=""):
    (root / name).write_text(f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n{extra}---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class ParaMocTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        note(r, "proj.md", "引っ越し", "- [ ] 荷造り 📅 2026-11-01")
        note(r, "area.md", "健康", "", "attribute: group\n")
        note(r, "ref.md", "睡眠の論文", "睡眠について")
        note(r, "oldref.md", "古い資料", "昔の資料")
        note(r, "forced.md", "指定した", "資料のつもりだが", "para: area\n")
        note(r, "doneproj.md", "終わった件", "- [x] 全部終わった ✅ 2024-01-01")
        old = time.time() - 900 * 86400
        for n in ("oldref.md", "doneproj.md"):
            os.utime(r / n, (old, old))
        # 健康グループの中身
        note(r, "sleep.md", "睡眠", "ParentBranch:\n\nGroup:\n[健康](area.md)\n", )
        note(r, "sub.md", "運動", "Group:\n[健康](area.md)\n", "attribute: group\n")
        note(r, "run.md", "ランニング", "Group:\n[運動](sub.md)\n")
        note(r, "linked.md", "本文リンク先", "")
        (r / "area.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: 健康\nattribute: group\n---\n\n# 健康\n\n[本文リンク先](linked.md)\n", encoding="utf-8")
        note(r, "t1.md", "睡眠の質", "睡眠の質を上げる方法。睡眠の環境と睡眠の習慣")
        note(r, "t2.md", "夜の睡眠", "睡眠の時間を決める")
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in r.glob("*.md")}

    def same(self):
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md") if p.name in self.before})

    def test_para_classifies_with_reasons_and_respects_explicit(self):
        r = pm.para(self.root, 365, dt.date.today())
        by = {x["path"]: (cat, x) for cat, xs in r["categories"].items() for x in xs}
        self.assertEqual(by["proj.md"][0], "project")
        self.assertIn("未完了のタスクが 1 件", by["proj.md"][1]["why"])
        self.assertEqual(by["area.md"][0], "area")
        self.assertEqual(by["ref.md"][0], "resource")
        self.assertEqual(by["oldref.md"][0], "archive")
        self.assertEqual(by["doneproj.md"][0], "archive")                      # 終えたタスクだけ・古い
        self.assertEqual(by["forced.md"][0], "area")                            # 自分の指定が最優先
        self.assertTrue(by["forced.md"][1]["explicit"])
        self.assertIn("自分で指定", by["forced.md"][1]["why"])
        self.assertTrue(all(x["why"] for _, x in by.values()))                  # 根拠の無い分類はない
        self.assertEqual(sum(r["counts"].values()), len(by))                    # どのノートもちょうど 1 つ
        self.assertIn("移動も変更もしていません", r["note_text"])
        self.same()

    def test_para_days_threshold(self):
        r = pm.para(self.root, 5000, dt.date.today())
        self.assertEqual(r["counts"]["archive"], 0)                             # 古さの基準を上げれば Archive は空

    def test_moc_groups_members_by_subgroup(self):
        m = pm.moc(self.root, "area.md")
        self.assertTrue(m["is_group"])
        self.assertEqual([s["path"] for s in m["subgroups"]], ["sub.md"])
        self.assertEqual([x["path"] for x in m["subgroups"][0]["members"]], ["run.md"])
        self.assertEqual({x["path"] for x in m["notes"]}, {"sleep.md", "linked.md"})
        self.assertEqual(m["count"], 3)
        self.assertEqual(pm.moc(self.root, "健康")["group"], "area.md")
        self.assertFalse(pm.moc(self.root, "ref.md")["is_group"])
        with self.assertRaises(ValueError):
            pm.moc(self.root, "nothing")
        md = pm.to_md("moc", m)
        self.assertIn("## [運動](sub.md)", md)
        self.assertIn("- [ランニング](run.md)", md)
        self.same()

    def test_propose_and_mark_already_in_index(self):
        p = pm.propose(self.root, "睡眠")
        paths = [x["path"] for x in p["items"]]
        self.assertIn("t1.md", paths)
        self.assertIn("t2.md", paths)
        self.assertIn("sleep.md", paths)
        sleep = next(x for x in p["items"] if x["path"] == "sleep.md")
        self.assertEqual(sleep["already_in"], ["健康"])                          # すでに索引にある
        self.assertEqual(next(x for x in p["items"] if x["path"] == "t1.md")["already_in"], [])
        self.assertIn("睡眠の索引（案）", p["draft"])
        self.assertIn("既存の索引は変えません", p["note_text"])
        self.assertEqual(pm.propose(self.root, "zzzzqqq")["items"], [])
        self.same()

    def test_write_draft_new_note_only(self):
        r = pm.write_draft(self.root, "睡眠", "moc/sleep.md", now=dt.datetime(2026, 10, 21, 9, 0, 0))
        text = (self.root / "moc" / "sleep.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\ntime: 2026-10-21 09:00:00\ntitle: 睡眠の索引（案）\nmoc: true\n---\n\n# 睡眠の索引（案）\n"))
        self.assertNotIn("attribute", text)                                      # グループにはしない
        self.assertEqual(text.count("# 睡眠の索引（案）"), 1)
        self.assertGreaterEqual(r["items"], 2)
        for bad, msg in (("moc/sleep.md", "上書きしません"), ("../x.md", "vault の外"), (".state/x.md", "ドット始まり")):
            with self.assertRaises(ValueError) as cm:
                pm.write_draft(self.root, "睡眠", bad)
            self.assertIn(msg, str(cm.exception))
        with self.assertRaises(ValueError):
            pm.write_draft(self.root, "zzzzqqq", "moc/none.md")
        self.assertFalse((self.root / "moc" / "none.md").exists())
        self.same()

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = pm.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertIn("## Projects", run("para", "--md")[1])
        self.assertIn("# MOC: 健康", run("moc", "area.md", "--md")[1])
        self.assertIn("睡眠の索引（案）", run("propose", "睡眠", "--md")[1])
        self.assertEqual(run("propose", "睡眠", "--write", "n.md")[0], 0)
        self.assertEqual(run("propose", "睡眠", "--write", "n.md")[0], 1)
        self.assertEqual(run("moc", "nothing")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
