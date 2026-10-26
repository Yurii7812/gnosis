#!/bin/sh
# DailyNotes:（時系列記録の包含関係・同じ日付の自動リンク）・日付指定の作成（\D）・上位の設定（\E）・継承
# 一時フォルダだけを使う。本物の vault・Gnosis ホームには触らない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-$HOME/gnosis-work/test}/dailynotes.XXXXXX")
trap 'rm -rf "$W"' EXIT
V="$W/v"
mkdir -p "$V" "$W/home"
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n' > "$V/index.md"
HOME="$W/home" GNOSIS_HOME="$W/home/gh" DN_VAULT="$V" DN_RESULT="$W/result.txt" \
  timeout 100 vim -u "$REPO/vimrc_gnosis" -N -n -i NONE -es --cmd "let g:gnosis_root='$V/'" -S "$REPO/test/daily_notes_check.vim" </dev/null >/dev/null 2>&1 || true
cat "$W/result.txt" 2>/dev/null || echo "NG 結果がありません"
if [ -f "$W/result.txt" ] && ! grep -q "^NG" "$W/result.txt"; then echo "daily_notes OK"; else echo "NG: daily_notes"; [ -n "${KEEP:-}" ] && cp -r "$W" "$KEEP"; exit 1; fi
