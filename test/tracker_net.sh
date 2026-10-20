#!/bin/sh
# 時間記録・ポモドーロ・習慣・ライフログのコマンドを実 Vim から。書くのは 記録.md への追記だけ。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/tk.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntime: 2026-10-01 09:00:00\ntitle: A\n---\n\n# A\n\n本文\n' > "$D/v/a.md"
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/tracker_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && find . -type f ! -name '記録.md' ! -path './.state/*' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 記録.md 以外が変わった" >&2; exit 1; }
grep -q '🌱 運動 ' "$D/v/記録.md" && grep -q '📋 ' "$D/v/記録.md" && grep -q '⏱ ' "$D/v/記録.md" || { echo "NG: 追記された行が足りない" >&2; exit 1; }
[ "$(grep -c '🌱 運動 ' "$D/v/記録.md")" = 1 ] || { echo "NG: 習慣が二重に書かれた" >&2; exit 1; }
printf '%s\n' 'tracker OK'
