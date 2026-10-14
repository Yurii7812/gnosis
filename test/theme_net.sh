#!/bin/sh
# テーマ（配色）の回帰網。HOME と GNOSIS_HOME は一時フォルダ（既定 ~/Desktop/test の下）。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home"
THEME_WORK="$WORK" HOME="$WORK/home" GNOSIS_HOME="$WORK/gnosis home" COLORTERM=truecolor WAYLAND_DISPLAY= DISPLAY= \
  timeout 90 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/theme_check.vim" </dev/null >"$WORK/out.txt" 2>&1 || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: theme の結果が無い（Vim のエラー）" >&2; cat "$WORK/out.txt" >&2; exit 1
fi
if grep -q '^NG' "$WORK/result.txt"; then
  grep -v '^OK' "$WORK/result.txt" >&2; echo "NG: theme" >&2; exit 1
fi
[ -n "$THEME_VERBOSE" ] && cat "$WORK/result.txt"
echo "theme OK ($(grep -c '^OK' "$WORK/result.txt") 項目)"
