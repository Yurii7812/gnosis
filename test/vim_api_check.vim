" 公開API(gnosis#*)の一覧を書き出す。分割リファクタの回帰網。
" 使い方: test/run.sh
" 出力先は g:gnosis_api_out（既定 /tmp/gnosis_api.txt）。
set nomore
" autoload は遅延読み込みなので、一覧の前に全部読む
runtime! autoload/gnosis.vim autoload/gnosis/*.vim autoload/gnosis_search.vim
redir => s:out
silent function /^gnosis\(_search\)\?#
redir END
let s:names = []
for s:l in split(s:out, "\n")
  let s:m = matchstr(s:l, 'gnosis\(_search\)\?#[A-Za-z0-9_#]*')
  if s:m != '' && s:m !~ '#$'
    call add(s:names, s:m)
  endif
endfor
call sort(s:names)
call writefile(s:names, get(g:, 'gnosis_api_out', '/tmp/gnosis_api.txt'))
