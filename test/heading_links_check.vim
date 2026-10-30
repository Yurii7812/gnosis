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
  " zo が slug だけで呼ばれても、実際の見出しを表示名に付ける。
  execute 'edit ' . fnameescape(s:v . '/c.md')
  let s:link_line = search('^\[A\](a\.md)$', 'nw')
  call s:ok('zo のテスト用リンクが見つかる', s:link_line > 0, string(getline(1, '$')))
  if s:link_line > 0
    call cursor(s:link_line, 3)
    call gnosis#link_to_outline('新しい-見出し')
    let s:expected = '[A#新しい 見出し](a.md#新しい-見出し)'
    call s:ok('zo: 見出しをリンク先と表示名の両方に反映', getline(s:link_line) ==# s:expected, getline(s:link_line))
    silent write
    call s:ok('zo: 保存後も表示名に見出しが残る', index(readfile(s:v . '/c.md'), s:expected) >= 0, string(readfile(s:v . '/c.md')))
  endif
catch
  call add(s:out, 'NG 例外: ' . v:exception . ' @ ' . v:throwpoint)
endtry
call writefile(s:out, $HL_RESULT)
qall!
