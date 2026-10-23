" 日記と Group: の回帰網（test/diary_group_net.sh から呼ぶ）。
"   日記の親（月）は本文冒頭の ParentBranch: のブロック（2026-10-20 から月はグループではない）。日記の「今日のノート」の節が、メモを足すたびに増えない。
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
call s:ok('日記: ParentBranch:（月）は H1 の直後（本文の末尾ではない）', index(s:dl, 'ParentBranch:') >= 0 && index(s:dl, 'ParentBranch:') < index(s:dl, '## 今日のノート'), string(s:dl))
call s:ok('日記: 「今日のノート」は 1 つ', s:count(s:dl, '^## 今日のノート$') == 1)

" ノートを作る → 日記の「今日のノート」に入る。節は増えない
" 日記を作ると、日記・月・日のノートが連続する秒の名前で作られるので、少し待つ
sleep 3300m
execute 'edit ' . fnameescape(s:v . '/index.md')
" 日記のバッファを閉じておく（開いたままだと日記へ入れた分が保存されず、BackLink が付かない）
execute 'silent! bwipeout ' . bufnr(s:v . '/' . s:d)
" 作ったあとの同期（日記に入れた分の BackLink）を動かす。この確認のあとは止める（あとの試験で、開いているバッファが同期で書き換わらないように）
let g:gnosis_autosync = 1
let g:gnosis_test_keys = ["\r"]
call gnosis#v2_new_plain()
stopinsert
let s:n1 = expand('%:t')
let s:cur1 = line('.')
let s:cur1_text = getline('.')
" 作ったあとの非同期の同期（日記に入れる → BackLink が付く）と読み直しを待つ
sleep 3000m
let s:l1 = readfile(s:v . '/' . s:n1)
let s:g1 = index(s:l1, 'Group:')
call s:ok('新ノート: Group: の下は 空行 / カーソル行 / 空行（3 行）で、そのあとに BackLink:（同期のあとも空行が減らない）',
      \ s:g1 >= 0 && s:l1[s:g1 + 2 : s:g1 + 4] ==# ['', '', ''] && s:l1[s:g1 + 5] ==# 'BackLink:', string(s:l1))
call s:ok('新ノート: 同期で読み直されても、カーソルは真ん中の空行のまま', line('.') == s:cur1 && s:cur1_text ==# '' && getline('.') ==# '' && line('.') == s:g1 + 4,
      \ 'line=' . line('.') . ' before=' . s:cur1 . ' group_line=' . (s:g1 + 1) . ' text=' . string(getline('.')))
silent! write
let g:gnosis_autosync = 0
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
call s:ok('日記: ParentBranch: は先頭のまま', index(s:dl, 'ParentBranch:') >= 0 && index(s:dl, 'ParentBranch:') < index(s:dl, '## 今日のノート'))

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

" ------------------------------------------------------------------ 月・日記のグループ: 子のリンクは本文（Group: の下に空行を挟む）。Context: を作らない
function! s:find_title(title) abort
  for l:f in glob(s:v . '/*.md', 1, 1)
    if index(readfile(l:f), '# ' . a:title) >= 0 | return l:f | endif
  endfor
  return ''
endfunction
let s:d_month = matchstr(get(filter(readfile(s:v . '/' . s:d), 'v:val =~# "^# "'), 0, ''), '\d\{4}-\d\d')
let s:mf = s:find_title(s:d_month)
let s:ml2 = filereadable(s:mf) ? readfile(s:mf) : []
let s:gi = index(s:ml2, 'ParentBranch:')
call s:ok('月のノート: ParentBranch: の次に親、空行を 1 つ挟んで子（今日の日記）が本文に入る',
      \ s:gi >= 0 && s:ml2[s:gi + 2] ==# '' && s:ml2[s:gi + 3] =~# '^\[\d\{4}-\d\d-\d\d-[A-Z][A-Z]\](', string(s:ml2))
call s:ok('月のノート: Context: を作らない', index(s:ml2, 'Context:') < 0, string(s:ml2))
call system('python3 ' . shellescape(g:gnosis_python) . ' update ' . shellescape(s:v))
call system('python3 ' . shellescape(g:gnosis_python) . ' update ' . shellescape(s:v))
let s:ml3 = readfile(s:mf)
" 同期は番号（folgezettel:）を振るので、それ以外が変わらないことを見る
call s:ok('同期のあとも、月のノートに Context: が出来ず、子は本文のまま', index(s:ml3, 'Context:') < 0
      \ && filter(copy(s:ml3), 'v:val !~# "^folgezettel:"') ==# filter(copy(s:ml2), 'v:val !~# "^folgezettel:"'), string(s:ml3))

" Group: ブロックだけ（本文なし）のノートに Enter でリンクを足す → Group: の下に空行を 1 つ挟む
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 本文なし', '---', '', '# 本文なし', '', 'Group:', '[Index](index.md)'], s:v . '/blk.md')
execute 'edit ' . fnameescape(s:v . '/blk.md')
let g:gnosis_test_keys = ["\r"]
call gnosis#insert_links_pick(['[相手](other.md)'], getpos('.'))
let s:bl = getline(1, '$')
call s:ok('本文なしのノート: Group: の下に空行を挟んで本文のリンク', s:bl[-3 :] ==# ['[Index](index.md)', '', '[相手](other.md)'], string(s:bl))
silent! write

" zk → n（グループを作る）: 元のノートに Group: ブロックがあっても、BranchGroup: はその上（並び: BranchGroup → Group）
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 元', '---', '', '# 元', '', 'Group:', '[Index](index.md)'], s:v . '/src.md')
execute 'edit ' . fnameescape(s:v . '/src.md')
sleep 3300m
let g:gnosis_test_keys = ['n']
call gnosis#v2_new_group()
stopinsert
silent! write
let s:sl = readfile(s:v . '/src.md')
call s:ok('zk n: BranchGroup: は Group: より上に入る', index(s:sl, 'BranchGroup:') >= 0 && index(s:sl, 'BranchGroup:') < index(s:sl, 'Group:'), string(s:sl))
call s:ok('zk n: 元のノートに Context: が出来ない', index(s:sl, 'Context:') < 0, string(s:sl))

call writefile(s:res, s:work . '/result.txt')
qa!
