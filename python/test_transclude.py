#!/usr/bin/env python3
import contextlib
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import transclude as tc


def note(root, name, title, body):
    (root / name).write_text(f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class TranscludeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        note(r, "src.md", "資料", "導入の文。\n\n## 栽培\n\n水やりは控えめに。\n\n要点の段落。 ^key\n\n## 料理\n\n焼く。\n\nParentBranch:\n[親](p.md)")
        note(r, "main.md", "本体", "前の文。\n\n{{include: src.md#栽培}}\n\n{{include: src.md#^key}}\n\n{{include: src.md}}\n\n後の文。")
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in r.glob("*.md")}

    def same(self):
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md") if p.name in self.before})

    def test_expand_section_block_and_whole_note(self):
        r = tc.expand(self.root, "main.md")
        t = r["text"]
        self.assertEqual(r["problems"], [])
        self.assertIn("> 水やりは控えめに。", t)
        self.assertIn("> — 出典: [資料](src.md#栽培)", t)                         # 出典リンク
        self.assertIn("> 要点の段落。\n> — 出典: [資料](src.md#^key)", t)           # ブロックは ID の印を外して取り込む
        self.assertNotIn(" ^key", t)                                              # ID の印は、節・全体の取り込みでも表示に出さない
        whole = t.split("> — 出典: [資料](src.md#^key)")[1]
        self.assertIn("> 導入の文。", whole)
        self.assertNotIn("# 資料", whole)                                         # 全体の取り込みは題を含めない
        self.assertNotIn("ParentBranch", whole)                                   # 関係ブロックも含めない
        self.assertIn("前の文。", t)
        self.assertIn("後の文。", t)
        self.assertNotIn("{{include", t)
        self.same()                                                               # 元のノートは書き換えない

    def test_cycle_is_detected_and_stops(self):
        note(self.root, "a.md", "A", "{{include: b.md}}")
        note(self.root, "b.md", "B", "{{include: a.md}}")
        r = tc.expand(self.root, "a.md")
        self.assertEqual({p["problem"] for p in r["problems"]}, {"cycle"})
        self.assertIn("⚠ 循環しているので展開しません", r["text"])
        self.assertLess(len(r["text"]), 500)                                      # 無限に広がらない
        note(self.root, "self.md", "S", "{{include: self.md}}")
        self.assertEqual(tc.expand(self.root, "self.md")["problems"][0]["problem"], "cycle")   # 自分自身

    def test_three_note_cycle(self):
        note(self.root, "x.md", "X", "{{include: y.md}}")
        note(self.root, "y.md", "Y", "{{include: z.md}}")
        note(self.root, "z.md", "Z", "{{include: x.md}}")
        r = tc.expand(self.root, "x.md")
        self.assertEqual([p["problem"] for p in r["problems"]], ["cycle"])

    def test_depth_limit(self):
        for i in range(8):
            note(self.root, f"d{i}.md", f"D{i}", f"{{{{include: d{i + 1}.md}}}}" if i < 7 else "底")
        r = tc.expand(self.root, "d0.md", max_depth=3)
        self.assertIn("depth", {p["problem"] for p in r["problems"]})
        self.assertNotIn("底", r["text"])
        deep = tc.expand(self.root, "d0.md", max_depth=10)
        self.assertEqual(deep["problems"], [])
        self.assertIn("> > > > > > > 底", deep["text"])                           # 入れ子は引用が重なる

    def test_nested_includes_expand_inside(self):
        note(self.root, "outer.md", "外", "外の文。\n\n{{include: mid.md}}")
        note(self.root, "mid.md", "中", "中の文。\n\n{{include: src.md#料理}}")
        t = tc.expand(self.root, "outer.md")["text"]
        self.assertIn("> 中の文。", t)
        self.assertIn("> > 焼く。", t)

    def test_missing_target_and_anchor(self):
        note(self.root, "m.md", "M", "{{include: nowhere.md}}\n{{include: src.md#存在しない}}\n{{include: src.md#^nope}}")
        r = tc.expand(self.root, "m.md")
        self.assertEqual([p["problem"] for p in r["problems"]], ["missing", "anchor", "anchor"])
        self.assertEqual(r["text"].count("⚠"), 3)

    def test_code_block_includes_are_literal(self):
        note(self.root, "c.md", "C", "```\n{{include: src.md}}\n```")
        r = tc.expand(self.root, "c.md")
        self.assertIn("{{include: src.md}}", r["text"])
        self.assertEqual(r["problems"], [])

    def test_check_whole_vault_dedupes(self):
        note(self.root, "a.md", "A", "{{include: b.md}}")
        note(self.root, "b.md", "B", "{{include: a.md}}")
        r = tc.check(self.root)
        self.assertEqual(r["notes_with_includes"], 3)                             # main.md・a.md・b.md
        keys = [(p["file"], p["line"], p["problem"]) for p in r["problems"]]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertTrue(all(p["problem"] == "cycle" for p in r["problems"]))
        self.same()

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = tc.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertIn("> 水やりは控えめに。", run("expand", "main.md", "--md")[1])
        self.assertEqual(run("expand", "main.md")[0], 0)
        self.assertIn("問題 0 件", run("check", "--md")[1])
        self.assertEqual(run("expand", "nothing.md")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
