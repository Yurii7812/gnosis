set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
GnosisCompat
call assert_equal('# Markdown 互換性検査', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^## error"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(bad.md):3 コードブロックが閉じていません"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^## info"')))
call cursor(match(getline(1, '$'), '(bad.md)') + 1, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/bad.md', expand('%:p'))
GnosisCompat error
call assert_true(empty(filter(getline(1, '$'), 'v:val =~# "^## info"')))
close
GnosisProfile
call assert_equal('# 性能診断', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "全文索引"')))
close
let s:w = winnr('$')
GnosisCompat bogus
call assert_equal(s:w, winnr('$'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
