"""ノートの中に画像を出す検出（imgview の scan）が、<img src="…" width="25%"> の行も拾うことを実 Vim で確かめる。"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

with tempfile.TemporaryDirectory(prefix="gnosis-imghtml-") as d:
    work = Path(d)
    note = work / "n.md"
    for name in ("a.png", "b.png", "c.png"):
        (work / name).write_bytes(b"x")
    note.write_text(
        "# n\n\n![](a.png)\n\n<img src=\"b.png\" width=\"25%\">\n\n  <img width='10' src='c.png'/>\n\n"
        "<img src=\"missing.png\">\n\n文 <img src=\"a.png\"> 文\n\n```\n<img src=\"a.png\">\n```\n",
        encoding="utf-8")
    out = work / "out.json"
    rc = work / "vimrc"
    rc.write_text(
        f"set nocp\nset rtp^={REPO}\nlet g:gnosis_skip_interactive_mount=1\nlet g:gnosis_start_screen=0\n"
        f"runtime autoload/gnosis/imgview.vim\n"
        f"edit {note}\n"
        "let s:sid = matchstr(execute('scriptnames'), '\\d\\+\\ze: [^\\n]*autoload/gnosis/imgview.vim')\n"
        "let s:items = function('<SNR>' . s:sid . '_scan')(bufnr('%'))\n"
        f"call writefile([json_encode(map(s:items, '[v:val.lnum, fnamemodify(v:val.path, \":t\")]'))], '{out}')\n"
        "qa!\n", encoding="utf-8")
    env = dict(os.environ, HOME=str(work), GNOSIS_HOME=str(work / "gh"))
    subprocess.run(["vim", "-u", str(rc), "-i", "NONE", "-n", "-es", "-N"], env=env, check=False, timeout=60,
                   stdin=subprocess.DEVNULL)
    got = json.loads(out.read_text())
    want = [[3, "a.png"], [5, "b.png"], [7, "c.png"]]
    print("OK" if got == want else f"NG got={got} want={want}")
    sys.exit(0 if got == want else 1)
