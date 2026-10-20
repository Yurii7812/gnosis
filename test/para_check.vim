set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
GnosisPara
call assert_equal('# PARA（仮想ビュー）', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^## Projects.* 1 件"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(proj.md) — 未完了のタスクが 1 件"')))
call cursor(match(getline(1, '$'), '(proj.md)') + 1, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/proj.md', expand('%:p'))
" 引数なしの GnosisMoc は今のノート。グループを開いて実行
execute 'edit ' . fnameescape($D . '/v/area.md')
GnosisMoc
call assert_equal('# MOC: 健康', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(sleep.md)"')))
close
GnosisMoc 健康
call assert_equal('# MOC: 健康', getline(1))
close
GnosisMocPropose 睡眠
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(t1.md)"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "すでに「健康」に載っている"')))
close
" 新しいノートとして書く。2 回目は上書きしない
GnosisMocPropose 睡眠 moc/sleep.md
call assert_equal($D . '/v/moc/sleep.md', expand('%:p'))
let s:first = readfile($D . '/v/moc/sleep.md')
call assert_equal('moc: true', s:first[3])
call writefile(s:first + ['手書き'], $D . '/v/moc/sleep.md')
GnosisMocPropose 睡眠 moc/sleep.md
call assert_equal(s:first + ['手書き'], readfile($D . '/v/moc/sleep.md'))
let s:w = winnr('$')
GnosisMoc nothing
call assert_equal(s:w, winnr('$'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
