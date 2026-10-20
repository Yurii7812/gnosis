set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
call gnosis#query('水 -やり')
let s:t = getline(1, '$')
call assert_equal('# 検索: 水 -やり', s:t[0])
call assert_match('^1 件', s:t[2])
call assert_match('^1 ハーブ', s:t[4])                       " 栽培(水やり)は -やり で除かれ、ハーブだけが残る
" Enter でそのノート（ヒットした行）へ
call cursor(5, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/a.md', expand('%:p'))
call assert_match('水', getline('.'))
" 保存検索 → 再実行 → 昇格（新規ファイルだけ）
call gnosis#query_save('水系', '水')
call gnosis#query_run('水系')
call assert_match('^# 検索: 水系', getline(1))
call assert_equal('水', b:gnosis_query.query)                " 名前ではなく保存したクエリを覚える（昇格で同じ検索をやり直す）
call gnosis#query_promote('found.md')
call assert_true(filereadable($D . '/v/found.md'))
call assert_true(!empty(filter(readfile($D . '/v/found.md'), 'v:val =~# "(a.md)"')))
let s:before = readfile($D . '/v/found.md')
call gnosis#query_promote('found.md')
call assert_equal(s:before, readfile($D . '/v/found.md'))
" 検索結果の画面以外では昇格しない
new
call gnosis#query_promote('other.md')
call assert_false(filereadable($D . '/v/other.md'))
close
" 不正な正規表現はエラー表示だけで、画面は開かない
let s:wins = winnr('$')
call gnosis#query('/(/')
call assert_equal(s:wins, winnr('$'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
