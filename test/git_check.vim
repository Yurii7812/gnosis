set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
GnosisGit status
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^# Git の状態（main）"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "変更: \\[a.md\\]"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "未追跡: \\[new.md\\]"')))
call cursor(match(getline(1, '$'), '\[a.md\]') + 1, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/a.md', expand('%:p'))
" ノートを開いていれば diff は今のノート
GnosisGit diff
call assert_true(!empty(filter(getline(1, '$'), 'v:val ==# "+二行目"')))
close
GnosisGit log
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "初回"')))
close
GnosisGit show a.md HEAD
call assert_true(empty(filter(getline(1, '$'), 'v:val =~# "二行目"')))       " HEAD の版にはまだ無い
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "一行目"')))
close
" 危険な引数・不正な指定は表示だけで画面を開かない
let s:w = winnr('$')
GnosisGit diff ../x
GnosisGit show a.md --help
GnosisGit bogus
GnosisGit commit
call assert_equal(s:w, winnr('$'))
" 派生データは作っても含まれない。メッセージつきでコミット
call mkdir($D . '/v/.state', 'p')
call writefile(['{}'], $D . '/v/.state/h.json')
GnosisGit commit 二行目と新規
GnosisGit status
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "変更はありません"')))
close
" リポジトリでない vault では何もしない
let g:gnosis_root = $D . '/plain/'
let s:w = winnr('$')
GnosisGit status
GnosisGit commit だめ
call assert_equal(s:w, winnr('$'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
