#!/bin/sh
# 曼荼羅ビュー（<Space>）の回帰網。一時フォルダ（既定 ~/Desktop/test）だけを使う。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO/test/noclip.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
LINES=60 COLUMNS=160 IMGH_WORK="$WORK" GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= \
  timeout 150 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/imgview_hide_check.vim" </dev/null >"$WORK/out.txt" 2>"$WORK/err.txt" || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: imgview_hide の結果が無い（Vim のエラー）" >&2; cat "$WORK/out.txt" "$WORK/err.txt" >&2; exit 1
fi
if grep -aq '^NG' "$WORK/result.txt"; then
  grep -av '^OK' "$WORK/result.txt" >&2
  echo "NG: imgview_hide" >&2; exit 1
fi
echo "imgview_hide OK ($(grep -ac '^OK' "$WORK/result.txt") 項目)"
