set nocp hidden
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
let g:gnosis_autosync = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
function! F(name) abort
  return readfile($D . '/v/' . a:name)
endfunction
execute 'edit ' . fnameescape($D . '/v/g.md')
" za: 既存のメンバーにも表示名とよみを入力できる。
call setreg('"', "[A](a.md)\n")
let g:gnosis_test_display_name = ['別名']
let g:gnosis_test_yomi = ['べつめい']
call gnosis#add_clipboard_before_up_note()
call assert_equal([], g:gnosis_test_display_name)
call assert_equal([], g:gnosis_test_yomi)
call assert_true(index(F('g.md'), '[aaa](a.md)') >= 0)
call assert_true(index(F('g.md'), '[別名](a.md)') >= 0)
call assert_true(join(F('a.md'), "\n") =~# 'べつめい')
" g: 外からも同じグループに再追加できる。
execute 'edit ' . fnameescape($D . '/v/a.md')
let g:gnosis_test_keys = ['g']
let g:gnosis_test_display_name = ['bbb']
let g:gnosis_test_yomi = ['びー']
call gnosis#insert_links_pick(['[G](g.md)'], getpos('.'))
call assert_equal([], g:gnosis_test_display_name)
call assert_true(index(F('g.md'), '[bbb](a.md)') >= 0)
call assert_true(index(getline(1, '$'), '[G:aaa,別名,bbb](g.md)') >= 0)
" 確認画面でも同じファイルの別名を独立に編集・削除できる。
execute 'edit ' . fnameescape($D . '/v/g.md')
GnosisYomiReview
sleep 100m
let s:line = search('^\[bbb\]')
call assert_true(s:line > 0)
call setline(s:line, substitute(getline(s:line), '^\[bbb\]', '[ccc]', ''))
let s:line = search('^\[別名\]')
execute s:line . 'delete _'
call gnosis#review_commit()
sleep 100m
call assert_true(index(F('g.md'), '[aaa](a.md)') >= 0)
call assert_true(index(F('g.md'), '[ccc](a.md)') >= 0)
call assert_equal(-1, index(F('g.md'), '[bbb](a.md)'))
call assert_equal(-1, index(F('g.md'), '[別名](a.md)'))
" CopyStack: ノートをまたぎ、y と d を混ぜ、同じショートカットで確定する。
execute 'edit ' . fnameescape($D . '/v/x.md')
nnoremap <buffer> y :let g:restored_y = 1<CR>
let s:oldmap = maparg('y', 'n', 0, 1)
normal \sc
call assert_equal(1, g:gnosis_stack_copy_mode)
call cursor(search('^\[A\]'), 1)
normal y
execute 'edit ' . fnameescape($D . '/v/z.md')
call cursor(search('^\[B\]'), 1)
normal d
call assert_equal(0, search('^\[B\]', 'nw'))
normal \sc
call assert_equal(0, g:gnosis_stack_copy_mode)
call assert_equal(['[A](a.md)', '[B](b.md)'], getreg('"', 1, 1))
call assert_equal('V', getregtype('"'))
call assert_equal(['[A](a.md)', '[B](b.md)'], getreg('0', 1, 1))
call assert_equal('', maparg('y', 'n'))
execute 'edit ' . fnameescape($D . '/v/x.md')
call assert_equal(s:oldmap.rhs, maparg('y', 'n', 0, 1).rhs)
execute 'edit ' . fnameescape($D . '/v/h.md')
let g:gnosis_test_display_name = ['', '']
let g:gnosis_test_yomi = ['えー', 'びー']
call gnosis#add_clipboard_before_up_note()
call assert_true(index(F('h.md'), '[A](a.md)') >= 0)
call assert_true(index(F('h.md'), '[B](b.md)') >= 0)
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
