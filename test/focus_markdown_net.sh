#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
cat > "$WORK/vault/plain.md" <<'EOF'
---
title: Colors
---

# Heading
あらゆるbash^[[O `
Ordinary prose must remain the normal text color
スクリーンショット_20261014_101732.png
*italic*
`code`
[LinkName](other.md)
EOF
HOME="$WORK/home" GNOSIS_HOME="$WORK/home/.local/share/gnosis" \
 FOCUS_MARKDOWN_VAULT="$WORK/vault" FOCUS_MARKDOWN_RESULT="$WORK/results.txt" \
 timeout 35 vim -u "$REPO/vimrc_gnosis" -N -n -i NONE -es -S "$REPO/test/focus_markdown_check.vim" \
 </dev/null > "$WORK/vim.log" 2>&1 || true
if [ ! -s "$WORK/results.txt" ]; then
 cat "$WORK/vim.log" >&2
 echo "NG: no markdown/focus result" >&2
 exit 1
fi
cat "$WORK/results.txt"
if grep -q '^NG' "$WORK/results.txt"; then
 cat "$WORK/vim.log" >&2
 exit 1
fi
echo "focus markdown OK"
