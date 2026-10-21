" 題の同期: 本文の「# 見出し」か title: の片方だけを書き換えて保存すると、もう片方もそろい、
" ほかのノートの古い題のリンクの表示名も（保存のあとの自動同期で）直る。
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
function! s:fm(f) abort
  return filter(readfile(a:f), 'v:val =~# "^title:"')[0]
endfunction
function! s:h1(f) abort
  return filter(readfile(a:f), 'v:val =~# "^# "')[0]
endfunction
" 1. H1 を書き換えて保存 → title: もそろう
execute 'edit ' . fnameescape(s:v . '/a.md')
call setline(search('^# '), '# 新しい題')
silent write
call assert_equal('title: 新しい題', s:fm(s:v . '/a.md'))
call assert_equal('# 新しい題', s:h1(s:v . '/a.md'))
" ほかのノートのリンクの表示名も（非同期の同期を待つ）
let s:i = 0
while s:i < 100 && join(readfile(s:v . '/b.md'), "\n") !~# '\[新しい題\](a\.md)'
  sleep 100m
  let s:i += 1
endwhile
call assert_match('\[新しい題\](a\.md)', join(readfile(s:v . '/b.md'), "\n"))
" 2. title: を書き換えて保存 → H1 もそろう
sleep 1200m
edit!
call setline(search('^title:'), 'title: 三つ目の題')
silent write
call assert_equal('# 三つ目の題', s:h1(s:v . '/a.md'))
" 3. 両方を同じに変えたとき・本文のほかの見出しを変えたときは何もしない
call setline(search('^# '), '# 三つ目の題')
call append('$', ['', '## 節'])
silent write
call setline(search('^## '), '## 節2')
silent write
call assert_equal('title: 三つ目の題', s:fm(s:v . '/a.md'))
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
