#!/usr/bin/env python3
import hashlib
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vault_index as vi


def note(root, name, title, body, time_="2026-10-01 09:00:00", extra=""):
    (root / name).write_text(f"---\ntime: {time_}\ntitle: {title}\n{extra}---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class IndexTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        note(r, "a.md", "ハーブ", "ローズマリーとタイムを育てる。水は少なめ。 [栽培](b.md)", "2026-10-01 09:00:00", 'folgezettel: "1"\n')
        note(r, "b.md", "栽培", "乾燥気味に。水やり控えめ。![](pic.png)", "2026-10-02 09:00:00", 'folgezettel: "1a"\n')
        note(r, "c.md", "Apple Pie", "english text recipe: 1 cup sugar", "2026-09-20 09:00:00")
        note(r, "d.md", "2026-10-19-MO", "今日は水やりをした\n\n- [ ] 買い物", "2026-10-19 08:00:00")
        note(r, "e.md", "Index", "[ハーブ](a.md)", "2026-10-01 08:00:00", "attribute: group\n")
        note(r, "f.md", "孤立", "水", "2026-10-05 09:00:00")
        (r / "sub").mkdir()
        note(r / "sub", "g.md", "入れ子", "ローズ畑", "2026-10-06 09:00:00")
        self.snapshot = self.md5()
        vi.update(r)

    def md5(self):
        return {str(p): hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.rglob("*.md") if ".gnosis" not in p.parts}

    def q(self, query):
        return sorted(x["path"] for x in vi.search(self.root, query))

    def test_text_terms_short_and_long(self):
        self.assertEqual(self.q("ローズ"), ["a.md", "sub/g.md"])                  # 3 文字（FTS）
        self.assertEqual(self.q("乾燥"), ["b.md"])                                  # 2 文字
        self.assertEqual(self.q("水"), ["a.md", "b.md", "d.md", "f.md"])           # 1 文字
        self.assertEqual(self.q("APPLE"), ["c.md"])                                 # 大文字小文字を区別しない
        self.assertEqual(self.q("ローズ 水"), ["a.md"])                             # AND
        self.assertEqual(self.q("水 -やり"), ["a.md", "f.md"])                      # 除外
        self.assertEqual(self.q('"水やり"'), ["b.md", "d.md"])                      # フレーズ
        self.assertEqual(self.q("栽培"), ["a.md", "b.md"])                          # 題でも本文（リンクの表示名）でも
        self.assertEqual(self.q("""
""".strip()), sorted(p for p in ["a.md", "b.md", "c.md", "d.md", "e.md", "f.md", "sub/g.md"]))   # 空クエリは全部

    def test_or_regex_and_invalid_regex(self):
        self.assertEqual(self.q("乾燥 OR english"), ["b.md", "c.md"])
        self.assertEqual(self.q("/水.り/"), ["b.md", "d.md"])
        self.assertEqual(self.q("/水.り/ -乾燥"), ["d.md"])
        with self.assertRaises(ValueError):
            vi.search(self.root, "/(/")

    def test_filters(self):
        self.assertEqual(self.q("title:栽培"), ["b.md"])
        self.assertEqual(self.q("fz:1*"), ["a.md", "b.md"])
        self.assertEqual(self.q("fz:1a"), ["b.md"])
        self.assertEqual(self.q("date:2026-09"), ["c.md"])
        self.assertEqual(self.q("before:2026-10-02"), ["a.md", "c.md", "e.md"])
        self.assertEqual(self.q("after:2026-10-05"), ["d.md", "sub/g.md"])
        self.assertEqual(self.q("type:group"), ["e.md"])
        self.assertEqual(self.q("type:diary"), ["d.md"])
        self.assertEqual(self.q("has:image"), ["b.md"])
        self.assertEqual(self.q("has:task"), ["d.md"])
        self.assertEqual(self.q("has:link"), ["a.md", "e.md"])
        self.assertEqual(self.q("links>=1"), ["a.md", "e.md"])
        self.assertEqual(self.q("backlinks>=1"), ["a.md", "b.md"])
        self.assertEqual(self.q("backlinks=0 type:note"), ["c.md", "f.md", "sub/g.md"])      # d.md は日記（type:diary）
        self.assertEqual(self.q("ローズ date:2026-10 -type:group"), ["a.md", "sub/g.md"])        # 複合
        self.assertEqual(self.q("type:note -has:link"), ["b.md", "c.md", "f.md", "sub/g.md"])   # b の画像リンクは .md でないのでリンクに数えない

    def test_scope_reachability(self):
        # 索引 e → ハーブ a → 栽培 b と辿れる範囲だけ（孤立 f・別の c は届かない）
        self.assertEqual(self.q("in:e.md"), ["a.md", "b.md", "e.md"])
        self.assertEqual(self.q("in:e.md 水"), ["a.md", "b.md"])
        self.assertEqual(self.q("水 -in:e.md"), ["d.md", "f.md"])
        self.assertEqual(self.q("in:nothing.md"), [])

    def test_snippet_ranges_only_in_result(self):
        r = vi.search(self.root, "ローズ")[0]
        sn = r["snippet"]
        self.assertEqual(sn["line"] > 0, True)
        file_lines = (self.root / r["path"]).read_text(encoding="utf-8").split("\n")
        self.assertIn("ローズ", file_lines[sn["line"] - 1])                         # ヒット行の番号はファイルの行番号（front matter の分も数える）
        s, e = sn["ranges"][0]
        self.assertEqual(sn["text"][s:e], "ローズ")
        self.assertEqual(self.snapshot, self.md5())                                  # 本文に装飾を残さない・何も書き換えない

    def test_ranking_title_first(self):
        note(self.root, "h.md", "水", "本文")
        res = vi.search(self.root, "水")
        self.assertEqual(res[0]["path"], "h.md")                                     # 題に当たったものが先

    def test_incremental_and_rebuildable(self):
        self.assertEqual(vi.update(self.root), {"added": 0, "changed": 0, "removed": 0, "total": 7})
        time.sleep(0.01)
        note(self.root, "c.md", "Apple Pie", "now japanese 柑橘")
        os.remove(self.root / "f.md")
        note(self.root, "z.md", "新規", "追加")
        self.assertEqual(vi.update(self.root), {"added": 1, "changed": 1, "removed": 1, "total": 7})
        self.assertEqual(self.q("柑橘"), ["c.md"])
        self.assertEqual(self.q("english"), [])
        self.assertEqual(self.q("孤立"), [])
        # 派生データ: 消しても作り直せる
        (self.root / ".gnosis" / "cache" / "index.sqlite").unlink()
        self.assertEqual(self.q("柑橘"), ["c.md"])
        # 古い版の形は作り直す
        import sqlite3
        con = sqlite3.connect(self.root / ".gnosis" / "cache" / "index.sqlite")
        con.execute("pragma user_version=0"); con.commit(); con.close()
        self.assertEqual(self.q("柑橘"), ["c.md"])

    def test_dot_dirs_are_not_indexed(self):
        (self.root / ".trash").mkdir()
        note(self.root / ".trash", "t.md", "ごみ", "捨てたノート")
        self.assertEqual(self.q("捨てた"), [])

    def test_fuzzy(self):
        self.assertEqual(vi.fuzzy(self.root, "ハブ")[0]["path"], "a.md")            # ハーブ（飛び飛びでも）
        self.assertEqual(vi.fuzzy(self.root, "1a")[0]["path"], "b.md")              # 番号
        self.assertEqual(vi.fuzzy(self.root, "appie")[0]["path"], "c.md")
        self.assertEqual(vi.fuzzy(self.root, "zzzz"), [])

    def test_saved_searches_and_dynamic_index(self):
        self.assertEqual(vi.saved(self.root, "list"), [])
        vi.saved(self.root, "add", "水やり系", '"水やり" -乾燥')
        vi.saved(self.root, "add", "水やり系", '"水やり"')                            # 同名は置き換え
        self.assertEqual(vi.saved(self.root, "list"), [{"name": "水やり系", "query": '"水やり"'}])
        self.assertEqual(sorted(r["path"] for r in vi.saved(self.root, "run", "水やり系")), ["b.md", "d.md"])
        data = json.loads((self.root / ".gnosis" / "searches.json").read_text(encoding="utf-8"))
        self.assertEqual(data["version"], 1)                                        # 共有できる素の JSON
        with self.assertRaises(ValueError):
            vi.saved(self.root, "run", "ない")
        vi.saved(self.root, "del", "水やり系")
        self.assertEqual(vi.saved(self.root, "list"), [])
        # 動的索引: 読み取り専用の Markdown。何も書かない。昇格は明示のときだけ・新規ファイルだけ
        res = vi.search(self.root, '"水やり"')
        md = vi.dynamic_markdown('"水やり"', res)
        self.assertIn("- [1a 栽培](b.md)", md)                                       # 番号つきの表示名
        self.assertIn("(この表は検索結果で、ノートではありません)", md.replace("（", "(").replace("）", ")"))
        self.assertEqual(self.snapshot, self.md5())
        made = vi.promote(self.root, "result.md", '"水やり"', res)
        self.assertEqual(made, "result.md")
        with self.assertRaises(OSError):
            vi.promote(self.root, "result.md", "x", res)                             # 上書きしない
        with self.assertRaises(ValueError):
            vi.promote(self.root, "../outside.md", "x", res)                         # vault の外には書かない
        self.assertEqual(self.snapshot, {k: v for k, v in self.md5().items() if not k.endswith("result.md")})   # 既存のノートは無変更

    def test_cli(self):
        self.assertEqual(vi.main([str(self.root), "update"]), 0)
        self.assertEqual(vi.main([str(self.root), "search", "/(/"]), 1)             # 不正な正規表現はエラー終了


if __name__ == "__main__":
    unittest.main()
