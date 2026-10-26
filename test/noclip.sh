# 試験は本物のクリップボードを読まない・書かない（sh から `. test/noclip.sh` で読む）。
# 2026-10-21: 試験の「クリップボードから貼る」が本物のクリップボードにあった vault の外のファイルへのリンクを拾い、
# そのファイルによみを書いてしまった。クリップボードのコマンドを「何も返さない」ものに差し替え、画面の接続も外す
# （Vim は + / * レジスタも読めず、試験が setreg した無名レジスタだけを使う）。
GNOSIS_NOCLIP_BIN="${TMPDIR:-$HOME/gnosis-work/test}/noclip-bin"
mkdir -p "$GNOSIS_NOCLIP_BIN"
for c in wl-paste wl-copy xclip xsel qdbus6 qclip pbpaste pbcopy klipper; do
  printf '#!/bin/sh\nexit 1\n' > "$GNOSIS_NOCLIP_BIN/$c"
  chmod +x "$GNOSIS_NOCLIP_BIN/$c"
done
PATH="$GNOSIS_NOCLIP_BIN:$PATH"
export PATH
unset WAYLAND_DISPLAY DISPLAY
