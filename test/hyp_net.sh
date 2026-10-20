#!/bin/sh
# :GnosisHypotheses / Hypothesis / Debate を実 Vim から。読むだけ。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/hy.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 睡眠の研究\n---\n\n# 睡眠の研究\n\n仮説: 睡眠は記憶に効く\n状態: 検証中\n+ 証拠: 成績が上がった [論文](p.md)\n+ 証拠: 追試 [追試](p2.md)\n- 反証: 昼寝は差なし [実験](nap.md)\n\n仮説: 昼寝は逆効果\n- 反証: [論文](p.md)\n' > "$D/v/sleep.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 運動の研究\n---\n\n# 運動の研究\n\n仮説: 運動が記憶に効く\n+ 証拠: [論文](p.md)\n- 反証: [追試](p2.md)\n- 反証: 別の研究\n' > "$D/v/sport.md"
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/hyp_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && find . -type f ! -path './.state/*' ! -name '*.un~' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: ノートが変わった" >&2; exit 1; }
printf '%s\n' 'hyp OK'
