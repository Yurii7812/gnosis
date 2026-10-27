#!/usr/bin/env python3
"""曼荼羅ビュー・Folgezettel ビューから右のノートへ移ったとき、画面は一番上から、カーソルだけがその同じ画面の一番下の行にある。
実 Vim＋擬似端末で確かめる（一時 vault だけを使う）。ノートの中でカーソルを動かしたあとは置き直さない。"""
import os, re, shutil, sys, tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "test"))
from keys_pty import Session  # noqa: E402

TMP = Path(os.environ.get("TMPDIR") or Path.home() / "gnosis-work/test")
TMP.mkdir(parents=True, exist_ok=True)
work = Path(tempfile.mkdtemp(dir=TMP))
res = []


def ok(name, cond, info=""):
    res.append(("OK " if cond else "NG ") + name + ("" if cond else ": " + str(info)))


def note(v, name, title, fz, body):
    (v / name).write_text(f'---\ntime: 2026-01-01 00:00:00\nfolgezettel: "{fz}"\n---\n\n# {title}\n\n{body}\n', encoding="utf-8")


def cursor_line(s):
    """ノートの窓のステータス行の「行:桁」から行を読む。"""
    m = re.findall(r"vault/[a-z0-9]+\.md (\d+):(\d+)", s.text())
    return int(m[-1][0]) if m else -1


try:
    (work / "home").mkdir()
    v = work / "vault"
    v.mkdir()
    body = "\n".join(f"行{i}" for i in range(1, 80))
    note(v, "index.md", "Index", "", "[a](a.md)")
    note(v, "a.md", "A", "1", body)
    note(v, "b.md", "B", "2", body)
    env = {"TMPDIR": str(work)}
    args = ["--cmd", "let g:gnosis_open_index_on_startup=0|let g:gnosis_autosync=0|let g:gnosis_mview_restore=0|let g:gnosis_root='" + str(v) + "/'", str(v / "a.md")]
    with Session(str(REPO / "vimrc_gnosis"), str(work / "home"), str(work / "home"), args, env, rows=24, cols=110) as s:
        s.wait(1.5)
        s.send(" ", 2.0)          # 曼荼羅が開く
        s.send(" ", 1.0)          # ノートへ
        bottom = cursor_line(s)
        ok("曼荼羅 → Space: カーソルは画面の一番下の行（1 行目ではない）", bottom > 10, bottom)
        s.send(" ", 1.0)          # 曼荼羅へ戻る
        s.send("\x1b[1;5C", 2.0)  # Folgezettel ビュー
        s.send(" ", 1.0)
        ok("Folgezettel ビュー → Space: 曼荼羅ビューと同じ行（画面の一番下）", cursor_line(s) == bottom, (cursor_line(s), bottom))
        s.send(" ", 1.0)
        s.send("j", 0.8)          # 別のノートへ（右の窓も切り替わる）
        s.send(" ", 1.0)
        ok("Folgezettel ビューで別のノートを選んで Space: その画面の一番下の行", cursor_line(s) == bottom, (cursor_line(s), bottom))
        s.send("k", 0.5)          # ノートの中でカーソルを動かす
        moved = cursor_line(s)
        s.send(" ", 1.0)
        s.send("\x1b[1;5D", 1.5)  # 曼荼羅ビューへ
        s.send(" ", 1.0)
        ok("ノートの中で動かしたあとは、置き直さない", cursor_line(s) == moved, (cursor_line(s), moved))
except Exception:
    import traceback
    res.append("NG 例外: " + traceback.format_exc())
finally:
    shutil.rmtree(work, ignore_errors=True)

print("\n".join(res))
sys.exit(1 if any(r.startswith("NG") for r in res) else 0)
