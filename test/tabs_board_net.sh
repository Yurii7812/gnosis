#!/bin/sh
# タブのボード（\q / \Q。\h / \H と同じ仕組みで別のファイル）の回帰網。一時フォルダ（既定 ~/Desktop/test）だけを使う。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO/test/noclip.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
TABS_WORK="$WORK" GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= \
  timeout 60 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/tabs_board_check.vim" </dev/null >"$WORK/out.txt" 2>"$WORK/err.txt" || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: tabs_board の結果が無い（Vim のエラー）" >&2; cat "$WORK/out.txt" "$WORK/err.txt" >&2; exit 1
fi
if grep -q '^NG' "$WORK/result.txt"; then
  grep -v '^OK' "$WORK/result.txt" >&2
  echo "NG: tabs_board" >&2; exit 1
fi
echo "tabs_board OK ($(grep -c '^OK' "$WORK/result.txt") 項目)"
