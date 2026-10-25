#!/usr/bin/env python3
"""起動画面（Chnoubis・ロゴ・キーの案内）を、いろいろな端末の大きさで描いて、崩れないことを確かめる。
  - どの行も窓の幅に収まる（はみ出すと折り返されて崩れる）
  - 行数が窓の高さに収まる（小さすぎる 6 行以下は除く）
  - vault の一覧の画面（v）も同じ
  - g（選んでいる vault を GUI で開く）の案内がキーの案内に出る
一時フォルダだけを使う（実 Vim を -es で動かす）。"""
import json, os, shutil, subprocess, sys, tempfile
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
    (work / "vault").mkdir()
    (work / "vault" / "a.md").write_text("# a\n", encoding="utf-8")
    (work / "home" / "vaults.json").write_text(json.dumps({"vaults": [{"path": str(work / "vault"), "name": "vault"}], "last": str(work / "vault")}), encoding="utf-8")
    script = work / "t.vim"
    out = work / "o.txt"
    script.write_text(f"""set nomore
let mode = $START_MODE
call gnosis#start#open()
if mode ==# 'vaults'
  call gnosis#start#key('v')
endif
let l = getline(1, '$')
let over = 0
for i in range(len(l))
  if strdisplaywidth(l[i]) > winwidth(0) | let over += 1 | endif
endfor
call writefile([winwidth(0) . ' ' . winheight(0) . ' ' . len(l) . ' ' . over . ' ' . (join(l, "\\n") =~# 'g ' ? 1 : 0)], '{out}')
qa!
""", encoding="utf-8")
    bad = []
    gflag = {}
    for mode in ("start", "vaults"):
        for cols in (20, 30, 40, 50, 80, 120):
            for rows in (8, 12, 20, 30, 43, 60):
                env = dict(os.environ, LINES=str(rows), COLUMNS=str(cols), GNOSIS_HOME=str(work / "home"), START_MODE=mode)
                if out.exists():
                    out.unlink()
                subprocess.run(["vim", "-u", str(REPO / "vimrc_gnosis"), "-N", "-es", "-S", str(script)], env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=60)
                try:
                    w, h, n, over, g = map(int, out.read_text().split())
                except Exception:
                    bad.append((mode, cols, rows, "結果なし"))
                    continue
                gflag[(mode, cols, rows)] = g
                if rows >= 20 and n < 5:
                    bad.append((mode, cols, rows, f"描かれていない（行数 {n}）"))
                if over:
                    bad.append((mode, cols, rows, f"幅からはみ出す行 {over}"))
                if n > h and rows >= 12:
                    bad.append((mode, cols, rows, f"行数 {n} > 窓の高さ {h}"))
    ok("どの大きさ（幅 20〜120・高さ 8〜60）でも、起動画面と vault の一覧が窓に収まる" + ("" if not bad else ": " + str(bad[:6])), not bad)
    ok("キーの案内に g（GUI で開く）が出る: " + str({k: v for k, v in gflag.items() if k[0] == "start" and k[1] >= 80}), gflag.get(("start", 120, 60)) == 1 and gflag.get(("start", 80, 30)) == 1)
    print("\n".join(res))
    sys.exit(1 if any(r.startswith("NG") for r in res) else 0)
finally:
    shutil.rmtree(work, ignore_errors=True)
