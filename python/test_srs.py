#!/usr/bin/env python3
import datetime as dt
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import srs

D = dt.date


class SrsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "a.md").write_text("---\ntitle: A\n---\n\n# A\n\nQ: 首都は？\nA: 東京\n\nQ: 複数行の問い\n続き\nA: 答え1\n答え2\n\n日本の首都は{{東京}}で、人口は{{c2::約1400万人::ヒント}}。\n\nふつうの文。\n\n```\nQ: コード内\nA: 無視\n{{無視}}\n```\n", encoding="utf-8")
        (self.root / "b.md").write_text("# B\n\n水の化学式は{{c1::H2O}}、沸点は{{c2::100}}度。\n", encoding="utf-8")
        (self.root / ".trash").mkdir()
        (self.root / ".trash" / "t.md").write_text("Q: ごみ\nA: 除外\n", encoding="utf-8")
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md")}

    def test_parse(self):
        cards = srs.parse_cards((self.root / "a.md").read_text(encoding="utf-8"), "a.md")
        fronts = [c["front"] for c in cards]
        self.assertEqual(len(cards), 4)                        # Q/A 2 + 穴埋めの番号 2（番号なしと c2）。ふつうの文・コード内は対象外
        qa = [c for c in cards if c["kind"] == "qa"]
        self.assertEqual((qa[0]["front"], qa[0]["back"]), ("首都は？", "東京"))
        self.assertEqual((qa[1]["front"], qa[1]["back"]), ("複数行の問い\n続き", "答え1\n答え2"))
        cl = [c for c in cards if c["kind"] == "cloze"]
        self.assertEqual(len(cl), 2)
        self.assertEqual(cl[0]["front"], "日本の首都は[…]で、人口は約1400万人。")           # 番号なし(0)を隠す
        self.assertEqual(cl[0]["back"], "日本の首都は**東京**で、人口は約1400万人。")
        self.assertEqual(cl[1]["front"], "日本の首都は東京で、人口は[ヒント]。")             # c2 を隠す（ヒントつき）
        self.assertTrue(all("コード内" not in f and "無視" not in f for f in fronts))
        b = srs.parse_cards((self.root / "b.md").read_text(encoding="utf-8"), "b.md")
        self.assertEqual([c["front"] for c in b], ["水の化学式は[…]、沸点は100度。", "水の化学式はH2O、沸点は[…]度。"])  # c1・c2 で別のカード
        self.assertEqual(len({c["id"] for c in cards + b}), 6)                              # ID はすべて別

    def test_front_matter_is_not_cards(self):
        self.assertEqual(srs.parse_cards("---\ntitle: Q: x\nnote: {{a}}\n---\n\n本文\n", "x.md"), [])

    def test_collect_skips_hidden_dirs(self):
        paths = {c["path"] for c in srs.collect(self.root)}
        self.assertEqual(paths, {"a.md", "b.md"})

    def test_sm2_schedule(self):
        t = D(2026, 10, 20)
        s1 = srs.schedule(None, 5, t)
        self.assertEqual((s1["interval"], s1["reps"], s1["due"]), (1, 1, "2026-10-21"))
        s2 = srs.schedule(s1, 5, D(2026, 10, 21))
        self.assertEqual((s2["interval"], s2["reps"]), (6, 2))
        s3 = srs.schedule(s2, 5, D(2026, 10, 27))
        self.assertEqual(s3["interval"], round(6 * s2["ease"]))                            # 3 回目は 前の間隔 × ease
        self.assertGreater(s3["ease"], 2.5)                                                # 満点で ease が上がる
        # 忘れた: 反復をやり直し・翌日・lapse が増える。ease は変えない（原典）
        f = srs.schedule(s3, 2, D(2026, 11, 20))
        self.assertEqual((f["interval"], f["reps"], f["lapses"], f["due"], f["ease"]), (1, 0, 1, "2026-11-21", s3["ease"]))
        # ease は 1.3 より下がらない
        c = {"ease": 1.31, "interval": 5, "reps": 5, "lapses": 0}
        self.assertEqual(srs.schedule(c, 3, t)["ease"], 1.3)
        for bad in (-1, 6):
            with self.assertRaises(ValueError):
                srs.schedule(None, bad, t)

    def test_due_new_answer_flow(self):
        t = D(2026, 10, 20)
        due = srs.due(self.root, t)
        self.assertEqual(len(due), 6)                                                      # 全部新規
        self.assertEqual(len(srs.due(self.root, t, limit=3)), 3)
        self.assertEqual(len(srs.due(self.root, t, new_limit=2)), 2)                       # 新規は 1 日の上限
        first = due[0]
        srs.answer(self.root, first["id"], 4, t)
        self.assertNotIn(first["id"], [c["id"] for c in srs.due(self.root, t)])            # 答えたら今日はもう出ない
        self.assertNotIn(first["id"], [c["id"] for c in srs.due(self.root, D(2026, 10, 20))])
        self.assertIn(first["id"], [c["id"] for c in srs.due(self.root, D(2026, 10, 21))])  # 翌日に期日
        # 期日が来たカードが新規より先
        st = srs.stats(self.root, D(2026, 10, 21))
        self.assertEqual((st["cards"], st["due"], st["new"], st["later"]), (6, 1, 5, 0))
        order = srs.due(self.root, D(2026, 10, 21))
        self.assertEqual(order[0]["id"], first["id"])
        self.assertEqual(srs.stats(self.root, t)["reviewed_today"], 1)
        # 記録は派生データ: 消してもカードは残り、全部新規に戻る
        srs.state_path(self.root).unlink()
        self.assertEqual(srs.stats(self.root, t)["new"], 6)

    def test_card_identity_follows_content(self):
        t = D(2026, 10, 20)
        c = srs.collect(self.root)[0]
        srs.answer(self.root, c["id"], 5, t)
        # 無関係な行を足してもカードは同じ（行番号に依らない）
        p = self.root / "a.md"
        p.write_text("追記の行\n\n" + p.read_text(encoding="utf-8"), encoding="utf-8")
        self.assertIn(c["id"], {x["id"] for x in srs.collect(self.root)})
        self.assertEqual(srs.status(next(x for x in srs.collect(self.root) if x["id"] == c["id"]), srs.load_state(self.root), t), "later")
        # カードの中身を直すと新しいカード。古い ID には答えられない
        p.write_text(p.read_text(encoding="utf-8").replace("東京\n", "とうきょう\n", 1), encoding="utf-8")
        self.assertNotIn(c["id"], {x["id"] for x in srs.collect(self.root)})
        with self.assertRaises(ValueError):
            srs.answer(self.root, c["id"], 5, t)

    def test_random_is_bounded_and_does_not_touch_state(self):
        r = srs.random_cards(self.root, 3, seed=1)
        self.assertEqual(len(r), 3)
        self.assertEqual(len(srs.random_cards(self.root, 100)), 6)
        self.assertFalse(srs.state_path(self.root).exists())                               # 出題だけでは記録しない

    def test_vault_notes_untouched_and_corrupt_state(self):
        srs.answer(self.root, srs.collect(self.root)[0]["id"], 3, D(2026, 10, 20))
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md")})
        srs.state_path(self.root).write_text("{壊れた", encoding="utf-8")
        with self.assertRaises(ValueError):
            srs.load_state(self.root)                                                      # 黙って捨てない
        srs.state_path(self.root).write_text("[]", encoding="utf-8")
        with self.assertRaises(ValueError):
            srs.load_state(self.root)

    def test_cli(self):
        self.assertEqual(srs.main([str(self.root), "stats", "2026-10-20"]), 0)
        self.assertEqual(srs.main([str(self.root), "answer", "nope", "5", "2026-10-20"]), 1)
        self.assertEqual(srs.main([str(self.root), "bogus"]), 2)


if __name__ == "__main__":
    unittest.main()
