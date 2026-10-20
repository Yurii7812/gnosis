#!/usr/bin/env python3
import contextlib
import datetime as dt
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import reading as rd

NOW = dt.datetime(2026, 10, 21, 9, 0, 0)


def note(root, name, title, body="", fm=""):
    (root / name).write_text(f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n{fm}---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class ReadingTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        note(r, "book.md", "知識の本", "==知識は力である== (p.12)\n普通の文。==二つ目の強調==（34ページ）\n==ページなし==\n```\n==コード内==\n```", "source: book\nauthor: 山田\nyear: 2020\n")
        note(r, "memo.md", "私のメモ", "[知識の本](book.md#p12)に書いてあった。\n[別](other.md)", "maturity: seed\n")
        note(r, "big.md", "育った", "長い本文。" * 120, "maturity: seed\n")
        for i in range(3):
            note(r, f"ref{i}.md", f"参照{i}", "[育った](big.md)")
        note(r, "alg.md", "代数", "代数の本文", "requires: basic.md, 数と式\n")
        note(r, "basic.md", "基礎", "基礎の本文")
        note(r, "num.md", "数と式", "数式", "requires: basic.md\n")
        note(r, "cyc1.md", "循環1", "", "requires: cyc2.md\n")
        note(r, "cyc2.md", "循環2", "", "requires: cyc1.md\n")
        note(r, "miss.md", "欠落", "", "requires: nowhere.md\n")
        note(r, "pb.md", "進捗", "- 📖 吾輩は猫である 50/300 2026-10-01\n- 📖 吾輩は猫である 120 2026-10-10\n- 📖 完読本 200/200 2026-09-01\n- 📖 同日 10/100 2026-10-05\n- 📖 同日 30/100 2026-10-05")
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in r.glob("*.md")}

    def same(self):
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md") if p.name in self.before})

    def test_highlights_pages_and_code_fence(self):
        h = rd.highlights(self.root)["highlights"]
        by = {x["text"]: x for x in h}
        self.assertEqual(set(by), {"知識は力である", "二つ目の強調", "ページなし"})          # コードの中は無視
        self.assertEqual((by["知識は力である"]["page"], by["二つ目の強調"]["page"], by["ページなし"]["page"]), (12, 34, None))
        self.assertEqual(by["知識は力である"]["source"], "book")
        line = by["知識は力である"]["line"]
        self.assertIn("==知識は力である==", (self.root / "book.md").read_text(encoding="utf-8").split("\n")[line - 1])   # 行番号は実ファイルの行
        self.assertEqual(len({x["id"] for x in h}), 3)
        self.assertEqual(rd.highlights(self.root, "知識の本")["count"], 3)
        self.assertEqual(rd.highlights(self.root, "memo.md")["count"], 0)
        with self.assertRaises(ValueError):
            rd.highlights(self.root, "nothing")
        self.same()

    def test_digest_draft_and_write_new_only(self):
        d = rd.digest(self.root, "book.md")
        self.assertIn("> 知識は力である\n> — [知識の本](book.md)（p.12）", d["draft"])
        self.assertLess(d["draft"].index("p.12"), d["draft"].index("p.34"))                # ページ順・ページなしは最後
        self.assertLess(d["draft"].index("p.34"), d["draft"].index("ページなし"))
        self.assertTrue(d["draft"].rstrip().endswith("Related:\n[知識の本](book.md)"))
        w = rd.digest(self.root, "book.md", "notes/digest.md", NOW)
        text = (self.root / "notes" / "digest.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\ntime: 2026-10-21 09:00:00\ntitle: 知識の本の読書メモ\n---\n\n# 知識の本の読書メモ"))
        self.assertEqual(w["written"], "notes/digest.md")
        for bad, msg in (("notes/digest.md", "上書きしません"), ("../x.md", "vault の外"), (".s/x.md", "ドット始まり"), ("x.txt", ".md")):
            with self.assertRaises(ValueError) as cm:
                rd.digest(self.root, "book.md", bad)
            self.assertIn(msg, str(cm.exception))
        with self.assertRaises(ValueError) as cm:
            rd.digest(self.root, "memo.md")
        self.assertIn("ハイライト", str(cm.exception))
        self.same()

    def test_progress_latest_by_date_and_resume(self):
        b = {x["name"]: x for x in rd.progress(self.root)["books"]}
        cat = b["吾輩は猫である"]
        self.assertEqual((cat["page"], cat["total"], cat["percent"], cat["resume_page"]), (120, 300, 40, 120))   # 合計を省いた行は前の合計を引き継ぐ
        self.assertTrue(b["完読本"]["finished"])
        self.assertIsNone(b["完読本"]["resume_page"])
        self.assertEqual(b["同日"]["page"], 30)                                                              # 同じ日は後の行
        md = rd.to_md("progress", rd.progress(self.root))
        self.assertIn("120/300（40%）", md)
        self.assertIn("再開は 120 ページから", md)
        self.assertIn("読了", md)

    def test_progress_set_appends_and_validates(self):
        r = rd.progress_set(self.root, "新しい本", 15, 200, "2026-10-21")
        self.assertEqual(r["line"], "- 📖 新しい本 15/200 2026-10-21")
        self.assertEqual({x["name"]: x["page"] for x in rd.progress(self.root)["books"]}["新しい本"], 15)
        for args in (("", 1, 10), ("本", -1, 10), ("本", 11, 10), ("本", 1, 0)):
            with self.assertRaises(ValueError):
                rd.progress_set(self.root, *args)
        with self.assertRaises(ValueError):
            rd.progress_set(self.root, "本", 1, 10, "2026-99-99")
        self.same()

    def test_maturity_list_suggest_set(self):
        m = rd.maturity(self.root)
        self.assertEqual(m["counts"], {"seed": 2, "growing": 0, "evergreen": 0})
        sug = {x["path"]: x for x in m["suggestions"]}
        self.assertEqual(set(sug), {"big.md"})                                  # 長くて 3 件から参照される種だけ。memo は短い
        self.assertEqual((sug["big.md"]["from"], sug["big.md"]["to"]), ("seed", "growing"))
        self.assertIn("自動では書き換えません", m["note_text"])
        self.same()                                                             # 提案しても書き換えない
        rd.maturity_set(self.root, "big.md", "growing")
        self.assertIn("maturity: growing\n", (self.root / "big.md").read_text(encoding="utf-8"))
        self.assertNotIn("maturity: seed", (self.root / "big.md").read_text(encoding="utf-8"))
        self.assertEqual(rd.maturity(self.root, "growing")["notes"][0]["path"], "big.md")
        rd.maturity_set(self.root, "basic.md", "evergreen")                      # front matter に無ければ足す
        self.assertIn("maturity: evergreen", (self.root / "basic.md").read_text(encoding="utf-8").split("---")[1])
        self.assertEqual(rd.maturity_set(self.root, "memo.md", "evergreen")["level"], "evergreen")
        with self.assertRaises(ValueError):
            rd.maturity_set(self.root, "memo.md", "bad")
        with self.assertRaises(ValueError):
            rd.maturity(self.root, "bad")

    def test_maturity_set_on_note_without_front_matter(self):
        (self.root / "plain.md").write_text("# 素の\n\n本文\n", encoding="utf-8")
        rd.maturity_set(self.root, "plain.md", "seed")
        self.assertEqual((self.root / "plain.md").read_text(encoding="utf-8"), "---\nmaturity: seed\n---\n\n# 素の\n\n本文\n")

    def test_learning_path_order_cycle_missing(self):
        p = rd.learning_path(self.root, "alg.md")
        self.assertEqual([x["path"] for x in p["order"]], ["basic.md", "num.md", "alg.md"])    # 前提が先・重複なし
        self.assertIsNone(p["cycle"])
        c = rd.learning_path(self.root, "cyc1.md")
        self.assertEqual(c["order"], [])
        self.assertEqual(c["cycle"], ["循環1", "循環2", "循環1"])
        m = rd.learning_path(self.root, "miss.md")
        self.assertEqual(m["missing"], [{"in": "miss.md", "requires": "nowhere.md"}])
        self.assertEqual([x["path"] for x in m["order"]], ["miss.md"])
        self.assertEqual([x["path"] for x in rd.learning_path(self.root, "basic.md")["order"]], ["basic.md"])

    def test_sources_and_back_links(self):
        s = rd.sources(self.root)["sources"]
        self.assertEqual([x["path"] for x in s], ["book.md"])
        self.assertEqual((s[0]["author"], s[0]["year"]), ("山田", "2020"))
        c = s[0]["cited_by"]
        self.assertEqual([(x["path"], x["anchor"]) for x in c], [("memo.md", "p12")])
        self.assertIn("(book.md#p12)", (self.root / "memo.md").read_text(encoding="utf-8").split("\n")[c[0]["line"] - 1])   # 戻る場所の行は実ファイルの行
        self.assertIn("(memo.md)", rd.to_md("sources", rd.sources(self.root)))

    def test_explain_coverage_is_a_hint(self):
        e = rd.explain(self.root, "book.md")
        self.assertEqual(len(e["prompts"]), 2)
        self.assertNotIn("coverage", e)                                         # 答えを渡す前に要点語は見せない
        self.assertGreaterEqual(e["key_terms_hidden"], 1)
        note(self.root, "cook.md", "料理", "ローズマリーを使ったチキンの料理。オーブンで焼いて、塩と胡椒で味を整える。")
        full = rd.explain(self.root, "cook.md", "ローズマリーを使ったチキンの料理。オーブンで焼いて、塩と胡椒で味を整える。")
        none = rd.explain(self.root, "cook.md", "全然関係ない話をしています")
        self.assertGreater(full["coverage"], none["coverage"])
        self.assertEqual(none["covered"], [])
        self.assertIn("目安", full["note_text"])

    def test_explain_partial_unaddressed_and_record(self):
        note(self.root, "cook.md", "料理", "ローズマリーを使ったチキンの料理。オーブンで焼いて、塩と胡椒で味を整える。最後にレモンを絞って仕上げる工程がとても大切です。")
        e = rd.explain(self.root, "cook.md", "ローズマリーのチキンをオーブンで焼きます", today="2026-10-20")
        self.assertIn("ローズマリー", "".join(e["covered"] + e["partial"]))
        self.assertGreaterEqual(e["coverage_loose"], e["coverage"])
        self.assertTrue(any("レモン" in x for x in e["unaddressed"]))                 # 触れていない文
        self.assertFalse(any("オーブン" in x for x in e["unaddressed"]))              # 触れた文は出ない
        self.assertNotIn("recorded", e)
        self.assertFalse((self.root / ".state" / "explain.json").exists())             # 記録しない限り何も書かない
        r1 = rd.explain(self.root, "cook.md", "全然関係ない話", record=True, today="2026-10-20")
        self.assertTrue(r1["recorded"] and r1["previous"] is None)
        r2 = rd.explain(self.root, "cook.md", "ローズマリーを使ったチキンの料理。オーブンで焼いて、塩と胡椒で味を整える。レモンを絞る。", record=True, today="2026-10-21")
        self.assertEqual(r2["previous"]["date"], "2026-10-20")
        self.assertGreater(r2["delta"], 0)
        md = rd.to_md("explain", r2)
        self.assertIn("前回（2026-10-20）", md)
        self.assertIn("採点でも", md)
        (self.root / ".state" / "explain.json").write_text("壊れた", encoding="utf-8")
        self.assertTrue(rd.explain(self.root, "cook.md", "x", record=True)["recorded"])   # 壊れた記録があっても落ちない

    def test_incremental_reading_schedule(self):
        n = rd.ir_next(self.root, "2026-10-21")
        self.assertEqual((n["item"]["state"], n["unseen"]), ("初回", 2))
        hid = n["item"]["id"]
        r = rd.ir_rate(self.root, hid, "good", "2026-10-21")
        self.assertEqual((r["interval_days"], r["due"]), (3, "2026-10-24"))
        self.assertNotEqual(rd.ir_next(self.root, "2026-10-21")["item"]["id"], hid)      # 次は別のもの
        r = rd.ir_rate(self.root, hid, "good", "2026-10-24")
        self.assertEqual(r["interval_days"], 6)                                          # 3 → 6
        self.assertEqual(rd.ir_rate(self.root, hid, "easy", "2026-10-30")["interval_days"], 21)
        self.assertEqual(rd.ir_rate(self.root, hid, "again", "2026-11-20")["interval_days"], 1)
        # 期日が来たものが未見より先
        for h in rd.highlights(self.root)["highlights"]:
            rd.ir_rate(self.root, h["id"], "good", "2026-10-21")
        self.assertIsNone(rd.ir_next(self.root, "2026-10-22")["item"])
        self.assertIsNotNone(rd.ir_next(self.root, "2026-10-22")["next_due"])
        due = rd.ir_next(self.root, "2026-10-24")
        self.assertEqual(due["item"]["state"], "復習")
        with self.assertRaises(ValueError):
            rd.ir_rate(self.root, "zzzz", "good")
        with self.assertRaises(ValueError):
            rd.ir_rate(self.root, hid, "meh")
        self.same()

    def test_ir_state_survives_corruption(self):
        hid = rd.ir_next(self.root, "2026-10-21")["item"]["id"]
        rd.ir_rate(self.root, hid, "good", "2026-10-21")
        (self.root / ".state" / "incremental.json").write_text("{bad", encoding="utf-8")
        self.assertEqual(rd.ir_next(self.root, "2026-10-21")["item"]["state"], "初回")        # 壊れたら最初から（ノートは無傷）
        self.same()

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = rd.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertIn("# ハイライト 3 件", run("highlights", "--md")[1])
        self.assertEqual(run("digest", "book.md", "--write", "d.md")[0], 0)
        self.assertEqual(run("digest", "book.md", "--write", "d.md")[0], 1)
        self.assertIn("# 読書の進捗", run("progress", "--md")[1])
        self.assertEqual(run("progress-set", "本", "5", "50", "2026-10-21")[0], 0)
        self.assertEqual(run("progress-set", "本2", "5", "2026-10-21")[0], 0)
        self.assertIn("# 成熟度", run("maturity", "--md")[1])
        self.assertEqual(run("maturity-set", "memo.md", "growing")[0], 0)
        self.assertIn("1. [基礎](basic.md)", run("path", "alg.md", "--md")[1])
        self.assertIn("# 出典", run("sources", "--md")[1])
        self.assertIn("見直しの手がかり", run("explain", "book.md", "知識は力", "--md")[1])
        self.assertIn("初回", run("ir-next", "2026-10-21", "--md")[1])
        self.assertEqual(run("ir-rate", "zz", "good")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
