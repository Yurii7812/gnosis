#!/usr/bin/env python3
"""曼荼羅で ' を押すと、右側に設定の画面が出る（実 Vim・擬似端末）。
  z で出る（画面の右半分）→ , で親子モード → j Enter で次の行を切り替え → q で閉じる（曼荼羅は残る）。
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

    mk("index.md", "Index", "")
    mk("top.md", "上位", "ParentBranch:\n[親](par.md)\n\n本文 [リンク先](linkonly.md)\n\nChildBranch:\n[子1](kid1.md)")
    mk("par.md", "親", "")
    mk("kid1.md", "子1", "")
    mk("kid2.md", "子2", "ParentBranch:\n[上位](top.md)")
    mk("linkonly.md", "リンク先", "")
    env = dict(os.environ, TERM="xterm-256color", GNOSIS_HOME=str(work / "home"), WAYLAND_DISPLAY="", DISPLAY="", TMPDIR=str(work))
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe("vim", ["vim", "-u", str(REPO / "vimrc_gnosis"), "-N", "--cmd",
                           "let g:gnosis_open_index_on_startup=0|let g:gnosis_skip_interactive_mount=1|let g:gnosis_autosync=0|let g:gnosis_mview_restore=0|let g:gnosis_root='" + str(v) + "/'",
                           str(v / "top.md")], env)
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

    def state():
        f = work / "st.txt"
        if f.exists():
            f.unlink()
        os.write(fd, (":call writefile([gnosis#mview#state().mode, string(get(gnosis#mview#state(), 'near_on', 0)), &filetype, get(gnosis#mview#state(), 'out_dir', 'all'), string(get(gnosis#mview#state(), 'depth', 1)), get(gnosis#mview#state(), 'dbasis', 'center')], '" + str(f) + "')\r").encode())
        pump(0.7)
        return f.read_text().split("\n") if f.exists() else []

    pump(1.5)
    os.write(fd, b" ")
    pump(2.0)
    st = state()
    ok("曼荼羅が開いている（全体モード）", st[:1] == ["all"] and st[2:3] == ["gnosis-mandala"])
    mark = len(out)
    os.write(fd, b"Z")
    pump(1.2)
    seg = out[mark:]
    ok("Z で設定の画面が出る", "曼荼羅の設定".encode() in seg and "プリセット".encode() in seg)
    i = seg.rfind("曼荼羅の設定".encode())
    m = list(re.finditer(rb"\x1b\[(\d+);(\d+)H", seg[:i]))
    col = int(m[-1].group(2)) if m else 0
    ok("画面の右半分に出る（列 %d）" % col, col > 70)
    os.write(fd, b"d")
    pump(0.8)
    os.write(fd, b"jj")
    pump(0.4)
    os.write(fd, b"\r")
    pump(0.8)
    os.write(fd, b"q")
    pump(0.8)
    st = state()
    ok(", で親子モードになった", st[:1] == ["family"])
    ok("jj Enter で 3 行目（近いグループを重ねる）がオンになった", st[1:2] == ["1"])
    ok("q で設定の画面だけ閉じ、曼荼羅は残る", st[2:3] == ["gnosis-mandala"])
    os.write(fd, b":call gnosis#mview#set_depth(3)\r")
    pump(0.8)
    os.write(fd, b"Z")
    pump(0.5)
    os.write(fd, b"D")
    pump(0.5)
    os.write(fd, b"q")
    pump(0.5)
    st = state()
    ok("設定画面の D で配下だけ・深さは維持", st[3:5] == ["down", "3"])
    os.write(fd, b"Z")
    pump(0.4)
    os.write(fd, b"D")
    pump(0.4)
    os.write(fd, b"q")
    pump(0.4)
    st = state()
    ok("設定画面の D でもう一度通常へ", st[3:5] == ["all", "3"])
    os.write(fd, b"wZ")
    pump(0.4)
    os.write(fd, b"b")
    pump(0.4)
    os.write(fd, b"q")
    pump(0.4)
    st = state()
    ok("近さ順の基準は b に移り、方向は変わらない", st[3:4] == ["all"] and st[5:6] == ["self"])
    os.write(fd, b"b")
    pump(0.4)
    st = state()
    ok("曼荼羅上の b でも基準が切り替わる", st[5:6] == ["center"] and st[3:5] == ["all", "3"])
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
