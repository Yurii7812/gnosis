" Gnosis Markdown 本文色と terminal focus 報告の安全性。
let s:out = []
function! s:ok(name, passed) abort
  call add(s:out, (a:passed ? 'OK ' : 'NG ') . a:name)
endfunction
function! s:stack(n, fragment) abort
  let l:line = getline(a:n)
  let l:at = match(l:line, '\V' . escape(a:fragment, '\')) + 1
  if l:at <= 0 | return [] | endif
  return map(synstack(a:n, l:at), 'synIDattr(v:val, "name")')
endfunction
function! s:has(n, fragment, expected) abort
  return index(s:stack(a:n, a:fragment), a:expected) >= 0
endfunction
try
  execute 'edit ' . fnameescape($FOCUS_MARKDOWN_VAULT . '/plain.md')
  setlocal filetype=markdown
  call gnosis#link_syntax()
  call s:ok('focus reporting explicitly enabled', &t_fe =~# '1004h' && &t_fd =~# '1004l')
  call s:ok('FocusLost escape recognized', execute('silent set <FocusLost>?') =~# 'O')
  call s:ok('FocusGained escape recognized', execute('silent set <FocusGained>?') =~# 'I')
  call s:ok('plain prose after lone backtick remains plain', !s:has(7, 'Ordinary prose', 'markdownCode') && !s:has(7, 'Ordinary prose', 'markdownItalic'))
  call s:ok('screenshot filename underscore is not italic', !s:has(8, '20261014', 'markdownItalic'))
  call s:ok('stray backtick does not highlight adjacent prose', !s:has(6, 'bash', 'markdownCode'))
  call s:ok('explicit italic retains emphasis', s:has(9, 'italic', 'markdownItalic'))
  call s:ok('explicit inline code retains code color', (s:has(10, 'code', 'markdownCode') || s:has(10, 'code', 'gnosisCodeInline')))
  call s:ok('headings keep heading syntax', s:has(5, 'Heading', 'markdownH1'))
  call s:ok('links keep link syntax', s:has(11, 'LinkName', 'gnosisLinkText'))
catch
  call add(s:out, 'NG exception: ' . v:exception . ' @ ' . v:throwpoint)
endtry
call writefile(s:out, $FOCUS_MARKDOWN_RESULT)
qall!
