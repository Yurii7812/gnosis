#!/bin/sh
# :GnosisCheck（vault の検査）: 壊れたリンク・Folgezettel の重複と抜け・孤立ノートを出し、何も書き換えない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/check-vault.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
n() { printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: %s\n%b---\n\n# %s\n\n%s\n' "$2" "$3" "$2" "$4" > "$D/v/$1.md"; }
n a A 'folgezettel: "1"\n' '[壊れた](nowhere.md) と [B](b.md)'
n b B 'folgezettel: "1a"\n' '本文'
n c C 'folgezettel: "5a1"\n' '[A](a.md)'
n d D 'folgezettel: "1a"\n' '重複'
n e E '' 'だれともつながらない'
( cd "$D/v" && find . -name '*.md' | sort | xargs md5sum > "$D/before.md5" )
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/check_vault_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
( cd "$D/v" && find . -name '*.md' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 検査がノートを書き換えた" >&2; exit 1; }
printf '%s\n' 'check_vault OK'
