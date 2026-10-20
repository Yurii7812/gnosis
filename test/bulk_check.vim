set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
function! TestOp() abort
  call writefile(['changed'], $D . '/v/a.md')
  call writefile(['new'], $D . '/v/new.md')
  call delete($D . '/v/b.md')
endfunction
command! TestOp call TestOp()
let s:a = readfile($D . '/v/a.md')
execute 'edit ' . fnameescape($D . '/v/c.md')
" 聞かれて「戻す」を選ぶ → 何も変わらない
let g:gnosis_bulk_answer = 2
GnosisBulk TestOp
call assert_equal(s:a, readfile($D . '/v/a.md'))
call assert_true(filereadable($D . '/v/b.md'))
call assert_false(filereadable($D . '/v/new.md'))
" 「残す」を選ぶ → 変更が残り、記録が増える
let g:gnosis_bulk_answer = 1
GnosisBulk TestOp
call assert_equal(['changed'], readfile($D . '/v/a.md'))
call assert_false(filereadable($D . '/v/b.md'))
" あとから戻す
GnosisBulkUndo
call assert_equal(s:a, readfile($D . '/v/a.md'))
call assert_true(filereadable($D . '/v/b.md'))
call assert_false(filereadable($D . '/v/new.md'))
GnosisBulkUndo                                          " 二度目は何も起きない(エラーを出すだけ)
" ! で聞かずに残す → 手で変えると戻さない → ! で上書き
unlet g:gnosis_bulk_answer
GnosisBulk! TestOp
call writefile(['手で変えた'], $D . '/v/a.md')
GnosisBulkUndo
call assert_equal(['手で変えた'], readfile($D . '/v/a.md'))
GnosisBulkUndo!
call assert_equal(s:a, readfile($D . '/v/a.md'))
" 変更が無いコマンド・未保存の編集・引数なし
let g:gnosis_bulk_answer = 2
GnosisBulk echo 1
set modified
GnosisBulk TestOp
call assert_equal(s:a, readfile($D . '/v/a.md'))       " 未保存のときは実行しない
set nomodified
GnosisBulkList
call assert_equal('# 一括変更の記録', getline(1))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
