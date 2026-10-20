source <sfile>:h/restore_head.vim
call assert_equal(1, argc())
let g:gnosis_restore_last = 1
doautocmd VimEnter
call assert_equal(1, tabpagenr('$'))                             " ファイルを指定して起動したときは復元しない
call assert_equal($D . '/v/d.md', expand('%:p'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
