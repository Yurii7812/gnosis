" 決まり（2026-11-03）: 索引（グループ）はノートだけを指す。グループ同士は Related: のときだけ。
" 試験: 書く入口（節・BranchGroup・branch の親子・グループ作成）がグループへのリンクを断ること、
" ノートへは従来どおり書けること、Related: だけは許すこと。
set nomore
let g:gnosis_history = []
let g:gnosis_history_max = 100
let g:gnosis_forward = []
let s:v = $RELATED_WORK . '/vault'
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0

function! s:mk(n, title, body, extra) abort
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title] + a:extra + ['---', '', '# ' . a:title, ''] + a:body, s:v . '/' . a:n . '.md')
endfunction

call mkdir(s:v, 'p')
call s:mk('idx', '索引', ['[ノート](n.md)'], ['attribute: group'])
call s:mk('grp1', 'グループA', ['本文'], ['attribute: group'])
call s:mk('grp2', 'グループB', ['本文'], ['attribute: group'])
call s:mk('n', 'ノート', ['本文'], [])

let s:p = {'idx': s:v . '/idx.md', 'grp1': s:v . '/grp1.md', 'grp2': s:v . '/grp2.md', 'n': s:v . '/n.md'}

" 判定そのもの
call assert_equal(1, gnosis#group_pair_refused(s:p.idx, s:p.grp2, 'body'), 'index body -> group refused')
call assert_equal(1, gnosis#group_pair_refused(s:p.idx, s:p.grp2, 'down'), 'index child -> group refused')
call assert_equal(0, gnosis#group_pair_refused(s:p.idx, s:p.grp2, 'related'), 'index related -> group allowed')
call assert_equal(0, gnosis#group_pair_refused(s:p.idx, s:p.n, 'body'), 'index -> note allowed')
call assert_equal(0, gnosis#group_pair_refused(s:p.n, s:p.grp2, 'body'), 'note -> group allowed')
call assert_equal(1, gnosis#group_pair_refused(s:p.grp1, s:p.grp2, 'up'), 'group parent -> group refused')
call assert_equal(1, gnosis#group_pair_refused(s:p.grp1, s:p.grp2, 'context'), 'group context -> group refused')
call assert_equal(0, gnosis#group_pair_refused(s:p.grp1, s:p.grp2, 'related'), 'group related -> group allowed')

" 入口: ブランチの親子（索引とグループ）は断り、ファイルは変わらない
let s:before = readfile(s:p.idx, 'b')
let s:r = gnosis#branch#add_paths(s:p.idx, [s:p.grp2])
call assert_equal('group_rule', get(s:r, 'code', ''), 'branch add refused for index -> group')
call assert_equal(s:before, readfile(s:p.idx, 'b'), 'refused branch add leaves index unchanged')
call assert_match('Related:', gnosis#branch#message(s:r), 'refusal message points to Related:')

" 入口: ノート → グループ（BranchGroup 相当）は従来どおり書ける（断らない）
call assert_equal(0, gnosis#group_pair_refused(s:p.n, s:p.grp1, 'branch_group'), 'note -> group membership allowed')

call writefile(v:errors, $RELATED_WORK . '/errors')
if !empty(v:errors) | cquit | endif
qa!
