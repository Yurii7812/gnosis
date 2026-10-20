set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
call gnosis#think_new('swot', '新事業')
call assert_true(index(getline(1, '$'), 'thinking: swot') >= 0)
call assert_true(index(getline(1, '$'), '## 強み（内部・良い）') >= 0)
call assert_true(index(getline(1, '$'), 'title: 新事業') >= 0)
let s:f = expand('%:p')
call gnosis#think_check()
let s:r = getline(1, '$')
call assert_match('^思考法: swot', s:r[0])
call assert_true(!empty(filter(copy(s:r), 'v:val =~# "まだ空の節"')))
close
" 4 象限を埋めて保存 → 『打ち手』を促す
let s:t = readfile(s:f)
for s:sec in ['強み（内部・良い）', '弱み（内部・悪い）', '機会（外部・良い）', '脅威（外部・悪い）']
  let s:at = index(s:t, '## ' . s:sec)
  let s:t[s:at + 2] = '- 項目'
endfor
call writefile(s:t, s:f)
execute 'edit! ' . fnameescape(s:f)
call gnosis#think_check()
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "打ち手"')))
close
" 種類の誤りは作らない・ふつうのノートには「思考法ではない」
let s:n = len(glob($D . '/v/*.md', 0, 1))
call gnosis#think_new('nope', 'x')
call assert_equal(s:n, len(glob($D . '/v/*.md', 0, 1)))
execute 'edit ' . fnameescape($D . '/v/plain.md')
call gnosis#think_check()
call assert_equal(s:n, len(glob($D . '/v/*.md', 0, 1)))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
