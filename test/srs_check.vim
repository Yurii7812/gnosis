set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
let s:state = $D . '/v/.gnosis/srs.json'
call gnosis#srs_review()
call assert_equal(2, len(b:gnosis_srs.cards))
" 見る前に採点しても記録されない（思い出してから答えを見る）
call feedkeys("5", "x")
call assert_false(filereadable(s:state))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "まず思い出してください"')))
" 答えを見て採点 → 記録され、次のカードへ
call feedkeys("\<Space>", "x")
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "答え:"')))
call feedkeys("4", "x")
call assert_true(filereadable(s:state))
call assert_equal(1, len(keys(json_decode(join(readfile(s:state), "\n")).cards)))
call assert_equal(1, b:gnosis_srs.i)
" 飛ばす（記録しない）→ おしまい
call feedkeys("s", "x")
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "おしまい"')))
close
" もう一度: 答えたカードは今日は出ない（残り 1 枚）
call gnosis#srs_review()
call assert_equal(1, len(b:gnosis_srs.cards))
close
" ランダム復習は記録しない
let s:n = len(keys(json_decode(join(readfile(s:state), "\n")).cards))
call gnosis#srs_review('random', 2)
call feedkeys("\<Space>", "x")
call feedkeys("5", "x")
call assert_equal(s:n, len(keys(json_decode(join(readfile(s:state), "\n")).cards)))
close
call gnosis#srs_stats()
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
