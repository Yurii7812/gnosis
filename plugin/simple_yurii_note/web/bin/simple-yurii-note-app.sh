#!/bin/sh
# simple_yurii_note デスクトップアプリ (Electron) を起動する。
# 使い方: simple-yurii-note-app.sh [VAULT_DIR]
#   VAULT_DIR 省略時は、Vim（SYN）が前回使った root。
set -eu
WEB=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ELECTRON="$WEB/node_modules/.bin/electron"
if [ ! -x "$ELECTRON" ]; then
  echo "electron が見つかりません。次を実行してください: cd \"$WEB\" && npm install" >&2
  exit 1
fi
# VAULT_DIR を渡したときだけ root を指定する。省略すると、ターミナルの yurii-note と同じく
# Vim（SYN）が前回使った root を使う。
if [ $# -ge 1 ]; then
  PKM_ROOT=$(CDPATH= cd -- "$1" && pwd)
  export PKM_ROOT
fi
# --no-sandbox: 環境によってはサンドボックスで起動できないため
# --ozone-platform=x11: KDE Wayland では Wayland+Vulkan でウィンドウが出ないことがある
#                       (XWayland 経由の x11 が確実)
# --disable-gpu: 上記 Vulkan 問題の回避
exec "$ELECTRON" "$WEB" --no-sandbox --ozone-platform=x11 --disable-gpu
