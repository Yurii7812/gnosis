source <sfile>:h/restore_head.vim
call assert_equal(0, argc())
let g:gnosis_restore_last = 0
doautocmd VimEnter
call assert_equal(0, len(filter(getbufinfo({'buflisted': 1}), 'v:val.name =~# "\.md$"')))   " 既定(0)では自動で復元しない
let g:gnosis_restore_last = 1
doautocmd VimEnter
call assert_equal($D . '/v/c.md', expand('%:p'))                 " 自動復元が効く
call assert_equal(2, tabpagenr('$'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
