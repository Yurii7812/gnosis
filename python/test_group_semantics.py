#!/usr/bin/env python3
"""Group: の解釈。メンバーかどうかは「グループの本文（文中）にその相手のリンクがあるか」だけで決まる。
グループ自身の Group: に書かれた相手はそのグループの親で、メンバーではない。Group: の範囲は直後に続くリンク行だけ（空行で終わる）。"""
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "note_format_v2.py"
ng = 0


def check(cond, name):
    global ng
    print(("  ok   " if cond else "  FAIL ") + name)
    if not cond:
        ng += 1


def note(root, name, title, body, group=False):
    fm = ["---", "time: 2026-01-01 00:00:00", f"title: {title}"] + (["attribute: group"] if group else []) + ["---", ""]
    (root / name).write_text("\n".join(fm + [f"# {title}", ""] + body) + "\n", encoding="utf-8")


def sync(root):
    subprocess.run([sys.executable, str(SCRIPT), "update", str(root)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def read(root, name):
    return (root / name).read_text(encoding="utf-8").split("\n")


with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    note(root, "index.md", "Index", ["[A](a.md)"], True)
    # A はグループ。A の Group: には親グループ P だけを書く。本文の B はメンバー。
    note(root, "p.md", "P", ["[A](a.md)"], True)
    note(root, "a.md", "A", ["Group:", "[P](p.md)", "", "[B](b.md)"], True)
    note(root, "b.md", "B", ["本文B"])
    note(root, "c.md", "C", ["[A](a.md)"])   # C は本文で A を指すだけ（A の本文には C が無い）
    sync(root)
    sync(root)
    b = read(root, "b.md")
    c = read(root, "c.md")
    a = read(root, "a.md")
    check("[A:B](a.md)" in b and b.index("Group:") < b.index("[A:B](a.md)"), "B: A の本文にいるので Group: に A が入る")
    check("Group:" not in c, "C: A の本文にいない（C から A へ向けて書いただけ）ので Group: は付かない")
    check("[B](b.md)" in a and "Group:" in a, "A: 本文の B は残り、A の Group: もある")
    check(a.index("[B](b.md)") > a.index("[P:A](p.md)"), "A: 本文のリンクは Group: の下")
    check("Context:" not in a, "A: 不要な Context: を作らない")

    # Group: の直後に空行を挟んだ本文のリンクは、Group: に取り込まれない
    note(root, "g2.md", "G2", ["Group:", "[P](p.md)", "", "[M](m.md)"], True)
    note(root, "m.md", "M", ["本文M"])
    sync(root)
    sync(root)
    g2 = read(root, "g2.md")
    check("[M](m.md)" in g2 and g2.index("[M](m.md)") > g2.index("[P](p.md)") and "Context:" not in g2,
          "Group: の下の本文のリンクは、Group: にも Context: にもならない")
    m = read(root, "m.md")
    check("[G2:M](g2.md)" in m, "M: G2 の本文にいるので Group: に G2 が入る")

    import io
    before = {p.name: p.read_text(encoding="utf-8") for p in root.glob("*.md")}
    sync(root)
    after = {p.name: p.read_text(encoding="utf-8") for p in root.glob("*.md")}
    check(before == after, "もう一度同期しても何も変わらない（冪等）")


# BranchGroup: が Group: の上にあっても、本文のリンク行が BranchGroup: に吸い込まれない
with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    note(root, "index.md", "Index", ["[R](r.md)"], group=True)
    note(root, "g.md", "G", ["[M1](m1.md)"], group=True)
    note(root, "m1.md", "M1", ["x"])
    note(root, "m2.md", "M2", ["y"])
    note(root, "r.md", "R", ["BranchGroup:", "[G](g.md)", "Group:", "[Index](index.md)", "", "[M2](m2.md)"])
    read(root, "r.md")
    r = "\n".join(read(root, "r.md"))
    bg = r.split("BranchGroup:")[1].split("\nGroup:")[0]
    check("[G](g.md)" in bg and "m2.md" not in bg, "BranchGroup: の上に Group: があっても本文リンクは BranchGroup: に入らない")
    check("[M2](m2.md)" in r.split("\nGroup:")[1], "本文のリンクは本文に残る")


# ChildBranch: は、本文にリンクがある子を書かない（BranchGroup: の子も書かない）
with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    note(root, "index.md", "Index", ["[P](p.md)"], group=True)
    note(root, "g.md", "G", [], group=True)
    for n_ in ("a", "b", "c"):
        note(root, n_ + ".md", n_.upper(), ["x"])
    note(root, "p.md", "P", ["BranchGroup:", "[G](g.md)", "Group:", "[Index](index.md)", "", "本文 [B](b.md)", "",
                              "ChildBranch:", "[A](a.md)", "[B](b.md)", "[C](c.md)", "[G](g.md)"])
    sync(root)
    sync(root)
    p_ = read(root, "p.md")
    i = p_.index("ChildBranch:")
    cb = p_[i + 1:p_.index("BackLink:") if "BackLink:" in p_ else len(p_)]
    # 本文にリンクがある子（B）も BranchGroup: の G も ChildBranch: に書かない
    check(cb[:2] == ["[A](a.md)", "[C](c.md)"] and "[B](b.md)" not in cb and "[G](g.md)" not in cb,
          f"ChildBranch: 本文にある子は書かない（ほかは元の並びのまま）: {cb}")
    # 本文からリンクを消すと、子の ParentBranch: をもとに ChildBranch: に戻る
    note(root, "b.md", "B", ["ParentBranch:", "[P](p.md)", "", "x"])
    txt = (root / "p.md").read_text(encoding="utf-8").replace("本文 [B](b.md)", "本文")
    (root / "p.md").write_text(txt, encoding="utf-8")
    sync(root)
    p_ = read(root, "p.md")
    cb = p_[p_.index("ChildBranch:") + 1:]
    check("[B](b.md)" in cb, f"本文から消した子は ChildBranch: に戻る: {cb}")
    # このノートを Context にしている子は上、空行、ただの子は下
    note(root, "c.md", "C", ["ParentBranch:", "[P](p.md)", "Context:", "[P](p.md)", "", "x"])
    sync(root)
    p_ = read(root, "p.md")
    cb = p_[p_.index("ChildBranch:") + 1:]
    check(cb[0] == "[C](c.md)" and cb[1] == "" and "[A](a.md)" in cb[2:], f"Context にしている子が上: {cb}")

# 同じグループに別名で複数掲載。削除・名前変更・再同期に追従する。
with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    note(root, "a.md", "A", ["本文"])
    note(root, "b.md", "B", ["[aaa](a.md)", "[bbb](a.md)", "[aaa](a.md#見出し)"], True)
    sync(root)
    check("[B:aaa,bbb](b.md)" in read(root, "a.md"), "複数の表示名をまとめ、同じ表示名は重ねない")
    before = read(root, "a.md")
    sync(root)
    check(before == read(root, "a.md"), "別名つき Group の同期は冪等")
    note(root, "b.md", "改名B", ["[bbb](a.md)"], True)
    sync(root)
    check("[改名B:bbb](b.md)" in read(root, "a.md"), "グループ改名と一つの別名削除に追従")
    note(root, "b.md", "改名B", [], True)
    sync(root)
    check("Group:" not in read(root, "a.md"), "最後の別名を消すと所属も消える")

print("all passed" if ng == 0 else f"{ng} failed")
sys.exit(1 if ng else 0)
