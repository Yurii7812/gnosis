#!/bin/sh
# :GnosisRename / :GnosisRenameUndo を実 Vim から。参照を更新し、取り消しで完全に戻る。未保存なら何もしない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/rn.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v/sub" "$D/home" "$D/gh"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 旧\n---\n\n# 旧\n\n[兄弟](sub/o.md)\n' > "$D/v/old.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: A\n---\n\n# A\n\n[旧](old.md)と[節](old.md#x)\n' > "$D/v/a.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: O\n---\n\n# O\n\n[旧](../old.md)\n' > "$D/v/sub/o.md"
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/rename_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && find . -type f ! -path './.state/*' ! -name '*.un~' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 取り消し後に元へ戻っていない" >&2; exit 1; }
printf '%s\n' 'rename OK'
