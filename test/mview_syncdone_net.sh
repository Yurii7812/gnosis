#!/bin/sh
# 同期が開いていない別のノートに BackLink: を書いたあと、曼荼羅がそのノートを読み直す（2026-10-27。BackLink が曼荼羅に出ないことがあった）。
# 一時フォルダだけを使う。本物の vault・Gnosis ホームには触らない。
set -e
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
V="$WORK/vault"
mkdir -p "$V" "$WORK/home"
printf -- '---\ntime: 2026-01-01 00:00:00\nattribute: group\n---\n\n# Index\n\n[相手B](b.md)\n[元A](a.md)\n' > "$V/index.md"
printf -- '---\ntime: 2026-01-01 00:00:00\n---\n\n# 相手B\n\n本文\n' > "$V/b.md"
printf -- '---\ntime: 2026-01-01 00:00:00\n---\n\n# 元A\n\n本文\n' > "$V/a.md"
cat > "$WORK/t.vim" <<VIM
let g:gnosis_root = '$V/'
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_mview_restore = 0
execute 'edit $V/b.md'
call gnosis#mview#toggle()
let s:st = gnosis#mview#state()
let s:res = []
function! s:ok(name, cond) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name)
endfunction
call s:ok('最初は B に BackLink が無い', !has_key(get(get(s:st.data.nodes, 'b.md', {}), 'o', {}), 'backlink'))
" A に B へのリンクを書いて同期する（同期は B のファイルに BackLink: を書く。B のバッファは曼荼羅の右で開いたまま。保存のイベントは来ない）
call writefile(readfile('$V/a.md') + ['', '[相手B](b.md)'], '$V/a.md')
call system('python3 $REPO/python/note_format_v2.py update_one $V/a.md $V')
call s:ok('同期が B に BackLink を書いた', join(readfile('$V/b.md'), "\\n") =~# 'BackLink:')
call gnosis#mview#sync_done()
sleep 800m
call s:ok('同期が終わると、曼荼羅が B を読み直して BackLink が出る', index(get(get(get(s:st.data.nodes, 'b.md', {}), 'o', {}), 'backlink', []), 'a.md') >= 0)
call writefile(s:res + ['DONE'], '$WORK/result.txt')
qa!
VIM
GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= \
  timeout 90 vim -u "$REPO/vimrc_gnosis" -N -n -i NONE -es -S "$WORK/t.vim" </dev/null >/dev/null 2>&1 || true
if [ ! -s "$WORK/result.txt" ]; then echo "NG: mview_syncdone の結果が無い" >&2; exit 1; fi
if grep -aq '^NG' "$WORK/result.txt"; then grep -av '^OK' "$WORK/result.txt" >&2; echo "NG: mview_syncdone" >&2; exit 1; fi
echo "mview_syncdone OK ($(grep -ac '^OK' "$WORK/result.txt") 項目)"
