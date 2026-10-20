#!/bin/sh
# :GnosisVersions を実 Vim から: 保存・一覧・差分・復元(戻す前の内容も残る)・未保存のときは戻さない・自動保存(既定は無効)。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/ver.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 甲\n---\n\n# 甲\n\n最初\n' > "$D/v/a.md"
REPO="$REPO" D="$D" HOME="$D/home" GNOSIS_HOME="$D/gh" timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/versions_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
grep -q '^最初$' "$D/v/a.md" || { echo "NG: 最終的に最初の内容でない" >&2; exit 1; }
printf '%s\n' 'versions OK'
