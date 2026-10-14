#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
cat > "$WORK/vault/a.md" <<'EOF'
---
title: A
---

# A

[B](b.md)
EOF
cat > "$WORK/vault/b.md" <<'EOF'
---
title: B
---

# B
EOF
cat > "$WORK/vault/outline.md" <<'EOF'
---
title: Outline
---

# First
## Second
### Third
EOF
HOME="$WORK/home" GNOSIS_HOME="$WORK/home/.local/share/gnosis" \
 TABS_TEST_VAULT="$WORK/vault" TABS_TEST_RESULT="$WORK/results.txt" \
 GNOSIS_HEADLESS=1 timeout 40 vim -u "$REPO/vimrc_gnosis" -N -i NONE -n -es \
  -S "$REPO/test/work_tabs_outline_check.vim" </dev/null > "$WORK/vim.log" 2>&1 || true
if [ ! -s "$WORK/results.txt" ]; then
  echo "NG: no tabs/outline result" >&2
  cat "$WORK/vim.log" >&2
  exit 1
fi
cat "$WORK/results.txt"
if grep -q '^NG' "$WORK/results.txt"; then
  cat "$WORK/vim.log" >&2
  exit 1
fi
echo 'tabs + outline OK'
