#!/bin/sh
# Gnosis one-command installer for Linux / macOS（git すら入っていない新しい環境でも、1 行で入る）
#
#   curl -fsSL https://raw.githubusercontent.com/Yurii7812/gnosis/main/install/bootstrap.sh | sh
#   （curl が無ければ: wget -qO- https://raw.githubusercontent.com/Yurii7812/gnosis/main/install/bootstrap.sh | sh）
#
# 行うこと: git が無ければ OS のパッケージ管理（apt / dnf / pacman / zypper / Homebrew）で入れる（確認してから）→
#   ~/gnosis に GitHub から取得（既にあれば最新へ ff 更新。未コミットの変更があれば止まる）→ install/install.sh を実行。
#   install.sh への引数は、そのまま渡せる（例: ... | sh -s -- --yes --no-system）。
# 環境変数: GNOSIS_DIR（置き場所。既定 ~/gnosis）、GNOSIS_REPO_URL（取得元。試験用）。
# ふだんの Vim の設定・ノートには触れない。
set -eu
URL=${GNOSIS_REPO_URL:-https://github.com/Yurii7812/gnosis.git}
DIR=${GNOSIS_DIR:-$HOME/gnosis}
JA=0; case "${LC_ALL:-${LANG:-}}" in ja*) JA=1 ;; esac
say() { if [ "$JA" = 1 ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

YES=0
for a in "$@"; do [ "$a" = "--yes" ] || [ "$a" = "-y" ] && YES=1; done
# パイプ（curl ... | sh）で実行されても、確認の入力は端末から受ける
TTY_IN=""
if [ ! -t 0 ] && [ -r /dev/tty ] && (: </dev/tty) 2>/dev/null; then TTY_IN=/dev/tty; fi
ask() {
  [ "$YES" = 1 ] && return 0
  printf '%s [Y/n] ' "$1"
  if [ -n "$TTY_IN" ]; then read -r ans <"$TTY_IN" || ans=n; else read -r ans || ans=n; fi
  case "$ans" in n|N|no|NO) return 1 ;; *) return 0 ;; esac
}

if ! have git; then
  say "git が見つかりません。入れます。" "git was not found. Installing it."
  SUDO=""; [ "$(id -u)" = 0 ] || SUDO=sudo
  if have apt-get; then cmd="$SUDO apt-get update && $SUDO apt-get install -y git ca-certificates"
  elif have dnf; then cmd="$SUDO dnf install -y git"
  elif have pacman; then cmd="$SUDO pacman -S --needed --noconfirm git"
  elif have zypper; then cmd="$SUDO zypper install -y git"
  elif have brew; then cmd="brew install git"
  else
    say "パッケージ管理（apt / dnf / pacman / zypper / brew）が見つかりません。git を自分で入れてから、もう一度実行してください。" "No package manager found. Install git yourself and run this again."
    exit 1
  fi
  if [ -n "$SUDO" ] && ! have sudo; then
    say "sudo がありません。root で実行するか、git を自分で入れてください: $cmd" "sudo is missing. Run as root or install git yourself: $cmd"
    exit 1
  fi
  ask "$(say "実行しますか？  $cmd" "Run this?  $cmd")" || { say "中止しました。" "Cancelled."; exit 1; }
  sh -c "$cmd" || { say "git を入れられませんでした。" "Could not install git."; exit 1; }
  have git || { say "git がまだ見つかりません。" "git is still missing."; exit 1; }
fi

if [ -d "$DIR/.git" ]; then
  say "$DIR は取得済みです。最新へ更新します。" "$DIR already exists. Updating it."
  if [ -n "$(git -C "$DIR" status --porcelain 2>/dev/null)" ]; then
    say "未コミットの変更があるため、更新せずに止まります（変更は消しません）: $DIR" "Uncommitted changes in $DIR; stopping without touching them."
    exit 1
  fi
  git -C "$DIR" pull --ff-only || { say "更新できませんでした。" "Could not update."; exit 1; }
elif [ -e "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
  say "$DIR は空ではなく、Gnosis でもありません。GNOSIS_DIR で別の場所を指定してください。" "$DIR exists and is not Gnosis. Set GNOSIS_DIR to another place."
  exit 1
else
  say "Gnosis を取得します: $URL → $DIR" "Cloning Gnosis: $URL -> $DIR"
  git clone "$URL" "$DIR" || { say "取得できませんでした（ネットワークを確認してください）。" "Clone failed (check the network)."; exit 1; }
fi

if [ -n "$TTY_IN" ]; then exec sh "$DIR/install/install.sh" "$@" <"$TTY_IN"; fi
exec sh "$DIR/install/install.sh" "$@"
