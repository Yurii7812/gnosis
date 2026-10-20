#!/bin/sh
# :GnosisExportBook を実 Vim から。既存のファイルは上書きしない。vault は変えない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/bk.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh" "$D/out"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 一章\nfolgezettel: "1"\n---\n\n# 一章\n\n本文\n' > "$D/v/a.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 一章の枝\nfolgezettel: "1a"\n---\n\n# 一章の枝\n\n枝\n' > "$D/v/b.md"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 秘密\nprivate: true\n---\n\n# 秘密\n\nTOPSECRET\n' > "$D/v/s.md"
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/book_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && find . -type f ! -path './.state/*' ! -name '*.un~' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: vault が変わった" >&2; exit 1; }
unzip -p "$D/out/book.epub" mimetype | grep -q 'application/epub+zip' || { echo "NG: EPUB でない" >&2; exit 1; }
! unzip -p "$D/out/book.epub" 'OEBPS/chapters/*' | grep -q TOPSECRET || { echo "NG: 非公開が EPUB に入った" >&2; exit 1; }
[ "$(cat "$D/out/keep.epub")" = "keep" ] || { echo "NG: 既存のファイルを上書きした" >&2; exit 1; }
[ -n "$(find "$D/gnosis-books" -name "*.epub" 2>/dev/null)" ] || { echo "NG: 既定の出力先に書かれていない" >&2; exit 1; }
printf '%s\n' 'book OK'
