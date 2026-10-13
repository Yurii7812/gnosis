#!/bin/sh
# Offline, isolated terminal Gnosis visual regression check.
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home" "$WORK/gnosis-home"
GNOSIS_TEST_OUT="$WORK/result" HOME="$WORK/home" GNOSIS_HOME="$WORK/gnosis-home" GNOSIS_HEADLESS=1 \
  vim -u "$REPO/vimrc_gnosis" -N -i NONE -n -es -S "$REPO/test/terminal_visual_check.vim" >"$WORK/log" 2>&1 || {
    cat "$WORK/log" >&2
    [ ! -f "$WORK/result" ] || cat "$WORK/result" >&2
    exit 1
  }
[ -f "$WORK/result" ] || { cat "$WORK/log" >&2; exit 1; }
[ ! -s "$WORK/result" ] || { cat "$WORK/result" >&2; exit 1; }
echo "terminal_visual_check OK"
