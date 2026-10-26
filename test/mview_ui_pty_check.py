#!/usr/bin/env python3
"""曼荼羅まわりの見た目を、実 Vim を擬似端末で動かして確かめる（一時 vault だけを使う）。
  - ``` で囲んだコードの行が、右端まで灰色の背景になる（文字の分だけではない）
  - 曼荼羅を開いたまま右のノートで挿入モードにすると、左下（曼荼羅の窓のステータス行）にも INSERT と出る
  - m（ハイライト）の入力欄: 入力中はカーソルが出て、q でやめたあとは入力欄の文字が残らない"""
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
    (v / "index.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[メモ](memo.md)\n", encoding="utf-8")
    (v / "memo.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: メモ\n---\n\n# メモ\n\n前の行\n\n```\ncode a\ncode b\n```\n\n後ろの行\n", encoding="utf-8")
    env = dict(os.environ, TERM="xterm-256color", GNOSIS_HOME=str(work / "home"), WAYLAND_DISPLAY="", DISPLAY="", TMPDIR=str(work))
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe("vim", ["vim", "-u", str(REPO / "vimrc_gnosis"), "-N", "--cmd",
                           "let g:gnosis_open_index_on_startup=0|let g:gnosis_skip_interactive_mount=1|let g:gnosis_autosync=0|let g:gnosis_mview_restore=0|let g:gnosis_root='" + str(v) + "/'",
                           str(v / "memo.md")], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
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

    pump(2.0)
    # 画面の一番下の行（コマンド行）を 0.1 秒ごとに記録して、あとで「q のあとに入力欄の文字が残っていないか」を読む
    logf = work / "cmdline.log"
    os.write(fd, (":let g:cl = []|call timer_start(100, {-> [add(g:cl, join(map(range(1, 70), 'screenstring(&lines, v:val)'), '')), writefile(g:cl[-30:], '" + str(logf) + "')]}, {'repeat': -1})\r").encode())
    pump(0.5)
    # 1) コードの行は、右端まで背景色がある: 「code a」の行の右端のセルと、ふつうの行（後ろの行）の右端のセルで、表示属性（screenattr）が違う
    f = work / "attr.txt"
    os.write(fd, (":call search('code a', 'w')|redraw|let g:r1 = win_screenpos(0)[0] + winline() - 1|call search('後ろの行', 'w')|redraw|let g:r2 = win_screenpos(0)[0] + winline() - 1|call writefile([string(screenattr(g:r1, 110)), string(screenattr(g:r2, 110))], '" + str(f) + "')\r").encode())
    pump(1.0)
    a1, a2 = (f.read_text().split() if f.exists() else ["?", "?"])
    ok("コードの行は右端のセルまで背景色が付く（行全体）: " + a1 + " vs " + a2, a1 != a2 and a1 not in ("?", "0"))
    # 2) 曼荼羅を開く（Space）→ 右のノートで挿入モード → 左下の曼荼羅の窓のステータス行にも INSERT が出る。
    #    端末へ出る文字は変わった所だけなので、Vim に「曼荼羅の窓のステータス行を今評価した文字」と、
    #    その窓が最後に描かれたときの状態（モード変化で全窓を描き直す autocmd があるか）を聞く
    os.write(fd, b" ")
    pump(1.8)
    os.write(fd, b"\x17l")      # 右の窓（ノート）へ
    pump(0.6)
    # 挿入モードに入った 0.5 秒後（描き直しのあと）に、左の窓のステータス行の文字を画面から読んでファイルへ書く
    f = work / "stl.txt"
    os.write(fd, (":autocmd InsertEnter * call timer_start(500, {-> writefile([join(map(range(1, 20), 'screenstring(win_screenpos(win_getid(1))[0] + winheight(win_getid(1)), v:val)'), '')], '" + str(f) + "')})\r").encode())
    pump(0.5)
    mark = len(out)
    os.write(fd, b"i")
    pump(1.5)
    seg = text(out[mark:])
    ok("挿入モード: ステータス行に INSERT が出る", "INSERT" in seg)
    left = f.read_text() if f.exists() else ""
    ok("挿入モード: 曼荼羅の窓（左）のステータス行も INSERT になっている: " + left.strip()[:20], "INSERT" in left)
    os.write(fd, b"\x1b")
    pump(0.6)
    mark = len(out)
    os.write(fd, b"\x17h")      # 曼荼羅の窓へ戻る
    pump(0.6)
    # 3) m の入力欄
    mark = len(out)
    os.write(fd, b"m")
    pump(0.8)
    seg = out[mark:]
    ok("m の入力欄が出る", "ハイライト".encode() in seg)
    ok("入力欄ではカーソルを出す（?25h）", b"\x1b[?25h" in seg)
    os.write(fd, b"\x1b")        # 入力欄をやめる（Esc）
    pump(0.6)
    mark = len(out)
    os.write(fd, b"mmemo\r")
    pump(1.0)
    os.write(fd, b"q")
    pump(1.2)
    last = (logf.read_text().rstrip("\n").split("\n") or [""])[-1] if logf.exists() else "?"
    ok("q のあと、下の行（コマンド行）に入力欄の文字が残らない: [" + last.strip()[:30] + "]", "ハイライト" not in last and "memo" not in last and last != "?")
    # 4) + で深さの入力欄が出て、数字を打つと外向きの深さが決まる（外向きでなくても外向きになる）
    mark = len(out)
    os.write(fd, b"+")
    pump(0.8)
    seg = out[mark:]
    ok("+ で深さの入力欄が出る", "外向きの深さ".encode() in seg)
    ok("深さの入力欄でもカーソルを出す", b"\x1b[?25h" in seg)
    os.write(fd, b"\x08\x083\r")
    pump(1.0)
    f = work / "depth.txt"
    os.write(fd, (":call writefile([string(gnosis#mview#state().depth), string(get(gnosis#mview#state(), 'out_on', 0))], '" + str(f) + "')\r").encode())
    pump(0.8)
    d = f.read_text().split() if f.exists() else []
    ok("3 と打つと深さ 3・外向きになる: " + " ".join(d), d[:2] == ["3", "1"])
    os.write(fd, b":qa!\r")
    pump(0.8)
    try:
        os.close(fd)
    except OSError:
        pass
    print("\n".join(res))
    sys.exit(1 if any(r.startswith("NG") for r in res) else 0)
finally:
    shutil.rmtree(work, ignore_errors=True)
