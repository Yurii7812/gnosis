#!/bin/sh
# 互換: 旧 simple-yurii-note のアプリの起動パス。Gnosis へ改名したあとも、以前に作った
# アプリメニュー（simple-yurii-note.desktop）や ~/.local/bin/simple-yurii-note-app が
# 動くように残している。中身は Gnosis のランチャー（bin/gnosis --app）。
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
if [ $# -ge 1 ]; then GNOSIS_ROOT=$(CDPATH= cd -- "$1" && pwd); export GNOSIS_ROOT; shift; fi
exec "$REPO/bin/gnosis" --app "$@"
