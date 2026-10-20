#!/bin/sh
# :GnosisSplit / SplitUndo / Stats / Diff を実 Vim から。未保存の編集があれば何もしない。取り消しで完全に元に戻る。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/sp.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 大\n---\n\n# 大\n\n導入\n\n## 栽培\n\n水やりは控えめに。\n\n## 料理\n\n焼く。\n' > "$D/v/big.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 小\n---\n\n# 小\n\n導入\n追加\n' > "$D/v/small.md"
printf -- '# 参照\n\n[栽培](big.md#栽培)\n' > "$D/v/ref.md"
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/split_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && find . -type f ! -path './.state/*' ! -name '*.un~' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 取り消し後に元へ戻っていない" >&2; exit 1; }
printf '%s\n' 'split OK'
