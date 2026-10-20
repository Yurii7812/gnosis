set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
GnosisCalendar 2026-10
call assert_equal('# 2026年10月', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "5<br>📝1"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "25<br>📅1"')))
close
GnosisDay 2026-10-05
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(a.md)"')))
call cursor(match(getline(1, '$'), '(a.md)') + 1, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/a.md', expand('%:p'))
GnosisOnThisDay 2026-10-21
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "1 年前"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(b.md)"')))
close
GnosisPeriodReview 週 2026-10-05
call assert_match('週のレビュー 2026-10-05〜2026-10-11', getline(1))
close
" 不正な期間はエラー表示だけで画面を開かない
let s:w = winnr('$')
GnosisPeriodReview 十年
GnosisDay not-a-date
call assert_equal(s:w, winnr('$'))
" レビューを新しいノートとして書く。同じ名前へ 2 回目は上書きされない
GnosisPeriodReviewWrite 週 2026-10-05 reviews/w41.md
call assert_equal($D . '/v/reviews/w41.md', expand('%:p'))
let s:first = readfile($D . '/v/reviews/w41.md')
call writefile(s:first + ['手書き'], $D . '/v/reviews/w41.md')
GnosisPeriodReviewWrite 週 2026-10-05 reviews/w41.md
call assert_equal(s:first + ['手書き'], readfile($D . '/v/reviews/w41.md'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
