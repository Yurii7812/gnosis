set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
call gnosis#graph_report()
let s:t = getline(1, '$')
call assert_equal('# グラフ分析', s:t[0])
call assert_true(!empty(filter(copy(s:t), 'v:val =~# "価値の大小を表すものではありません"')))
call assert_true(!empty(filter(copy(s:t), 'v:val =~# "孤立したノート: 1 件"')))
" Enter でレポートのノートへ
let s:ln = match(s:t, '](\S*\.md)') + 1
call cursor(s:ln, 1)
execute "normal \<CR>"
call assert_match('\.md$', expand('%:p'))
call assert_equal($D . '/v', fnamemodify(expand('%:p'), ':h'))
" パターン探索: D の親は C
call gnosis#graph_query('?a -[parent_branch]-> ?b')
call assert_equal('# パターン: ?a -[parent_branch]-> ?b', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "d.md  →  c.md"')))
close
" 経路: A から D（A→C→D）
call gnosis#graph_paths('a.md', 'd.md')
let s:p = getline(1, '$')
call assert_equal('# a.md → d.md', s:p[0])
call assert_true(!empty(filter(copy(s:p), 'v:val =~# "経路 1: (2 歩)"')))
call assert_true(!empty(filter(copy(s:p), 'v:val =~# "\\[link\\] C"')))
call assert_true(!empty(filter(copy(s:p), 'v:val =~# "\\[parent_branch\\] D"')) || !empty(filter(copy(s:p), 'v:val =~# "\\[link\\] D"')))
close
" 孤立へは経路が無い・存在しないノートはエラー表示だけ
let s:w = winnr('$')
call gnosis#graph_paths('a.md', 'e.md')
call gnosis#graph_paths('a.md', 'zzz.md')
call assert_equal(s:w, winnr('$'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
