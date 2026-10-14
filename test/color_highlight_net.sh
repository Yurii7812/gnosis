#!/bin/sh
# 起動直後のVim検索/matchハイライトと配色の回帰検査。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
cat > "$WORK/vault/index.md" <<'EOF'
---
time: 2026-10-14 09:00:00
title: Index
attribute: group
---

# Index

[解剖学サイト集](page.md)
EOF
printf '%s\n' '---' 'title: 解剖学サイト集' '---' '' '# 解剖学サイト集' '全ての筋肉ではないがストレッチ' > "$WORK/vault/page.md"
HOME="$WORK/home" GNOSIS_HOME="$WORK/home/.local/share/gnosis" \
COLOR_TEST_VAULT="$WORK/vault" COLOR_TEST_RESULTS="$WORK/results.txt" \
timeout 40 vim -u "$REPO/vimrc_gnosis" -N -n -i NONE -es -S "$REPO/test/color_highlight_check.vim" \
 </dev/null > "$WORK/err.log" 2>&1 || true
if [ ! -s "$WORK/results.txt" ]; then
  cat "$WORK/err.log" >&2
  echo 'NG highlight results missing' >&2
  exit 1
fi
cat "$WORK/results.txt"
if grep -q '^NG' "$WORK/results.txt"; then
  cat "$WORK/err.log" >&2
  exit 1
fi
echo 'color highlight OK'
