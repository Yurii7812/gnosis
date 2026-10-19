" test/capture_import_net.sh から使う
set nocp
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
call gnosis#create_vault_files($D . '/v')
call gnosis#capture_import($D . '/pack/capture.json')
call gnosis#capture_import($D . '/pack')
" PC でその日の夢の記録に書いた分（07:30）
for s:f in glob($D . '/v/*.md', 0, 1)
  let s:l = readfile(s:f)
  if index(s:l, 'title: 2026-10-18-SU-夢') >= 0
    call insert(s:l, '07:30 PCで書いた', index(s:l, '07:10 海の夢') + 1)
    call insert(s:l, '', index(s:l, '07:10 海の夢') + 1)
    call writefile(s:l, s:f)
  endif
endfor
call gnosis#capture_import($D . '/pack2')
qa!
