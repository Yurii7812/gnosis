#!/bin/sh
# :GnosisBulk を実 Vim から: 変更・追加・削除を記録 → 戻す(聞かれて「戻す」)→ 残す(!)→ :GnosisBulkUndo → 手で変えたら戻さない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/blk.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
for n in a b c; do printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: %s\n---\n\n# %s\n\n%s1\n' $n $n $n > "$D/v/$n.md"; done
REPO="$REPO" D="$D" HOME="$D/home" GNOSIS_HOME="$D/gh" timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/bulk_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
printf '%s\n' 'bulk OK'
