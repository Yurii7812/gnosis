" test/group_review_net.sh から使う。$D に vault（v/）を用意して呼ぶ。
set nocp
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
let g:R = []
let s:g = $D . '/v/g.md'
function! Members() abort
  return filter(readfile(s:g), 'v:val =~# ''^\[''')
endfunction
function! OnScreen() abort
  return fnamemodify(bufname('%'), ':t') =~# '^review-'
endfunction
function! WaitScreen(want) abort
  for l:i in range(60)
    if OnScreen() == a:want | return 1 | endif
    sleep 100m
  endfor
  return 0
endfunction
execute 'edit ' . fnameescape(s:g)
" 1) za（複数）→ 確認画面（未登録はすべて「（推測）」）→ 筋トレのよみを直して q
call setreg('"', "[筋トレ](k.md)\n[アヒル](a.md)\n")
call gnosis#add_clipboard_before_up_note()
call add(g:R, 'screen1 ' . WaitScreen(1))
call add(g:R, 'guess ' . (search('筋トレ.*すじとれ（推測）') > 0))
" Enter で中身を見て、<BS> で戻ると画面はそのまま（q も効く）
call cursor(search('筋トレ'), 2)
call gnosis#open_link_under_cursor()
sleep 300m
call add(g:R, 'enter ' . fnamemodify(bufname('%'), ':t'))
call gnosis#go_back()
sleep 300m
call add(g:R, 'back ' . OnScreen() . ' ' . (maparg('q', 'n') =~# 'review_commit'))
let s:n = search('筋トレ')
call setline(s:n, substitute(getline(s:n), '— .*$', '— きんとれ', ''))
call gnosis#review_commit()
call WaitScreen(0)
call add(g:R, 'after1 ' . string(Members()))
call add(g:R, 'yomi ' . string(filter(readfile($D . '/v/k.md'), 'v:val =~# "きんとれ"')))
" 2) 手で貼って保存 → 確認画面（今回足した 2 本だけ）→ ゼブラの行を消して q（グループから外れる）
call append(line('$'), ['[ゼブラ](z.md)', '[ウシ](u.md)'])
write
call add(g:R, 'screen2 ' . WaitScreen(1) . ' n=' . len(filter(getline(1, '$'), 'v:val =~# ''^\['''))) 
execute search('ゼブラ') . 'delete'
call gnosis#review_commit()
call WaitScreen(0)
call add(g:R, 'after2 ' . string(Members()))
" 3) :GnosisYomiReview（全員）→ Q（保存せず並べる）→ グループに戻る
GnosisYomiReview
call add(g:R, 'screen3 ' . WaitScreen(1) . ' n=' . len(filter(getline(1, '$'), 'v:val =~# ''^\['''))) 
call gnosis#review_skip()
call WaitScreen(0)
call add(g:R, 'back ' . fnamemodify(bufname('%'), ':t'))
call writefile(g:R, $D . '/out.txt')
qa!
