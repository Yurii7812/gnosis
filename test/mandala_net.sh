#!/bin/sh
# 曼荼羅: 作る → マスから実ノート／別の曼荼羅 → sync → 静的サイトで 81 マスの格子。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/mandala.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/mandala_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
python3 "$REPO/python/export_site.py" "$D/v" "$D/site" >/dev/null
M=$(grep -l 'class="mandala"' "$D"/site/*.html | head -1)
[ -n "$M" ] || { echo "NG: 曼荼羅の HTML が無い" >&2; exit 1; }
[ "$(grep -o '<td class="m' "$M" | wc -l)" = 81 ] || { echo "NG: 81 マスでない" >&2; exit 1; }
grep -q 'href="[0-9-]*\.html"' "$M" || { echo "NG: マスのリンクが HTML に無い" >&2; exit 1; }
printf '%s\n' 'mandala OK'
