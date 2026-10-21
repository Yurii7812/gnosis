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
" 1) za（複数）→ 確認画面は出さず、1 本ずつ表示名とよみを聞いて入れ、よみの順に並ぶ
"    筋トレ: 表示名はそのまま（空 Enter）・よみを「きんとれ」に / アヒル: 表示名「あひる」・よみは Esc（登録しない）
call setreg('"', "[筋トレ](k.md)\n[アヒル](a.md)\n")
let g:gnosis_test_display_name = ['', 'あひる']
let g:gnosis_test_yomi = ['きんとれ', "\x1b"]
call gnosis#add_clipboard_before_up_note()
call add(g:R, 'screen1 ' . WaitScreen(1))
unlet g:gnosis_test_display_name g:gnosis_test_yomi
call add(g:R, 'after1 ' . string(Members()))
call add(g:R, 'yomi ' . string(filter(readfile($D . '/v/k.md'), 'v:val =~# "きんとれ"')) . ' ' . len(filter(readfile($D . '/v/a.md'), 'v:val =~# "yomi"')))
" Esc で取り消すと何も入らない
call setreg('"', "[ウシ](u.md)\n")
let g:gnosis_test_display_name = ["\x1b"]
call gnosis#add_clipboard_before_up_note()
unlet g:gnosis_test_display_name
call add(g:R, 'cancel ' . string(Members()))
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
" 4) vault の外のファイルへのリンクを入れても、そのファイルにはよみを書かない（2026-10-21 の事故の再発防止）
call writefile(['# 外のファイル', '', '本文'], $D . '/outside.md')
call setreg('"', "[外のファイル](../outside.md)\n")
let g:gnosis_test_display_name = ['']
let g:gnosis_test_yomi = ['そと']
call gnosis#add_clipboard_before_up_note()
unlet g:gnosis_test_display_name g:gnosis_test_yomi
call WaitScreen(0)
call add(g:R, 'outside ' . string(readfile($D . '/outside.md')))
call writefile(g:R, $D . '/out.txt')
qa!
