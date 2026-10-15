#!/bin/sh
# 日記と Group:（日記の節が増えない・Group: は先頭・二重の節は 1 つにまとまる）の回帰網。
# 一時フォルダ（既定 ~/Desktop/test）だけを使う。本物の vault や Gnosis ホームには触らない。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
DIARY_WORK="$WORK" GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= \
  timeout 120 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/diary_group_check.vim" </dev/null >"$WORK/out.txt" 2>"$WORK/err.txt" || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: diary_group の結果が無い（Vim のエラー）" >&2; cat "$WORK/out.txt" "$WORK/err.txt" >&2; exit 1
fi
if grep -q '^NG' "$WORK/result.txt"; then
  grep -v '^OK' "$WORK/result.txt" >&2
  echo "NG: diary_group" >&2; exit 1
fi
echo "diary_group OK ($(grep -c '^OK' "$WORK/result.txt") 項目)"
