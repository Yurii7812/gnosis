#!/usr/bin/env python3
"""関係の節の見出しは「名前:」の形（ParentBranch: / ChildBranch: / Related: / BackLink:）。
旧形式の `### 名前` も読め、同期すると新形式に書き直される（リンクは 1 本も失わない）。"""
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "note_format_v2.py"
sys.path.insert(0, str(HERE))
import branch_ops  # noqa: E402

ng = 0


def check(cond, name):
    global ng
    print(("  ok   " if cond else "  FAIL ") + name)
    if not cond:
        ng += 1


def put(root, name, title, body, group=False):
    fm = ["---", "time: 2026-01-01 00:00:00", f"title: {title}"] + (["attribute: group"] if group else []) + ["---", ""]
    (root / name).write_text("\n".join(fm + [f"# {title}", ""] + body) + "\n", encoding="utf-8")


def sync(root):
    subprocess.run([sys.executable, str(SCRIPT), "update", str(root)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def lines(root, name):
    return (root / name).read_text(encoding="utf-8").split("\n")


OLD_HEADS = ("### ParentBranch", "### ChildBranch", "### Related", "### BackLink")

with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    put(root, "index.md", "Index", ["[A](a.md)"], True)
    # 旧形式（### 見出し）の関係の節を持つノート
    put(root, "a.md", "A", ["本文A。", "", "### ChildBranch", "[B](b.md)", "### Related", "[R](r.md)"])
    put(root, "b.md", "B", ["本文B。", "", "### ParentBranch", "[A](a.md)"])
    put(root, "r.md", "R", ["本文R。", "", "### Related", "[A](a.md)"])
    put(root, "c.md", "C", ["[A](a.md) に言及する本文。"])
    sync(root)
    sync(root)
    a, b, r = lines(root, "a.md"), lines(root, "b.md"), lines(root, "r.md")
    check(not any(h in ln for ln in a + b + r for h in OLD_HEADS), "同期すると旧形式の見出し（###）は残らない")
    check("ChildBranch:" in a and "[B](b.md)" in a, "A: ChildBranch: に B が残る")
    check("Related:" in a and "[R](r.md)" in a, "A: Related: に R が残る")
    check("ParentBranch:" in b and "[A](a.md)" in b, "B: ParentBranch: に A が残る")
    check("Related:" in r and "[A](r.md)" not in r and "[A](a.md)" in r, "R: Related: に A が残る")
    check("BackLink:" in a and "[C](c.md)" in a, "A: 本文で言及した C が BackLink: に出る")
    check(a.index("ChildBranch:") < a.index("Related:") < a.index("BackLink:"), "並びは ChildBranch → Related → BackLink")
    before = {p.name: p.read_text(encoding="utf-8") for p in root.glob("*.md")}
    sync(root)
    after = {p.name: p.read_text(encoding="utf-8") for p in root.glob("*.md")}
    check(before == after, "もう一度同期しても何も変わらない（冪等）")

with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    put(root, "a.md", "A", ["本文A。"])
    put(root, "b.md", "B", ["本文B。"])
    put(root, "c.md", "C", ["本文C。"])
    r = branch_ops.add_branches(root, root / "a.md", [root / "b.md"])
    check(r["ok"], "Branch を足せる")
    a = lines(root, "a.md")
    check(a.count("ChildBranch:") == 1 and "[B](b.md)" in a, "新しい節は ChildBranch: の形で作られる")
    # 旧形式の節があるノートには、その節に足す（新旧の 2 つに分けない）
    put(root, "p.md", "P", ["本文P。", "", "### ChildBranch", "[X](x.md)"])
    put(root, "x.md", "X", ["本文X。", "", "### ParentBranch", "[P](p.md)"])
    put(root, "y.md", "Y", ["本文Y。"])
    r = branch_ops.add_branches(root, root / "p.md", [root / "y.md"])
    p = lines(root, "p.md")
    check(r["ok"] and p.count("### ChildBranch") == 1 and "ChildBranch:" not in p and "[Y](y.md)" in p,
          "旧形式の ### ChildBranch の節に足す（節を 2 つに分けない）")

print("all passed" if ng == 0 else f"{ng} failed")
sys.exit(1 if ng else 0)
