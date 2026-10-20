#!/bin/sh
# :GnosisImport(plan→run→verify→undo)を実 Vim から。plan は何も書かない。元のフォルダは変えない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/im.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/src" "$D/home" "$D/gh"
printf -- '# 既存\n' > "$D/v/keep.md"
printf -- '# Home\n\n[[Herb]] と [[Nothing]]\n' > "$D/src/Home.md"
printf -- '# Herb\n\n[[Home]]\n' > "$D/src/Herb.md"
( cd "$D/src" && find . -type f | sort | xargs md5sum > "$D/src.md5" )
( cd "$D/v" && find . -type f ! -path './.state/*' ! -path './.gnosis/*' ! -name '*.un~' | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/import_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/src" && md5sum -c --quiet "$D/src.md5" ) || { echo "NG: 取り込み元が変わった" >&2; exit 1; }
( cd "$D/v" && find . -type f ! -path './.state/*' ! -path './.gnosis/*' ! -name '*.un~' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: undo 後に vault が元に戻っていない" >&2; exit 1; }
printf '%s\n' 'import OK'
