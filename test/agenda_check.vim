set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
call gnosis#agenda('2026-10-20')
let s:all = getline(1, '$')
call assert_equal('# Agenda 2026-10-20', s:all[0])
call assert_true(index(s:all, '## 期限切れ (1)') >= 0)
call assert_true(index(s:all, '## 今日 (1)') >= 0)
call assert_true(index(s:all, '## 期限なし (1)') >= 0)
call assert_equal(0, len(filter(copy(s:all), 'v:val =~# "コード内"')))
" 今日の「毎週の掃除」で x → 完了し、次の回(10-27)が a.md に入る。画面は読み直される
call cursor(index(s:all, '## 今日 (1)') + 2, 1)
call assert_match('毎週の掃除', getline('.'))
execute "normal x"
let s:a = readfile($D . '/v/a.md')
call assert_true(index(s:a, '- [x] 毎週の掃除 📅 2026-10-20 🔁 weekly ✅ 2026-10-20') >= 0)
call assert_true(index(s:a, '- [ ] 毎週の掃除 📅 2026-10-27 🔁 weekly') >= 0)
call assert_true(index(s:a, '- [ ] コード内') >= 0)
call assert_equal(0, len(filter(getline(1, '$'), 'v:val =~# "今日 ("')))
" Enter でそのタスクの行へ移る
call cursor(index(getline(1, '$'), '## 期限切れ (1)') + 2, 1)
call assert_match('過去の提出', getline('.'))
execute "normal \<CR>"
call assert_equal($D . '/v/a.md', expand('%:p'))
call assert_match('過去の提出', getline('.'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
