#!/bin/sh
# :GnosisPreset を実 Vim から。秘密らしい変数は保存しない・不正な読込は無視・自動読込は次の起動で効く。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/ps.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v/.gnosis" "$D/home" "$D/gh"
printf -- '# 題\n' > "$D/v/a.md"
run() { REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/$1" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }; }
run preset_check1.vim
grep -q '"fast"' "$D/v/.gnosis/presets.json" || { echo "NG: プリセットが保存されていない" >&2; exit 1; }
! grep -qi 'hunter2\|gnosis_api_key\|gnosis_root' "$D/v/.gnosis/presets.json" || { echo "NG: 秘密らしい変数や gnosis_root が保存された" >&2; exit 1; }
run preset_check2.vim      # 2 回目の起動: auto 指定のプリセットが効く
printf '%s\n' 'preset OK'
