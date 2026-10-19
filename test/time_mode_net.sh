#!/bin/sh
# 時刻の挿入（Ctrl-T）と時刻モード（\T）
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-$HOME/Desktop/test}/time-mode.XXXXXX")
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/v" "$W/home"
printf '%s\n' '---' 'title: t' '---' '' '# t' '' > "$W/v/t.md"
HOME="$W/home" GNOSIS_HOME="$W/home/gh" TIME_VAULT="$W/v" TIME_RESULT="$W/result.txt" \
  timeout 40 vim -u "$REPO/vimrc_gnosis" -N -n -i NONE -es --cmd "let g:gnosis_root='$W/v/'" -S "$REPO/test/time_mode_check.vim" </dev/null >/dev/null 2>&1 || true
cat "$W/result.txt" 2>/dev/null || echo "NG 結果がありません"
if [ -f "$W/result.txt" ] && ! grep -q '^NG' "$W/result.txt"; then echo "time_mode OK"; else echo "NG: time_mode"; exit 1; fi
