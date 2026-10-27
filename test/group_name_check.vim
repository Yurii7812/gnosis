" zg: ノートが、グループの中でどう表示されているかを変える（test/group_name_net.sh から）。$D に vault（v/）を用意して呼ぶ
set nocp
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
let g:R = []
function! Body(f) abort
  return filter(readfile($D . '/v/' . a:f), 'v:val =~# ''^\[''')
endfunction
" 同期で a.md に Group: を書かせる
call system(gnosis#python_cmd() . ' ' . shellescape(g:gnosis_python) . ' update ' . shellescape($D . '/v'))
execute 'edit! ' . fnameescape($D . '/v/a.md')
call add(g:R, 'group: ' . string(filter(getline(1, '$'), 'v:val =~# "^\\["')))
" 1) 表示名が 1 つのグループ（h）: Group: のリンクの上で zg → そのまま入力
call cursor(search('^\[[^]]*\](h.md)', 'nw'), 1)
let g:gnosis_test_display_name = ['ひとつ目']
call gnosis#group_name_here()
call add(g:R, 'h ' . string(Body('h.md')))
" 2) 表示名が 2 つのグループ（g）: Group: のリンクの上で zg → どの表示名か選ぶ（2 番目）→ 改名
execute 'edit! ' . fnameescape($D . '/v/a.md')
call cursor(search('^\[[^]]*\](g.md)', 'nw'), 1)
let g:gnosis_test_keys = ['2']
let g:gnosis_test_display_name = ['改名']
call gnosis#group_name_here()
call add(g:R, 'g ' . string(Body('g.md')))
" 3) カーソルがリンクの上でなく、グループが複数: どのグループか選ぶ（h の番号を探して選ぶ）
execute 'edit! ' . fnameescape($D . '/v/a.md')
call cursor(1, 1)
let s:links = filter(getline(1, '$'), 'v:val =~# "^\\[.*\\](\\(g\\|h\\).md)"')
let s:hi = 0
for s:i in range(len(s:links))
  if s:links[s:i] =~# '(h.md)' | let s:hi = s:i | endif
endfor
let g:gnosis_test_keys = [string(s:hi + 1)]
let g:gnosis_test_display_name = ['選んだ']
call gnosis#group_name_here()
call add(g:R, 'pick ' . string(Body('h.md')))
" 4) グループに入っていないノート
execute 'edit! ' . fnameescape($D . '/v/lone.md')
call gnosis#group_name_here()
call add(g:R, 'lone ' . len(Body('g.md')))
call writefile(g:R, $D . '/out.txt')
qa!
