#!/bin/sh
# 右のパネル（\s・Tab での切り替え・s x m n N・\l の e）の回帰網。一時フォルダ（既定 ~/gnosis-work/test）だけを使う。
set -e
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO/test/noclip.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
LINES=60 COLUMNS=160 SP_WORK="$WORK" GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= \
  timeout 90 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/side_panel_check.vim" </dev/null >"$WORK/out.txt" 2>"$WORK/err.txt" || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: side_panel の結果が無い（Vim のエラー）" >&2; cat "$WORK/out.txt" "$WORK/err.txt" >&2; exit 1
fi
if grep -q '^NG' "$WORK/result.txt"; then
  grep -v '^OK' "$WORK/result.txt" >&2
  echo "NG: side_panel" >&2; exit 1
fi
echo "side_panel OK ($(grep -c '^OK' "$WORK/result.txt") 項目)"
