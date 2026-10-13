#!/bin/sh
# Gnosis のランチャー・アプリメニュー・アイコンを取り除く（Linux / macOS）。
# vault（ノート）と、ふだんの Vim の設定には触らない。Gnosis ホーム（vault の一覧・テーマ・
# プラグイン）は --purge を付けたときだけ消す（vault の中身は消さない）。
set -eu
PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1
if [ -z "${GNOSIS_HOME:-}" ]; then
  if [ "$(uname -s)" = Darwin ]; then GNOSIS_HOME="$HOME/Library/Application Support/Gnosis"
  else GNOSIS_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/gnosis"; fi
fi
rm -f "$HOME/.local/bin/gnosis"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/gnosis.desktop"
for d in "${XDG_DATA_HOME:-$HOME/.local/share}"/icons/hicolor/*/apps; do rm -f "$d/gnosis.png" "$d/gnosis.svg"; done
rm -rf "$HOME/Applications/Gnosis.app"
if [ "$PURGE" = 1 ]; then rm -rf "$GNOSIS_HOME"; fi
echo "Gnosis のランチャーとアイコンを取り除きました（vault は残っています） / removed the launcher and icons (vaults are kept)"
