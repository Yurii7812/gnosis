" Gnosis の組み込み配色。色は g:gnosis_palette（gnosis#theme が設定）から取る。
"   bg 背景 / fg 本文 / link リンク / heading 見出し / selection 選択範囲 / cursorline カーソル行
" g:gnosis_palette が無いときは &background に合わせた組み込みの色。
highlight clear
if exists('syntax_on')
  syntax reset
endif
let g:colors_name = 'gnosis'

if exists('g:gnosis_palette') && type(g:gnosis_palette) == v:t_dict && has_key(g:gnosis_palette, 'bg')
  let s:p = g:gnosis_palette
else
  let s:p = get(gnosis#settings#builtin_palettes(), &background ==# 'dark' ? 'dark' : 'light')
endif

function! s:mix(a, b, t) abort
  let l:out = '#'
  for l:i in [1, 3, 5]
    let l:x = str2nr(a:a[l:i : l:i + 1], 16)
    let l:y = str2nr(a:b[l:i : l:i + 1], 16)
    let l:out .= printf('%02x', float2nr(l:x + (l:y - l:x) * a:t + 0.5))
  endfor
  return l:out
endfunction

let s:bg = s:p.bg
let s:fg = s:p.fg
let s:dim = s:mix(s:fg, s:bg, 0.45)
let s:line = s:mix(s:fg, s:bg, 0.85)
let s:panel = s:mix(s:fg, s:bg, 0.93)

function! s:hl(group, fg, bg, attr) abort
  let l:cmd = 'highlight ' . a:group
  if !empty(a:fg)
    let l:cmd .= ' guifg=' . a:fg . ' ctermfg=' . gnosis#theme#to_cterm(a:fg)
  else
    let l:cmd .= ' guifg=NONE ctermfg=NONE'
  endif
  if !empty(a:bg)
    let l:cmd .= ' guibg=' . a:bg . ' ctermbg=' . gnosis#theme#to_cterm(a:bg)
  else
    let l:cmd .= ' guibg=NONE ctermbg=NONE'
  endif
  let l:a = empty(a:attr) ? 'NONE' : a:attr
  let l:cmd .= ' gui=' . l:a . ' cterm=' . l:a . ' term=' . l:a
  execute l:cmd
endfunction

call s:hl('Normal', s:fg, s:bg, '')
call s:hl('NonText', s:line, '', '')
call s:hl('EndOfBuffer', s:bg, '', '')
call s:hl('LineNr', s:dim, '', '')
call s:hl('CursorLineNr', s:fg, s:p.cursorline, 'bold')
call s:hl('CursorLine', '', s:p.cursorline, '')
call s:hl('CursorColumn', '', s:p.cursorline, '')
call s:hl('ColorColumn', '', s:panel, '')
call s:hl('Visual', '', s:p.selection, '')
call s:hl('VisualNOS', '', s:p.selection, '')
call s:hl('Search', s:fg, s:mix('#f5c400', s:bg, 0.45), '')
call s:hl('IncSearch', s:bg, s:p.link, '')
call s:hl('CurSearch', s:bg, s:p.link, '')
call s:hl('MatchParen', s:fg, s:p.selection, 'bold')
call s:hl('StatusLine', s:fg, s:panel, 'bold')
call s:hl('StatusLineNC', s:dim, s:panel, '')
call s:hl('StatusLineTerm', s:fg, s:panel, 'bold')
call s:hl('StatusLineTermNC', s:dim, s:panel, '')
call s:hl('VertSplit', s:line, s:bg, '')
call s:hl('TabLine', s:dim, s:panel, '')
call s:hl('TabLineFill', '', s:panel, '')
call s:hl('TabLineSel', s:fg, s:bg, 'bold')
call s:hl('Pmenu', s:fg, s:panel, '')
call s:hl('PmenuSel', s:bg, s:p.link, '')
call s:hl('PmenuSbar', '', s:line, '')
call s:hl('PmenuThumb', '', s:dim, '')
call s:hl('Folded', s:dim, s:panel, '')
call s:hl('FoldColumn', s:dim, s:bg, '')
call s:hl('SignColumn', s:dim, s:bg, '')
call s:hl('Conceal', s:dim, '', '')
call s:hl('SpecialKey', s:line, '', '')
call s:hl('Directory', s:p.link, '', '')
call s:hl('Title', s:p.heading, '', 'bold')
call s:hl('Comment', s:dim, '', 'italic')
call s:hl('Constant', s:fg, '', '')
call s:hl('String', s:fg, '', '')
call s:hl('Identifier', s:fg, '', '')
call s:hl('Statement', s:fg, '', 'bold')
call s:hl('PreProc', s:dim, '', '')
call s:hl('Type', s:fg, '', '')
call s:hl('Special', s:dim, '', '')
call s:hl('Underlined', s:p.link, '', 'underline')
call s:hl('Todo', s:p.heading, '', 'bold')
call s:hl('Error', '#cf222e', '', 'bold')
call s:hl('ErrorMsg', '#cf222e', '', 'bold')
call s:hl('WarningMsg', s:mix('#bf8700', s:fg, 0.2), '', 'bold')
call s:hl('ModeMsg', s:fg, '', 'bold')
call s:hl('MoreMsg', s:p.link, '', 'bold')
call s:hl('Question', s:p.link, '', 'bold')
call s:hl('WildMenu', s:bg, s:p.link, '')
call s:hl('Cursor', s:bg, s:fg, '')
call s:hl('markdownH1', s:p.heading, '', 'bold')
call s:hl('markdownH2', s:p.heading, '', 'bold')
call s:hl('markdownH3', s:p.heading, '', 'bold')
call s:hl('markdownH4', s:p.heading, '', 'bold')
call s:hl('markdownH5', s:p.heading, '', 'bold')
call s:hl('markdownH6', s:p.heading, '', 'bold')
call s:hl('markdownHeadingDelimiter', s:p.heading, '', 'bold')
call s:hl('markdownCode', s:fg, s:panel, '')
call s:hl('markdownCodeBlock', s:fg, s:panel, '')
call s:hl('markdownLinkText', s:p.link, '', 'underline')
call s:hl('markdownUrl', s:dim, '', '')
call s:hl('gnosisLinkText', s:p.link, '', 'underline')
call s:hl('gnosisStartArt', s:fg, s:bg, '')
call s:hl('gnosisStartTitle', s:fg, s:bg, 'bold')
call s:hl('gnosisStartDim', s:dim, s:bg, '')
call s:hl('gnosisStartSel', s:fg, s:p.selection, 'bold')
call s:hl('gnosisStartKey', s:fg, s:panel, 'bold')
call s:hl('gnosisStartWarn', '#cf222e', s:bg, 'bold')
