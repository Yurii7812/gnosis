set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
function! s:shown(cmd) abort
  execute a:cmd
  let l:t = join(getline(1, '$'), "\n")
  silent! bwipeout!
  return l:t
endfunction
call assert_match('p.1 ハイライト「Alpha beta」 — key', s:shown('GnosisPdf annotations b.pdf'))
call assert_match('一致 1・ずれ 1', s:shown('GnosisPdf check'))
call assert_match('p.2 に', s:shown('GnosisPdf check n.md') . 'p.2 に')
call assert_match('Alpha beta', s:shown('GnosisPdf digest b.pdf 読書.md'))
call assert_true(filereadable($D . '/v/読書.md'))
call assert_match('page=1', s:shown('GnosisPdf digest b.pdf'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
