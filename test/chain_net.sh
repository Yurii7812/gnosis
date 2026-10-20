#!/bin/sh
# :GnosisChain(試走→適用→取り消し)を実 Vim から。! なしは何も書かない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/ch.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
n() { printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: %s\n---\n\n# %s\n\n%s\n' "$2" "$2" "$3" > "$D/v/$1.md"; }
n h1 ハーブ1 '水やりのコツ'
n h2 ハーブ2 '水やりと日当たり'
n other 別の話 '料理のこと'
n hub ハブ 'まとめ'
( cd "$D/v" && find . -type f ! -path './.gnosis/*' ! -path './.state/*' | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/chain_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
# 最後: related を適用して取り消し済み → hub.md は元通り。index で作った idx.md だけが増えている
grep -v 'hub.md' "$D/before.md5" > "$D/before_other.md5"
( cd "$D/v" && md5sum -c --quiet "$D/before_other.md5" ) || { echo "NG: 想定外のノートが変わった" >&2; exit 1; }
grep 'hub.md' "$D/before.md5" | ( cd "$D/v" && md5sum -c --quiet ) || { echo "NG: 取り消し後に hub.md が元に戻っていない" >&2; exit 1; }
[ -f "$D/v/idx.md" ] || { echo "NG: 索引案のノートが無い" >&2; exit 1; }
printf '%s\n' 'chain OK'
