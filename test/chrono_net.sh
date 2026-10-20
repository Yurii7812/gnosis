#!/bin/sh
# :GnosisCalendar / Day / OnThisDay / Review / ReviewWrite を実 Vim から。読むだけ。ReviewWrite は新しいノートだけを作り上書きしない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/ch.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
n() { printf -- '---\ntime: %s\ntitle: %s\n---\n\n# %s\n\n%s\n' "$3" "$2" "$2" "$4" > "$D/v/$1.md"; }
n a 十月 '2026-10-05 09:00:00' '- [ ] 提出 📅 2026-10-25'
n b 去年 '2025-10-21 10:00:00' ''
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/chrono_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && find . -type f ! -path './reviews/*' ! -path './.state/*' ! -name '*.un~' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 既存のノートが変わった" >&2; exit 1; }
[ "$(find "$D/v/reviews" -type f | wc -l)" = 1 ] || { echo "NG: レビューのノートが 1 つではない" >&2; exit 1; }
printf '%s\n' 'chrono OK'
