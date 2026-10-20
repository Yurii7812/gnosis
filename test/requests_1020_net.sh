#!/bin/sh
# i（行の中）・\L の b / c・\l → g（分岐したグループ）・\l → m（マージと取り消し）の回帰網。
# 使い方: test/requests_1020_net.sh   （一時フォルダだけを使う。本物の vault には触らない）
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-$HOME/Desktop/test}/r1020.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
note() { printf -- "---\ntime: 2026-01-01 00:00:00\ntitle: %s\n%b---\n\n# %s\n\n%b\n" "$2" "$3" "$2" "$4" > "$D/v/$1.md"; }
note index Index "attribute: group\n" "[A](a.md)"
note a A "" "BranchGroup:\n[G](g.md)\n\n本文A。\n\n- [ ] "
note g G "attribute: group\n" "ParentBranch:\n[A](a.md)\n\n[ゼブラ](z.md)\n[アヒル](h.md)"
note z ゼブラ "" "z"
note h アヒル "" "h"
note b B "" "本文B"
note m M "" "スマホのメモ"
note x X "" "[M](m.md) を見る"
note e E "attribute: group\n" "ParentBranch:\n[A](a.md)\n\n"
note e2 E2 "attribute: group\n" "ParentBranch:\n[A](a.md)\n\n"
python3 "$REPO/python/note_format_v2.py" update "$D/v" >/dev/null
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -S "$REPO/test/requests_1020_check.vim" </dev/null 2>"$D/err" || true
WANT="inline - [ ] [ビー](b.md)
inline-saved 1
L-b 1 1 1
L-c 1 1
L-esc 1 a.md
join 1 2 1
sorted ['[A](a.md)', '', '[アヒル](h.md)', '[えー](a.md)', '[ゼブラ](z.md)']
empty-za ['ParentBranch:', '[A](a.md)', '', '[ゼブラ](z.md)']
empty-g ['ParentBranch:', '[A](a.md)', '', '[E2-A](a.md)']
merge 0 1 0 1
buffer 1
undo 1 0 1
merge-s 0 m.md 1"
if [ "$(cat "$D/out.txt" 2>/dev/null)" = "$WANT" ]; then
  echo "requests_1020 OK"
else
  echo "NG: i・\\L・g・マージの流れが期待どおりでない" >&2
  cat "$D/out.txt" "$D/err" >&2 2>/dev/null || true
  exit 1
fi
