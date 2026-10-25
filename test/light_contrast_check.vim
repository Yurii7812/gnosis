" ライト（と、ついでにダーク）で、曼荼羅などの色の文字が背景の上で読める（コントラスト比 4.5 以上）こと。
" 結果は $LC_OUT に OK / NG で書く（test/light_contrast_net.sh から）
set nomore
let s:res = []
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_mview_restore = 0
let s:v = $LC_VAULT
let g:gnosis_root = s:v . '/'

function! s:audit(label) abort
  let l:nb = synIDattr(hlID('Normal'), 'bg#')
  let l:bad = []
  for l:l in split(execute('highlight'), "\n")
    let l:n = matchstr(l:l, '^\S\+')
    " 見せるための文字ではないもの（空行の ~ など）・カーソルそのもの・9×9 の背景だけのグループは見ない
    if l:n =~# '^\(NonText\|EndOfBuffer\|SpecialKey\|VertSplit\|Ignore\|Cursor\|lCursor\|Conceal\|GnosisMvBg\|GnosisMvCBg\)'
      continue
    endif
    let l:id = synIDtrans(hlID(l:n))
    let l:fg = synIDattr(l:id, 'fg#')
    if empty(l:fg) | continue | endif
    let l:bg = synIDattr(l:id, 'bg#')
    let l:b = empty(l:bg) ? l:nb : l:bg
    let l:c = gnosis#color#contrast(l:fg, l:b)
    " コメントなど、控えめにする目的の文字は 3 以上、ほかは 4.5 以上
    let l:min = l:n =~# '^\(Comment\|LineNr\|Folded\|markdownBlockquote\|markdownListMarker\|markdownOrderedListMarker\|markdownHeadingDelimiter\|markdown.*Delimiter\|markdownUrl\|markdownId\|markdownRule\|markdownCodeDelimiter\|GnosisStartDim\|GnosisSettingsDim\)' ? 3.0 : 4.5
    if l:c < l:min
      call add(l:bad, printf('%s fg=%s bg=%s %.2f', l:n, l:fg, l:b, l:c))
    endif
  endfor
  call add(s:res, (empty(l:bad) ? 'OK ' : 'NG ') . a:label . ': 色の文字が背景の上で読める' . (empty(l:bad) ? '' : ': ' . join(l:bad[:8], ' / ')))
endfunction

for s:ap in ['light', 'dark']
  call gnosis#settings#set('appearance', s:ap)
  call gnosis#theme#apply(gnosis#settings#current())
  execute 'edit ' . s:v . '/a.md'
  call feedkeys(' ', 'xt')
  call s:audit(s:ap)
  call feedkeys('Q', 'xt')
endfor
call writefile(s:res, $LC_OUT)
qa!
