#!/bin/sh
# CUI・GUI 間の曼荼羅の状態引き継ぎ。一時フォルダだけを使う。
set -e
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO/test/noclip.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
LINES=60 COLUMNS=160 MV_WORK="$WORK" GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= \
  timeout 150 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/mview_handoff_check.vim" </dev/null >"$WORK/out.txt" 2>"$WORK/err.txt" || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: mview handoff の結果が無い（Vim のエラー）" >&2; cat "$WORK/out.txt" "$WORK/err.txt" >&2; exit 1
fi
if ! grep -aq '^DONE$' "$WORK/result.txt"; then
  echo "NG: mview handoff の検証が途中で終了した" >&2
  cat "$WORK/result.txt" "$WORK/out.txt" "$WORK/err.txt" >&2
  exit 1
fi
if grep -aq '^NG' "$WORK/result.txt"; then
  grep -av '^OK' "$WORK/result.txt" >&2
  echo "NG: mview" >&2; exit 1
fi
echo "mview handoff OK ($(grep -ac '^OK' "$WORK/result.txt") 項目)"
