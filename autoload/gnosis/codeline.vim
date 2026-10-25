" ``` / ~~~ で囲んだコードブロックの行を、文字の部分だけでなく行全体（右端まで）うす灰色にする。
" Vim の構文ハイライトは文字の長さの分しか塗れないので、サイン（sign）の linehl で行ごとに塗る。
" サインの欄（signcolumn）は文字が無いので出ない。ファイルの中身は変えない。

let s:group = 'gnosis_code'

function! s:define() abort
  if empty(sign_getdefined('GnosisCodeLine'))
    call sign_define('GnosisCodeLine', {'linehl': 'GnosisCodeLine'})
  endif
  " どの配色でも見えるように（colors/gnosis.vim が定義していれば、そちらが先）
  silent! highlight default link GnosisCodeLine ColorColumn
endfunction

" コードブロックの行番号（囲みの行を含む）。閉じていないときは最後まで
function! gnosis#codeline#lines(lines) abort
  let l:out = []
  let l:in = 0
  let l:n = 0
  for l:ln in a:lines
    let l:n += 1
    if l:ln =~# '^\s*\(```\|\~\~\~\)'
      call add(l:out, l:n)
      let l:in = !l:in
    elseif l:in
      call add(l:out, l:n)
    endif
  endfor
  return l:out
endfunction

function! gnosis#codeline#update() abort
  if (&filetype !=# 'markdown' && &filetype !=# 'vimwiki') || &buftype !=# '' || !has('signs')
    return
  endif
  call s:define()
  let l:lines = gnosis#codeline#lines(getline(1, '$'))
  let l:key = join(l:lines, ',')
  if l:key ==# get(b:, 'gnosis_codeline_key', 'x')
    return
  endif
  let b:gnosis_codeline_key = l:key
  let l:buf = bufnr('%')
  call sign_unplace(s:group, {'buffer': l:buf})
  if len(l:lines) > 20000
    return
  endif
  call sign_placelist(map(l:lines, {_, n -> {'id': 0, 'group': s:group, 'name': 'GnosisCodeLine', 'buffer': l:buf, 'lnum': n, 'priority': 5}}))
endfunction
