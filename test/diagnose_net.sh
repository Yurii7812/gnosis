#!/bin/sh
# :GnosisCompat / :GnosisProfile を実 Vim から。読むだけ。vault に何も作らない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/dg.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '# 題\n\n```\n閉じない\n' > "$D/v/bad.md"
printf -- '# 良\n\n==強調==\n' > "$D/v/ok.md"
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/diagnose_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && find . -type f ! -path './.state/*' ! -name '*.un~' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: vault が変わった" >&2; exit 1; }
[ ! -d "$D/v/.gnosis" ] || { echo "NG: 診断が .gnosis を作った" >&2; exit 1; }
printf '%s\n' 'diagnose OK'
