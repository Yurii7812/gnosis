#!/bin/sh
# \\d のグループ階層を一時 vault で検証。実際のノートには触らない。
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

EOF
DIARY_TREE_VAULT="$WORK/vault" DIARY_TREE_RESULT="$WORK/results.txt" \
  HOME="$WORK/home" GNOSIS_HOME="$WORK/home/.local/share/gnosis" \
  timeout 45 vim -u "$REPO/vimrc_gnosis" -N -n -i NONE -es \
    -S "$REPO/test/diary_hierarchy_check.vim" </dev/null >"$WORK/vim.log" 2>&1 || true
if [ ! -s "$WORK/results.txt" ]; then
  echo "NG diary hierarchy: no test result" >&2
  cat "$WORK/vim.log" >&2
  exit 1
fi
cat "$WORK/results.txt"
if grep -q '^NG' "$WORK/results.txt"; then
  cat "$WORK/vim.log" >&2
  exit 1
fi
echo 'diary hierarchy OK'
