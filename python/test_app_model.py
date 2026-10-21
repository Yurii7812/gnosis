#!/usr/bin/env python3
"""app_model（\\A の索引ナビ・カレンダーのデータ）の試験。一時フォルダの vault だけを使う。"""
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_model as am  # noqa: E402

HERE = Path(__file__).resolve().parent


def write(root: Path, name: str, text: str) -> Path:
    p = root / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text.lstrip("\n"), encoding="utf-8")
    return p


def make_vault(root: Path) -> None:
    """ハーブ → ローズマリー → 栽培 のダブルインデックス（原本の説明どおりの形）。"""
    write(root, "index.md", """
---
time: 2026-09-09 10:50:56
title: Index
attribute: group
---

# Index

は
[ハーブ](h.md)
[薬草](h.md)
[運動](u.md)
""")
    write(root, "h.md", """
---
time: 2026-09-12 08:23:55
title: ハーブ
yomi:
  "ハーブ": "はーぶ"
  "薬草": "やくそう"
folgezettel: "1"
---

# ハーブ

BranchGroup:
[ハーブ](gh.md)
Group:
[Index:ハーブ](index.md)
[Index:薬草](index.md)

ハーブについて最初に書いたノート。
""")
    write(root, "gh.md", """
---
time: 2026-09-20 10:00:00
title: ハーブ
attribute: group
folgezettel: "1"
---

# ハーブ

ParentBranch:
[ハーブ](h.md)

[まとめ](hm.md)
[ローズマリー](r.md)
## 育てる
[栽培](hs.md)
""")
    write(root, "r.md", """
---
time: 2026-10-01 09:00:00
title: ローズマリーを育ててみた
---

# ローズマリーを育ててみた

BranchGroup:
[ローズマリー](gr.md)
Group:
[ハーブ:ローズマリー](gh.md)

ベランダで育て始めた。
""")
    write(root, "gr.md", """
---
time: 2026-10-05 09:00:00
title: ローズマリー
attribute: group
---

# ローズマリー

ParentBranch:
[ローズマリーを育ててみた](r.md)

[栽培](rs.md)
[利用](ru.md)
""")
    for n, t in (("hm.md", "ハーブのまとめ"), ("hs.md", "ハーブの栽培"), ("rs.md", "ローズマリーの栽培"), ("ru.md", "ローズマリーの利用"), ("u.md", "運動")):
        write(root, n, f"---\ntime: 2026-10-10 12:00:00\ntitle: {t}\n---\n\n# {t}\n\n本文。\n")
    write(root, "d1.md", """
---
time: 2026-10-19 07:00:00
title: 2026-10-19-SU
timeline: true
---

# 2026-10-19-SU

07:00 起きた。
- [ ] 水やり 📅 2026-10-19 09:30
- [x] 買い物 ✅ 2026-10-19
""")
    write(root, "d2.md", """
---
time: 2026-10-19 23:00:00
title: 2026-10-19-SU-夢
record: "夢"
---

# 2026-10-19-SU-夢

空を飛んだ。
""")
    write(root, "t.md", """
---
time: 2026-10-19 12:00:00
title: その日に作ったノート
---

# その日に作ったノート

- [ ] 剪定する 📅 2026-10-25 🔁 weekly
""")


