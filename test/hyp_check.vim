set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
GnosisHypotheses
call assert_equal('# 仮説 3 件', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "睡眠は記憶に効く.*検証中・証拠 2・反証 1"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "目安: 支持"')))
call cursor(match(getline(1, '$'), '(sleep.md)') + 1, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/sleep.md', expand('%:p'))
GnosisHypotheses 検証中
call assert_equal('# 仮説 1 件', getline(1))
close
GnosisHypothesis
call assert_true(!empty(filter(getline(1, '$'), 'v:val ==# "# 仮説: 睡眠は記憶に効く"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val ==# "# 仮説: 昼寝は逆効果"')))
close
GnosisHypothesis sleep.md 2
call assert_equal('# 仮説: 昼寝は逆効果', getline(1))
close
GnosisDebate 睡眠は記憶 運動が記憶
call assert_equal('# 思考の対戦', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val ==# "| 証拠 | 2 | 1 |"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "A は証拠・B は反証"')))
close
" 曖昧・存在しない・同じ仮説はエラー表示だけ
let s:w = winnr('$')
GnosisDebate 記憶 運動が記憶
GnosisDebate 存在しない 運動が記憶
GnosisDebate 睡眠は記憶 睡眠は記憶
GnosisHypothesis none.md
call assert_equal(s:w, winnr('$'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
