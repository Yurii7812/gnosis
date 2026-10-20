#!/bin/sh
# :GnosisSrs（間隔反復の復習）: 出題・答えを見てから採点・記録・翌日・ランダムは記録しない。ノートは書き換えない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/srs.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntitle: A\n---\n\n# A\n\nQ: 首都は？\nA: 東京\n\n水は{{H2O}}です。\n' > "$D/v/a.md"
( cd "$D/v" && md5sum a.md > "$D/before.md5" )
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/srs_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
( cd "$D/v" && md5sum -c "$D/before.md5" >/dev/null ) || { echo "NG: 復習がノートを書き換えた" >&2; exit 1; }
printf '%s\n' 'srs OK'
