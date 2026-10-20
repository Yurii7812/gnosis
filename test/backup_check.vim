set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
" vault の中への出力は拒否される
call gnosis#backup($D . '/v/inside')
call assert_false(isdirectory($D . '/v/inside'))
" 外へバックアップ（検証つき）
call gnosis#backup($D . '/bkout')
let s:ar = glob($D . '/bkout/*.tar.gz', 0, 1)
call assert_equal(1, len(s:ar))
call assert_true(filereadable(substitute(s:ar[0], '\.tar\.gz$', '.manifest.json', '')))
" 検証 OK
redir => s:m
silent call gnosis#backup_verify(s:ar[0])
redir END
call assert_match('検証 OK', s:m)
" 一覧
call gnosis#backup_list($D . '/bkout')
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# fnamemodify(s:ar[0], ":t")')))
close
" 復元: 新しいフォルダへ。空でないフォルダへは復元しない
call gnosis#backup_restore(s:ar[0], $D . '/restored')
call mkdir($D . '/occupied', 'p')
call writefile(['keep'], $D . '/occupied/keep.txt')
call gnosis#backup_restore(s:ar[0], $D . '/occupied')
" 壊したバックアップは検証 NG になり、復元されない
call system('cp ' . shellescape(s:ar[0]) . ' ' . shellescape($D . '/broken.tar.gz'))
call system('cp ' . shellescape(substitute(s:ar[0], '\.tar\.gz$', '.manifest.json', '')) . ' ' . shellescape($D . '/broken.manifest.json'))
call system('python3 ' . shellescape($REPO . '/test/corrupt_file.py') . ' ' . shellescape($D . '/broken.tar.gz'))
call system('cmp -s ' . shellescape(s:ar[0]) . ' ' . shellescape($D . '/broken.tar.gz'))
call assert_notequal(0, v:shell_error)   " 実際に壊れている
redir => s:bv
silent call gnosis#backup_verify($D . '/broken.tar.gz')
redir END
call assert_match('検証 NG', s:bv)
call gnosis#backup_restore($D . '/broken.tar.gz', $D . '/never')
call assert_false(isdirectory($D . '/never'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
