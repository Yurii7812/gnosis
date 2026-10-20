#!/bin/sh
# :GnosisGraphReport / :GnosisGraphQuery / :GnosisPaths: 実 Vim から分析を開く。ノートを書き換えない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/graph.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
n() { printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: %s\n%b---\n\n# %s\n\n%b\n' "$2" "$3" "$2" "$4" > "$D/v/$1.md"; }
n a A '' '[B](b.md) [C](c.md)'
n b B '' '[A](a.md) [C](c.md)'
n c C '' '[A](a.md) [D](d.md)'
n d D '' 'ParentBranch:\n[C](c.md)\n'
n e E '' '孤立'
( cd "$D/v" && find . -name '*.md' | sort | xargs md5sum > "$D/before.md5" )
if ! REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/graph_check.vim" </dev/null >"$D/out" 2>"$D/err"; then
  cat "$D/errors" "$D/out" "$D/err" "$D/vim.log" >&2
  exit 1
fi
( cd "$D/v" && find . -name '*.md' | sort | xargs md5sum | diff - "$D/before.md5" ) || { echo "NG: 分析がノートを書き換えた" >&2; exit 1; }
printf '%s\n' 'graph OK'