class AppModelTest(unittest.TestCase):
    def setUp(self):
        base = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")
        Path(base).mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=base)
        self.root = Path(self.tmp.name)
        make_vault(self.root)
        self.v = am.Vault(self.root)
        self.v.refresh()

    def tearDown(self):
        self.tmp.cleanup()

    def test_crumbs_follow_double_index(self):
        # Index → ハーブ（最初のノート）→ BranchGroup の索引「ハーブ」→ 項目「ローズマリー」→ … → 栽培
        c = self.v.crumbs("rs.md")[0]
        self.assertEqual([x["rel"] for x in c], ["index.md", "h.md", "gh.md", "r.md", "gr.md", "rs.md"])
        self.assertEqual([x["via"] for x in c], ["", "entry", "topic", "entry", "topic", "entry"])
        self.assertEqual(c[3]["label"], "ローズマリー")      # 索引での名前（ノートの題ではない）
        self.assertEqual(self.v.path_text("rs.md"), "Index › ハーブ › ローズマリー › 栽培")

    def test_global_index_never_points_to_topic_index(self):
        # Global Index の項目は最初のノート（h.md）を指し、トピック索引（gh.md）へは BranchGroup からだけ行ける
        c = self.v.crumbs("gh.md")[0]
        self.assertEqual([x["rel"] for x in c], ["index.md", "h.md", "gh.md"])

    def test_note_info(self):
        d = self.v.note_info("r.md")
        self.assertEqual(d["title"], "ローズマリーを育ててみた")
        self.assertEqual([(x["index"]["rel"], x["label"]) for x in d["indexed"]], [("gh.md", "ローズマリー")])
        self.assertEqual(d["indexed"][0]["origin"]["rel"], "h.md")
        self.assertEqual(d["indexed"][0]["path"], "Index › ハーブ")
        self.assertEqual(len(d["topics"]), 1)
        self.assertEqual([e["label"] for e in d["topics"][0]["entries"]], ["栽培", "利用"])
        # 別名（薬草）でも載っている
        h = self.v.note_info("h.md")
        self.assertEqual(sorted(x["label"] for x in h["indexed"]), ["ハーブ", "薬草"])
        self.assertEqual(h["kind"], "note")
        self.assertEqual(self.v.note_info("gh.md")["kind"], "topic")
        self.assertEqual(self.v.note_info("index.md")["kind"], "index")
        self.assertEqual(self.v.note_info(str(self.root / "r.md"))["rel"], "r.md")   # 絶対パスでも

    def test_links_backlinks_outgoing_relations(self):
        d = self.v.links("r.md")
        # r.md へリンクしているのは、索引 gh.md の本文と、gr.md の ParentBranch:
        back = {x["rel"]: x["places"] for x in d["backlinks"]}
        self.assertEqual(back, {"gh.md": ["本文"], "gr.md": ["ParentBranch"]})
        self.assertEqual([x["rel"] for x in d["children"]], ["gr.md"])
        self.assertEqual([x["rel"] for x in d["groups"]], ["gh.md"])
        self.assertEqual([x["rel"] for x in d["topics"]], ["gr.md"])
        # 出ていくリンクは本文のものだけ（先頭のブロックは関係として別に出す）
        self.assertEqual([x["rel"] for x in self.v.links("gr.md")["outgoing"]], ["rs.md", "ru.md"])
        self.assertEqual(self.v.links("gr.md")["parents"][0]["rel"], "r.md")
        self.assertTrue(self.v.links("nai.md")["missing"])

    def test_search_full_and_mandala_index(self):
        r = self.v.search_full("栽培 -ハーブ")
        self.assertEqual([x["rel"] for x in r["results"]], ["gr.md", "rs.md"])   # 索引「ローズマリー」の項目と、題「ローズマリーの栽培」（ハーブを含まない）
        r = self.v.search_full("line:(水やり 📅)")
        self.assertEqual([x["rel"] for x in r["results"]], ["d1.md"])
        self.assertEqual(r["results"][0]["lines"][0]["line"], 10)
        self.assertIn("error", self.v.search_full("/[/"))
        names = [x["title"] for x in self.v.search_full("本文", sort="name-desc")["results"]]
        self.assertEqual(names, sorted(names, reverse=True))
        # 索引を曼荼羅で: 真ん中は索引、周りは項目、そのまわりは項目のトピック索引の項目
        m = self.v.mandala_index("gh.md")
        self.assertEqual([u["label"] for u in m["units"]], ["まとめ", "ローズマリー", "栽培"])
        rose = m["units"][1]
        self.assertEqual([c["label"] for c in rose["children"]], ["栽培", "利用"])
        self.assertEqual(rose["drill"], "gr.md")
        # 普通のノートなら、その BranchGroup の索引で
        self.assertEqual(self.v.mandala_index("h.md")["rel"], "gh.md")
        self.assertEqual(self.v.yomi_order(["みかん", "あんず", "かき"]), [1, 2, 0])

    def test_entries_rows(self):
        e = self.v.entries("gh.md")
        self.assertEqual([(x["label"], x["row"]) for x in e], [("まとめ", ""), ("ローズマリー", ""), ("栽培", "育てる")])
        self.assertEqual(e[1]["topics"], 1)
        self.assertEqual([x["row"] for x in self.v.entries("index.md")], ["は", "は", "は"])
        # 本文の上の ParentBranch: のリンクは項目ではない
        self.assertNotIn("h.md", [x["rel"] for x in e])

    def test_search_keyword_in_context(self):
        r = self.v.search("栽培")
        entries = [(x["path"], x["label"]) for x in r if x["kind"] == "entry"]
        self.assertIn(("Index › ハーブ", "栽培"), entries)
        self.assertIn(("Index › ハーブ › ローズマリー", "栽培"), entries)
        # よみ・カタカナ/ひらがなの違いでも見つかる
        self.assertTrue(any(x["label"] == "薬草" for x in self.v.search("やくそう")))
        self.assertTrue(any(x["label"] == "ハーブ" for x in self.v.search("はーぶ")))
        self.assertEqual(self.v.search("  "), [])

    def test_unindexed(self):
        write(self.root, "x.md", "---\ntime: 2026-10-20 10:00:00\ntitle: まだ載せていない\n---\n\n# まだ載せていない\n")
        self.v.refresh()
        rels = [x["rel"] for x in self.v.unindexed()]
        self.assertEqual(rels[0], "x.md")
        self.assertNotIn("d1.md", rels)          # 日記
        self.assertNotIn("d2.md", rels)          # 時系列記録のその日のノート
        self.assertNotIn("rs.md", rels)          # 索引から辿れる
        self.assertIn("t.md", rels)

    def test_indexes(self):
        ix = self.v.indexes()
        self.assertEqual(ix[0]["rel"], "index.md")
        self.assertEqual({x["rel"] for x in ix}, {"index.md", "gh.md", "gr.md"})
        self.assertEqual(next(x for x in ix if x["rel"] == "gr.md")["path"], "Index › ハーブ › ローズマリー")

    def test_refresh_only_changed(self):
        self.assertEqual(self.v.refresh(), 0)
        time.sleep(0.01)
        p = self.root / "gr.md"
        p.write_text(p.read_text(encoding="utf-8") + "[香り](rk.md)\n", encoding="utf-8")
        write(self.root, "rk.md", "---\ntitle: 香り\n---\n\n# 香り\n")
        self.assertEqual(self.v.refresh(), 2)
        self.assertEqual([x["label"] for x in self.v.entries("gr.md")], ["栽培", "利用", "香り"])
        (self.root / "rk.md").unlink()
        self.assertEqual(self.v.refresh(), 1)
        self.assertTrue(self.v.entries("gr.md")[-1].get("missing"))

    def test_month_and_day(self):
        m = self.v.month("2026-10")
        d = m["days"]["2026-10-19"]
        self.assertEqual(d["diary"]["rel"], "d1.md")
        self.assertEqual([x["record"] for x in d["records"]], ["夢"])
        self.assertEqual([x["text"] for x in d["due"]], ["水やり"])
        self.assertEqual(d["due"][0]["time"], "09:30")
        self.assertEqual(d["done"], 1)
        self.assertEqual(d["created"], 1)                      # t.md（日記・記録は数えない）
        self.assertEqual([x["text"] for x in m["days"]["2026-10-25"]["due"]], ["剪定する"])
        day = self.v.day("2026-10-19")
        self.assertEqual(day["diary"]["rel"], "d1.md")
        self.assertEqual([x["rel"] for x in day["created"]], ["t.md"])
        self.assertEqual([x["text"] for x in day["done"]], ["買い物"])
        with self.assertRaises(ValueError):
            self.v.day("2026-13-01")

    def test_task_complete_does_not_write(self):
        before = (self.root / "t.md").read_text(encoding="utf-8")
        r = am.task_complete_text(self.v, "t.md", 8, "2026-10-25")
        self.assertTrue(r["changed"])
        self.assertIn("- [x] 剪定する 📅 2026-10-25 🔁 weekly ✅ 2026-10-25", r["text"])
        self.assertIn("- [ ] 剪定する 📅 2026-11-01 🔁 weekly", r["text"])
        self.assertEqual((self.root / "t.md").read_text(encoding="utf-8"), before)   # 書くのは Vim

    def test_serve_protocol(self):
        p = subprocess.run([sys.executable, str(HERE / "app_model.py"), "serve", str(self.root)],
                           input='{"id": 1, "method": "nav.note", "params": {"file": "r.md"}}\n{"id": 2, "method": "nope"}\nこわれた\n',
                           capture_output=True, text=True, timeout=30)
        out = [json.loads(x) for x in p.stdout.splitlines()]
        self.assertEqual(out[0]["id"], 1)
        self.assertEqual(out[0]["result"]["rel"], "r.md")
        self.assertIn("error", out[1])
        self.assertEqual(len(out), 2)


if __name__ == "__main__":
    unittest.main()
