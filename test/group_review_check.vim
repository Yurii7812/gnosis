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
" 一覧画面（ポップアップ）は、キーを読み切るまで開いている。g:gnosis_test_keys が空になり、書き込みが済むのを待つ
function! WaitKeys() abort
  for l:i in range(80)
    if empty(get(g:, 'gnosis_test_keys', [])) | break | endif
    sleep 100m
  endfor
  sleep 400m
  return empty(get(g:, 'gnosis_test_keys', []))
endfunction
execute 'edit ' . fnameescape(s:g)
" 1) za（複数）→ 確認画面は出さず、1 本ずつ表示名とよみを聞いて入れ、よみの順に並ぶ
"    筋トレ: 表示名はそのまま（空 Enter）・よみを「きんとれ」に / アヒル: 表示名「あひる」・よみは Esc（登録しない）
call setreg('"', "[筋トレ](k.md)\n[アヒル](a.md)\n")
let g:gnosis_test_display_name = ['', 'あひる']
let g:gnosis_test_yomi = ['きんとれ']
let g:gnosis_test_keys = ["\<CR>", "\<CR>"]
call gnosis#add_clipboard_before_up_note()
call add(g:R, 'list1 ' . WaitKeys())
unlet g:gnosis_test_display_name g:gnosis_test_yomi
call add(g:R, 'after1 ' . string(Members()))
" よみはノートの YAML ではなく vault の .gnosis/yomi/（JSON Lines）に入る
call add(g:R, 'yomi ' . string(filter(systemlist('cat ' . shellescape($D . '/v/.gnosis/yomi') . '/*.jsonl 2>/dev/null'), 'v:val =~# "きんとれ"')) . ' ' . len(filter(readfile($D . '/v/a.md'), 'v:val =~# "yomi"')))
" Esc で取り消すと何も入らない
call setreg('"', "[ウシ](u.md)\n")
let g:gnosis_test_display_name = ["\x1b"]
call gnosis#add_clipboard_before_up_note()
unlet g:gnosis_test_display_name
call add(g:R, 'cancel ' . string(Members()))
" 2) 手で貼って保存 → 確認画面（今回足した 2 本だけ）→ ゼブラの行を消して q（グループから外れる）
call append(line('$'), ['[ゼブラ](z.md)', '[ウシ](u.md)'])
let g:gnosis_test_keys = ["\x01goto:ゼブラ", 'd', 'A']
write
call add(g:R, 'list2 ' . WaitKeys())
call add(g:R, 'after2 ' . string(Members()))
" 3) :GnosisYomiReview（全員）→ Q（保存せず並べる）→ グループに戻る
let g:gnosis_test_keys = ['q']
GnosisYomiReview
call add(g:R, 'list3 ' . WaitKeys())
call add(g:R, 'back ' . fnamemodify(bufname('%'), ':t'))
" 4) vault の外のファイルへのリンクを入れても、そのファイルにはよみを書かない（2026-10-21 の事故の再発防止）
call writefile(['# 外のファイル', '', '本文'], $D . '/outside.md')
call setreg('"', "[外のファイル](../outside.md)\n")
let g:gnosis_test_display_name = ['']
let g:gnosis_test_yomi = ['そと']
call gnosis#add_clipboard_before_up_note()
unlet g:gnosis_test_display_name g:gnosis_test_yomi
call add(g:R, 'outside ' . string(readfile($D . '/outside.md')))
" 5) 自動で入るメンバー（操作ガイド・時系列記録の木）は、名前もよみも聞かない（一覧に出さない）
call writefile(['---', 'time: 2026-01-01 00:00:00', '---', '', '# Gnosis 操作ガイド', '', '本文'], $D . '/v/gnosis-guide.md')
call writefile(['---', 'time: 2026-01-01 00:00:00', 'timeline: true', '---', '', '# 時系列記録', '', '本文'], $D . '/v/tl.md')
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 自動', 'attribute: group', '---', '', '# 自動', ''], $D . '/v/g2.md')
execute 'edit! ' . fnameescape($D . '/v/g2.md')
call append(line('$'), ['[Gnosis 操作ガイド](gnosis-guide.md)', '[時系列記録](tl.md)'])
let g:gnosis_test_keys = ['q']
write
call add(g:R, 'auto ' . WaitKeys() . ' keys=' . string(g:gnosis_test_keys))
call writefile(g:R, $D . '/out.txt')
qa!
