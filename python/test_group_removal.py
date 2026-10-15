#!/usr/bin/env python3
"""Group: からグループへのリンクを消したら、そのグループの所属から外れる（次の sync で戻らない）。"""
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "note_format_v2.py"
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
    return (root / name).read_text(encoding="utf-8")


with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    note(root, "index.md", "Index", ["[グループG](g.md)", "[グループH](h.md)", "[ノートM](m.md)"], True)
    note(root, "g.md", "グループG", ["[ノートN](n.md)", "[ノートM](m.md)"], True)
    note(root, "h.md", "グループH", ["[ノートN](n.md)"], True)
    note(root, "n.md", "ノートN", ["本文。"])
    note(root, "m.md", "ノートM", ["本文。"])
    sync(root)
    sync(root)
    check("(g.md)" in read(root, "n.md") and "(h.md)" in read(root, "n.md"), "sync で N の Group: に G と H が入る")

    # N の Group: から G へのリンクだけを消す
    text = read(root, "n.md")
    text = "\n".join(ln for ln in text.split("\n") if ln != "[グループG](g.md)")
    (root / "n.md").write_text(text, encoding="utf-8")
    sync(root)
    check("(n.md)" not in read(root, "g.md"), "G の本文から N が消える")
    check("(m.md)" in read(root, "g.md"), "G の他のメンバー M は残る")
    check("(g.md)" not in read(root, "n.md"), "N の Group: に G は戻らない")
    check("(h.md)" in read(root, "n.md"), "N の他の所属 H は残る")
    check("(n.md)" in read(root, "h.md"), "H の本文の N は残る")
    sync(root)
    sync(root)
    check("(g.md)" not in read(root, "n.md") and "(n.md)" not in read(root, "g.md"), "何度同期しても戻らない")

    # sync が自動で足した [Index] を消しても、Index から外れる
    text = read(root, "m.md")
    check("(index.md)" in text, "M の Group: に Index が自動で入っている")
    (root / "m.md").write_text("\n".join(ln for ln in text.split("\n") if "(index.md)" not in ln), encoding="utf-8")
    sync(root)
    sync(root)
    check("(m.md)" not in read(root, "index.md"), "Index の本文から M が消える")
    check("(index.md)" not in read(root, "m.md"), "M の Group: に Index は戻らない")

print("all passed" if ng == 0 else f"{ng} failed")
sys.exit(1 if ng else 0)
