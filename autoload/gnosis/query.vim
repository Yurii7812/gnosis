" =============================================================================
" autoload/gnosis/query.vim — 検索の書き方（gs・s・m・x で共通）。Python 側は python/search_query.py（同じ規則）。
"
"   AND   空白（半角・全角・タブ）                 ハーブ 栽培
"   NOT   語の先頭の -（直後に文字が続くとき）      ハーブ -メモ        … `-` だけ・`a-b` の途中の - は、ふつうの文字
"   OR    前後に空白のある |                        ハーブ | バジル      … AND より弱い: `a b | c` は (a かつ b) または c
"   句    "…" で囲む（中の空白も含めて 1 つの語）    "育て 方"           … NOT は -"育て 方"。閉じていない " は最後まで
"   文字  \ の次の 1 文字をそのまま                 \-foo  \|  \"       … 先頭の - や | を探したいときは、これか "…" で囲む
" 大文字小文字・全角半角はそろえて照らす（match）。何も入っていない（空）ときは「全部」に合う。
" =============================================================================

" 戻り値: [{'pos': [語, …], 'neg': [語, …]}, …]（OR で分けた組。空なら []）
function! gnosis#query#parse(q) abort
  let l:chars = split(a:q, '\zs')
  let l:n = len(l:chars)
  let l:groups = [{'pos': [], 'neg': []}]
  let l:i = 0
  while l:i < l:n
    if l:chars[l:i] =~# '^[ \t\n　]$'
      let l:i += 1
      continue
    endif
    let l:neg = 0
    let l:start = l:i
    let l:buf = ''
    let l:quoted = 0
    if l:chars[l:i] ==# '-' && l:i + 1 < l:n && l:chars[l:i + 1] !~# '^[ \t\n　]$'
      let l:neg = 1
      let l:i += 1
    endif
    while l:i < l:n && (l:quoted || l:chars[l:i] !~# '^[ \t\n　]$')
      let l:c = l:chars[l:i]
      if l:c ==# '\' && l:i + 1 < l:n
        let l:buf .= l:chars[l:i + 1]
        let l:i += 2
        continue
      endif
      if l:c ==# '"'
        let l:quoted = !l:quoted
        let l:i += 1
        continue
      endif
      let l:buf .= l:c
      let l:i += 1
    endwhile
    let l:raw = join(l:chars[l:start : l:i - 1], '')
    if l:raw ==# '|'
      if !empty(l:groups[-1].pos) || !empty(l:groups[-1].neg)
        call add(l:groups, {'pos': [], 'neg': []})
      endif
    elseif l:buf !=# '' || l:neg
      if l:neg && l:buf ==# ''
        call add(l:groups[-1].pos, '-')
      elseif l:neg
        call add(l:groups[-1].neg, l:buf)
      else
        call add(l:groups[-1].pos, l:buf)
      endif
    endif
  endwhile
  return filter(l:groups, '!empty(v:val.pos) || !empty(v:val.neg)')
endfunction

" 照らす文字をそろえる（大文字小文字・全角半角の英数・カタカナ→ひらがな）
function! gnosis#query#normalize(s) abort
  let l:s = tolower(a:s)
  " 全角の英数字・記号 → 半角（U+FF01〜FF5E）
  let l:s = substitute(l:s, '[！-～]', '\=nr2char(char2nr(submatch(0)) - 0xFEE0)', 'g')
  " カタカナ → ひらがな（ァ〜ヶ）
  let l:s = substitute(l:s, '[ァ-ヶ]', '\=nr2char(char2nr(submatch(0)) - 0x60)', 'g')
  return tolower(l:s)
endfunction

" 色をつける語（肯定の語だけ。重複なし・書いた順）
function! gnosis#query#terms(q) abort
  let l:out = []
  for l:g in gnosis#query#parse(a:q)
    for l:w in l:g.pos
      if index(l:out, l:w) < 0 | call add(l:out, l:w) | endif
    endfor
  endfor
  return l:out
endfunction

" text が検索に合うか（空の検索は合う）。groups は gnosis#query#parse の戻り値を渡すと、何度も解析しない
function! gnosis#query#match(q_or_groups, text) abort
  let l:gs = type(a:q_or_groups) == v:t_list ? a:q_or_groups : gnosis#query#parse(a:q_or_groups)
  if empty(l:gs)
    return 1
  endif
  let l:t = gnosis#query#normalize(a:text)
  for l:g in l:gs
    let l:ok = 1
    for l:w in l:g.pos
      if stridx(l:t, gnosis#query#normalize(l:w)) < 0 | let l:ok = 0 | break | endif
    endfor
    if l:ok
      for l:w in l:g.neg
        if stridx(l:t, gnosis#query#normalize(l:w)) >= 0 | let l:ok = 0 | break | endif
      endfor
    endif
    if l:ok | return 1 | endif
  endfor
  return 0
endfunction
