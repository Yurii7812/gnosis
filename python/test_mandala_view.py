#!/usr/bin/env python3
"""曼荼羅ビューの元データ（mandala_view.py）の試験。一時フォルダ（既定 ~/gnosis-work/test）の vault だけを使う。"""
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mandala_view as mv  # noqa: E402


def note(title, attr=False, groups=(), body=(), fzid=""):
    s = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n" + ("attribute: group\n" if attr else "") + (f'folgezettel: "{fzid}"\n' if fzid else "") + f"---\n\n# {title}\n\n"
    if groups:
        s += "Group:\n" + "".join(f"[{t}]({f})\n" for t, f in groups) + "\n"
    return s + "".join(b + "\n" for b in body)


class T(unittest.TestCase):
    def setUp(self):
        base = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")
        os.makedirs(base, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=base)
        r = Path(self.tmp.name)
        (r / "index.md").write_text(note("Index", body=["[植物](plant.md)", "[料理](cook.md)", "[壊れた](nothing.md)"]))
        (r / "plant.md").write_text(note("植物", True, [("Index", "index.md")], ["[ハーブ](herb.md)", "[栽培](grow.md)", "[下位](sub.md)"]))
        (r / "cook.md").write_text(note("料理", True, [("Index", "index.md")], ["[ハーブ](herb.md)"]))
        (r / "sub.md").write_text(note("下位", True, [("植物", "plant.md")]))
        (r / "herb.md").write_text(note("ハーブ", False, [("植物", "plant.md"), ("料理", "cook.md")], ["[栽培](grow.md)", "[自分](herb.md)"]))
        (r / "grow.md").write_text(note("栽培", False, [("植物", "plant.md")]))
        self.d = mv.dump(r)

    def tearDown(self):
        self.tmp.cleanup()

    def test_note_center(self):
        self.assertEqual(mv.items(self.d, "herb.md", "groups"), ["plant.md", "cook.md"])
        self.assertEqual(mv.items(self.d, "herb.md", "notes"), ["grow.md"])  # 自分へのリンクは出さない
        self.assertEqual(mv.items(self.d, "herb.md", "all"), ["plant.md", "cook.md", "grow.md"])

    def test_group_center(self):
        # 所属する索引（Index）が先、そのあとに載っているノート
        self.assertEqual(mv.items(self.d, "plant.md", "all"), ["index.md", "herb.md", "grow.md", "sub.md"])
        # i（索引）モード: 所属する索引のあと、索引の項目すべて（索引でないノートも）
        self.assertEqual(mv.items(self.d, "plant.md", "groups"), ["index.md", "herb.md", "grow.md", "sub.md"])
        self.assertEqual(mv.items(self.d, "plant.md", "notes"), ["herb.md", "grow.md"])

    def test_index_center_skips_broken(self):
        self.assertEqual(mv.items(self.d, "index.md", "all"), ["plant.md", "cook.md"])
        self.assertTrue(self.d["nodes"]["index.md"]["g"])

    def test_near_uses_fz_links_and_titles(self):
        r = Path(self.tmp.name)
        # 番号 1a の「ハーブ」と同じ枝（1a1）のノートが載っている索引・つながり・題が近い索引
        (r / "herb.md").write_text(note("ハーブ", False, [("植物", "plant.md")], ["[栽培](grow.md)"], "1a"))
        (r / "kid.md").write_text(note("ハーブの子", False, [("枝の索引", "branch.md")], [], "1a1"))
        (r / "branch.md").write_text(note("枝の索引", True, [("Index", "index.md")], ["[ハーブの子](kid.md)"]))
        (r / "title.md").write_text(note("ハーブの育て方", True, [("Index", "index.md")], []))
        (r / "far.md").write_text(note("関係ない索引", True, [("Index", "index.md")], ["[他](other.md)"]))
        (r / "other.md").write_text(note("他", False, [("関係ない索引", "far.md")], [], "9"))
        (r / "index.md").write_text(note("Index", body=["[植物](plant.md)", "[料理](cook.md)", "[枝の索引](branch.md)", "[ハーブの育て方](title.md)", "[関係ない索引](far.md)"]))
        got = mv.near(r, "herb.md")
        ids = [d["id"] for d in got]
        self.assertNotIn("plant.md", ids)  # もう載っている索引は出さない
        self.assertNotIn("far.md", ids)    # 手がかりが無い索引は出さない
        self.assertEqual(ids[0], "branch.md")  # 番号が同じ枝のノートが載っている
        self.assertIn("枝の子", got[0]["why"])
        self.assertIn("title.md", ids)
        self.assertIn("題が近い", next(d for d in got if d["id"] == "title.md")["why"])

    def test_search_title_first(self):
        r = Path(self.tmp.name)
        self.assertEqual(mv.search(r, ["ハーブ"])[0], "herb.md")
        (r / "body.md").write_text(note("別の話", False, [], ["栽培のハーブについて"]))
        hits = mv.search(r, ["ハーブ"])
        self.assertEqual(hits[0], "herb.md")
        self.assertIn("body.md", hits)
        self.assertEqual(mv.search(r, ["ハーブ", "存在しない語"]), [])

    def test_search_matches_filename_case_kana_and_fuzzy(self):
        r = Path(self.tmp.name)
        # 題が日本語でも、ファイル名（index.md）で見つかる。大文字小文字・全角半角・カタカナ/ひらがなの違いは無視
        (r / "toc.md").write_text(note("目次", True, [], ["[ハーブ](herb.md)"]))
        (r / "memo-index.md").write_text(note("メモ", False, [], []))
        (r / "kana.md").write_text(note("カタカナのノート", False, [], []))
        hits = mv.search(r, ["index"])
        self.assertIn("index.md", hits)
        self.assertIn("memo-index.md", hits)          # ファイル名の一部
        self.assertEqual(hits[0], "index.md")         # 題（Index）が完全に合うものが先
        self.assertEqual(mv.search(r, ["INDEX"])[0], "index.md")
        self.assertEqual(mv.search(r, ["ｉｎｄｅｘ"])[0], "index.md")   # 全角
        self.assertIn("kana.md", mv.search(r, ["かたかな"]))          # ひらがなでカタカナの題
        # 厳密に合うものが無いときだけ、曖昧（文字が順に並ぶ）も使う
        self.assertIn("kana.md", mv.search(r, ["かなの"]) + mv.search(r, ["かのと"]))
        self.assertEqual(mv.search(r, ["zzzqqq"]), [])

    def test_related_any_kind(self):
        r = Path(self.tmp.name)
        (r / "herb.md").write_text(note("ハーブ", False, [("植物", "plant.md")], ["[栽培](grow.md)"], "1a"))
        (r / "kid.md").write_text(note("ハーブの子", False, [], [], "1a1"))
        (r / "grow.md").write_text(note("栽培", False, [("植物", "plant.md")], ["ハーブを育てる話。水やりと土のこと"]))
        (r / "unrelated.md").write_text(note("全然別の話", False, [], ["天気とスポーツ"], "7"))
        got = mv.related(r, "herb.md")
        ids = [d["id"] for d in got]
        self.assertIn("grow.md", ids)   # 本文でリンクしている
        self.assertIn("kid.md", ids)    # 番号の子
        self.assertIn("plant.md", ids)  # 所属の索引も出る（索引もノートも）
        self.assertNotIn("herb.md", ids)
        self.assertLess(ids.index("grow.md"), ids.index("unrelated.md") if "unrelated.md" in ids else 99)
        why = next(d for d in got if d["id"] == "kid.md")["why"]
        self.assertIn("枝の子", why)

    def test_double_index_path(self):
        """Index → 最初のノート → BranchGroup のトピック索引 → ノート。進む先と戻る道が周りに出る。"""
        r = Path(self.tmp.name)
        (r / "first.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: 最初のノート\n---\n\n# 最初のノート\n\nBranchGroup:\n[トピック](topic.md)\n\nGroup:\n[Index](index.md)\n\n本文\n")
        (r / "topic.md").write_text(note("トピック", True, [], ["[中身のノート](item.md)"]))
        (r / "item.md").write_text(note("中身のノート", False, [("トピック", "topic.md")], []))
        (r / "index.md").write_text(note("Index", True, [], ["[最初](first.md)"]))
        d = mv.dump(r)
        # ノートが中心: 進む先のトピック索引が先、戻る方向の Index が後
        self.assertEqual(mv.items(d, "first.md", "groups"), ["topic.md", "index.md"])
        # 索引（トピック索引）が中心: その索引を持つノートに戻れる。載っているノートも出る
        got = mv.items(d, "topic.md", "all")
        self.assertEqual(got[0], "first.md")
        self.assertIn("item.md", got)
        # i モードでも項目は全部出る。戻る道のノートは n / a のときだけ
        self.assertEqual(mv.items(d, "topic.md", "groups"), ["item.md"])
        self.assertEqual(mv.items(d, "topic.md", "notes")[0], "first.md")

    def test_entry_names_are_index_words(self):
        """索引の項目の名前は、その索引に書かれたリンクの文字（索引語）。題と違うものだけ nm に入る。"""
        r = Path(self.tmp.name)
        (r / "kw.md").write_text(note("アイコンどれがいいのか"))
        (r / "idx2.md").write_text(note("索引2", True, [], ["[アイコン](kw.md)", "[ハーブ](herb.md)"]))
        d = mv.dump(r)
        en = dict(d["nodes"]["idx2.md"]["en"])
        self.assertEqual(en["kw.md"], "アイコン")
        self.assertEqual(en["herb.md"], "")  # 題と同じなら空（題で出す）

    def test_same_note_listed_twice_in_a_group(self):
        """同じノートが同じ索引に別の索引語で載っていれば、載っている回数だけ周りに出る。"""
        r = Path(self.tmp.name)
        (r / "kw2.md").write_text(note("ひとつのノート"))
        (r / "idx3.md").write_text(note("索引3", True, [], ["[アイコン](kw2.md)", "[デザイン](kw2.md)", "[アイコン](kw2.md)"]))
        d = mv.dump(r)
        self.assertEqual(d["nodes"]["idx3.md"]["en"], [["kw2.md", "アイコン"], ["kw2.md", "デザイン"]])  # 同じ名前の重複は 1 つ
        self.assertEqual(mv.items(d, "idx3.md", "all"), ["kw2.md", "kw2.md"])

    def test_unknown(self):
        self.assertEqual(mv.items(self.d, "x.md"), [])


class ManyTests(unittest.TestCase):
    def test_near_related_many_match_single(self):
        import io, json, contextlib, tempfile, os
        d = tempfile.mkdtemp(dir=os.environ.get("TMPDIR"))
        open(d + "/index.md", "w", encoding="utf-8").write("---\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[a](a.md)\n[b](b.md)\n")
        open(d + "/a.md", "w", encoding="utf-8").write("# a\n\n[b](b.md)\n")
        open(d + "/b.md", "w", encoding="utf-8").write("# b\n\nhello\n")
        for many, single in (("near_many", "near"), ("related_many", "related")):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                mv.main(["x", many, d, "a.md", "b.md"])
            got = json.loads(buf.getvalue())
            for n in ("a.md", "b.md"):
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    mv.main(["x", single, d, n])
                self.assertEqual(got[n], json.loads(buf.getvalue()), (many, n))


if __name__ == "__main__":
    unittest.main()
