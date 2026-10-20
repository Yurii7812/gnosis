#!/bin/sh
# :GnosisDedupe を実 Vim から: 見せるだけ → ! で除く(版に残る)→ 戻せる / scan は報告だけ。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/dd.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
P='水やりは朝に行うのがよい。夕方に行うと葉が濡れたまま夜を迎えて病気の原因になる。'
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 甲\n---\n\n# 甲\n\n%s\n\n別の段落もそれなりの長さにして置いておくことにします。\n\n%s\n' "$P" "$P" > "$D/v/a.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 乙\n---\n\n# 乙\n\n%s\n\n乙にしかない、三十文字を超える長さの段落をここに置きます。\n' "$P" > "$D/v/b.md"
REPO="$REPO" D="$D" HOME="$D/home" GNOSIS_HOME="$D/gh" timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/dedupe_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
printf '%s\n' 'dedupe OK'
