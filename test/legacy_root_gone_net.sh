#!/bin/sh
# 消した vault を指す古い root.txt（~/.vim/simple_yurii_note/root.txt）が残っていても、
# 起動してもそのフォルダ（と .state / viminfo）を作り直さない（2026-10-26。Desktop/test2 が毎回できた件）。
# 一時フォルダだけを使う。本物の HOME・vault・Gnosis ホームには触らない。
set -e
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home/.vim/simple_yurii_note" "$WORK/gnosis"
printf '%s\n' "$WORK/gone/" > "$WORK/home/.vim/simple_yurii_note/root.txt"
HOME="$WORK/home" GNOSIS_HOME="$WORK/gnosis" WAYLAND_DISPLAY= DISPLAY= \
  timeout 60 vim -u "$REPO/vimrc_gnosis" -N -es -c 'call gnosis#state_dir()' -c 'call gnosis#home#setup_viminfo()' -c 'call gnosis#vault#load()' -c 'qa!' </dev/null >/dev/null 2>&1 || true
if [ -e "$WORK/gone" ]; then echo "NG: 消えた vault の場所が作り直された: $(find "$WORK/gone" | head -3)"; exit 1; fi
if grep -q "gone" "$WORK/gnosis/vaults.json" 2>/dev/null; then echo "NG: 消えた vault が登録簿に取り込まれた"; exit 1; fi
# 登録簿が無く、管理外（vimrc 無し）で起動して plugin を読み込んでも、消えた場所を作り直さない（2026-10-29。Desktop/test2 がまた出た件）
HOME="$WORK/home" GNOSIS_HOME="$WORK/gnosis" WAYLAND_DISPLAY= DISPLAY= \
  timeout 60 vim -u NONE -N -es --cmd "set rtp^=$REPO" -c 'runtime plugin/gnosis.vim' -c 'silent! call gnosis#state_dir()' -c 'silent! doautocmd VimEnter' -c 'silent! edit /tmp/gnosis_legacy_x.md' -c 'qa!' </dev/null >/dev/null 2>&1 || true
if [ -e "$WORK/gone" ]; then echo "NG: 管理外の起動で消えた vault の場所が作り直された: $(find "$WORK/gone" | head -3)"; exit 1; fi
echo "legacy_root_gone OK (消えた vault の場所を作り直さず、登録簿にも入れない)"
