" 保存時の同期の回数（同時 1 本・内容が同じなら起動しない）の試験。一時フォルダだけを使う。
" 結果は $AUTOSYNC_WORK/result.txt に「OK 名前」「NG 名前: 詳細」で書く。
set nomore
let s:work = $AUTOSYNC_WORK
let s:v = s:work . '/vault'
let s:res = []
function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
function! s:wait_idle(sec) abort
  let l:t = reltime()
  while !gnosis#autosync_idle() && reltimefloat(reltime(l:t)) < a:sec
    sleep 50m
  endwhile
endfunction
call mkdir(s:v, 'p')
call writefile(['---', 'title: Index', 'attribute: group', '---', '', '# Index', '', '[a](a.md)'], s:v . '/index.md')
call writefile(['---', 'title: a', '---', '', '# a', '', '本文'], s:v . '/a.md')
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 1
let g:gnosis_python = expand('<sfile>:p:h:h') . '/python/note_format_v2.py'
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_autosync_test_nolog = 1
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:start = g:gnosis_test_sync_starts
" 1) 連続して 5 回保存（内容は同じ）→ 起動は多くても 2 回（今の 1 本 + 待ちの 1 本）
for s:i in range(5)
  call gnosis#autosync_on_save()
endfor
call s:wait_idle(20)
let s:n1 = g:gnosis_test_sync_starts - s:start
call s:ok('連続 5 回の保存で同期の起動は 2 回まで（実際 ' . s:n1 . '）', s:n1 >= 1 && s:n1 <= 2, string(s:n1))
" 2) 同期済みの内容をもう一度保存 → 起動しない
" 同期の後の読み直し（本番では 120ms のタイマーが行う）を、ここで明示的に行う
silent! edit!
let s:before = g:gnosis_test_sync_starts
call gnosis#autosync_on_save()
call s:wait_idle(5)
call s:ok('内容が同期済みと同じなら、起動しない', g:gnosis_test_sync_starts == s:before)
" 3) 内容を変えて保存 → 1 回起動する
call append(line('$'), '追記')
write
let s:before = g:gnosis_test_sync_starts
call gnosis#autosync_on_save()
call s:wait_idle(20)
call s:ok('内容を変えたら 1 回起動する', g:gnosis_test_sync_starts == s:before + 1)
call writefile(s:res, s:work . '/result.txt')
if !empty(filter(copy(s:res), 'v:val =~# "^NG"')) | cquit | endif
qa!
