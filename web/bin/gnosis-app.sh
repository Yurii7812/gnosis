#!/bin/sh
# 旧名（互換）: Gnosis のランチャー bin/gnosis --app を呼ぶ。新しい起動は bin/gnosis。
WEB=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ $# -ge 1 ]; then GNOSIS_ROOT=$(CDPATH= cd -- "$1" && pwd); export GNOSIS_ROOT; shift; fi
exec "$WEB/../bin/gnosis" --app "$@"
