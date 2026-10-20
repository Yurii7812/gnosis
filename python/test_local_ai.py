#!/usr/bin/env python3
import datetime as dt
import hashlib
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import local_ai as ai
import vault_index as vi

TODAY = dt.date(2026, 10, 20)


def note(root, name, title, body, time_="2026-10-01 09:00:00", extra=""):
    (root / name).write_text(f"---\ntime: {time_}\ntitle: {title}\n{extra}---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class AiTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        note(r, "rose.md", "ローズマリー", "ローズマリーは地中海原産のハーブです。乾燥した土を好み、水やりは控えめにします。挿し木で増やせます。")
        note(r, "thyme.md", "タイム", "タイムは乾燥に強いハーブです。水やりは週に一度で足ります。日当たりのよい場所で育てます。")
        note(r, "rose2.md", "ローズマリーの育て方", "ローズマリーは地中海原産のハーブです。乾燥した土を好み、水やりは控えめにします。挿し木で増やすことができます。")
        note(r, "bh.md", "ブラックホール", "ブラックホールとは重い星が崩壊してできる天体である。事象の地平線の内側からは光も脱出できない。")
        note(r, "cook.md", "チキンの料理", "ローズマリーを使ったチキンの料理です。オーブンで焼きます。")
        note(r, "p1.md", "価格メモ", "現在の価格は100円です。送料は別にかかります。")
        note(r, "p2.md", "価格メモ2", "現在の価格は200円です。送料は別にかかります。")
        note(r, "c1.md", "コマンドA", "このコマンドは本番の環境で使えます。")
        note(r, "c2.md", "コマンドB", "このコマンドは本番の環境で使えません。")
        note(r, "herbidx.md", "ハーブ索引", "[ローズマリー](rose.md)\n[タイム](thyme.md)", extra="attribute: group\n")
        note(r, "old.md", "古い情報", "現在の最新バージョンは2.0です。2019年に調べました。", "2019-01-01 00:00:00")
        two_years = time.time() - 2 * 365 * 86400
        os.utime(r / "old.md", (two_years, two_years))
        self.before = self.md5()
        self.c = ai.Corpus.build(r)

    def md5(self):
        return {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md")}

    def tearDown(self):
        pass

    def test_tokens(self):
        self.assertEqual(ai.tokens("ハーブです"), ["ハー", "ーブ", "ブで", "です"])
        self.assertIn("python", ai.tokens("Python と vault"))
        self.assertEqual(ai.tokens("A"), [])                       # 1 文字の英字は捨てる
        self.assertEqual(ai.tokens("星"), ["星"])                   # 1 文字の漢字は語として残す
        self.assertEqual(ai.tokens("あ"), [])                       # 1 文字のかなは捨てる

    def test_similar_and_duplicates(self):
        s = ai.similar(self.c, "rose.md", 6)
        self.assertEqual(s["similar"][0]["path"], "rose2.md")
        self.assertTrue(s["similar"][0]["duplicate_suspect"])
        order = [x["path"] for x in s["similar"]]
        self.assertIn("thyme.md", order)                               # 同じ話題（ハーブ・水やり）の別のノートも出る
        self.assertLess(order.index("rose2.md"), order.index("thyme.md"))   # ほぼ同文のほうが上
        self.assertNotIn("bh.md", order)                               # 別の話題は出ない
        self.assertTrue(s["similar"][0]["shared"])                  # 共有している語を根拠として出す
        d = ai.duplicates(self.c)
        pairs = {tuple(sorted((x["a"], x["b"]))) for x in d}
        self.assertIn(("rose.md", "rose2.md"), pairs)                # ほぼ同文
        self.assertIn(("p1.md", "p2.md"), pairs)                     # 数字だけが違う文も「ほぼ同じ」には入る（食い違いは別に報告）
        self.assertFalse(any("thyme.md" in p or "bh.md" in p for p in pairs))   # 別の話題は入らない
        with self.assertRaises(ValueError):
            ai.similar(self.c, "nothing.md")

    def test_link_suggestions_and_unlinked_mentions(self):
        s = ai.link_suggestions(self.c, "cook.md")
        self.assertIn("rose.md", [x["path"] for x in s["similar_unlinked"]] + [m["path"] for m in s["unlinked_mentions"]])
        m = next(x for x in s["unlinked_mentions"] if x["path"] == "rose.md")
        self.assertIn("リンクされていない", m["reason"])
        # リンクすると候補から消える
        note(self.root, "cook.md", "チキンの料理", "[ローズマリー](rose.md)を使ったチキンの料理です。オーブンで焼きます。")
        c2 = ai.Corpus.build(self.root)
        s2 = ai.link_suggestions(c2, "cook.md")
        self.assertNotIn("rose.md", [x["path"] for x in s2["similar_unlinked"]] + [m["path"] for m in s2["unlinked_mentions"]])

    def test_index_candidates_propose_only(self):
        r = ai.index_candidates(self.c, "rose2.md")
        self.assertEqual(r["candidates"][0]["index"], "herbidx.md")
        self.assertIn("書き換えていません", r["note_text"])
        self.assertEqual(self.before, self.md5())

    def test_keywords_are_phrases(self):
        k = ai.keywords(self.c, "bh.md", 6)["keywords"]
        self.assertTrue(any("ブラックホール" in x or x in "ブラックホール" and len(x) >= 4 for x in k), k)
        self.assertTrue(all(len(x) >= 2 for x in k))
        self.assertEqual(len(k), len(set(k)))

    def test_summary_extracts_original_sentences(self):
        s = ai.summarize(self.c, "bh.md", 1)
        text = self.c.docs["bh.md"]["clean"]
        self.assertEqual(len(s["summary"]), 1)
        self.assertIn(s["summary"][0], text)                        # 言い換えない（原文の文）
        s2 = ai.summarize(self.c, "rose.md", 2)
        self.assertEqual(len(s2["summary"]), 2)
        self.assertEqual(s2["summary"], sorted(s2["summary"], key=text_pos(self.c, "rose.md")))   # 元の順序

    def test_common_points(self):
        r = ai.common(self.c, ["rose.md", "thyme.md", "rose2.md"])
        for t in r["shared_in_all"]:
            self.assertTrue(all(t in self.c.docs[p]["vec"] for p in r["notes"]))
        self.assertTrue(r["shared_in_all"] or r["shared_in_most"])
        with self.assertRaises(ValueError):
            ai.common(self.c, ["rose.md"])

    def test_conflicts_are_suspicions_with_evidence(self):
        cs = ai.conflicts(self.c)
        pairs = {(x["a"]["path"], x["b"]["path"]): x for x in cs}
        num = pairs.get(("p1.md", "p2.md"))
        self.assertIsNotNone(num, [(x["a"]["path"], x["b"]["path"], x["reason"]) for x in cs])
        self.assertIn("数字が違います", num["reason"])
        self.assertIn("100", num["a"]["text"])
        self.assertGreater(num["a"]["line"], 0)                      # 根拠の行番号（ファイルの行）
        neg = pairs.get(("c1.md", "c2.md"))
        self.assertIsNotNone(neg)
        self.assertIn("否定", neg["reason"])
        self.assertIn(neg["confidence"], ("低", "中"))
        self.assertIn("疑い", neg["note_text"])                      # 断定しない
        file_lines = (self.root / "p1.md").read_text(encoding="utf-8").split("\n")
        self.assertIn("100円", file_lines[num["a"]["line"] - 1])       # 行番号はファイルの実際の行
        self.assertFalse(any({x["a"]["path"], x["b"]["path"]} == {"rose.md", "thyme.md"} for x in cs))   # 無関係な組は挙げない

    def test_stale(self):
        s = ai.stale(self.c, 365, TODAY)
        self.assertEqual([x["path"] for x in s][:1], ["old.md"])
        joined = " ".join(s[0]["reasons"])
        self.assertIn("時点によって変わる語", joined)
        self.assertIn("2019", joined)
        # 期限つき: reverify
        note(self.root, "dated.md", "期限つき", "reverify: 2026-09-01\n中身")
        c2 = ai.Corpus.build(self.root)
        self.assertTrue(any(x["path"] == "dated.md" and "再確認の期限" in " ".join(x["reasons"]) for x in ai.stale(c2, 365, TODAY)))

    def test_questions_are_srs_compatible_and_not_written(self):
        q = ai.questions(self.c, "bh.md", 5)
        texts = [x["text"] for x in q["questions"]]
        self.assertTrue(any(t.startswith("Q: ブラックホールとは何ですか？\nA: ") for t in texts), texts)
        self.assertTrue(any("{{" in t and "}}" in t for t in texts))
        import srs
        cards = srs.parse_cards("\n\n".join(texts), "x.md")          # そのまま SRS のカードとして読める
        self.assertGreaterEqual(len(cards), 2)
        self.assertEqual(self.before, self.md5())

    def test_ask_cites_sources_and_refuses_without_evidence(self):
        a = ai.ask(self.c, "ローズマリーの水やりはどうする？")
        self.assertTrue(a["answers"])
        top = a["answers"][0]
        self.assertIn(top["path"], ("rose.md", "rose2.md"))
        self.assertIn("水やり", top["text"])
        self.assertGreater(top["line"], 0)
        self.assertIn("抜き出し", a["note_text"])                     # 生成ではない
        none = ai.ask(self.c, "量子もつれの歴史を教えて")
        self.assertEqual(none["answers"], [])
        self.assertIn("手がかり", none["note_text"])                  # 語がノートに 1 つも無い質問: 手がかりが取れないと言う
        weak = ai.ask(self.c, "ブラックホールの料理のレシピ", min_score=0.9)   # 語はあるが根拠が弱い: 作り話をしない
        self.assertEqual(weak["answers"], [])
        self.assertIn("作り話はしません", weak["note_text"])

    def test_semantic_and_hybrid(self):
        s = ai.semantic(self.c, "乾燥に強い植物")
        self.assertIn(s[0]["path"], ("thyme.md", "rose.md", "rose2.md"))
        self.assertEqual(ai.semantic(self.c, "zzzzzz"), [])
        h = ai.hybrid(self.root, "水やり", 5, self.c)
        self.assertTrue(h)
        self.assertTrue(any("全文" in x["from"] and "意味" in x["from"] for x in h))     # 両方に出たものが上位に
        self.assertEqual(h[0]["from"], ["全文", "意味"])

    def test_natural_language_to_query(self):
        r = ai.nl_to_query("先月の未完了のタスク", TODAY)
        self.assertIn("has:task", r["query"])
        self.assertIn("after:2026-08-31", r["query"])
        self.assertIn("before:2026-10-01", r["query"])
        self.assertTrue(any("先月" in x for x in r["read_as"]))
        r = ai.nl_to_query("今月の日記で「ローズマリー」を含むもの", TODAY)
        self.assertIn("type:diary", r["query"])
        self.assertIn("ローズマリー", r["query"])
        r = ai.nl_to_query("番号 1a の画像つきノート")
        self.assertIn("fz:1a*", r["query"])
        self.assertIn("has:image", r["query"])
        self.assertIn("直接書いて", ai.nl_to_query("なにか")["note_text"])
        # 作った検索条件は、そのまま vault_index で解釈できる
        vi.parse(ai.nl_to_query("今週の画像つきグループ", TODAY)["query"])

    def test_activity_report(self):
        rep = ai.activity(self.c, "月", dt.date(2026, 10, 20))
        self.assertEqual(rep["period"], ["2026-10-01", "2026-10-31"])
        self.assertGreaterEqual(rep["new_notes"], 9)
        self.assertEqual(rep["previous_period_new"], 0)
        md = ai.activity_md(rep)
        self.assertIn("# 活動レポート 2026-10-01〜2026-10-31", md)
        self.assertIn("事実です", md)

    def test_patrol_reports_only_new_matches_and_moves_nothing(self):
        vi.saved(self.root, "add", "ローズ系", "ローズマリー")
        r1 = ai.patrol(self.root)["searches"][0]
        self.assertTrue(r1["first_run"])
        self.assertGreaterEqual(r1["count"], 3)
        r2 = ai.patrol(self.root)["searches"][0]
        self.assertEqual((r2["first_run"], r2["new"]), (False, []))
        note(self.root, "rose3.md", "ローズマリー3", "ローズマリーの新しいメモ")
        r3 = ai.patrol(self.root)["searches"][0]
        self.assertEqual(r3["new"], ["rose3.md"])
        self.assertEqual({k: v for k, v in self.before.items()}, {k: v for k, v in self.md5().items() if k != "rose3.md"})   # ノートは移動も変更もしない

    def test_markdown_rendering(self):
        import io, contextlib
        def md(*args):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                self.assertEqual(ai.main([str(self.root), *args, "--md"]), 0)
            return buf.getvalue()
        self.assertIn("(rose2.md)", md("similar", "rose.md"))
        self.assertIn("**重複の疑い**", md("similar", "rose.md"))
        self.assertIn("本文にこの題が出ているが", md("links", "cook.md"))
        self.assertIn("(p1.md):", md("conflicts"))
        self.assertIn("疑いです", md("conflicts"))
        self.assertIn("生成ではなく", md("ask", "ローズマリーの水やり"))
        self.assertIn("Q: ブラックホールとは何ですか？", md("questions", "bh.md"))
        self.assertTrue(md("nl", "今月のタスク").startswith("# 検索条件"))
        self.assertIn("# 活動レポート", md("report", "月", "2026-10-20"))
        self.assertIn("has:task", md("nl", "今月のタスク"))

    def test_never_writes_notes_and_cli(self):
        for cmd in (["similar", "rose.md"], ["links", "cook.md"], ["index", "rose2.md"], ["summary", "bh.md"], ["common", "rose.md", "thyme.md"], ["conflicts"], ["stale"],
                    ["keywords", "bh.md"], ["questions", "bh.md"], ["ask", "ローズマリーの水やり"], ["semantic", "水やり"], ["hybrid", "水やり"], ["nl", "今月のタスク"], ["report", "月"]):
            self.assertEqual(ai.main([str(self.root)] + cmd), 0, cmd)
        self.assertEqual(ai.main([str(self.root), "similar", "nothing.md"]), 1)
        self.assertEqual(ai.main([str(self.root), "bogus"]), 2)
        self.assertEqual(self.before, self.md5())
        self.assertFalse(any(p for p in self.root.iterdir() if p.is_file() and p.suffix != ".md"))


def text_pos(c, rel):
    text = c.docs[rel]["clean"]
    return lambda s: text.find(s)


if __name__ == "__main__":
    unittest.main()
