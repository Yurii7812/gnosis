#!/bin/sh
# :GnosisPara / Moc / MocPropose を実 Vim から。既存ノートは書き換えない。索引案は新しいノートだけ。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/pm.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 健康\nattribute: group\n---\n\n# 健康\n\n' > "$D/v/area.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 睡眠\n---\n\n# 睡眠\n\n睡眠について\n\nGroup:\n[健康](area.md)\n' > "$D/v/sleep.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 引っ越し\n---\n\n# 引っ越し\n\n- [ ] 荷造り 📅 2026-11-01\n' > "$D/v/proj.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 睡眠の質\n---\n\n# 睡眠の質\n\n睡眠の質を上げる\n' > "$D/v/t1.md"
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/para_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && find . -type f ! -path './moc/*' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 既存のノートが変わった" >&2; exit 1; }
[ "$(find "$D/v/moc" -type f | wc -l)" = 1 ] || { echo "NG: 索引案のノートが 1 つではない" >&2; exit 1; }
printf '%s\n' 'para OK'
