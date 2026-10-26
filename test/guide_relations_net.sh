#!/bin/sh
# 操作ガイドの所属関係（### Group / Context / BackLink）を、ガイドの更新・同期・言語の切り替えで
# 失わないことの回帰網。HOME と GNOSIS_HOME は一時フォルダ（既定 ~/gnosis-work/test の下）。
set -e
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home"
GR_WORK="$WORK" HOME="$WORK/home" GNOSIS_HOME="$WORK/gnosis-home" WAYLAND_DISPLAY= DISPLAY= \
  timeout 60 vim -u "$REPO/vimrc_gnosis" -N -i NONE -n -es -S "$REPO/test/guide_relations_check.vim" </dev/null >"$WORK/out.txt" 2>&1 || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: guide_relations の結果が無い" >&2; cat "$WORK/out.txt" >&2; exit 1
fi
if grep -q '^NG' "$WORK/result.txt"; then
  cat "$WORK/result.txt" >&2; echo "NG: guide_relations" >&2; exit 1
fi
echo "guide_relations OK ($(grep -c '^OK' "$WORK/result.txt") 項目)"
