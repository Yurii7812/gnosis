source <sfile>:h/restore_head.vim
" 履歴に頼らず、a・b・c を開いてカーソルを置き、c を今のノートにして終了する
execute 'edit ' . fnameescape($D . '/v/a.md')
call cursor(6, 1)
execute 'edit ' . fnameescape($D . '/v/b.md')
call cursor(9, 1)
execute 'edit ' . fnameescape($D . '/v/c.md')
call cursor(4, 1)
call gnosis#session_save()
let d = json_decode(join(readfile($D . '/v/.state/session.json'), "\n"))
call assert_equal(['a.md', 'b.md', 'c.md'], sort(copy(d.files)))
call assert_equal('c.md', d.current)
call assert_equal(9, d.pos['b.md'][0])
call assert_false(has_key(d, 'password'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
