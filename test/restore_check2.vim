source <sfile>:h/restore_head.vim
GnosisRestore
let s:names = map(filter(getbufinfo({'buflisted': 1}), 'v:val.name =~# "\\.md$"'), 'fnamemodify(v:val.name, ":t")')
call assert_equal(['b.md', 'c.md'], sort(s:names))              " 消えた a.md は飛ばす
call assert_equal($D . '/v/c.md', expand('%:p'))                " 今のノートが最初に開かれる
call assert_equal(2, tabpagenr('$'))
tabnext 2
call assert_equal($D . '/v/b.md', expand('%:p'))
call assert_equal(9, line('.'))                                  " カーソル位置も戻る
tabfirst
call assert_equal(4, line('.'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
