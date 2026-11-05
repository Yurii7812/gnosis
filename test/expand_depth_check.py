#!/usr/bin/env python3
"""曼荼羅の \\e（表示中のノートを起点に深さ N）の検査。一時 vault（TMPDIR 配下）だけを使う。

期待: 起点 A と X（表示中）から、深さ 0 は A・X のみ、深さ 1 で B・D が加わり、深さ 2 で C が加わる。
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PY = REPO / "python/expand_v2.py"


def note(path: Path, title: str, body: str) -> None:
    path.write_text(f"---\ntitle: {title}\n---\n# {title}\n\n{body}\n", encoding="utf-8")


def run(root: Path, listfile: Path, depth: int) -> str:
    out = subprocess.run([sys.executable, str(PY), "files_depth", str(root), str(listfile), str(depth)],
                         capture_output=True, text=True, check=True).stdout.strip()
    text = Path(out).read_text(encoding="utf-8")
    return ",".join(re.findall(r"^## (\S+)$", text, flags=re.M)[1:])  # 先頭は目次の見出し


base = Path(os.environ.get("TMPDIR", tempfile.gettempdir()))
with tempfile.TemporaryDirectory(dir=base) as td:
    root = Path(td) / "vault"
    root.mkdir()
    note(root / "A.md", "A", "[B](B.md) と [X](X.md)")
    note(root / "B.md", "B", "[C](C.md)")
    note(root / "C.md", "C", "end")
    note(root / "X.md", "X", "[D](D.md)")
    note(root / "D.md", "D", "d")
    lst = Path(td) / "list.txt"
    lst.write_text("A.md\nX.md\n", encoding="utf-8")
    ok = True
    for depth, want in [(0, "A,X"), (1, "A,X,B,D"), (2, "A,X,B,D,C")]:
        got = run(root, lst, depth)
        # 見出しは「題」で出る。出力順は起点→発見順
        names = [n for n in got.split(",") if n]
        same = set(names) == set(want.split(","))
        print(("OK  " if same else "NG  ") + f"depth {depth}: {got} (want {want})")
        ok = ok and same
print("expand_depth OK" if ok else "expand_depth NG")
sys.exit(0 if ok else 1)
