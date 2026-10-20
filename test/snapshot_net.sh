#!/bin/sh
# :GnosisSnapshot / Verify / Restore / List を実 Vim から。vault は読むだけ・復元は空のフォルダにだけ・壊れたバックアップは復元しない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/bk.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntime: 2026-10-01 09:00:00\ntitle: A\n---\n\n# A\n\n本文\n' > "$D/v/a.md"
printf -- '---\ntime: 2026-10-01 09:00:00\ntitle: B\n---\n\n# B\n\n[A](a.md)\n' > "$D/v/b.md"
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/snapshot_check.vim" </dev/null >"$D/out" 2>"$D/err" \
  || { cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && find . -type f | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: スナップショットが vault を書き換えた" >&2; exit 1; }
# 復元先の中身は元と同じ
( cd "$D/restored" && find . -type f | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 復元の中身が元と違う" >&2; exit 1; }
# 既存の中身があるフォルダへは復元されていない
[ "$(cat "$D/occupied/keep.txt")" = keep ] && [ ! -e "$D/occupied/a.md" ] || { echo "NG: 空でないフォルダへ復元した" >&2; exit 1; }
printf '%s\n' 'snapshot OK'
