set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
let s:orig = readfile($D . '/v/a.md')
execute 'edit ' . fnameescape($D . '/v/a.md')
GnosisDedupe
call assert_equal('# ノート内の重複: [a.md](a.md)', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "12 行目（8 行目と同じ）"')))
close
call assert_equal(s:orig, readfile($D . '/v/a.md'))          " 見せるだけ
GnosisDedupe scan
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "複数のノートにある同じ段落（1 件"')))
close
" scan に ! は使えない
GnosisDedupe! scan
call assert_equal(s:orig, readfile($D . '/v/a.md'))
GnosisDedupe!
close
call assert_equal(1, len(filter(readfile($D . '/v/a.md'), 'v:val =~# "水やりは朝"')))
GnosisVersions restore 1
call assert_equal(s:orig, readfile($D . '/v/a.md'))          " 版から戻せる
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
