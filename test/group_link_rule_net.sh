#!/bin/sh
# 決まり（索引はノートだけ・グループ同士は Related: のみ）の入口の試験。一時フォルダだけを使う。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO/test/noclip.sh"   # 本物のクリップボードを読まない・書かない
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
if ! RELATED_WORK="$WORK" GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= timeout 90 vim -u NONE -i NONE --cmd "set runtimepath^=$REPO" -N -es -S "$REPO/test/group_link_rule_check.vim" >"$WORK/out" 2>&1; then
  cat "$WORK/out" "$WORK/errors" 2>/dev/null
  exit 1
fi
[ -f "$WORK/errors" ] || { echo "Vim did not finish"; exit 1; }
echo "group link rule OK (Vim assertions)"
