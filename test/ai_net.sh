#!/bin/sh
# :GnosisAi（ローカルの知識支援）: 実 Vim から実行し、結果の画面で Enter でノートへ。ノートを書き換えない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/ai.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
n() { printf -- '---\ntime: 2026-10-01 09:00:00\ntitle: %s\n---\n\n# %s\n\n%s\n' "$2" "$2" "$3" > "$D/v/$1.md"; }
n rose ローズマリー 'ローズマリーは地中海原産のハーブです。乾燥した土を好み、水やりは控えめにします。'
n rose2 ローズマリーの育て方 'ローズマリーは地中海原産のハーブです。乾燥した土を好み、水やりは控えめにします。挿し木で増やせます。'
n ref 参照元 '[ローズマリー](rose.md)を見る'
n bh ブラックホール 'ブラックホールとは重い星が崩壊してできる天体である。'
( cd "$D/v" && find . -name '*.md' | sort | xargs md5sum > "$D/before.md5" )
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/ai_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
( cd "$D/v" && find . -name '*.md' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 知識支援がノートを書き換えた" >&2; exit 1; }
[ -z "$(find "$D/v" -type f ! -name '*.md' ! -path '*/.gnosis/*' ! -path '*/.state/*')" ] || { echo "NG: ノート以外のファイルが増えた" >&2; exit 1; }
printf '%s\n' 'ai OK'
