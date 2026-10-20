set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
let s:url = 'http://127.0.0.1:' . $PORT . '/feed.xml'
" 既定: 無効・許可なし。run は通信しない(! をつけても、条件がそろわなければ何もしない)
GnosisCollect status
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "無効（通信しません）"')))
close
GnosisCollect! run
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "有効になっていません"')))
close
" 不正な URL は許可できない
let s:w = winnr('$')
GnosisCollect allow ftp://x/y
GnosisCollect allow
GnosisCollect bogus
call assert_equal(s:w, winnr('$'))
" 許可だけでは(有効にしていないので)通信しない
execute 'GnosisCollect allow ' . s:url
close
GnosisCollect! run
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "有効になっていません"')))
close
GnosisCollect enable
close
GnosisCollect status
call assert_true(!empty(filter(getline(1, '$'), 'v:val ==# "収集: 有効"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "feed.xml"')))
close
" 確認ダイアログ(! なし)は -es では「いいえ」(既定の 2)になるので、通信しない
GnosisCollect run
call assert_false(isdirectory($D . '/v/収集'))
" 実行
GnosisCollect! run
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "新しいノート 1 件"')))
close
call assert_equal(1, len(glob($D . '/v/収集/*.md', 0, 1)))
let s:note = join(readfile(glob($D . '/v/収集/*.md', 0, 1)[0]), "\n")
call assert_match('title: 外部の記事', s:note)
call assert_match('本文 です', s:note)                    " 記事の HTML のタグは捨てて、文字だけにする
call assert_true(s:note !~# '<b>')
" 2 回目は増えない
GnosisCollect! run
close
call assert_equal(1, len(glob($D . '/v/収集/*.md', 0, 1)))
GnosisCollect disable
close
GnosisCollect! run
close
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
