#!/bin/sh
# \S（選択なし）が、本文のリンク行をよみ順に並べ、### Group 以降は動かさないことの回帰網。
# 使い方: test/sort_yomi_net.sh   （一時フォルダだけを使う。本物の vault には触らない）
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mk() { printf -- "---\ntime: 2026-01-01 00:00:00\ntitle: %s\n---\n\n# %s\n" "$2" "$2" > "$TMP/$1.md"; }
mk n1 日記; mk n2 暗号化; mk n3 アプリ; mk n4 移動
cat > "$TMP/g.md" <<'EOF'
---
time: 2026-01-01 00:00:00
title: SYN
attribute: group
---

# SYN

[日記](n1.md)
[暗号化](n2.md)
[アプリ](n3.md)
[移動](n4.md)
### Group
[日記](n1.md)
EOF
cat > "$TMP/t.vim" <<EOF
set nocp
let g:simple_yurii_note_skip_interactive_mount=1
set rtp^=$REPO/plugin/simple_yurii_note
runtime plugin/simple_yurii_note.vim
edit $TMP/g.md
call simple_yurii_note#sort_yomi()
call writefile(getline(1,'\$'), '$TMP/out.txt')
qa!
EOF
timeout 60 vim -u NONE -N -es -S "$TMP/t.vim" </dev/null 2>"$TMP/err" || true
WANT="[アプリ](n3.md)
[暗号化](n2.md)
[移動](n4.md)
[日記](n1.md)
### Group
[日記](n1.md)"
GOT=$(tail -6 "$TMP/out.txt" 2>/dev/null || true)
if [ "$GOT" = "$WANT" ] && ! grep -q . "$TMP/err"; then
  echo "sort_yomi OK (選択なしの \\S は本文リンクをよみ順に並べ、Group 以降は動かさない)"
else
  echo "NG: sort_yomi" >&2; echo "$GOT" >&2; cat "$TMP/err" >&2; exit 1
fi
