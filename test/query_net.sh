#!/bin/sh
# :GnosisQuery（構造化検索）: 実 Vim から検索・保存・再実行・昇格。ノートを書き換えない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/query.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
n() { printf -- '---\ntime: %s\ntitle: %s\n%b---\n\n# %s\n\n%s\n' "$1" "$3" "$4" "$3" "$5" > "$D/v/$2.md"; }
n '2026-10-01 09:00:00' a ハーブ 'folgezettel: "1"\n' 'ローズマリーを育てる。水は少なめ。[栽培](b.md)'
n '2026-10-02 09:00:00' b 栽培 'folgezettel: "1a"\n' '乾燥気味に。水やり控えめ。'
n '2026-09-20 09:00:00' c 'Apple Pie' '' 'english text'
( cd "$D/v" && find . -name '*.md' | sort | xargs md5sum > "$D/before.md5" )
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/query_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
( cd "$D/v" && find . -name '*.md' -not -name 'found.md' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 検索がノートを書き換えた" >&2; exit 1; }
printf '%s\n' 'query OK'
