#!/bin/sh
# Verify Vim feature/version detection does not truncate later +job rows.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
cat > "$WORK/fake-vim" <<'EOF'
#!/bin/sh
[ "$1" = --version ] || exit 2
cat "$GNOSIS_TEST_VIM_VERSION"
EOF
chmod +x "$WORK/fake-vim"

# Test the exact function from the actual installer, not a duplicate.
{
  printf '%s\n' 'have() { command -v "$1" >/dev/null 2>&1; }'
  sed -n '/^vim_ok() {/,/^}/p' "$ROOT/install/install.sh"
} > "$WORK/functions.sh"
[ "$(grep -c '^vim_ok() {' "$WORK/functions.sh")" -eq 1 ]

cat > "$WORK/check.sh" <<'EOF'
#!/bin/sh
set -eu
. "$GNOSIS_TEST_HELPERS"
if vim_ok "$GNOSIS_TEST_VIM"; then
  [ "$1" = pass ] || { echo 'FAIL: expected Vim to be rejected'; exit 1; }
else
  [ "$1" = fail ] || { echo 'FAIL: expected Vim to be accepted'; exit 1; }
fi
EOF
chmod +x "$WORK/check.sh"

export GNOSIS_TEST_HELPERS="$WORK/functions.sh"
export GNOSIS_TEST_VIM="$WORK/fake-vim"
export GNOSIS_TEST_VIM_VERSION="$WORK/version.txt"

# Simulate a real Vim 9.1 version banner with +job located past line 40.
printf '%s\n' 'VIM - Vi IMproved 9.1 (2024 Jan 02)' > "$WORK/version.txt"
i=0
while [ "$i" -lt 50 ]; do printf 'dummy feature line %s\n' "$i" >> "$WORK/version.txt"; i=$((i + 1)); done
printf '%s\n' '+channel +timers +textprop +popupwin +job' >> "$WORK/version.txt"
sh "$WORK/check.sh" pass

# Remove +job: must reject, despite the other four required features.
sed 's/+job/-job/' "$WORK/version.txt" > "$WORK/missing.txt"
export GNOSIS_TEST_VIM_VERSION="$WORK/missing.txt"
sh "$WORK/check.sh" fail

# Old Vim is rejected even with every required feature.
sed 's/Vi IMproved 9.1/Vi IMproved 8.1/' "$WORK/version.txt" > "$WORK/old.txt"
export GNOSIS_TEST_VIM_VERSION="$WORK/old.txt"
sh "$WORK/check.sh" fail

echo 'OK: full Vim output checked; later +job accepted; missing feature and old version rejected'
