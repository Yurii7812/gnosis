set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
" 既定の出力先(vault の外の gnosis-books/)に作られる
GnosisExportBook epub
call assert_equal(1, len(glob($D . '/gnosis-books/*.epub', 0, 1)))
execute 'GnosisExportBook epub ' . $D . '/out/book.epub'
call assert_true(filereadable($D . '/out/book.epub'))
" 既存のファイルは上書きしない
call writefile(['keep'], $D . '/out/keep.epub')
execute 'GnosisExportBook epub ' . $D . '/out/keep.epub'
call assert_equal(['keep'], readfile($D . '/out/keep.epub'))
" vault の中へは書かない
execute 'GnosisExportBook html ' . $D . '/v/inside.html'
call assert_false(filereadable($D . '/v/inside.html'))
" 起点のノートで枝だけ(一章 と 一章の枝)。秘密は含めない
execute 'GnosisExportBook html ' . $D . '/out/branch.html 一章'
call assert_true(filereadable($D . '/out/branch.html'))
let s:t = join(readfile($D . '/out/branch.html'), "\n")
call assert_true(s:t =~# '一章の枝')
call assert_true(s:t !~# 'TOPSECRET')
" 形式の誤り・存在しない起点はエラー表示だけ
GnosisExportBook docx
execute 'GnosisExportBook html ' . $D . '/out/none.html 存在しない'
call assert_false(filereadable($D . '/out/none.html'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
