set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
" 試走: 何も書かない
execute 'GnosisImport plan ' . $D . '/src imp'
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "試走です。何も書いていません"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "Nothing"')))
close
call assert_false(isdirectory($D . '/v/imp'))
" 実行
execute 'GnosisImport run ' . $D . '/src imp'
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^ID: [0-9a-f]\\{12}$"')))
let s:id = matchstr(join(getline(1, '$'), "\n"), 'ID: \zs[0-9a-f]\{12}')
close
call assert_true(filereadable($D . '/v/imp/Home.md'))
call assert_true(!empty(filter(readfile($D . '/v/imp/Home.md'), 'v:val =~# "\\[Herb\\](Herb.md)"')))
" 検証・もう一度の run は拒否(すでにある)
execute 'GnosisImport verify ' . s:id
call assert_true(!empty(filter(getline(1, '$'), 'v:val ==# "問題なし"')))
close
let s:w = winnr('$')
execute 'GnosisImport run ' . $D . '/src imp'
GnosisImport bogus
GnosisImport verify
execute 'GnosisImport verify 000000000000'
call assert_equal(s:w, winnr('$'))
" 取り消し
execute 'GnosisImport undo ' . s:id
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "消した: 2"')))
close
call assert_false(isdirectory($D . '/v/imp'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
