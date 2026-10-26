#!/usr/bin/env python3
"""\\. （曼荼羅の戻るを戻す）を、実 Vim を擬似端末で動かして確かめる。元は \\l → e の試験:\n  \\l → （曼荼羅で選ぶ）→ e を、実 Vim を擬似端末で動かして確かめる（2026-10-24 の不具合の回帰）。
  前回の検索（@/）が残っていて、typeahead に <Cmd>nohlsearch<CR> が積まれていても、
  e のあとに「どこに置く？」の選択肢が出て、E486 が出ず、ノートの中身も変わらない。
一時 vault だけを使う。"""
import fcntl, os, pty, re, select, shutil, struct, sys, tempfile, termios, time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TMP = Path(os.environ.get("TMPDIR") or Path.home() / "gnosis-work/test")
TMP.mkdir(parents=True, exist_ok=True)
work = Path(tempfile.mkdtemp(dir=TMP))
res = []


def ok(name, cond):
    res.append(("OK " if cond else "NG ") + name)


try:
    (work / "home").mkdir()
    v = work / "vault"
    v.mkdir()

    def mk(n, t, body):
        (v / n).write_text(f"---\ntime: 2026-01-01 00:00:00\ntitle: {t}\n---\n\n# {t}\n\n{body}\n", encoding="utf-8")

    (v / "index.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[植物](plant.md)\n", encoding="utf-8")
    mk("plant.md", "植物", "あいうえお。AI の話。\n\n末尾の行。\n\n[ハーブ](herb.md)")
    mk("herb.md", "ハーブ", "ハーブの話。[植物](plant.md)")
    before = (v / "plant.md").read_text(encoding="utf-8")
    env = dict(os.environ, TERM="xterm-256color", GNOSIS_HOME=str(work / "home"), WAYLAND_DISPLAY="", DISPLAY="", TMPDIR=str(work))
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe("vim", ["vim", "-u", str(REPO / "vimrc_gnosis"), "-N", "--cmd",
                           "let g:gnosis_open_index_on_startup=0|let g:gnosis_skip_interactive_mount=1|let g:gnosis_autosync=0|let g:gnosis_root='" + str(v) + "/'",
                           "-c", "let @/='ZZZ-no-such-word'", str(v / "plant.md")], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 0, 0))
    out = b""

    def pump(t):
        global out
        end = time.time() + t
        while time.time() < end:
            if select.select([fd], [], [], 0.05)[0]:
                try:
                    out += os.read(fd, 65536)
                except OSError:
                    return

    def text(b):
        return re.sub(rb"\x1b\[[0-9;?<>]*[a-zA-Z]|\x1b[()78=>]", b"", b).decode("utf8", "replace")

    pump(1.5)

    def center():
        f = work / "center.txt"
        if f.exists():
            f.unlink()
        os.write(fd, (":call writefile([gnosis#mview#state().center], '" + str(f) + "')\r").encode())
        pump(0.6)
        return f.read_text().strip() if f.exists() else ""

    # ノートで <Space> → 曼荼羅にカーソルがある状態で \\l（ノートにカーソルがあるときの \\l は、ふつうの全文検索）
    for k, w in [("8G", 0.4), (" ", 1.5)]:
        os.write(fd, k.encode())
        pump(w)
    c1 = center()
    for rc in ("0,1", "1,0", "1,2", "2,1", "0,0", "2,2"):   # 周りのマスをクリックして中心にする（履歴に積まれる）
        os.write(fd, (":call gnosis#mview#gui_click(" + rc + ",1)\r").encode())
        pump(1.0)
        c1 = center()
        if c1 not in ("", "plant.md"):
            break
    ok("マスを選ぶと別のノートが中心になる", c1 not in ("", "plant.md"))
    os.write(fd, b"\x7f")  # BS: 戻る
    pump(1.0)
    ok("BS で戻る", center() == "plant.md")
    os.write(fd, b"\\.")   # \. : 戻るを戻す（曼荼羅の上でも動く）
    pump(1.5)
    ok("\\. で戻るを戻せる", center() == c1)
    os.write(fd, b"\x1b")
    pump(0.6)
    os.write(fd, b":qa!\r")
    pump(1.0)
    try:
        os.close(fd)
    except OSError:
        pass
    print("\n".join(res))
    sys.exit(1 if any(r.startswith("NG") for r in res) else 0)
finally:
    shutil.rmtree(work, ignore_errors=True)
