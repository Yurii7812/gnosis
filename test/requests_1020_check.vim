" test/requests_1020_net.sh から使う。$D に vault（v/）を用意して呼ぶ。
"   i（行の中）・\L の b / c・\l → g（zk で分岐したグループに入る。表示名とよみ）・\l → m（マージと取り消し）
set nocp
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
let g:R = []
function! F(name) abort
  return readfile($D . '/v/' . a:name)
endfunction
function! Has(name, pat) abort
  return len(filter(F(a:name), 'v:val =~# a:pat'))
endfunction

" 1) \l → i: カーソルの文字のすぐ後ろに、そのまま入れる（関係は付けない）
execute 'edit ' . fnameescape($D . '/v/a.md')
call cursor(search('^- \[ \] '), 1)
normal! $
let g:gnosis_test_keys = ['i']
call gnosis#insert_links_pick(['[ビー](b.md)'], getpos('.'))
call add(g:R, 'inline ' . getline('.'))
call add(g:R, 'inline-saved ' . Has('a.md', '^- \[ \] \[ビー\](b.md)$'))

" 2) \L（ビジュアル）→ b: 新しいノートが今のノートの子になる
call setline(line('$') + 1, '修正5')
call cursor(line('$'), 1)
let g:gnosis_test_keys = ['b']
execute "normal! v$\<Esc>"
call gnosis#linkify_selection_new_note()
let s:n1 = expand('%:p')
stopinsert
call add(g:R, 'L-b ' . (s:n1 !=# $D . '/v/a.md') . ' ' . len(filter(readfile(s:n1), 'v:val ==# "[A](a.md)"')) . ' ' . len(filter(readfile(s:n1), 'v:val ==# "ParentBranch:"')))
" 3) \L → c: 新しいノートの Context: に元のノート
execute 'edit ' . fnameescape($D . '/v/a.md')
sleep 1100m
call setline(line('$') + 1, '修正6')
call cursor(line('$'), 1)
let g:gnosis_test_keys = ['c']
execute "normal! v$\<Esc>"
call gnosis#linkify_selection_new_note()
let s:n2 = expand('%:p')
stopinsert
call add(g:R, 'L-c ' . (s:n2 !=# s:n1) . ' ' . len(filter(readfile(s:n2), 'v:val ==# "Context:"')))
" Esc はやめる（ノートを作らない）
" 直前の保存で始まった自動同期（非同期のジョブ）が a.md を書き終えるのを待ってから読み直す（待たないと、
" 読んだあとにジョブが書き換えて、Vim の「読込んだ後にファイルに変更がありました」の確認で止まることがある）
sleep 1100m
execute 'edit ' . fnameescape($D . '/v/a.md')
let s:before = len(glob($D . '/v/*.md', 0, 1))
call setline(line('$') + 1, '修正7')
call cursor(line('$'), 1)
let g:gnosis_test_keys = ["\<Esc>"]
execute "normal! v$\<Esc>"
call gnosis#linkify_selection_new_note()
call add(g:R, 'L-esc ' . (len(glob($D . '/v/*.md', 0, 1)) == s:before) . ' ' . fnamemodify(bufname('%'), ':t'))

" 4) A の BranchGroup: にあるグループ G へ、A を入れる（\l → e → g の決定と同じ gnosis#index_add。表示名・よみ）
" 保存は自動保存と同じ方法で（保存のあとの同期がファイルを書き換えていても止まらない）
call gnosis#conflict#safe_update()
let g:gnosis_test_display_name = ['えー']
let g:gnosis_test_yomi = ['えー']
call gnosis#index_add($D . '/v/a.md', $D . '/v/g.md')
execute 'silent! edit ' . fnameescape($D . '/v/a.md')
unlet! g:gnosis_test_display_name g:gnosis_test_yomi
call add(g:R, 'join ' . Has('g.md', '^\[えー\](a.md)$') . ' ' . Has('a.md', '^\[G\](g.md)$') . ' ' . Has('a.md', 'えー'))
call add(g:R, 'sorted ' . string(F('g.md')[-5:]))

" 4b) zk で作ったばかりの空のグループ（末尾に書き出しの余白）: 中で za → ParentBranch: のブロックから空行 1 つ空けて入る
execute 'edit ' . fnameescape($D . '/v/e.md')
call setreg('"', "[ゼブラ](z.md)\n")
let g:gnosis_test_display_name = ['']
let g:gnosis_test_yomi = ['ぜぶら']
call gnosis#add_clipboard_before_up_note()
unlet! g:gnosis_test_display_name g:gnosis_test_yomi
call add(g:R, 'empty-za ' . string(F('e.md')[-4:]))
" 外から \l → g で入れる（別の空のグループ）も同じ形
execute 'edit ' . fnameescape($D . '/v/a.md')
let g:gnosis_test_display_name = ['E2-A']
let g:gnosis_test_yomi = ['えー']
call gnosis#index_add($D . '/v/a.md', $D . '/v/e2.md')
execute 'silent! edit ' . fnameescape($D . '/v/a.md')
unlet! g:gnosis_test_display_name g:gnosis_test_yomi
call add(g:R, 'empty-g ' . string(F('e2.md')[-4:]))

" 5) \l → m → o: 開いているノート（A）へ M をマージ。:GnosisMergeUndo で戻す
let g:gnosis_test_keys = ['m', 'o']
call gnosis#insert_links_pick(['[M](m.md)'], getpos('.'))
call add(g:R, 'merge ' . filereadable($D . '/v/m.md') . ' ' . Has('a.md', 'スマホのメモ') . ' ' . Has('x.md', '(m.md)') . ' ' . Has('x.md', '\[A\](a.md)'))
call add(g:R, 'buffer ' . (getline(1, '$') ==# F('a.md')))
let g:gnosis_test_keys = ['y']
call gnosis#merge#undo()
call add(g:R, 'undo ' . filereadable($D . '/v/m.md') . ' ' . Has('a.md', 'スマホのメモ') . ' ' . Has('x.md', '(m.md)'))
" s: 選んだノート（M）へ、開いているノート（B）をまとめる → M が開く
execute 'edit ' . fnameescape($D . '/v/b.md')
let g:gnosis_test_keys = ['m', 's']
call gnosis#insert_links_pick(['[M](m.md)'], getpos('.'))
call add(g:R, 'merge-s ' . filereadable($D . '/v/b.md') . ' ' . fnamemodify(bufname('%'), ':t') . ' ' . Has('m.md', '本文B'))
call writefile(g:R, $D . '/out.txt')
qa!
