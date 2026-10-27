#!/bin/sh
# 3ビュー・リストの探索・元の位置・Folgezettelの検索。使い捨てvaultだけで実行する。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}; mkdir -p "$TMPDIR"; export TMPDIR
. "$REPO/test/noclip.sh"
D=$(mktemp -d "$TMPDIR/listnav.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home"
LIST_WORK="$D" GNOSIS_HOME="$D/home" GNOSIS_LANG=ja timeout 90 \
  vim -u "$REPO/vimrc_gnosis" -N -n -i NONE -es -S "$REPO/test/listnav_check.vim" >"$D/log" 2>&1 || {
    cat "$D/log" >&2; [ ! -f "$D/result" ] || cat "$D/result" >&2; exit 1;
  }
[ -f "$D/result" ] || { cat "$D/log" >&2; exit 1; }
if grep -aq '^NG' "$D/result"; then cat "$D/result" >&2; exit 1; fi
printf 'listnav OK (%s 項目)\n' "$(wc -l < "$D/result")"
