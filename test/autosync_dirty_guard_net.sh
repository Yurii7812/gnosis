#!/bin/sh
# 未保存編集中にバックグラウンド同期が同一ノートを書き換えないことを確認。
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

[Child](child.md)
EOF
cat > "$WORK/vault/child.md" <<'EOF'
---
time: 2026-10-14 09:01:00
title: Child
---

# Child

Original
EOF
SYNC_GUARD_VAULT="$WORK/vault" SYNC_GUARD_WORK="$WORK" SYNC_GUARD_PY="$REPO/python/note_format_v2.py" \
 GNOSIS_HOME="$WORK/home/.local/share/gnosis" HOME="$WORK/home" \
 timeout 35 vim -u "$REPO/vimrc_gnosis" -N -i NONE -n -es -S "$REPO/test/autosync_dirty_guard_check.vim" \
 </dev/null >"$WORK/vim.log" 2>&1 || true
if [ ! -s "$WORK/guard-result.txt" ]; then
  echo "NG: dirty guard test result missing" >&2
  cat "$WORK/vim.log" >&2
  exit 1
fi
cat "$WORK/guard-result.txt"
if grep -q '^NG' "$WORK/guard-result.txt"; then exit 1; fi
echo "autosync_dirty_guard OK"
