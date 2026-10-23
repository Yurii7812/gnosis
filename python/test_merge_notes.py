"""ノートのマージ（\\l → m）と取り消しの回帰網。"""
import json
import tempfile
import unittest
from pathlib import Path

import merge_notes as mn
import note_format_v2 as nf


def put(root, name, title, body, extra=""):
    (root / name).write_text(f"---\ntime: 2026-10-20 10:00:00\n{extra}---\n\n# {title}\n\n" + "\n".join(body) + "\n",
                             encoding="utf-8")


class MergeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def read(self, name):
        return (self.root / name).read_text(encoding="utf-8")

    def test_merge_and_undo(self):
        r = self.root
        put(r, "index.md", "Index", ["[A](a.md)"], "attribute: group\n")
        put(r, "a.md", "A", ["本文A。", "", "ChildBranch:", "[M](m.md)"])
        put(r, "c.md", "C", ["文脈C。"])
        put(r, "g.md", "G", ["[メモ](m.md)", "[D](d.md)"], "attribute: group\n")
        put(r, "m.md", "M", ["ParentBranch:", "[A](a.md)", "Context:", "[C](c.md)", "", "スマホのメモ。", "2 行目。"])
        put(r, "d.md", "D", ["ParentBranch:", "[A](a.md)", "", "本文D。", "[M](m.md) を参照。", "", "BackLink:", "[G](g.md)"])
        put(r, "x.md", "X", ["[M](m.md) と [D](d.md)"])
        (r / ".state").mkdir()
        (r / ".state/capture_imported.json").write_text(json.dumps({"ids": {"261020": "m.md"}, "entries": {}}), encoding="utf-8")
        before = {p.name: p.read_text(encoding="utf-8") for p in r.glob("*.md")}
        res = mn.merge(r, r / "m.md", r / "d.md")
        self.assertTrue(res["ok"], res)
        self.assertFalse((r / "m.md").exists())
        d = self.read("d.md")
        # 本文は DST の本文の最後に、関係の節の手前に入る
        self.assertLess(d.index("本文D。"), d.index("スマホのメモ。"))
        self.assertLess(d.index("2 行目。"), d.index("BackLink:"))
        self.assertIn("Context:\n[C](c.md)", d)
        self.assertNotIn("m.md", d)                         # 自分へのリンクになるものは消す（文中は表示名だけ残す）
        self.assertIn("M を参照。", d)
        self.assertEqual(d.count("ParentBranch:"), 1)
        g = self.read("g.md")
        self.assertEqual(g.count("](d.md)"), 1)              # グループの中で重なったら 1 本
        self.assertIn("[D](d.md) と [D](d.md)", self.read("x.md"))   # 文中のリンクは書き換えるだけ
        a = self.read("a.md")
        self.assertNotIn("m.md", a)
        st = json.loads((r / ".state/capture_imported.json").read_text(encoding="utf-8"))
        self.assertEqual(st["ids"]["261020"], "d.md")
        self.assertTrue(mn.last(r)["ok"])
        # 取り消し: 全部元に戻る
        u = mn.undo(r)
        self.assertTrue(u["ok"], u)
        self.assertEqual(before, {p.name: p.read_text(encoding="utf-8") for p in r.glob("*.md")})
        st = json.loads((r / ".state/capture_imported.json").read_text(encoding="utf-8"))
        self.assertEqual(st["ids"]["261020"], "m.md")
        self.assertFalse(mn.last(r)["ok"])

    def test_undo_refuses_after_edit(self):
        r = self.root
        put(r, "a.md", "A", ["本文A。"])
        put(r, "b.md", "B", ["本文B。"])
        self.assertTrue(mn.merge(r, r / "b.md", r / "a.md")["ok"])
        (r / "a.md").write_text(self.read("a.md") + "あとで書いた。\n", encoding="utf-8")
        u = mn.undo(r)
        self.assertFalse(u["ok"])
        self.assertEqual(u["code"], "changed")
        self.assertTrue(mn.undo(r, force=True)["ok"])
        self.assertTrue((r / "b.md").exists())

    def test_parent_moves_when_dst_has_none(self):
        r = self.root
        put(r, "p.md", "P", ["本文P。", "", "ChildBranch:", "[S](s.md)"])
        put(r, "s.md", "S", ["ParentBranch:", "[P](p.md)", "", "本文S。"])
        put(r, "t.md", "T", ["本文T。"])
        self.assertTrue(mn.merge(r, r / "s.md", r / "t.md")["ok"])
        self.assertIn("ParentBranch:\n[P](p.md)", self.read("t.md"))
        self.assertIn("[T](t.md)", self.read("p.md"))
        nf.simple_sync(r)
        import branch_ops
        self.assertTrue(branch_ops.check(r)["ok"])

    def test_refuses_group_and_same(self):
        r = self.root
        put(r, "g.md", "G", ["[A](a.md)"], "attribute: group\n")
        put(r, "a.md", "A", ["本文A。"])
        self.assertFalse(mn.merge(r, r / "g.md", r / "a.md")["ok"])
        self.assertFalse(mn.merge(r, r / "a.md", r / "a.md")["ok"])


if __name__ == "__main__":
    unittest.main()
