#!/bin/sh
# 軽い封印: 日付前は本文を見せない(保存もできない)・日付後は普通に開く・開封・封印を外す・front matter が無いノートには付けない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/seal.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 未来の自分へ\n---\n\n# 未来の自分へ\n\n秘密の本文です\n' > "$D/v/a.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 過去\nsealed_until: 2020-01-01\n---\n\n# 過去\n\n開ける本文\n' > "$D/v/old.md"
printf 'front matter なし\n' > "$D/v/plain.md"
REPO="$REPO" D="$D" HOME="$D/home" GNOSIS_HOME="$D/gh" timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/seal_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
grep -q '^sealed_until: ' "$D/v/a.md" && { echo "NG: 最後は封印が外れているはず" >&2; exit 1; }
grep -q '^秘密の本文です$' "$D/v/a.md" || { echo "NG: 本文が壊れた" >&2; exit 1; }
printf '%s\n' 'seal OK'
