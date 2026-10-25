#!/bin/sh
# ライト・ダークの色（曼荼羅など）のコントラストの回帰網。一時フォルダだけを使う。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
printf -- '---\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[a](a.md)\n' > "$WORK/vault/index.md"
printf -- '# a\n' > "$WORK/vault/a.md"
LINES=50 COLUMNS=140 LC_VAULT="$WORK/vault" LC_OUT="$WORK/out.txt" GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= \
  timeout 90 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/light_contrast_check.vim" </dev/null >/dev/null 2>&1 || true
if [ ! -s "$WORK/out.txt" ]; then echo "NG: コントラストの結果が無い" >&2; exit 1; fi
if grep -aq '^NG' "$WORK/out.txt"; then grep -a '^NG' "$WORK/out.txt" >&2; echo "NG: light_contrast" >&2; exit 1; fi
echo "light_contrast OK (ライト・ダーク)"
