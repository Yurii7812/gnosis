source <sfile>:h/preset_head.vim
let g:gnosis_root = $D . '/v/'
let g:gnosis_test_speed = 1
runtime plugin/gnosis.vim
doautocmd VimEnter
call assert_equal(5, g:gnosis_test_speed)                " 起動時に auto のプリセットが適用される
GnosisPreset auto off
let g:gnosis_test_speed = 1
call assert_equal(0, gnosis#preset_autoload())           " off にしたら適用されない
call assert_equal(1, g:gnosis_test_speed)
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
