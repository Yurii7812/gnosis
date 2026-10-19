#!/bin/sh
# グループで複数のリンクを za すると追加待ち画面が開き、q で足して並べ、Q で取り消せることの回帰網。
# 使い方: test/stage_net.sh   （一時フォルダだけを使う。本物の vault には触らない）
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-$HOME/Desktop/test}/stg.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/v" "$TMP/home" "$TMP/gh"
mk() { printf -- "---\ntime: 2026-01-01 00:00:00\ntitle: %s\n---\n\n# %s\n" "$2" "$2" > "$TMP/v/$1.md"; }
mk u ウ; mk i イ; mk a ア; mk e エ
mkg() { printf -- "---\ntime: 2026-01-01 00:00:00\ntitle: テスト\nattribute: group\n---\n\n# テスト\n\n[イ](i.md)\n" > "$TMP/v/g.md"; }
mkg
cat > "$TMP/t.vim" <<EOF
set nocp
let g:gnosis_skip_interactive_mount=1
let g:gnosis_open_index_on_startup = 0
set rtp^=$REPO
runtime plugin/gnosis.vim
let g:gnosis_root = '$TMP/v/'
edit $TMP/v/g.md
call setreg('"', "[ウ](u.md)\n[エ](e.md)\n[ア](a.md)\n")
call gnosis#add_clipboard_before_up_note()
sleep 400m
let s:opened = fnamemodify(bufname('%'), ':t') =~# '^stage-'
let n = search('(.*u.md)')
call setline(n, substitute(getline(n), '\[ウ\]', '[ウサギ]', ''))
let s:before = join(readfile('$TMP/v/g.md'), "\n")
call gnosis#stage_commit()
sleep 300m
call writefile([string(s:opened), s:before], '$TMP/pre.txt')
call writefile(readfile('$TMP/v/g.md'), '$TMP/out.txt')
" 取り消し: 何も足されない
call setreg('"', "[ウ](u.md)\n[エ](e.md)\n")
call gnosis#add_clipboard_before_up_note()
sleep 400m
call gnosis#stage_cancel()
sleep 100m
call writefile(readfile('$TMP/v/g.md'), '$TMP/out2.txt')
qa!
EOF
PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$TMP/home" GNOSIS_HOME="$TMP/gh" timeout 90 vim -u NONE -N -es -S "$TMP/t.vim" </dev/null 2>"$TMP/err" || true
WANT="[ア](a.md)
[イ](i.md)
[ウサギ](u.md)
[エ](e.md)"
GOT=$(tail -4 "$TMP/out.txt")
if [ "$(head -1 "$TMP/pre.txt")" = "1" ] && [ "$GOT" = "$WANT" ] && [ "$(tail -4 "$TMP/out2.txt")" = "$WANT" ]; then
  echo "stage OK"
else
  echo "NG: 追加待ち画面の流れが期待どおりでない" >&2
  cat "$TMP/out.txt" "$TMP/err" >&2
  exit 1
fi
