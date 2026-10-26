#!/usr/bin/env python3
import datetime as dt
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import thinking as th

NOW = dt.datetime(2026, 10, 20, 12, 0, 0)


def fill(text: str, section: str, body: str) -> str:
    """雛形の節 `## section` の直後（空行 1 つの後）に body を入れる。"""
    head = f"## {section}\n\n"
    assert head in text, section
    return text.replace(head, head + body + "\n", 1)


class ThinkingTest(unittest.TestCase):
    def test_every_kind_makes_a_valid_template(self):
        self.assertEqual(len(th.SPECS), 12)                                   # KM05〜KM16 の 12 種
        for kind, spec in th.SPECS.items():
            text = th.new_text(kind, "題", now=NOW)
            self.assertTrue(text.startswith("---\n"), kind)
            self.assertIn(f"thinking: {kind}\n", text)
            self.assertIn("# 題", text)
            sec = th._sections(text)
            self.assertEqual(list(sec), [n for n, _, _ in spec["sections"]], kind)   # 節は仕様どおり・順序どおり
            c = th.check(text)
            self.assertTrue(c["ok"], kind)
            self.assertEqual(c["missing"], [], kind)
            self.assertEqual(len(c["empty"]) > 0, True, kind)                     # 雛形のままは「まだ空」と分かる

    def test_unknown_kind_and_not_a_thinking_note(self):
        with self.assertRaises(ValueError):
            th.new_text("nope", "x")
        c = th.check("---\ntitle: ふつうのノート\n---\n\n# x\n")
        self.assertFalse(c["ok"])
        self.assertTrue(c["notes"])

    def test_missing_and_empty_sections(self):
        text = th.new_text("swot", "S", now=NOW)
        text = text.replace("## 脅威（外部・悪い）\n\n- \n\n", "")                 # 節を消した
        c = th.check(text)
        self.assertFalse(c["ok"])
        self.assertEqual(c["missing"], ["脅威（外部・悪い）"])
        text = fill(text, "強み（内部・良い）", "- 技術力")
        self.assertEqual(th.check(text)["counts"]["強み（内部・良い）"], 1)
        self.assertNotIn("強み（内部・良い）", th.check(text)["empty"])
        # 空の箇条書き（`- ` だけ）は数えない
        self.assertIn("弱み（内部・悪い）", th.check(text)["empty"])

    def test_headings_inside_code_blocks_are_not_sections(self):
        text = th.new_text("5w1h", "x", now=NOW) + "\n```\n## Why（なぜ）\n偽の節\n```\n"
        self.assertEqual(list(th._sections(text)).count("Why（なぜ）"), 1)

    def test_ibis_structure(self):
        text = th.new_text("ibis", "I", now=NOW)
        text = fill(text, "Issue（問題）", "どの DB にするか")
        text = fill(text, "Position（提案）", "- P1: SQLite\n- P2: PostgreSQL")
        text = fill(text, "Argument（根拠）", "- +P1: 配布が簡単\n- -P1: 同時書き込みに弱い\n- +P3: 存在しない提案\n- ただの文")
        c = th.check(text)
        joined = "\n".join(c["notes"])
        self.assertIn("存在しない提案 P3", joined)
        self.assertIn("根拠の書き方は", joined)
        self.assertIn("提案 P2 に根拠がまだありません", joined)
        s = th.summary(text)
        self.assertEqual(s["positions"]["P1"], {"pro": 1, "con": 1})
        self.assertEqual(s["positions"]["P2"], {"pro": 0, "con": 0})
        text2 = th.new_text("ibis", "I", now=NOW)
        text2 = fill(text2, "Position（提案）", "- 名前の無い提案")
        self.assertIn("P1:", "\n".join(th.check(text2)["notes"]))

    def test_adr_state_and_history(self):
        text = th.new_text("adr", "A", now=NOW)
        self.assertEqual(th.check(text)["notes"], [])                             # 既定は「提案中」で問題なし
        text = text.replace("## 状態\n\n提案中", "## 状態\n\n採用")
        notes = "\n".join(th.check(text)["notes"])
        self.assertIn("『決定』が空", notes)
        self.assertIn("変更履歴", notes)
        text = fill(text, "決定", "SQLite を使う")
        text = fill(text, "変更履歴", "- 2026-10-20 採用（性能試験の結果）")
        self.assertEqual(th.check(text)["notes"], [])
        bad = text.replace("## 状態\n\n採用", "## 状態\n\nたぶん")
        self.assertIn("のどれかで始めて", "\n".join(th.check(bad)["notes"]))
        self.assertEqual(th.summary(text)["state"], "採用")

    def test_mece_only_suspects_never_asserts(self):
        text = th.new_text("mece", "M", now=NOW)
        text = fill(text, "区分", "- 国内の個人顧客\n- 国内の法人顧客\n- 海外の顧客")
        c = th.check(text)
        self.assertTrue(any("重複の疑い" in n and "国内" in n for n in c["notes"]))   # 同じ語「国内」「顧客」が複数の区分に
        self.assertTrue(all("重複しています" not in n and "漏れています" not in n for n in c["notes"]))   # 断定しない
        text = th.new_text("mece", "M", now=NOW)
        self.assertTrue(any("2 つ未満" in n for n in th.check(text)["notes"]))

    def test_hats_and_swot_and_kj_hints(self):
        t = th.new_text("hats", "H", now=NOW)
        t = fill(t, "白（事実・データ）", "- 売上は前年比 -5%")
        self.assertTrue(any("青" in n for n in th.check(t)["notes"]))
        t = th.new_text("swot", "S", now=NOW)
        for sec in ("強み（内部・良い）", "弱み（内部・悪い）", "機会（外部・良い）", "脅威（外部・悪い）"):
            t = fill(t, sec, "- 何か")
        self.assertTrue(any("打ち手" in n for n in th.check(t)["notes"]))
        t = th.new_text("kj", "K", now=NOW)
        t = fill(t, "カード", "- a\n- b")
        self.assertTrue(any("カードが少なめ" in n for n in th.check(t)["notes"]))

    def test_scamper_target(self):
        t = th.new_text("scamper", "S", ["水筒"], now=NOW)
        self.assertIn("対象: 水筒", t)
        self.assertTrue(th.check(t)["ok"])

    def test_cli_and_no_overwrite(self):
        with tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test")) as d:
            p = Path(d) / "n.md"
            self.assertEqual(th.main(["new", "feynman", str(p), "量子"]), 0)
            before = p.read_text(encoding="utf-8")
            self.assertEqual(th.main(["new", "swot", str(p), "別"]), 1)          # 上書きしない
            self.assertEqual(p.read_text(encoding="utf-8"), before)
            self.assertEqual(th.main(["check", str(p)]), 0)
            self.assertEqual(th.main(["summary", str(p)]), 0)
            self.assertEqual(th.main(["kinds"]), 0)
            self.assertEqual(th.main(["bogus"]), 2)


if __name__ == "__main__":
    unittest.main()
