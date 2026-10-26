# 試験は本物のクリップボード・日本語入力・デスクトップを操作しない（sh から `. test/noclip.sh` で読む）。
# 2026-10-21: 試験の「クリップボードから貼る」が本物のクリップボードにあった vault の外のファイルへのリンクを拾い、
# そのファイルによみを書いてしまった。クリップボードのコマンドを「何も返さない」ものに差し替え、画面の接続も外す
# （Vim は + / * レジスタも読めず、試験が setreg した無名レジスタだけを使う）。
GNOSIS_NOCLIP_BIN="${TMPDIR:-$HOME/gnosis-work/test}/noclip-bin"
mkdir -p "$GNOSIS_NOCLIP_BIN"
for c in wl-paste wl-copy xclip xsel qdbus6 qdbus qclip pbpaste pbcopy klipper fcitx5-remote fcitx-remote ibus wmctrl xdotool; do
  printf '#!/bin/sh\nexit 1\n' > "$GNOSIS_NOCLIP_BIN/$c"
  chmod +x "$GNOSIS_NOCLIP_BIN/$c"
done
PATH="$GNOSIS_NOCLIP_BIN:$PATH"
export PATH
GNOSIS_TEST_NO_DESKTOP=1
export GNOSIS_TEST_NO_DESKTOP
unset WAYLAND_DISPLAY DISPLAY
