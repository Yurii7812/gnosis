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
    Image.new("RGB", (80, 60), (30, 200, 30)).save(work / "vault" / "other.png")  # ノートに書かれていない画像
    (work / "vault" / "index.md").write_text("# Index\n", encoding="utf-8")
    note = work / "vault" / "n.md"
    note.write_text("# n\n\n![](a.jpg)\n\n![](b.png)\n\nlast\n", encoding="utf-8")
    res = []

    fake = work / "bin"
    fake.mkdir()
    (fake / "xdg-open").write_text('#!/bin/sh\necho "$1" >> "%s"\n' % (work / "opened.txt"))
    (fake / "xdg-open").chmod(0o755)

    def run(keys, extra_init="", pre_hidden=False, viewer="sixel"):
        shutil.rmtree(work / "vault" / ".gnosis", ignore_errors=True)  # 前の run の設定（\\zz で変えたもの）を持ち越さない
        env = dict(os.environ, XDG_CACHE_HOME=str(work / "cache"), PATH=str(fake) + ":" + os.environ["PATH"], TERM="xterm-256color", GNOSIS_HOME=str(work / "home"), KONSOLE_VERSION="250402",
                   GNOSIS_CELL_PX="10x20", WAYLAND_DISPLAY="", DISPLAY="", TMPDIR=str(work))
        pid, fd = pty.fork()
        if pid == 0:
            os.execvpe("vim", ["vim", "-u", str(REPO / "vimrc_gnosis"), "-N", "--cmd",
                               ("let g:gnosis_image_viewer='" + viewer + "'|" if viewer else "") + "let g:gnosis_open_index_on_startup=0|let g:gnosis_skip_interactive_mount=1|let g:gnosis_autosync=0|let g:gnosis_root='" + str(work / "vault") + "/'" + extra_init,
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
    # 2) ノートを開くだけで、画像の行の下に画像が出る（hide.image が既定でオフ＝表示する）
    out, m = run([("3G", 3.0), ("j", 1.0), ("G", 1.0)])
    ok("開くと画像が sixel で出る", out.count(b"\x1bP0;1;0q") >= 1 or out.count(b"\x1bP0;") >= 1)
    # 3) \\zz の「画像」をオン（＝隠す）にすると、画像は出ない
    out, m = run([("\\zz", 0.5), ("jjj", 0.3), (" ", 0.6), ("q", 0.8)], pre_hidden=True)
    ok("\\zz の窓に画像の項目がある", "画像（ノートの中".encode() in out)
    # 4) a（全部オン）を押しても、画像はオンにならない
    out, m = run([("\\zz", 0.8), ("a", 0.8), ("q", 0.3)])
    ok("a で YAML などはオンになり、画像の項目はオンにならない", "[x] YAML".encode() in out and "[x] 画像".encode() not in out)
    # 5) 既定は xdg-open（外のビューア）。sixel は出ない
    out, m = run([("3G", 0.3), ("gz", 1.0), ("\r", 1.5)], viewer=None)
    opened = (work / "opened.txt").read_text() if (work / "opened.txt").exists() else ""
    ok("既定は xdg-open で開く", opened.strip().endswith("a.jpg"))
    ok("既定では gz で sixel を出さない", b"\x1bP0;1;0q" not in out[m[1]:])
    staged = Path(opened.strip().splitlines()[-1]) if opened.strip() else Path("/nonexistent")
    ok("ビューアには、このノートの画像だけを入れた一時フォルダのファイルを渡す", sorted(x.name for x in staged.parent.iterdir()) == ["01-a.jpg", "02-b.png"] if staged.exists() else False)
    # 一覧は端でループしない: 先頭で k → まだ先頭（a.jpg）、下へ何回 j しても最後（b.png）で止まる
    (work / "opened.txt").unlink()
    run([("3G", 0.3), ("gz", 1.0), ("k", 0.3), ("\r", 1.5)], viewer=None)
    ok("一覧の先頭で k を押しても最後へ回らない", (work / "opened.txt").read_text().strip().endswith("01-a.jpg"))
    (work / "opened.txt").unlink()
    run([("3G", 0.3), ("gz", 1.0), ("j", 0.2), ("j", 0.2), ("j", 0.2), ("k", 0.2), ("\r", 1.5)], viewer=None)
    ok("最後で j を重ねても先頭へ回らない（k で 1 つ戻れば先頭）", (work / "opened.txt").read_text().strip().endswith("01-a.jpg"))
    # 6) \zz の窓の「gz で画像を開く方法」を切り替えると、gz が sixel になり、設定に残る
    out, m = run([("\\zz", 0.8), ("jjjj", 0.3), ("\r", 0.5), ("q", 0.3), ("3G", 0.3), ("gz", 1.0), ("\r", 4.0), ("q", 0.8), ("q", 0.5)], viewer=None)
    ok("\\zz の窓に開く方法の行がある", "gz で画像を開く方法".encode() in out[: m[0]])
    ok("切り替えると sixel（この端末の中）と出る", "sixel（この端末の中）".encode() in out[m[1]: m[2]])
    ok("切り替えたあとの gz は sixel で出る", b"\x1bP0;1;0q" in out[m[5]: m[6]])
    print("\n".join(res))
    sys.exit(1 if any(r.startswith("NG") for r in res) else 0)
finally:
    shutil.rmtree(work, ignore_errors=True)
