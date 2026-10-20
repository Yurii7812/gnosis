set nocp hidden
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
let g:gnosis_autosync = 0
let g:gnosis_autosave = 0
let g:gnosis_diary_auto = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
function! F(path) abort
  return readfile(a:path)
endfunction
function! PB(path) abort
  let l:ls = F(a:path)
  let l:i = index(l:ls, 'ParentBranch:')
  if l:i < 0 | return [] | endif
  let l:out = []
  for l:line in l:ls[l:i + 1 :]
    if l:line !~# '^\[' | break | endif
    call add(l:out, l:line)
  endfor
  return l:out
endfunction
function! New(group, key, name) abort
  execute 'edit ' . fnameescape(a:group)
  sleep 1100m
  let g:gnosis_test_keys = [a:key]
  let g:gnosis_test_display_name = [a:name]
  let g:gnosis_test_yomi = ['しんき']
  call gnosis#v2_new_plain()
  stopinsert
  return expand('%:p')
endfunction
let s:a = $D . '/v/a.md'
execute 'edit ' . fnameescape(s:a)
let g:gnosis_test_keys = ['n']
call gnosis#v2_new_group()
stopinsert
let s:b = expand('%:p')
call assert_notequal(s:a, s:b)
call assert_equal(['[A](a.md)'], PB(s:b))
let s:c = New(s:b, "\r", '子C')
call assert_notequal(s:b, s:c)
call assert_equal(['[A](a.md)'], PB(s:c))
call assert_true(index(F(s:b), '[子C](' . fnamemodify(s:c, ':t') . ')') >= 0)
call assert_true(index(F(s:c), 'Group:') >= 0)
call assert_equal(-1, index(F(s:c), 'Context:'))
call assert_true(join(F(s:a), "\n") =~# fnamemodify(s:c, ':t'))
let s:d = New(s:b, 'g', '親なしD')
call assert_equal([], PB(s:d))
call assert_true(index(F(s:b), '[親なしD](' . fnamemodify(s:d, ':t') . ')') >= 0)
call assert_true(index(F(s:d), 'Group:') >= 0)
let s:e = New(s:b, 'o', '')
call assert_equal([], PB(s:e))
call assert_equal(-1, index(F(s:e), 'Group:'))
" 通常のグループと Index は親を付けない。
let s:plain = New($D . '/v/plain.md', "\r", '通常')
call assert_equal([], PB(s:plain))
let s:idx = New($D . '/v/index.md', "\r", '索引')
call assert_equal([], PB(s:idx))
" A と B が別フォルダでも、A から見た BranchGroup の相対リンクを解決できる。
let s:sub = New($D . '/v/sub/b.md', "\r", '別フォルダ')
call assert_equal(['[別A](../other/a.md)'], PB(s:sub))
" za: 親のないノートだけ起点へ接続し、既存の親は保持する。
execute 'edit ' . fnameescape(s:b)
call setreg('"', "[未所属](orphan.md)\n[既存](existing.md)", 'V')
call setreg('0', getreg('"'))
let g:gnosis_test_display_name = ['追加した子', '既存の子']
let g:gnosis_test_yomi = ['ついか', 'きそん']
call gnosis#add_clipboard_before_up_note()
call assert_equal(['[A](a.md)'], PB($D . '/v/orphan.md'))
call assert_equal(['[元の親](parent.md)'], PB($D . '/v/existing.md'))
" モードオフなら za と zn Enter のどちらも親を作らない。
GnosisGroupParent off
call setreg('"', '[自動オフ](modeoff.md)', 'V')
call setreg('0', getreg('"'))
let g:gnosis_test_display_name = ['自動オフ']
let g:gnosis_test_yomi = ['じどうおふ']
call gnosis#add_clipboard_before_up_note()
call assert_equal([], PB($D . '/v/modeoff.md'))
let s:off = New(s:b, "\r", '設定オフ')
call assert_equal([], PB(s:off))
GnosisGroupParent on
" 外から za g でグループを選ぶ場合も同じ。
execute 'edit ' . fnameescape($D . '/v/joiner.md')
let g:gnosis_test_keys = ['g']
let g:gnosis_test_display_name = ['外から追加']
let g:gnosis_test_yomi = ['そと']
call gnosis#insert_links_pick(['[B](' . fnamemodify(s:b, ':t') . ')'], getpos('.'))
call assert_equal(['[A](a.md)'], PB($D . '/v/joiner.md'))
" 起点の未保存編集がある場合は何も作らず、グループにも登録しない。
execute 'edit ' . fnameescape(s:a)
call append(line('$'), '未保存の本文')
execute 'edit ' . fnameescape(s:b)
let s:files = glob($D . '/v/*.md', 0, 1)
let s:before = F(s:b)
let g:gnosis_test_keys = ["\r"]
let g:gnosis_test_display_name = ['作らない']
call gnosis#v2_new_plain()
stopinsert
call assert_equal(s:files, glob($D . '/v/*.md', 0, 1))
call assert_equal(s:before, F(s:b))
execute 'buffer ' . bufnr(s:a)
edit!
call writefile([s:c, s:d, s:e, s:plain, s:idx, s:sub], $D . '/created')
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
