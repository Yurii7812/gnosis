set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
call gnosis#export_site(0, $D . '/site')
call assert_true(filereadable($D . '/site/a.html'))
call assert_true(filereadable($D . '/site/FOLGEZETTEL.md'))
call assert_false(filereadable($D . '/site/p.html'))
call assert_equal(0, len(filter(readfile($D . '/site/a.html'), 'v:val =~# "p.html"')))
" 既定の出力先は vault 内の .site
call gnosis#export_site(0)
call assert_true(filereadable($D . '/v/.site/index.html'))
" 空でも前回の書き出しでもないフォルダには何も書かない
call gnosis#export_site(0, $D . '/mine')
call assert_false(filereadable($D . '/mine/index.html'))
" ! で非公開も含める
call gnosis#export_site(1, $D . '/site')
call assert_true(filereadable($D . '/site/p.html'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
