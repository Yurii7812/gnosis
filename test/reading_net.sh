#!/bin/sh
# 読書・学習コマンドを実 Vim から。書くのは 明示したとき(記録.md への追記・maturity の 1 行・新規ノート)だけ。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/rd.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 知識の本\nsource: book\nauthor: 山田\n---\n\n# 知識の本\n\n==知識は力である== (p.12)\n==二つ目==\n' > "$D/v/book.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: メモ\n---\n\n# メモ\n\n[本](book.md#p12)に書いてあった\n' > "$D/v/memo.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 代数\nrequires: basic.md\n---\n\n# 代数\n' > "$D/v/alg.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 基礎\n---\n\n# 基礎\n' > "$D/v/basic.md"
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/reading_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
# 変わってよいのは memo.md(成熟度を書いた)だけ。他のノートは完全に同じ
grep -v 'memo.md' "$D/before.md5" > "$D/before_other.md5"
( cd "$D/v" && find . -type f ! -path './.state/*' ! -name '*.un~' ! -name '記録.md' ! -path './notes/*' ! -name memo.md | sort | xargs md5sum | diff - "$D/before_other.md5" ) || { echo "NG: 想定外のノートが変わった" >&2; exit 1; }
grep -q '📖 吾輩は猫である 50/300' "$D/v/記録.md" || { echo "NG: 進捗が追記されていない" >&2; exit 1; }
grep -q '^maturity: growing$' "$D/v/memo.md" || { echo "NG: maturity が書かれていない" >&2; exit 1; }
[ -f "$D/v/notes/digest.md" ] || { echo "NG: 読書メモが無い" >&2; exit 1; }
printf '%s\n' 'reading OK'
