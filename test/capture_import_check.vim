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
qa!
