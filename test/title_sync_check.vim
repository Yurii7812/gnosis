" 題は先頭の「# 見出し」。書き換えて保存すると、ほかのノートの古い題のリンクの表示名が（保存のあとの自動同期で）直る。
" 古い title: は同期で消える。
set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let s:v = $D . '/v'
let g:gnosis_root = s:v . '/'
call writefile(['---', 'time: 2026-10-01 09:00:00', 'title: Index', 'attribute: group', '---', '', '# Index', '', '[古い題](a.md)'], s:v . '/index.md')
call writefile(['---', 'time: 2026-10-01 09:00:00', 'title: 古い題', '---', '', '# 古い題', '', '本文。'], s:v . '/a.md')
call writefile(['---', 'time: 2026-10-01 09:00:00', 'title: 別のノート', '---', '', '# 別のノート', '', '[古い題](a.md) を見る。'], s:v . '/b.md')
function! s:h1(f) abort
  return filter(readfile(a:f), 'v:val =~# "^# "')[0]
endfunction
" 1. 題は先頭の # 見出し。H1 を書き換えて保存 → 古い title: は同期で消え、ほかのノートのリンクの表示名が追従する
execute 'edit ' . fnameescape(s:v . '/a.md')
call setline(search('^# '), '# 新しい題')
silent write
call assert_equal('# 新しい題', s:h1(s:v . '/a.md'))
" ほかのノートのリンクの表示名も（非同期の同期を待つ）
let s:i = 0
while s:i < 100 && join(readfile(s:v . '/b.md'), "\n") !~# '\[新しい題\](a\.md)'
  sleep 100m
  let s:i += 1
endwhile
call assert_match('\[新しい題\](a\.md)', join(readfile(s:v . '/b.md'), "\n"))
" 古い title: は、同期のあとで消えている（題は H1 だけ）
let s:i = 0
while s:i < 100 && !empty(filter(readfile(s:v . '/a.md'), 'v:val =~# "^title:"'))
  sleep 100m
  let s:i += 1
endwhile
call assert_equal([], filter(readfile(s:v . '/a.md'), 'v:val =~# "^title:"'))
" 2. もう一度 H1 を変えても、同じように追従する
sleep 1200m
edit!
call setline(search('^# '), '# 三つ目の題')
silent write
call assert_equal('# 三つ目の題', s:h1(s:v . '/a.md'))
let s:i = 0
while s:i < 100 && join(readfile(s:v . '/b.md'), "\n") !~# '\[三つ目の題\](a\.md)'
  sleep 100m
  let s:i += 1
endwhile
call assert_match('\[三つ目の題\](a\.md)', join(readfile(s:v . '/b.md'), "\n"))
" 3. 本文のほかの見出しを変えても、題は変わらない
call append('$', ['', '## 節'])
silent write
call setline(search('^## '), '## 節2')
silent write
call assert_equal('# 三つ目の題', s:h1(s:v . '/a.md'))
" 4. front matter の無いノートは触らない
call writefile(['# 題だけ', '', '本文'], s:v . '/c.md')
execute 'edit ' . fnameescape(s:v . '/c.md')
call setline(1, '# 変えた')
silent write
call assert_equal(['# 変えた', '', '本文'], readfile(s:v . '/c.md'))
if !empty(v:errors)
  call writefile(v:errors, $D . '/errors')
  cquit 1
endif
qall!
