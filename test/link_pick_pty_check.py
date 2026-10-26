#!/usr/bin/env python3
"""\\l → （曼荼羅で選ぶ）→ e を、実 Vim を擬似端末で動かして確かめる（2026-10-24 の不具合の回帰）。
  前回の検索（@/）が残っていて、typeahead に <Cmd>nohlsearch<CR> が積まれていても、
  e のあとに「どこに置く？」の選択肢が出て、E486 が出ず、ノートの中身も変わらない。
一時 vault だけを使う。"""
import fcntl, os, pty, re, select, shutil, struct, sys, tempfile, termios, time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TMP = Path(os.environ.get("TMPDIR") or Path.home() / "Desktop/test")
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
    mk("plant.md", "植物", "あいうえお。AI の話。\n\n末尾の行。")
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
    for k, w in [("8G", 0.4), (" ", 1.5), ("\\l", 2.0)]:
        os.write(fd, k.encode())
        pump(w)
    # ハーブを中心にする（曼荼羅の状態を直接書き換えて、z で描き直す）
    os.write(fd, b":let g:d = gnosis#mview#state() | let g:d.center = 'herb.md'\r")
    pump(0.6)
    os.write(fd, b"\x0c")      # Ctrl-L: 盤面を中央に戻す
    pump(0.8)
    ok("曼荼羅でハーブを選べた", center() == "herb.md")
    before = (v / "plant.md").read_text(encoding="utf-8")
    mark = len(out)
    os.write(fd, b"e")
    pump(2.0)
    after_e = text(out[mark:])
    ok("e のあとに置き場所の選択肢が出る（どこに置く？）", "どこに置く" in after_e)
    ok("E486 が出ない", "E486" not in after_e)
    ok("ここまでノートの中身は変わっていない", (v / "plant.md").read_text(encoding="utf-8") == before)
    # h: 右の元のノートで場所を選ぶモードへ。q でやめると置き場所の選択に戻る（\l は続く）
    mark = len(out)
    os.write(fd, b"h")
    pump(1.5)
    after_h = text(out[mark:])
    ok("h: 右のノートで場所を選ぶ案内が出る", "Enter で決定" in after_h)
    mark = len(out)
    os.write(fd, b"q")
    pump(1.5)
    after_q = text(out[mark:])
    ok("h のあと q: 置き場所の選択に戻る（どこに置く？がもう一度出る）", "どこに置く" in after_q)
    # もう一度 h → 1 行下へ動いて Enter で決める → リンクがその行の下に入る
    os.write(fd, b"h")
    pump(1.0)
    os.write(fd, b"gg")
    pump(0.4)
    os.write(fd, b"\r")
    pump(2.5)
    body = (v / "plant.md").read_text(encoding="utf-8")
    print(repr(body)) if os.environ.get("DBG") else None
    ok("h → Enter: 先頭行(gg)の下に、選んだノートへのリンクが入る", "[ハーブ](herb.md)" in body and body.index("[ハーブ](herb.md)") < body.index("あいうえお"))
    ok("h → Enter のあと、曼荼羅の中心も右のノートも元のノート(plant.md)のまま", center() == "plant.md")
    f2 = work / "win.txt"
    os.write(fd, (":call writefile(map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), \":t\")'), '" + str(f2) + "')\r").encode())
    pump(0.6)
    ok("右の窓に開いているのは plant.md", f2.exists() and "plant.md" in f2.read_text().split() and "herb.md" not in f2.read_text().split())
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
