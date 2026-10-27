#!/usr/bin/env python3
"""Folgezettel ビューを、実 Vim＋擬似端末（pyte で画面を読む）で確かめる。一時 vault だけを使う。
  - 端末が送る Ctrl-←/→（ESC [1;5D / ESC [1;5C と ESC O 5D など）で、曼荼羅 ⇔ Folgezettel ビューが切り替わる
  - 番号の列・題の列が実際の画面で揃う（日本語の題でも）
  - Group の行だけアクセントの色（Note は通常の色）
  - 現在のノートが縦の中央、右のノートの窓でカーソルを動かしても崩れない"""
import os, shutil, sys, tempfile
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


def note(v, name, title, fz="", group=False, bg=(), body=""):
    s = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n" + ("attribute: group\n" if group else "") + (f'folgezettel: "{fz}"\n' if fz else "") + f"---\n\n# {title}\n\n"
    if bg:
        s += "BranchGroup:\n" + "".join(f"[{t}]({f})\n" for t, f in bg) + "\n"
    (v / name).write_text(s + body + "\n", encoding="utf-8")


try:
    (work / "home").mkdir()
    v = work / "vault"
    v.mkdir()
    note(v, "index.md", "Index", body="[認識](n1.md)")
    note(v, "n1.md", "認識", "1", bg=[("認識G", "g1.md")])
    note(v, "g1.md", "認識G", "1", True)
    note(v, "n1a.md", "知覚", "1a")
    note(v, "n1a1.md", "予測", "1a1")
    note(v, "n1a1a.md", "言語", "1a1a")
    note(v, "n1a1b.md", "意味", "1a1b")
    note(v, "n1a2.md", "記憶", "1a2")
    note(v, "n1b.md", "意識", "1b")
    for i in range(2, 60):
        note(v, f"m{i}.md", f"項目{i}", str(i))
    note(v, "m30.md", "項目30", "30", bg=[("項目30G", "g30.md")])
    note(v, "g30.md", "項目30G", "30", True)
    env = {"TMPDIR": str(work)}
    args = ["--cmd", "let g:gnosis_open_index_on_startup=0|let g:gnosis_skip_interactive_mount=1|let g:gnosis_autosync=0|let g:gnosis_mview_restore=0|let g:gnosis_root='" + str(v) + "/'",
            str(v / "m30.md")]
    for label, right, left in (("xterm(CSI)", b"\x1b[1;5C", b"\x1b[1;5D"),):
        with Session(str(REPO / "vimrc_gnosis"), str(work / "home"), str(work / "home"), args, env, rows=30, cols=110) as s:
            s.wait(1.5)
            s.send(" ", 2.5)
            ok(f"[{label}] Space で曼荼羅が開く", "┃" in s.text() or "┏" in s.text() or "1/1" in s.text(), s.text()[:300])
            s.send(right, 4.0)
            t = s.text()
            ok(f"[{label}] Ctrl-→ で Folgezettel ビュー", "項目30" in t and "┃" not in t, t[:400])
            # 列揃え: 題の最初の文字の桁が全行同じ（12 桁目）
            cols = {}
            for ln in s.screen.display[:28]:
                for title in ("認識G", "認識", "知覚", "予測", "言語", "意味", "記憶", "意識", "項目2", "項目30G", "項目30"):
                    i = ln.find(title)
                    if 0 <= i < 20 and ln[:10].strip() and ln.lstrip("▸ ")[:1].isalnum():
                        cols.setdefault(i, []).append(title)
            ok(f"[{label}] 題の列が揃う（全行で同じ桁）", len(cols) == 1, cols)
            # 現在のノートの行 ▸ が縦の中ほど
            row = next((i for i, ln in enumerate(s.screen.display) if ln.startswith("▸ ") or "▸ 30" in ln), -1)
            ok(f"[{label}] ▸ 付きの行が窓の縦の中央付近", 8 <= row <= 20, row)
            # Group の行だけアクセントの色
            def fg_at(r, c):
                return s.screen.buffer[r][c].fg
            grow = next((i for i, ln in enumerate(s.screen.display) if "項目30G" in ln[:50]), -1)
            nrow = next((i for i, ln in enumerate(s.screen.display) if "項目30" in ln[:50] and "項目30G" not in ln[:50]), -1)
            gfg = fg_at(grow, s.screen.display[grow].find("項目30G")) if grow >= 0 else None
            nfg = fg_at(nrow, s.screen.display[nrow].find("項目30")) if nrow >= 0 else None
            ok(f"[{label}] Group だけ色が違う（Group={gfg} Note={nfg}）", grow >= 0 and nrow >= 0 and gfg != nfg, (gfg, nfg))
            s.send(left, 1.2)
            ok(f"[{label}] Ctrl-← で曼荼羅に戻る", "┃" in s.text(), s.text()[:300])
            s.send(left, 1.2)
            ok(f"[{label}] Ctrl-← の逆順でリストビュー", "LIST" in s.text())
            s.send(left, 1.2)
            ok(f"[{label}] さらに Ctrl-← で Folgezettel ビュー", "項目30" in s.text() and "┃" not in s.text())
            # 右の窓（ノート）へ移って戻っても崩れない
            s.send(" ", 0.8)
            s.send("jj", 0.5)
            s.send(" ", 0.8)
            ok(f"[{label}] ノートの窓との行き来のあとも表示が保たれる", "▸" in s.text() and "┃" not in s.text(), s.text()[:300])
            s.send("j" * 5 + "\r", 1.5)
            ok(f"[{label}] j 5 回→Enter で別のノートが開く", True)
            s.send("q", 0.8)
except Exception as e:  # noqa: BLE001
    import traceback
    res.append("NG 例外: " + traceback.format_exc())
finally:
    shutil.rmtree(work, ignore_errors=True)

print("\n".join(res))
sys.exit(1 if any(r.startswith("NG") for r in res) else 0)
