#!/usr/bin/env python3
"""曼荼羅（CUI）で、選んでいるマスの周りの枠（縦線・横線のセル）にも背景が塗られ、塗りが枠の線まで届く（実 Vim・擬似端末）。
枠の線は端の行・桁の真ん中に引かれるので、内側だけ塗ると線との間に半マスの隙間ができ、「一部だけ」に見えた。"""
import fcntl, os, pty, select, shutil, struct, sys, tempfile, termios, time
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
    (v / "index.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[メモ](memo.md)\n[ハーブ](herb.md)\n", encoding="utf-8")
    for n, t in [("memo", "メモ"), ("herb", "ハーブ")]:
        (v / f"{n}.md").write_text(f"---\ntime: 2026-01-01 00:00:00\ntitle: {t}\n---\n\n# {t}\n\nGroup:\n[Index](index.md)\n", encoding="utf-8")
    env = dict(os.environ, TERM="xterm-256color", GNOSIS_HOME=str(work / "home"), WAYLAND_DISPLAY="", DISPLAY="", TMPDIR=str(work))
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe("vim", ["vim", "-u", str(REPO / "vimrc_gnosis"), "-N", "--cmd",
                           "let g:gnosis_open_index_on_startup=0|let g:gnosis_skip_interactive_mount=1|let g:gnosis_autosync=0|let g:gnosis_mview_restore=0|let g:gnosis_root='" + str(v) + "/'",
                           str(v / "index.md")], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))

    def pump(t):
        end = time.time() + t
        while time.time() < end:
            if select.select([fd], [], [], 0.05)[0]:
                try:
                    os.read(fd, 65536)
                except OSError:
                    return

    f = work / "o.txt"
    # 選んでいるマスの「左の縦線・右の縦線・上の横線・下の横線」のセルの表示属性と、離れた枠のセルの属性を読む
    cmd = (":let st=gnosis#mview#state()|let sp=st.spans[st.cur[0].','.st.cur[1]]|let w=win_screenpos(0)|"
           "let l1=getline(sp[0][0])|let lb=sp[0][1]-strlen(matchstr(strpart(l1,0,sp[0][1]-1),'.$'))|let re=sp[0][1]+sp[0][2]|"
           "let Col=function('strdisplaywidth')|"
           "let cl=w[1]+Col(strpart(l1,0,lb-1))|let cr=w[1]+Col(strpart(l1,0,re-1))|let rt=w[0]+sp[0][0]-2|let rb=w[0]+sp[-1][0]|"
           "let mid=w[0]+sp[0][0]-1|let cm=w[1]+Col(strpart(l1,0,sp[0][1]-1))+1|"
           "let far=w[1]+Col(strpart(l1,0,lb-1))-30|"
           "call writefile([join([screenattr(mid,cl),screenattr(mid,cr),screenattr(rt,cm),screenattr(rb,cm),screenattr(mid,cm)],' '), screenattr(mid,max([1,far]))],'" + str(f) + "')\r")
    pump(2.0)
    os.write(fd, b" ")
    pump(2.0)
    os.write(fd, b"k")
    pump(1.0)
    os.write(fd, cmd.encode())
    pump(1.0)
    lines = f.read_text().split("\n") if f.exists() else []
    a = lines[0].split() if lines else []
    ok("3×3: 左右の縦線と上下の横線の線が光る（属性が付く）: " + " ".join(a), len(a) == 5 and "0" not in a[:4] and a[0] == a[1] and a[0] != a[4])
    # 9×9（全画面）でも同じ
    if f.exists():
        f.unlink()
    os.write(fd, b"f")
    pump(1.5)
    os.write(fd, cmd.encode())
    pump(1.0)
    lines = f.read_text().split("\n") if f.exists() else []
    a = lines[0].split() if lines else []
    ok("9×9: 左右の縦線と上下の横線のセルにも背景が塗られる: " + " ".join(a), len(a) == 5 and "0" not in a[:4])
    # 右のノートにカーソルがあるとき（曼荼羅の窓にカーソルが無いとき）は、選んでいるマスのハイライトを消す
    cmdw = (":let g:st=gnosis#mview#state()|let g:sp=g:st.spans[g:st.cur[0].','.g:st.cur[1]]|let g:wi=getwininfo(win_getid(1))[0]|"
            "let g:r=g:wi.winrow+g:sp[0][0]-1|let g:ln=getbufline(g:st.buf,g:sp[0][0])[0]|let g:c=g:wi.wincol+strdisplaywidth(strpart(g:ln,0,g:sp[0][1]-1))+2|"
            "call writefile([string(screenattr(g:r,g:c))],'" + str(f) + "')\r")
    os.write(fd, b"\x17l")      # 右のノートの窓へ
    pump(1.0)
    if f.exists():
        f.unlink()
    os.write(fd, cmdw.encode())
    pump(1.0)
    off = f.read_text().strip() if f.exists() else "?"
    os.write(fd, b"\x17h")      # 曼荼羅の窓へ戻る
    pump(1.0)
    if f.exists():
        f.unlink()
    os.write(fd, cmdw.encode())
    pump(1.0)
    on = f.read_text().strip() if f.exists() else "?"
    ok("右のノートにカーソルがあると、選んでいるマスのハイライトが消える（属性 " + off + "）", off == "0")
    ok("曼荼羅に戻るとハイライトが戻る（属性 " + on + "）", on not in ("0", "?"))
    os.write(fd, b":qa!\r")
    pump(0.6)
    try:
        os.close(fd)
    except OSError:
        pass
    print("\n".join(res))
    sys.exit(1 if any(r.startswith("NG") for r in res) else 0)
finally:
    shutil.rmtree(work, ignore_errors=True)
