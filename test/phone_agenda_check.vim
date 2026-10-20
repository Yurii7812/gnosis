set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
" 完了の記録が無いときは何もしない
redir => s:m0
silent GnosisPullDone
redir END
call assert_match('反映しました（0 件', s:m0)
" 送る
GnosisPushAgenda
call assert_true(filereadable($D . '/phone/agenda.tsv'))
let s:tsv = readfile($D . '/phone/agenda.tsv')
call assert_equal('# gnosis-agenda v1', s:tsv[0])
call assert_equal(3, len(filter(copy(s:tsv), 'v:val =~# "^task\t"')))
call assert_true(!empty(filter(copy(s:tsv), 'v:val =~# "^task\t' . $KEY . '\t2026-10-21\t"')))
" スマホで「ゴミ出し」を完了にした記録(未知のキーも混ぜる)
call writefile(['done' . "\t" . $KEY . "\t2026-10-21T09:12", 'done' . "\t0123456789\t2026-10-21T09:13"], $D . '/phone/agenda-done.tsv')
" 未保存の編集があるときは反映しない(ノートを書き換えるので)
execute 'edit ' . fnameescape($D . '/v/a.md')
set modified
GnosisPullDone
call assert_true(filereadable($D . '/phone/agenda-done.tsv'))
call assert_true(empty(filter(readfile($D . '/v/a.md'), 'v:val =~# "^- \\[x\\]"')))
set nomodified
GnosisPullDone
call assert_false(filereadable($D . '/phone/agenda-done.tsv'))
call assert_true(!empty(filter(readfile($D . '/v/a.md'), 'v:val =~# "^- \\[x\\] ゴミ出し"')))
" もう一度は何も起きない
GnosisPullDone
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
