set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
" 今のノートに似たノート（引数なし = 今のノート）
execute 'edit ' . fnameescape($D . '/v/rose.md')
call gnosis#ai('similar')
let s:t = getline(1, '$')
call assert_match('^# 似たノート: rose.md', s:t[0])
call assert_true(!empty(filter(copy(s:t), 'v:val =~# "rose2.md" && v:val =~# "重複の疑い"')))
" Enter でそのノートへ
call cursor(match(s:t, 'rose2.md') + 1, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/rose2.md', expand('%:p'))
" 質問: 出典つき。根拠が無ければ見つからないと言う
call gnosis#ai('ask', 'ローズマリーの', '水やり')
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "生成ではなく"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(rose.md):" || v:val =~# "(rose2.md):"')))
close
call gnosis#ai('ask', '量子もつれの歴史')
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "手がかり"')))
close
" 問題の候補は表示するだけ（ノートに書かない）
call gnosis#ai('questions', 'bh.md')
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "Q: ブラックホールとは何ですか"')))
close
" 自然な文 → 検索条件
call gnosis#ai('nl', '今月の', 'タスク')
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "has:task"')))
close
" 種類の誤り・存在しないノートはエラー表示だけ
let s:w = winnr('$')
call gnosis#ai('nonsense')
call gnosis#ai('similar', 'zzz.md')
call assert_equal(s:w, winnr('$'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
