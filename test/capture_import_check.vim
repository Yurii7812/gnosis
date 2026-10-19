" test/capture_import_net.sh から使う
set nocp
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
call gnosis#create_vault_files($D . '/v')
let g:gnosis_test_capture_password = 'PW123'
call gnosis#capture_import($D . '/gnosis-capture-test.7z')
call gnosis#capture_import($D . '/gnosis-capture-test.7z')
qa!
