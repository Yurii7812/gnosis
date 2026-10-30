#!/bin/sh
# 見出しを書き換えたら、その見出しへのリンク（[題#見出し](ノート.md#スラッグ)）も直る
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-$HOME/gnosis-work/test}/heading-links.XXXXXX")
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/v" "$W/home"
printf '%s\n' '---' 'title: A' '---' '' '# A' '' '## 古い見出し' '' '本文' '' '## 別' '' 'その2' > "$W/v/a.md"
printf '%s\n' '---' 'title: B' '---' '' '# B' '' '[A#古い見出し](a.md#古い見出し)' '前に[見て](a.md#古い見出し)ね' '[A#別](a.md#別)' > "$W/v/b.md"
printf '%s\n' '# C' '' 'Context:' '[A](a.md)' > "$W/v/c.md"
HOME="$W/home" GNOSIS_HOME="$W/home/gh" HL_VAULT="$W/v" HL_RESULT="$W/result.txt" \
  timeout 40 vim -u "$REPO/vimrc_gnosis" -N -n -i NONE -es --cmd "let g:gnosis_root='$W/v/'" -S "$REPO/test/heading_links_check.vim" </dev/null >/dev/null 2>&1 || true
cat "$W/result.txt" 2>/dev/null || echo "NG 結果がありません"
if [ -f "$W/result.txt" ] && ! grep -q '^NG' "$W/result.txt"; then echo "heading_links OK"; else echo "NG: heading_links"; exit 1; fi
