#!/bin/sh
# :GnosisExportSite: 実 Vim から書き出し、vault を変えず、非公開を除き、既存フォルダを守る。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/export-site.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh" "$D/mine"
n() { printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: %s\n%b---\n\n# %s\n\n%s\n' "$2" "$3" "$2" "$4" > "$D/v/$1.md"; }
n a A 'folgezettel: "1"\n' '[B](b.md) と [P](p.md)'
n b B 'folgezettel: "1a"\n' '本文'
n p P 'private: true\n' 'TOPSECRET'
echo 大事 > "$D/mine/keep.txt"
( cd "$D/v" && find . -name '*.md' -not -path './.site/*' | sort | xargs md5sum > "$D/before.md5" )
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/export_site_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
( cd "$D/v" && find . -name '*.md' -not -path './.site/*' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 書き出しがノートを書き換えた" >&2; exit 1; }
[ "$(cat "$D/mine/keep.txt")" = "大事" ] && [ "$(ls "$D/mine")" = "keep.txt" ] || { echo "NG: 既存フォルダを書き換えた" >&2; exit 1; }
printf '%s\n' 'export_site OK'
