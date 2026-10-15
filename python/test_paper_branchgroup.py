#!/usr/bin/env python3
"""紙の PKM のトピック: `1-Index` グループは作らず、ID ノート `1` の BranchGroup: にトピックを入れる。
階層（親トピック）は BranchGroup: の並びとインデント（2 スペース）だけで表す。"""
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
    check(b[1].startswith("  [1-四念処]") and not b[0].startswith(" ") and not b[2].startswith(" "),
          f"四念処だけ仏教の下に 2 スペース下がる: {b}")
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
    check([ln.strip().split("]")[0].lstrip("[") for ln in b] == ["1-仏教", "1-四念処"] and b[1].startswith("  "),
          f"旧 1-Index の並びとインデントを BranchGroup に引き継ぐ: {b}")
    check(not legacy.exists() and any(p.name.endswith("261001000000.md") for p in (root / ".trash").glob("*")),
          "旧 1-Index グループはごみ箱へ")

print("all passed" if ng == 0 else f"{ng} failed")
sys.exit(1 if ng else 0)
