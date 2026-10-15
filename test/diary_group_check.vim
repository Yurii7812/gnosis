" 日記と Group: の回帰網（test/diary_group_net.sh から呼ぶ）。
"   Group: は本文冒頭のブロック。日記の「今日のノート」の節が、メモを足すたびに増えない。
"   Group: のあるノートで、Enter のリンクが Group: より上に入らない。すでに二重になった節は 1 つにまとまる。
set nomore
let s:work = $DIARY_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
function! s:count(lines, pat) abort
  return len(filter(copy(a:lines), 'v:val =~# a:pat'))
endfunction

call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: Index', 'attribute: group', '---', '', '# Index', ''], s:v . '/index.md')
execute 'edit ' . fnameescape(s:v . '/index.md')
sleep 1100m
call gnosis#diary_today()
stopinsert
silent! write
let s:d = expand('%:t')
let s:dl = readfile(s:v . '/' . s:d)
call s:ok('日記: Group: は H1 の直後（本文の末尾ではない）', index(s:dl, 'Group:') >= 0 && index(s:dl, 'Group:') < index(s:dl, '## 今日のノート'), string(s:dl))
call s:ok('日記: 「今日のノート」は 1 つ', s:count(s:dl, '^## 今日のノート$') == 1)

" ノートを作る → 日記の「今日のノート」に入る。節は増えない
" 日記を作ると、日記・月・日のノートが連続する秒の名前で作られるので、少し待つ
sleep 3300m
execute 'edit ' . fnameescape(s:v . '/index.md')
let g:gnosis_test_keys = ["\r"]
call gnosis#v2_new_plain()
stopinsert
silent! write
let s:n1 = expand('%:t')
sleep 1100m
execute 'edit ' . fnameescape(s:v . '/index.md')
let g:gnosis_test_keys = ["\r"]
call gnosis#v2_new_plain()
stopinsert
silent! write
let s:n2 = expand('%:t')
let s:dl = readfile(s:v . '/' . s:d)
call s:ok('日記: ノートを 2 つ作っても「今日のノート」は 1 つ', s:count(s:dl, '^## 今日のノート$') == 1, string(s:dl))
call s:ok('日記: 2 つとも 1 回ずつ入る', s:count(s:dl, '(' . s:n1 . ')') == 1 && s:count(s:dl, '(' . s:n2 . ')') == 1, string(s:dl))
call s:ok('日記: Group: は先頭のまま', index(s:dl, 'Group:') >= 0 && index(s:dl, 'Group:') < index(s:dl, '## 今日のノート'))

" Group: のあるノートで Enter（本文の最後）にリンクを置く → Group: の下の本文に入る（Group: より上には入らない）
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 仲間', '---', '', '# 仲間', '', 'Group:', '[Index](index.md)', '', '本文。'], s:v . '/mem.md')
execute 'edit ' . fnameescape(s:v . '/mem.md')
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 相手', '---', '', '# 相手', '', '相手の本文。'], s:v . '/other.md')
let g:gnosis_test_keys = ["\r"]
call gnosis#insert_links_pick(['[相手](other.md)'], getpos('.'))
let s:ml = getline(1, '$')
call s:ok('Group: のあるノート: Enter のリンクは Group: の下（本文の最後）', index(s:ml, '[相手](other.md)') > index(s:ml, '[Index](index.md)'), string(s:ml))
silent! write

" すでに二重になった「## 今日のノート」は、次にノートを足すときに 1 つにまとまる
let s:dup = ['---', 'time: 2026-10-15 11:17:36', 'title: 2026-10-15-TH', '---', '', '# 2026-10-15-TH', '', 'Group:', '[Index](index.md)', '',
      \ '## 今日のノート', '', '[A](a.md)', '[B](b.md)', '', '## 今日のノート', '', '[A](a.md)', '[B](b.md)', '[C](c.md)']
call writefile(s:dup, s:v . '/dup.md')
execute 'edit ' . fnameescape(s:v . '/dup.md')
let g:gnosis_diary_section = '今日のノート'
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: D', '---', '', '# D', ''], s:v . '/d.md')
call gnosis#diary_test_add(s:v . '/dup.md', '[D](d.md)', '今日のノート')
silent! write
let s:ul = readfile(s:v . '/dup.md')
call s:ok('二重の節: 1 つにまとまる', s:count(s:ul, '^## 今日のノート$') == 1, string(s:ul))
call s:ok('二重の節: リンクは重複なく全部残る（A B C D）', s:count(s:ul, '(a.md)') == 1 && s:count(s:ul, '(b.md)') == 1 && s:count(s:ul, '(c.md)') == 1 && s:count(s:ul, '(d.md)') == 1, string(s:ul))
call s:ok('二重の節: Group: は先頭のまま', index(s:ul, 'Group:') >= 0 && index(s:ul, '[Index](index.md)') == index(s:ul, 'Group:') + 1)

call writefile(s:res, s:work . '/result.txt')
qa!
