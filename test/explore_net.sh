#!/bin/sh
# :GnosisExplore を実 Vim から。読むだけ。Enter でノートへ。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/ex.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
n() { printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: %s\n---\n\n# %s\n\n%s\n' "$2" "$2" "$3" > "$D/v/$1.md"; }
n a ハーブの水やり '[b](b.md)
ハーブは乾燥した土を好み水やりは控えめにする'
n b 土の話 '[a](a.md) [c](c.md)'
n c 道具 '[b](b.md)'
n f ローズマリー 'ハーブは乾燥した土を好み水やりは控えめにする'
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/explore_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && find . -type f | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 探索がノートを書き換えた" >&2; exit 1; }
printf '%s\n' 'explore OK'
