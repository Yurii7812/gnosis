#!/bin/sh
# ブックマーク・履歴・最近・知識リマインダー・トレイルを実 Vim から。ノートは書き換えない。履歴は終了時に保存され、次の起動で読み戻される。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/nv.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
n() { printf -- '---\ntime: %s\ntitle: %s\n---\n\n# %s\n\n%s\n' "$3" "$2" "$2" "$4" > "$D/v/$1.md"; }
n a 甲 '2026-10-01 09:00:00' '? これは本当にそうなのか調べる
❓ 2020-01-01 昔に書いた問い'
n b 乙 '2026-10-02 09:00:00' '🕰 2020-01-01'
n c 丙 '2026-10-03 09:00:00' ''
n d 丁 '2026-10-04 09:00:00' ''
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
run() { REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/$1" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }; }
run nav_check1.vim
[ -f "$D/v/.state/history.json" ] || { echo "NG: 履歴が保存されていない" >&2; exit 1; }
run nav_check2.vim        # 2 回目の起動: 前回の履歴が読み戻される
( cd "$D/v" && find . -type f ! -path './.state/*' ! -path './.gnosis/*' ! -name '*.un~' ! -path './trails/*' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: ノートが変わった" >&2; exit 1; }
[ -f "$D/v/trails/route.md" ] || { echo "NG: トレイルの書き出しが無い" >&2; exit 1; }
printf '%s\n' 'nav OK'
