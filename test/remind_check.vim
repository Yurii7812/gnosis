set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
GnosisReminders
call assert_match('^# リマインダー', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "薬を飲む（今"')))
call assert_true(empty(filter(getline(1, '$'), 'v:val =~# "先の予定"')))   " 14 日より先は出さない
let s:id = matchstr(join(getline(1, '$'), "\n"), 'ID `\zs[0-9a-f]\{10}\ze`')
call assert_equal(10, len(s:id))
call cursor(match(getline(1, '$'), '薬を飲む') + 1, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/a.md', expand('%:p'))
GnosisRemindFire
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "薬を飲む（1 回目"')))
close
" 2 回目の Fire は再通知の間隔内なので何も出ない
GnosisRemindFire
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^なし$"')))
close
GnosisNotifyHistory
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "通知 — 薬を飲む"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "通知したのに未処理"')))
close
GnosisRemindSnooze xxxxxxxxxx 0
GnosisRemindSnooze xxxxxxxxxx
GnosisRemindAck nothing
GnosisRemindAck xxxxxxxxxx
execute 'GnosisRemindSnooze ' . s:id . ' 30'
GnosisReminders
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "スヌーズ中"')))
close
execute 'GnosisRemindAck ' . s:id
GnosisNotifyHistory
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "扱い済み — 薬を飲む"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^なし$"')))
close
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
