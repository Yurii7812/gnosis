#!/bin/sh
# c（i / o）・a（今のノートの Context: に選んだノート）・\y（題と本文だけをコピー）・リンクで戻ったときのカーソルの回帰網。
# 使い方: test/requests_1020b_net.sh   （一時フォルダだけを使う。本物の vault には触らない）
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-$HOME/gnosis-work/test}/r1020b.XXXXXX")
[ -n "$KEEP" ] || trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
note() { printf -- "---\ntime: 2026-01-01 00:00:00\ntitle: %s\n%b---\n\n# %s\n\n%b\n" "$2" "$3" "$2" "$4" > "$D/v/$1.md"; }
note index Index "attribute: group\n" "[A](a.md)"
note a A "" "本文A。\n\nあいう"
note b B "" "本文B。\n\n## 節\n\n節の本文。"
note c C "" "本文C。"
note d D "" "本文D。"
note e E "" "本文E。"
note p P "" "ParentBranch:\n[A](a.md)\n\n- [x] [キュー](q.md)\n- [ ] [アール](r.md)"
note q キュー "" "ParentBranch:\n[P](p.md)\n\n本文Q。[外](https://example.com) と [C](c.md)。\n\nChildBranch:\n[E](e.md)\nBackLink:\n[A](a.md)"
note r アール "" "ParentBranch:\n[P](p.md)\n\n本文R。"
python3 "$REPO/python/note_format_v2.py" update "$D/v" >/dev/null
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -S "$REPO/test/requests_1020b_check.vim" </dev/null 2>"$D/err" || true
WANT="c-i あ[シー](c.md)いう
c-i-ctx 1
c-o-body 0
c-o-ctx 1
a-end-ctx 1
a-end-back 1
a-o-ctx 1
a-o-back 0
a-w-ctx 1
a-w-open d.md [E](e.md)
nav 3 7
yank ['# キュー', '', '本文Q。[外](https://example.com) と C。']"
if [ "$(cat "$D/out.txt" 2>/dev/null)" = "$WANT" ]; then
  echo "requests_1020b OK"
else
  echo "NG: c / a / \\y / リンクで戻ったときの流れが期待どおりでない" >&2
  cat "$D/out.txt" "$D/err" >&2 2>/dev/null || true
  exit 1
fi
