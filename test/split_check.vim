set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
" 統計・比較（読み取り専用）
execute 'edit ' . fnameescape($D . '/v/small.md')
GnosisStats
call assert_match('^# 統計: \[小\]', getline(1))
close
GnosisStats!
call assert_equal('# vault の統計', getline(1))
close
GnosisDiff big.md
call assert_match('^# 比較: small.md と big.md', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^```diff"')))
close
" 分割: 未保存の編集があるときは何もしない
execute 'edit ' . fnameescape($D . '/v/big.md')
call cursor(search('水やり'), 1)
set modified                " 未保存の状態（Gnosis の自動保存は挿入を抜けたときに働くので、直接立てる）
GnosisSplit cultivation
call assert_false(filereadable($D . '/v/cultivation.md'))
GnosisSplitUndo
call assert_true(&modified)  " 取り消しも何もしない
set nomodified
" 保存済みで分割
call cursor(search('水やり'), 1)
GnosisSplit cultivation
call assert_true(filereadable($D . '/v/cultivation.md'))
call assert_true(!empty(filter(readfile($D . '/v/cultivation.md'), 'v:val ==# "Related:"')))
call assert_true(index(getline(1, '$'), '→ [栽培](cultivation.md)（分割しました）') >= 0)
call assert_true(!empty(filter(readfile($D . '/v/ref.md'), 'v:val =~# "(cultivation.md)"')))
" 見出しの外(題の行)では分割しない。題のみの節は分割できない
call cursor(search('^# 大'), 1)
let s:n = len(glob($D . '/v/*.md', 0, 1))
GnosisSplit titlepart
call assert_equal(s:n, len(glob($D . '/v/*.md', 0, 1)))
" 取り消し
GnosisSplitUndo
call assert_false(filereadable($D . '/v/cultivation.md'))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "水やりは控えめに"')))
" 2 回目の取り消しは何もしない
GnosisSplitUndo
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
