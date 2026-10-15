#!/usr/bin/env python3
"""紙の PKM のトピック: `1-Index` グループは作らず、ID ノート `1` の BranchGroup: にトピックを入れる。
トピックの親子（front matter の topic_parent）は表示順のためだけ: 親を子より先に並べ、インデントは付けない。
紙ノートの親子（1 と 1a）・紙ノートとトピックは Branch（ParentBranch: / ChildBranch:）で表す。"""
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import paper_pkm as pp  # noqa: E402

ng = 0


def check(cond, name):
    global ng
    print(("  ok   " if cond else "  FAIL ") + name)
    if not cond:
        ng += 1


def make_vault(root: Path) -> Path:
    (root / "index.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n",
                                   encoding="utf-8")
    return root


def img(root: Path, name: str):
    p = root / name
    p.write_bytes(b"x")
    return p


def lines_of(path: Path):
    return path.read_text(encoding="utf-8").split("\n")


def branch_block(path: Path):
    ls = lines_of(path)
    i = ls.index("BranchGroup:")
    j = i + 1
    while j < len(ls) and ls[j].strip().startswith("["):
        j += 1
    return ls[i + 1:j]


def sync(root):
    subprocess.run([sys.executable, str(HERE / "note_format_v2.py"), "update", str(root)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


with tempfile.TemporaryDirectory() as d:
    root = make_vault(Path(d))
    pp.create_paper_index(root)
    moved, errors = pp.move_images(root, root, [(img(root, "s1.jpg"), "1"), (img(root, "s2.jpg"), "2"),
                                                 (img(root, "t1.jpg"), "1", "仏教")])
    check(len(moved) == 3 and not errors, "ID 1・2 とトピック 1-仏教 を取り込む")
    notes = {fid: p for fid, p in moved}
    pp.regen(root)
    check(pp.find_id_index(root, "1") is None and not any(p.name.endswith("Index.md") and "1-Index" in p.read_text(encoding="utf-8")
                                                          for p in root.glob("*.md")), "1-Index グループは作られない")
    n1 = notes["1"]
    b = branch_block(n1)
    check(len(b) == 1 and "[1-仏教](" in b[0] and not b[0].startswith(" "), f"ID ノート 1 の BranchGroup: にトピック 1-仏教: {b}")
    check("BranchGroup:" not in notes["2"].read_text(encoding="utf-8"), "トピックが無い ID ノート 2 には BranchGroup: を作らない")
    ls = lines_of(n1)
    check(ls.index("BranchGroup:") == ls.index("# 1") + 2 and ls[ls.index("# 1") + 1] == "", "BranchGroup: は H1 の直後（空行 1 つ挟む）")
    topic = notes["1-仏教"].read_text(encoding="utf-8")
    check("1-Index" not in topic and "folgezettel-Index-1" in topic, "トピックノートの Context は folgezettel-Index-1 だけ")

    # 階層: 四念処 は 仏教 の下
    moved2, errors2 = pp.move_images(root, root, [(img(root, "t2.jpg"), "1", "四念処", "1-仏教"),
                                                   (img(root, "t3.jpg"), "1", "禅")])
    check(len(moved2) == 2 and not errors2, "階層トピックの取り込み")
    pp.regen(root)
    b = branch_block(n1)
    names = [ln.strip().split("]")[0].lstrip("[") for ln in b]
    check(names == ["1-仏教", "1-四念処", "1-禅"], f"並び: 仏教 → 四念処 → 禅: {names}")
    check(not any(ln.startswith(" ") for ln in b), f"自動ではインデントしない: {b}")
    # 並びとインデントは利用者が直せる。regen は手で直した並びを変えない
    ls = lines_of(n1)
    i = ls.index("BranchGroup:")
    ls[i + 1], ls[i + 2], ls[i + 3] = ls[i + 3], ls[i + 1], ls[i + 2].strip()
    n1.write_text("\n".join(ls), encoding="utf-8")
    manual = branch_block(n1)
    pp.regen(root)
    check(branch_block(n1) == manual, "手で直した並び・インデントは、再生成しても変えない")
    # 同期のあとも残る（BranchGroup は同期がそのまま保つ）
    sync(root)
    sync(root)
    check(branch_block(n1) == manual, "同期のあとも並び・インデントが残る")
    before = {p.name: p.read_text(encoding="utf-8") for p in root.glob("*.md")}
    pp.regen(root)
    sync(root)
    after = {p.name: p.read_text(encoding="utf-8") for p in root.glob("*.md")}
    check(before == after, "regen と同期を繰り返しても変わらない（冪等）")

# 旧 `1-Index` グループ（本文のインデントが階層）は、BranchGroup に引き継いでからごみ箱へ
with tempfile.TemporaryDirectory() as d:
    root = make_vault(Path(d))
    pp.create_paper_index(root)
    moved, errors = pp.move_images(root, root, [(img(root, "s1.jpg"), "1"), (img(root, "t1.jpg"), "1", "仏教"),
                                                 (img(root, "t2.jpg"), "1", "四念処", "1-仏教")])
    notes = {fid: p for fid, p in moved}
    pp.regen(root)
    # 旧い形に戻す: BranchGroup を外し、旧 1-Index グループ（インデントが階層）を作る
    n1 = notes["1"]
    ls = lines_of(n1)
    i = ls.index("BranchGroup:")
    j = i + 1
    while j < len(ls) and ls[j].strip().startswith("["):
        j += 1
    del ls[i:j + 1]
    n1.write_text("\n".join(ls), encoding="utf-8")
    legacy = root / "261001000000.md"
    legacy.write_text("---\ntime: 2026-10-01 00:00:00\ntitle: 1-Index\nattribute: group\n---\n\n# 1-Index\n"
                      f"[1]({n1.name})\n[1-仏教]({notes['1-仏教'].name})\n  [1-四念処]({notes['1-四念処'].name})\n", encoding="utf-8")
    pp.regen(root)
    b = branch_block(n1)
    check([ln.strip().split("]")[0].lstrip("[") for ln in b] == ["1-仏教", "1-四念処"] and not any(ln.startswith(" ") for ln in b),
          f"旧 1-Index の並びを BranchGroup に引き継ぐ（インデントは外す）: {b}")
    check(not legacy.exists() and any(p.name.endswith("261001000000.md") for p in (root / ".trash").glob("*")),
          "旧 1-Index グループはごみ箱へ")



def fm_of(path: Path):
    ls = lines_of(path)
    return ls[1:ls.index("---", 1)]


def block(path: Path, head: str):
    ls = lines_of(path)
    if head not in ls:
        return []
    i = ls.index(head) + 1
    out = []
    while i < len(ls) and ls[i].strip().startswith("["):
        out.append(ls[i])
        i += 1
    return out


# 紙ノートの親子・トピックの親子・folgezettel-Index-N・トピック本文・スキャンの印
with tempfile.TemporaryDirectory() as d:
    root = make_vault(Path(d))
    pp.create_paper_index(root)
    moved, errors = pp.move_images(root, root, [(img(root, "s1.jpg"), "1"), (img(root, "s1a.jpg"), "1a"),
                                                 (img(root, "t1.jpg"), "1", "仏教")])
    moved2, _e = pp.move_images(root, root, [(img(root, "t2.jpg"), "1", "四念処", "1-仏教")])
    moved3, _e = pp.move_images(root, root, [(img(root, "t3.jpg"), "1", "阿含")])
    notes = {fid: p for fid, p in moved + moved2 + moved3}
    pp.regen(root)
    n1, n1a = notes["1"], notes["1a"]
    check(any(f"]({n1.name})" in ln for ln in block(n1a, "ParentBranch:")), f"1a の ParentBranch: に 1: {block(n1a, 'ParentBranch:')}")
    check(any(f"]({n1a.name})" in ln for ln in block(n1, "ChildBranch:")), f"1 の ChildBranch: に 1a: {block(n1, 'ChildBranch:')}")
    ctx_1a = block(n1a, "### Context") + block(n1a, "Context:")
    check(not any(f"]({n1.name})" in ln for ln in ctx_1a), f"1a の親子を Context で代用しない: {ctx_1a}")
    for t in ("1-仏教", "1-四念処", "1-阿含"):
        check(any(f"]({n1.name})" in ln for ln in block(notes[t], "ParentBranch:"))
              and any(f"]({notes[t].name})" in ln for ln in block(n1, "ChildBranch:")),
              f"トピック {t} の ParentBranch: に 1・1 の ChildBranch: に {t}")
    check("topic_parent: 1-仏教" in fm_of(notes["1-四念処"]) and not any(l.startswith("topic_parent") for l in fm_of(notes["1-仏教"])),
          f"親トピックは front matter の topic_parent に残る: {fm_of(notes['1-四念処'])}")
    check(all("source: scan" in fm_of(p) for p in notes.values()), "スキャン由来のノートに source: scan")
    fi = root / "folgezettel-Index-1.md"
    names = [ln.split("]")[0].lstrip("[") for ln in lines_of(fi) if ln.startswith("[1-")]
    check(names == ["1-仏教", "1-四念処", "1-阿含"], f"folgezettel-Index-1 にトピックを、親を子より先に（インデントなし）: {names}")
    fl = lines_of(fi)
    check(fl.index(next(l for l in fl if l.startswith("[1-仏教]"))) < fl.index(next(l for l in fl if l.startswith("## [1a]"))),
          "トピックは ## 1 の節に並ぶ（## 1a より前）")
    # トピック本文の Context より下を切り捨てない
    tp = notes["1-仏教"]
    tp.write_text(tp.read_text(encoding="utf-8").rstrip("\n") + "\n\nRelated:\n[1a](" + n1a.name + ")\n\n手書きの続き\n", encoding="utf-8")
    pp.regen(root)
    check("手書きの続き" in tp.read_text(encoding="utf-8") and "Related:" in tp.read_text(encoding="utf-8"),
          "トピックノートの Context より下を切り捨てない")
    # 親が特定できないときは推測しない（topic_parent の相手が無い）
    moved4, _e = pp.move_images(root, root, [(img(root, "t4.jpg"), "1", "禅", "1-存在しない")])
    t4 = dict(moved4)["1-禅"]
    pp.regen(root)
    check(not any(l.startswith("topic_parent") for l in fm_of(t4)), "親トピックが見つからなければ topic_parent を書かない")
    sync(root)
    before = {p.name: p.read_text(encoding="utf-8") for p in root.glob("*.md")}
    pp.regen(root)
    sync(root)
    after = {p.name: p.read_text(encoding="utf-8") for p in root.glob("*.md")}
    check(before == after, f"regen と同期を繰り返しても変わらない（冪等）: {[k for k in after if before.get(k) != after[k]]}")

# 紙の日記: その日のデジタル日記の、タイトルの下・本文より上にリンク（重複しない・デジタル日記が無い日は何もしない）
with tempfile.TemporaryDirectory() as d:
    root = make_vault(Path(d))
    pp.create_paper_index(root)
    (root / "261001000000.md").write_text("---\ntime: 2026-10-01 00:00:00\ntitle: 10月\nattribute: group\n---\n\n# 10月\n\n"
                                          "[2026-10-14-TU](261014090000.md)\n", encoding="utf-8")
    dg = root / "261014090000.md"
    dg.write_text("---\ntime: 2026-10-14 09:00:00\ntitle: 2026-10-14-TU\n---\n\n# 2026-10-14-TU\n\nGroup:\n[10月](261001000000.md)\n\n朝の日記。\n", encoding="utf-8")
    moved, errors = pp.register_diary_pages(root, root, [(img(root, "p1.jpg"), "2026-10-14"), (img(root, "p2.jpg"), "2026-10-13")])
    check(len(moved) == 2 and not errors, "紙の日記 2 日分を取り込む")
    pd = dict(moved)
    pp.regen(root)
    dl = lines_of(dg)
    link = f"[紙の日記]({pd['2026-10-14'].name})"
    check(link in dl, f"デジタル日記に紙の日記へのリンク: {dl}")
    i = dl.index(link)
    check(dl[i - 1] == "" and dl[i + 1] == "" and dl[i + 2] == "朝の日記。" and dl.index("Group:") < i,
          f"タイトル（と上のブロック）の下・空行 1 行・本文より上: {dl}")
    check("source: scan" in fm_of(pd["2026-10-14"]) and "source: scan" in fm_of(pd["2026-10-13"]), "紙の日記に source: scan")
    check(not any(p.read_text(encoding="utf-8").count(pd["2026-10-13"].name) for p in root.glob("*.md")
                  if p != pd["2026-10-13"] and "title: 2026-10-13-MO" in p.read_text(encoding="utf-8") and "source: scan" not in p.read_text(encoding="utf-8")),
          "デジタル日記が無い日は作らない")
    check(not any("2026-10-13-MO" in p.read_text(encoding="utf-8") and "source: scan" not in p.read_text(encoding="utf-8")
                  for p in root.glob("*.md")), "デジタル日記が無い日に日記を作らない")
    pp.regen(root)
    sync(root)
    pp.regen(root)
    check(dg.read_text(encoding="utf-8").count(pd["2026-10-14"].name + ")") == 1, "再生成・同期を繰り返してもリンクは 1 つ")

print("all passed" if ng == 0 else f"{ng} failed")
sys.exit(1 if ng else 0)
