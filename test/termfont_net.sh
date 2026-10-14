#!/bin/sh
# 文字サイズの回帰網: Vim 側の保存・説明と、ランチャーが新しい窓に渡す引数（実際には起動しない）。
# HOME と GNOSIS_HOME は一時フォルダ（既定 ~/Desktop/test の下）。端末の環境変数は空にして動かす。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home"
H="$WORK/gnosis ホーム"
CLEAN="env -u KONSOLE_DBUS_SESSION -u KONSOLE_DBUS_SERVICE -u KONSOLE_VERSION -u KITTY_WINDOW_ID -u ALACRITTY_SOCKET -u ALACRITTY_WINDOW_ID -u ALACRITTY_LOG -u WEZTERM_PANE -u XTERM_VERSION -u VTE_VERSION -u GNOSIS_TERMINAL_KIND -u TERM_PROGRAM"
$CLEAN TF_WORK="$WORK" HOME="$WORK/home" GNOSIS_HOME="$H" WAYLAND_DISPLAY= DISPLAY= \
  timeout 60 vim -u "$REPO/vimrc_gnosis" -N -i NONE -n -es -S "$REPO/test/termfont_check.vim" </dev/null >"$WORK/out.txt" 2>&1 || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: termfont の結果が無い" >&2; cat "$WORK/out.txt" >&2; exit 1
fi
ng=0
if grep -q '^NG' "$WORK/result.txt"; then cat "$WORK/result.txt" >&2; ng=1; fi
n=$(grep -c '^OK' "$WORK/result.txt")

# ---- ランチャー（GNOSIS_DRY_RUN=1 で端末を起動せず引数を表示）。端末は偽物の実行ファイルで用意する
mkdir -p "$WORK/bin"
for t in konsole kitty alacritty wezterm xterm gnome-terminal xfce4-terminal; do
  printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/$t"; chmod +x "$WORK/bin/$t"
done
check() { # 名前 条件の grep パターン ファイル
  if grep -q -- "$2" "$3"; then n=$((n + 1)); else echo "NG launcher: $1" >&2; cat "$3" >&2; ng=1; fi
}
launch() { # 出力 端末 [デスクトップ]
  out=$1; t=$2; desk=${3:-}
  $CLEAN PATH="$WORK/bin:$PATH" HOME="$WORK/home" GNOSIS_HOME="$H" GNOSIS_DRY_RUN=1 GNOSIS_TERMINAL="$t" \
    XDG_CURRENT_DESKTOP="$desk" sh "$REPO/bin/gnosis" --new-terminal </dev/null >"$out" 2>&1 || true
}
# Vim 側の試験で最後に保存した大きさ（17）とフォント・行間を使う
launch "$WORK/konsole.txt" konsole
# デフォルトの gnosis は、既に対話端末内で実行されていても新しい専用窓を開く。
# pty を付けない試験だと従来の不具合（-t なら run_tui）が検出できない。
if python3 - "$REPO/bin/gnosis" "$WORK" "$H" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

launcher, work, home = sys.argv[1:]
env = os.environ.copy()
for key in ("KONSOLE_DBUS_SESSION", "KONSOLE_DBUS_SERVICE", "GNOSIS_TERMINAL_KIND"):
    env.pop(key, None)
env.update({
    "HOME": work + "/home",
    "GNOSIS_HOME": home,
    "GNOSIS_DRY_RUN": "1",
    "GNOSIS_TERMINAL": "konsole",
    "XDG_CURRENT_DESKTOP": "KDE",
    "PATH": work + "/bin:" + env.get("PATH", ""),
})
master, slave = pty.openpty()
process = subprocess.Popen(["sh", launcher], stdin=slave, stdout=slave, stderr=slave, env=env)
os.close(slave)
output = bytearray()
deadline = time.monotonic() + 8
try:
    while time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            output.extend(chunk)
        if process.poll() is not None and not ready:
            break
    if process.poll() is None:
        process.kill()
    process.wait(timeout=3)
finally:
    os.close(master)
text = output.decode("utf-8", errors="replace")
if process.returncode != 0 or "Gnosis-17.profile" not in text or "Font=DejaVu Sans Mono,17," not in text:
    print("NG: 対話端末からの gnosis が専用 Konsole を開きませんでした")
    print(text[:1200])
    sys.exit(1)
