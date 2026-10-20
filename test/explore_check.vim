set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
GnosisExplore walk a.md
call assert_match('^# 散歩', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(a.md)"')))
close
GnosisExplore roulette orphan
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(f.md)"')))
call cursor(match(getline(1, '$'), '(f.md)') + 1, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/f.md', expand('%:p'))
" 引数なしの serendipity は今のノート（f.md）。a.md はリンクで遠くないので候補は出ないが画面は開く
GnosisExplore serendipity
call assert_match('^# 意外な近さ: f.md', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(a.md)"')))
close
GnosisExplore between a.md c.md
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "ハーブの水やり → 土の話 → 道具"')))
close
GnosisExplore archaeology
call assert_match('^# 知識考古学', getline(1))
close
" エラーは表示だけで画面を開かない
let s:w = winnr('$')
GnosisExplore bogus
GnosisExplore walk zzz.md
GnosisExplore between a.md
call assert_equal(s:w, winnr('$'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
