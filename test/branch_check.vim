" Branch（b モード）の回帰網（test/branch_net.sh から呼ぶ）。
"   zn / zk / za / \l の位置キー b: 親の ChildBranch ＋ 子の ParentBranch を両方に書く。
"   2 つ目の親・自己参照・循環・index.md は拒否し、どのノートも（バッファも）変更しない。
" 結果は $BRANCH_WORK/result.txt に「OK 名前」「NG 名前: 詳細」で書く。
set nomore
let s:work = $BRANCH_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
function! s:mk(name, title, body, ...) abort
  let l:attr = a:0 && a:1 ? ['attribute: group'] : []
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title] + l:attr + ['---', '', '# ' . a:title, ''] + a:body, s:v . '/' . a:name)
endfunction
function! s:file(name) abort
  return readfile(s:v . '/' . a:name)
endfunction
function! s:count(name, pat) abort
  return len(filter(s:file(a:name), 'v:val =~# a:pat'))
endfunction
function! s:files() abort
  return map(glob(s:v . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")')
endfunction
function! s:newest_except(before) abort
  let l:now = filter(s:files(), 'index(a:before, v:val) < 0')
  return get(l:now, 0, '')
endfunction

call s:mk('index.md', 'Index', ['[A](a.md)'], 1)
call s:mk('a.md', 'ノートA', ['本文の文。', ''])
call s:mk('b.md', 'ノートB', ['B の本文。'])
call s:mk('c.md', 'ノートC', ['C の本文。'])
call s:mk('d.md', 'ノートD', ['D の本文。'])
call s:mk('e.md', 'ノートE', ['E の本文。'])

" ---------------------------------------------------------------- zn → b（新ノートを子として作る）
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:before = s:files()
let g:gnosis_test_keys = ['b']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:n1 = s:newest_except(s:before)
call s:ok('zn b: 新ノートができる', !empty(s:n1))
call s:ok('zn b: A に ChildBranch と新ノートへのリンク', index(s:file('a.md'), '### ChildBranch') >= 0 && s:count('a.md', '(' . s:n1 . ')') == 1)
call s:ok('zn b: 新ノートに ParentBranch と A へのリンク', index(s:file(s:n1), '### ParentBranch') >= 0 && s:count(s:n1, '^\[ノートA\](a\.md)$') == 1)
call s:ok('zn b: Context には入れない', index(s:file('a.md'), '### Context') < 0 && index(s:file(s:n1), '### Context') < 0)
call s:ok('zn b: 新ノートが開いている', expand('%:t') ==# s:n1)

" ---------------------------------------------------------------- 2 本目の子（1 つの親から複数の子）
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:before = s:files()
let g:gnosis_test_keys = ['b']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:n2 = s:newest_except(s:before)
call s:ok('zn b 2 本目: A の ChildBranch に 2 本', s:count('a.md', '^### ChildBranch$') == 1 && s:count('a.md', '(' . s:n1 . ')') == 1 && s:count('a.md', '(' . s:n2 . ')') == 1)
call s:ok('zn b 2 本目: 2 本目の子の親も A', s:count(s:n2, '^\[ノートA\](a\.md)$') == 1)

" ---------------------------------------------------------------- za → b（既存ノート B を子に）
execute 'edit ' . fnameescape(s:v . '/a.md')
let @" = '[ノートB](b.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('za b: A の ChildBranch に B', s:count('a.md', '^\[ノートB\](b\.md)$') == 1)
call s:ok('za b: B の ParentBranch に A', index(s:file('b.md'), '### ParentBranch') >= 0 && s:count('b.md', '^\[ノートA\](a\.md)$') == 1)
call s:ok('za b: バッファが読み直されている（未保存でない）', !&modified && join(getline(1, '$'), "\n") ==# join(s:file('a.md'), "\n"))

" ---------------------------------------------------------------- 同じ組をもう一度（重複を作らない）
let s:a_snap = s:file('a.md')
let s:b_snap = s:file('b.md')
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('za b 再実行: 重複を作らない', s:file('a.md') ==# s:a_snap && s:file('b.md') ==# s:b_snap)

" ---------------------------------------------------------------- 2 つ目の親は拒否（C から B）
execute 'edit ' . fnameescape(s:v . '/c.md')
let s:c_snap = s:file('c.md')
let @" = '[ノートB](b.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('C→B 拒否: C は変わらない', s:file('c.md') ==# s:c_snap && getline(1, '$') ==# s:c_snap)
call s:ok('C→B 拒否: B の親は A のまま（C を足さない・A を消さない）', s:file('b.md') ==# s:b_snap)
call s:ok('C→B 拒否: A も変わらない', s:file('a.md') ==# s:a_snap)

" ---------------------------------------------------------------- 自己参照は拒否
execute 'edit ' . fnameescape(s:v . '/c.md')
let @" = '[ノートC](c.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('自己参照 拒否: C は変わらない', s:file('c.md') ==# s:c_snap)

" ---------------------------------------------------------------- 循環は拒否（A → B、B → D、D → A）
execute 'edit ' . fnameescape(s:v . '/b.md')
let @" = '[ノートD](d.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('B→D: 追加できる', s:count('b.md', '^\[ノートD\](d\.md)$') == 1 && s:count('d.md', '^\[ノートB\](b\.md)$') == 1)
let s:d_snap = s:file('d.md')
let s:a2 = s:file('a.md')
execute 'edit ' . fnameescape(s:v . '/d.md')
let @" = '[ノートA](a.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('D→A 循環 拒否: D も A も変わらない', s:file('d.md') ==# s:d_snap && s:file('a.md') ==# s:a2)

" ---------------------------------------------------------------- index.md からの zn → b は何も作らない
execute 'edit ' . fnameescape(s:v . '/index.md')
let s:before = s:files()
let s:i_snap = s:file('index.md')
let g:gnosis_test_keys = ['b']
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('index.md の zn b: 新ノートを作らない・index.md も変わらない', s:files() ==# s:before && s:file('index.md') ==# s:i_snap)

" ---------------------------------------------------------------- 未保存の編集は失われない（保存してから足す）
execute 'edit ' . fnameescape(s:v . '/e.md')
call append(line('$'), '未保存で書いた行')
let @" = '[ノートC](c.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('未保存の編集: ファイルに残り、ChildBranch も入る', s:count('e.md', '^未保存で書いた行$') == 1 && s:count('e.md', '^\[ノートC\](c\.md)$') == 1 && !&modified)
call s:ok('未保存の編集: C の ParentBranch は E', s:count('c.md', '^\[ノートE\](e\.md)$') == 1)

" ---------------------------------------------------------------- \l（gnosis#insert_links_pick）からの b
call s:mk('f.md', 'ノートF', ['F の本文。'])
execute 'edit ' . fnameescape(s:v . '/e.md')
let g:gnosis_test_keys = ['b']
call gnosis#insert_links_pick(['[ノートF](f.md)'], getpos('.'))
call s:ok('\l b: E の ChildBranch に F・F の ParentBranch に E', s:count('e.md', '^\[ノートF\](f\.md)$') == 1 && s:count('f.md', '^\[ノートE\](e\.md)$') == 1)

" ---------------------------------------------------------------- zk → b（グループノートを子に）
execute 'edit ' . fnameescape(s:v . '/f.md')
let s:before = s:files()
let g:gnosis_test_keys = ['b']
sleep 1100m
call gnosis#v2_new_group()
stopinsert
let s:g = s:newest_except(s:before)
call s:ok('zk b: グループノートが F の ChildBranch に入る', !empty(s:g) && s:count('f.md', '(' . s:g . ')') == 1 && s:count(s:g, '^attribute: group$') == 1 && s:count(s:g, '^\[ノートF\](f\.md)$') == 1)

" ---------------------------------------------------------------- 既存の c / Enter は意味が変わらない
execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ['c', "\r"]
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:nc = s:newest_except(s:before)
call s:ok('zn c Enter は従来どおり（Context に入る・Branch は作らない）', !empty(s:nc) && index(s:file('d.md'), '### Context') >= 0 && s:count(s:nc, 'Branch') == 0)
execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:ne = s:newest_except(s:before)
call s:ok('zn Enter は従来どおり（子の Context に親・Branch は作らない）', !empty(s:ne) && s:count(s:ne, '^### Context$') == 1 && s:count(s:ne, 'Branch') == 0)

call writefile(s:res, s:work . '/result.txt')
qa!
