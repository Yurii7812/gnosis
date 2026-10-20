set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
execute 'edit ' . fnameescape($D . '/v/old.md')
" 未保存なら何もしない
set modified
GnosisRename! sub/deep/new
call assert_true(filereadable($D . '/v/old.md'))
call assert_false(filereadable($D . '/v/sub/deep/new.md'))
set nomodified
" 既存への上書きは拒否
GnosisRename! a.md
call assert_true(filereadable($D . '/v/old.md'))
" 別フォルダへ移す(! で確認なし)。.md は補われる
GnosisRename! sub/deep/new
call assert_equal($D . '/v/sub/deep/new.md', expand('%:p'))
call assert_false(filereadable($D . '/v/old.md'))
call assert_equal([], filter(getbufinfo({'buflisted': 1}), 'v:val.name =~# "/old.md$"'))   " 旧名のバッファは残らない
call assert_true(!empty(filter(getline(1, '$'), 'v:val ==# "[兄弟](../o.md)"')))       " 移した先から計算し直した
call assert_true(!empty(filter(readfile($D . '/v/a.md'), 'v:val ==# "[旧](sub/deep/new.md)と[節](sub/deep/new.md#x)"')))
call assert_true(!empty(filter(readfile($D . '/v/sub/o.md'), 'v:val ==# "[旧](deep/new.md)"')))
" 取り消し
GnosisRenameUndo
call assert_equal($D . '/v/old.md', expand('%:p'))
call assert_false(filereadable($D . '/v/sub/deep/new.md'))
call assert_true(!empty(filter(readfile($D . '/v/a.md'), 'v:val ==# "[旧](old.md)と[節](old.md#x)"')))
" 2 回目の取り消しは何もしない
GnosisRenameUndo
call assert_equal($D . '/v/old.md', expand('%:p'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
