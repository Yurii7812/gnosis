" 見出しを書き換えたら、その見出しへのリンクも直る
let s:out = []
function! s:ok(name, passed, ...) abort
  call add(s:out, (a:passed ? 'OK ' : 'NG ') . a:name . (a:passed || a:0 == 0 ? '' : ': ' . a:1))
endfunction
let s:v = $HL_VAULT
try
  execute 'edit ' . fnameescape(s:v . '/a.md')
  call setline(search('^## 古い見出し$', 'nw'), '## 新しい 見出し')
  silent write
  let s:b = readfile(s:v . '/b.md')
  call s:ok('表示名が「題#見出し」のリンクは、表示名もスラッグも直る', index(s:b, '[A#新しい 見出し](a.md#新しい-見出し)') >= 0, string(s:b))
  call s:ok('表示名が別の文字なら、スラッグだけ直る', index(s:b, '前に[見て](a.md#新しい-見出し)ね') >= 0, string(s:b))
  call s:ok('ほかの見出しへのリンクはそのまま', index(s:b, '[A#別](a.md#別)') >= 0, string(s:b))
  " 見出しを足しただけでは、ほかのリンクを変えない
  call append(search('^## 別$', 'nw'), ['', '## 足した'])
  silent write
  call s:ok('見出しを足しただけでは変えない', readfile(s:v . '/b.md') ==# s:b, string(readfile(s:v . '/b.md')))
catch
  call add(s:out, 'NG 例外: ' . v:exception . ' @ ' . v:throwpoint)
endtry
call writefile(s:out, $HL_RESULT)
qall!
