set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
call gnosis#check_vault()
let s:t = getline(1, '$')
call assert_true(index(s:t, '## 壊れたリンク (1)') >= 0)
call assert_true(index(s:t, 'a.md → nowhere.md  [link]') >= 0)
call assert_true(index(s:t, '## Folgezettel: 重複した番号 (1)') >= 0)
call assert_true(index(s:t, '## Folgezettel: 抜けている親の番号 (2)') >= 0)
call assert_true(index(s:t, '5 5a') >= 0)
call assert_true(index(s:t, '## 孤立したノート（関係が1本も無い） (2)') >= 0)
call assert_true(index(s:t, 'e.md') >= 0)
call cursor(index(s:t, 'e.md') + 1, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/e.md', expand('%:p'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
