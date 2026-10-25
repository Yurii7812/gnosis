#!/bin/sh
# 検索の書き方の回帰網（Python と Vim が同じ試験データで同じ答え）。一時フォルダだけを使う。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python3 "$REPO/python/test_search_query.py"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
SQ_CASES="$REPO/test/search_query_cases.json" SQ_OUT="$OUT" GNOSIS_HOME=$(mktemp -d) timeout 60 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/search_query_check.vim" </dev/null >/dev/null 2>&1 || true
if [ ! -s "$OUT" ]; then echo "NG: 検索の書き方（Vim）の結果が無い" >&2; exit 1; fi
if grep -aq '^NG' "$OUT"; then grep -a '^NG' "$OUT" >&2; echo "NG: search_query (Vim)" >&2; exit 1; fi
echo "search_query OK (Python と Vim。Vim は $(grep -ac '^OK' "$OUT") 項目)"
