set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
function! s:count() abort
  return len(glob($D . '/v/.gnosis/versions/*/*.md', 0, 1))
endfunction
execute 'edit ' . fnameescape($D . '/v/a.md')
" 自動保存は既定で無効(保存しても版は増えない)
call setline(line('$'), '途中')
write
call assert_equal(0, s:count())
GnosisVersions save
call assert_equal(1, s:count())
GnosisVersions save
call assert_equal(1, s:count())                      " 同じ内容は足さない
" 内容を変えて保存 → 差分 → 戻す
call setline(line('$'), '最後')
write
GnosisVersions diff 1
call assert_true(!empty(filter(getline(1, '$'), 'v:val ==# "-途中"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val ==# "+最後"')))
close
" 未保存の編集があるときは戻さない
call setline(line('$'), '書きかけ')
GnosisVersions restore 1
call assert_equal('書きかけ', getline('$'))
write
GnosisVersions restore 1
call assert_equal('途中', getline('$'))
call assert_equal('途中', readfile($D . '/v/a.md')[-1])
call assert_equal(2, s:count())                      " 戻す前の内容(書きかけ)が残った
" 戻しすぎても戻せる: 版 1 は書きかけ
GnosisVersions restore 1
call assert_equal('書きかけ', readfile($D . '/v/a.md')[-1])
" 存在しない番号・引数なし
GnosisVersions restore 99
call assert_equal('書きかけ', readfile($D . '/v/a.md')[-1])
GnosisVersions restore
GnosisVersions bogus
" 一覧
GnosisVersions
call assert_equal('# 版の履歴: a.md', getline(1))
close
" 自動保存を有効にすると、保存のたびに版が増える
let g:gnosis_auto_versions = 1
let s:before = s:count()
call setline(line('$'), '最初')
write
call assert_equal(s:before + 1, s:count())
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