print("OK: 対話端末からの gnosis は専用 Konsole を開く")
PY
then
  n=$((n + 1))
else
  ng=1
fi
check "Konsole: 保存した大きさのプロファイル" 'Gnosis-17.profile' "$WORK/konsole.txt"
check "Konsole: フォントサイズを起動時に指定" '^Font=DejaVu Sans Mono,17,' "$WORK/konsole.txt"
check "Konsole: タイトルに Gnosis を指定" '^LocalTabTitleFormat=Gnosis$' "$WORK/konsole.txt"
check "Konsole: state を専用に分離" "XDG_STATE_HOME=$H/terminal/state" "$WORK/konsole.txt"
check "Konsole: Gnosis が開いた窓の印" 'GNOSIS_TERMINAL_KIND=konsole' "$WORK/konsole.txt"
check "Konsole: 専用プロファイルはこの窓にだけ見せる" "XDG_DATA_DIRS=$H/terminal/share:" "$WORK/konsole.txt"
grep -q '^Font=DejaVu Sans Mono,20,' "$H/terminal/share/konsole/Gnosis-20.profile" && n=$((n + 1)) || { echo "NG launcher: Konsole プロファイルのフォント" >&2; ng=1; }
grep -q '^LineSpacing=4$' "$H/terminal/share/konsole/Gnosis-17.profile" && n=$((n + 1)) || { echo "NG launcher: Konsole プロファイルの行間" >&2; ng=1; }
[ ! -e "$WORK/home/.local/share/konsole" ] && n=$((n + 1)) || { echo "NG launcher: ふだんの Konsole のプロファイル置き場に書いた" >&2; ng=1; }
launch "$WORK/xfce.txt" xfce4-terminal
check "XFCE: --font に名前と大きさ" '^DejaVu Sans Mono 17$' "$WORK/xfce.txt"
launch "$WORK/kitty.txt" kitty
check "kitty: font_size" '^font_size=17$' "$WORK/kitty.txt"
check "kitty: Gnosis の窓は遠隔操作を許可（その場で変える）" '^allow_remote_control=yes$' "$WORK/kitty.txt"
launch "$WORK/alacritty.txt" alacritty
check "Alacritty: font.size" '^font.size=17$' "$WORK/alacritty.txt"
launch "$WORK/xterm.txt" xterm
check "xterm: -fs" '^17$' "$WORK/xterm.txt"
check "xterm: 実際のフォント名（Monospace ではない）" '^DejaVu Sans Mono$' "$WORK/xterm.txt"
launch "$WORK/wezterm.txt" wezterm
check "WezTerm: font_size" '^font_size=17$' "$WORK/wezterm.txt"
# 端末の自動選択: デスクトップに合うもの
printf '{\n  "fontFamily": "",\n  "fontSize": 15,\n  "lineSpacing": 2,\n  "terminal": ""\n}\n' > "$H/terminal.json"
launch "$WORK/kde.txt" "" KDE
check "自動選択: KDE なら Konsole" '^konsole$' "$WORK/kde.txt"
check "自動選択: 保存した大きさ（15）" 'Gnosis-15.profile' "$WORK/kde.txt"
launch "$WORK/xfce2.txt" "" XFCE
check "自動選択: XFCE なら XFCE Terminal" '^xfce4-terminal$' "$WORK/xfce2.txt"
printf '{\n  "fontFamily": "",\n  "fontSize": 15,\n  "lineSpacing": 2,\n  "terminal": "xterm"\n}\n' > "$H/terminal.json"
launch "$WORK/pref.txt" "" KDE
check "設定で選んだ端末を優先" '^xterm$' "$WORK/pref.txt"
# ふだんの Vim の設定は作らない・変えない
[ ! -e "$WORK/home/.vimrc" ] && [ ! -e "$WORK/home/.vim" ] && n=$((n + 1)) || { echo "NG: ふだんの Vim の設定に触れた" >&2; ng=1; }
[ "$ng" = 0 ] || { echo "NG: termfont" >&2; exit 1; }
echo "termfont OK ($n 項目)"
