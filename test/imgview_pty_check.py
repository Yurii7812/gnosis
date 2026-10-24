#!/usr/bin/env python3
"""gz の画像ポップアップを、実 Vim を擬似端末で動かして確かめる（キーボードだけ）。
一時フォルダだけを使う。確かめること:
  一覧が出る → Enter で sixel が出る → j で次 → q で一覧 → q で閉じる → カーソルが Vim にあり、編集できる。
  オフにすると出ない。"""
import fcntl, os, pty, select, shutil, struct, sys, tempfile, termios, time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TMP = Path(os.environ.get("TMPDIR") or Path.home() / "Desktop/test")
TMP.mkdir(parents=True, exist_ok=True)
from PIL import Image

work = Path(tempfile.mkdtemp(dir=TMP))
try:
    (work / "home").mkdir()
    (work / "vault").mkdir()
    Image.new("RGB", (400, 300), (200, 30, 30)).save(work / "vault" / "a.jpg")
    Image.new("RGB", (80, 60), (30, 30, 200)).save(work / "vault" / "b.png")
    note = work / "vault" / "n.md"
    note.write_text("# n\n\n![](a.jpg)\n\n![](b.png)\n\nlast\n", encoding="utf-8")
    res = []

    def run(keys, extra_init=""):
        env = dict(os.environ, TERM="xterm-256color", GNOSIS_HOME=str(work / "home"), KONSOLE_VERSION="250402",
                   GNOSIS_CELL_PX="10x20", WAYLAND_DISPLAY="", DISPLAY="", TMPDIR=str(work))
        pid, fd = pty.fork()
        if pid == 0:
            os.execvpe("vim", ["vim", "-u", str(REPO / "vimrc_gnosis"), "-N", "--cmd",
                               "let g:gnosis_open_index_on_startup=0|let g:gnosis_skip_interactive_mount=1|let g:gnosis_autosync=0" + extra_init,
                               str(note)], env)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 1200, 800))
        out = b""

        def pump(t):
            nonlocal out
            end = time.time() + t
            while time.time() < end:
                if select.select([fd], [], [], 0.05)[0]:
                    try:
                        out += os.read(fd, 65536)
                    except OSError:
                        return

        pump(1.5)
        marks = []
        for k, wait in keys:
            os.write(fd, k.encode())
            pump(wait)
            marks.append(len(out))
        os.write(fd, b"\x1b:q!\r")
        pump(0.5)
        try:
            os.close(fd)
            os.waitpid(pid, 0)
        except OSError:
            pass
        return out, marks

    def ok(name, cond):
        res.append(("OK " if cond else "NG ") + name)

    # 1) gz → 一覧。 3(行)に画像リンクがあるので a.jpg が最初に選ばれる。Enter で表示 → j → q → q → Gx で編集できる
    out, m = run([("3G", 0.3), ("gz", 1.0), ("\r", 4.0), ("j", 4.0), ("q", 0.8), ("q", 0.8), ("Goedit\x1b", 0.6)])
    ok("一覧の題が出る", "画像（Enter".encode() in out[: m[1]])
    ok("Enter で sixel が出る", b"\x1bP0;1;0q" in out[m[1]: m[2]])
    ok("j で 2 枚目の sixel が出る", b"\x1bP0;1;0q" in out[m[2]: m[3]])
    ok("q で一覧に戻る", "画像（Enter".encode() in out[m[3]: m[4]])
    ok("もう一度 q で閉じたあと Vim で編集できる", b"edit" in out[m[5]:])
    # 2) \\zz の窓に「画像の行」の項目がある（畳まれることの確認は imgview_hide_check.vim）
    out, m = run([("\\zz", 0.8), ("q", 0.3)])
    ok("\\zz の窓に画像の行の項目", "画像の行".encode() in out[: m[0]])
    # 3) a（全部オン）を押しても、画像の行はオンにならない（YAML などの 3 つだけ）
    out, m = run([("\\zz", 0.8), ("a", 0.8), ("q", 0.3)])
    ok("a で YAML などはオンになり、画像の行はオンにならない", "[x] YAML".encode() in out and "[x] 画像の行".encode() not in out)
    print("\n".join(res))
    sys.exit(1 if any(r.startswith("NG") for r in res) else 0)
finally:
    shutil.rmtree(work, ignore_errors=True)
