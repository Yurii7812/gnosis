#!/bin/sh
# グループに新しいメンバーを足して保存すると、自動でよみ順に並び直すことの回帰網。
# 使い方: test/group_autosort_net.sh   （一時フォルダだけを使う。本物の vault には触らない）
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-$HOME/Desktop/test}/gas.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mk() { printf -- "---\ntime: 2026-01-01 00:00:00\ntitle: %s\n---\n\n# %s\n" "$2" "$2" > "$TMP/$1.md"; }
mk u ウ; mk i イ; mk a ア
cat > "$TMP/g.md" <<'EOF'
---
time: 2026-01-01 00:00:00
title: テスト
attribute: group
---

# テスト

[ウ](u.md)
[イ](i.md)
EOF
cat > "$TMP/t.vim" <<EOF
set nocp
let g:gnosis_skip_interactive_mount=1
set rtp^=$REPO
runtime plugin/gnosis.vim
edit $TMP/g.md
call append(line('\$'), '[ア](a.md)')
write
sleep 2000m
call writefile(readfile('$TMP/g.md'), '$TMP/out.txt')
qa!
EOF
timeout 60 vim -u NONE -N -es -S "$TMP/t.vim" </dev/null 2>"$TMP/err" || true
WANT="[ア](a.md)
[イ](i.md)
[ウ](u.md)"
GOT=$(tail -3 "$TMP/out.txt")
if [ "$GOT" = "$WANT" ]; then
  echo "group_autosort OK"
else
  echo "NG: グループに足して保存してもよみ順に並ばない" >&2
  cat "$TMP/out.txt" >&2
  cat "$TMP/err" >&2
  exit 1
fi
