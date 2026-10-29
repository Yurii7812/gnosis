#!/usr/bin/env python3
"""ノートで \\l（fzf の検索画面）→ Shift+← で画面を閉じて曼荼羅ビューで選び続ける／Shift+→ で右のパネルが開く、
\\l のまま。実 Vim + fzf を擬似端末で動かして確かめる。一時 vault だけを使う。"""
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
    mk("plant.md", "植物", "あいうえお。\n\n末尾の行。\n\n## 見出し")
    mk("herb.md", "ハーブ", "ハーブの話。[植物](plant.md)")
    env = dict(os.environ, TERM="xterm-256color", GNOSIS_HOME=str(work / "home"), WAYLAND_DISPLAY="", DISPLAY="", TMPDIR=str(work))

    def run(keys_after):
        pid, fd = pty.fork()
        if pid == 0:
            os.execvpe("vim", ["vim", "-u", str(REPO / "vimrc_gnosis"), "-N", "--cmd",
                               "let g:gnosis_open_index_on_startup=0|let g:gnosis_skip_interactive_mount=1|let g:gnosis_autosync=0|let g:gnosis_mandala_on_start=0|let g:gnosis_root='" + str(v) + "/'",
                               str(v / "plant.md")], env)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 0, 0))
        buf = [b""]

        def pump(t):
            end = time.time() + t
            while time.time() < end:
                if select.select([fd], [], [], 0.05)[0]:
                    try:
                        buf[0] += os.read(fd, 65536)
                    except OSError:
                        return

        def state():
            f = work / "st.txt"
            if f.exists():
                f.unlink()
            cmd = ":call writefile([string(gnosis#mview#pick_active()), gnosis#panel#kind(), string(gnosis#mview#is_open()), &filetype, fnamemodify(bufname('%'), ':t')], '" + str(f) + "')\r"
            os.write(fd, cmd.encode())
            pump(0.8)
            return f.read_text().split("\n") if f.exists() else []

        pump(1.5)
        os.write(fd, b"\\l")             # fzf の検索画面
        pump(2.5)
        shown = b"Title>" in buf[0] or "Title>".encode() in buf[0]
        for k, w in keys_after:
            os.write(fd, k)
            pump(w)
        st = state()
        os.write(fd, b"\x1b:qa!\r")
        pump(0.5)
        try:
            os.close(fd)
            os.waitpid(pid, 0)
        except OSError:
            pass
        return shown, st

    # Shift+← = ESC [ 1 ; 2 D   /   Shift+→ = ESC [ 1 ; 2 C
    shown, st = run([(b"\x1b[1;2D", 3.0)])
    ok("\\l で fzf の検索画面が出る", shown)
    ok("Shift+← のあと: \\l の選ぶモードが続いている", len(st) > 3 and st[0] == "1")
    ok("Shift+← のあと: 曼荼羅ビューが開いている", len(st) > 3 and st[2] == "1")
    ok("Shift+← のあと: 右のパネルは開いていない", len(st) > 3 and st[1] == "")
    shown, st = run([(b"\x1b[1;2C", 3.0)])
    ok("Shift+→ のあと: \\l の選ぶモードが続いている", len(st) > 3 and st[0] == "1")
    ok("Shift+→ のあと: 右のパネルが開く（最初はアウトライン）", len(st) > 3 and st[1] == "outline")
    ok("Shift+→ のあと: カーソルはパネルにある", len(st) > 4 and st[3] == "gnosis-outline")
    print("\n".join(res))
    sys.exit(1 if any(r.startswith("NG") for r in res) else 0)
finally:
    shutil.rmtree(work, ignore_errors=True)
