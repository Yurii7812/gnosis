" Gnosis の組み込み配色。色は g:gnosis_palette（gnosis#theme が設定）から取る。
"   bg 背景 / fg 本文 / link リンク / heading 見出し / selection 選択範囲 / cursorline カーソル行
"   muted 補助の文字（行番号・パス・コメントなど。無ければ fg と bg から作る）
"   accent 起動画面の Chnoubis と GNOSIS ロゴ（無ければ link）
" g:gnosis_palette が無いときは &background に合わせた組み込みの色。
"
" 読みやすさの方針（役割で色を分ける。起動画面はダークの背景に、ダークのリンクの色の Chnoubis）:
"   - ダークは普通の濃い灰色の背景に明るい灰色の本文、ライトは白い背景に黒に近い本文
"   - リンクは本文と見分けられる空色＋下線（本文と同じ明るさの色だと区別がつかない）
"   - 見出しは太字。標準・ダークは # ## が淡い金・### 以下は水色、ライトは本文と同じ黒（ブラウザの表示と同じ）
"   - 補助の文字も背景との差を十分に取る（コントラスト比 4.5:1 以上）
"   - 斜体は Markdown の *強調* だけ（コメントなどに斜体は使わない）
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
let s:link = s:p.link
let s:heading = s:p.heading
let s:dim = get(s:p, 'muted', '') =~# '^#\x\{6}$' ? s:p.muted : s:mix(s:fg, s:bg, 0.35)
let s:accent = get(s:p, 'accent', '') =~# '^#\x\{6}$' ? s:p.accent : s:link
" ### 以下の見出し（無ければ見出しと同じ色。ライトはブラウザの表示に合わせて本文と同じ黒の太字）
let s:subheading = get(s:p, 'subheading', '') =~# '^#\x\{6}$' ? s:p.subheading : s:heading
let s:strong = s:mix(s:fg, &background ==# 'dark' ? '#ffffff' : '#000000', 0.6)
let s:line = s:mix(s:fg, s:bg, 0.80)
let s:panel = s:mix(s:fg, s:bg, 0.92)
let s:dark = &background ==# 'dark'
let s:red = s:dark ? '#FF8A8A' : '#B42318'
let s:yellow = s:dark ? '#FFD479' : '#8A5A00'
let s:green = s:dark ? '#8FE3A8' : '#1A7F37'

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

" ---- 画面の基本
call s:hl('Normal', s:fg, s:bg, '')
call s:hl('NonText', s:line, '', '')
call s:hl('EndOfBuffer', s:bg, '', '')
call s:hl('LineNr', s:dim, '', '')
call s:hl('CursorLineNr', s:strong, s:p.cursorline, 'bold')
call s:hl('CursorLine', '', s:p.cursorline, '')
call s:hl('CursorColumn', '', s:p.cursorline, '')
call s:hl('ColorColumn', '', s:panel, '')
call s:hl('Visual', s:strong, s:p.selection, '')
call s:hl('VisualNOS', s:strong, s:p.selection, '')
call s:hl('Search', s:bg, s:yellow, '')
call s:hl('IncSearch', s:bg, s:link, 'bold')
call s:hl('CurSearch', s:bg, s:link, 'bold')
call s:hl('MatchParen', s:strong, s:p.selection, 'bold')
call s:hl('StatusLine', s:fg, s:panel, 'bold')
call s:hl('StatusLineNC', s:dim, s:panel, '')
call s:hl('StatusLineTerm', s:fg, s:panel, 'bold')
call s:hl('StatusLineTermNC', s:dim, s:panel, '')
call s:hl('VertSplit', s:line, s:bg, '')
call s:hl('TabLine', s:dim, s:panel, '')
call s:hl('TabLineFill', '', s:panel, '')
call s:hl('TabLineSel', s:strong, s:bg, 'bold')
call s:hl('Pmenu', s:fg, s:panel, '')
call s:hl('PmenuSel', s:bg, s:link, 'bold')
call s:hl('PmenuSbar', '', s:line, '')
call s:hl('PmenuThumb', '', s:dim, '')
call s:hl('Folded', s:dim, s:panel, '')
call s:hl('FoldColumn', s:dim, s:bg, '')
call s:hl('SignColumn', s:dim, s:bg, '')
call s:hl('Conceal', s:dim, '', '')
call s:hl('SpecialKey', s:line, '', '')
call s:hl('Directory', s:link, '', '')
call s:hl('Title', s:heading, '', 'bold')
call s:hl('Comment', s:dim, '', '')
call s:hl('Constant', s:fg, '', '')
call s:hl('String', s:fg, '', '')
call s:hl('Identifier', s:fg, '', '')
call s:hl('Statement', s:strong, '', 'bold')
call s:hl('PreProc', s:dim, '', '')
call s:hl('Type', s:fg, '', '')
call s:hl('Special', s:dim, '', '')
call s:hl('Delimiter', s:dim, '', '')
call s:hl('Underlined', s:link, '', 'underline')
call s:hl('Todo', s:heading, '', 'bold')
call s:hl('Error', s:red, '', 'bold')
call s:hl('ErrorMsg', s:red, '', 'bold')
call s:hl('WarningMsg', s:yellow, '', 'bold')
call s:hl('ModeMsg', s:bg, s:accent, 'bold')
" 状態は背景付きの高コントラストなモード表示に統一。
call s:hl('GnosisModeNormal', s:bg, s:heading, 'bold')
call s:hl('GnosisModeInsert', s:bg, s:accent, 'bold')
call s:hl('GnosisModeVisual', s:bg, s:green, 'bold')
call s:hl('GnosisModeReplace', s:bg, s:red, 'bold')
call s:hl('MoreMsg', s:link, '', 'bold')
call s:hl('Question', s:link, '', 'bold')
call s:hl('WildMenu', s:bg, s:link, 'bold')
call s:hl('Cursor', s:bg, s:strong, '')
call s:hl('lCursor', s:bg, s:strong, '')
call s:hl('DiffAdd', s:green, s:panel, '')
call s:hl('DiffDelete', s:red, s:panel, '')
call s:hl('DiffChange', s:fg, s:panel, '')
call s:hl('DiffText', s:yellow, s:panel, 'bold')
call s:hl('SpellBad', '', '', 'undercurl')
call s:hl('SpellCap', '', '', 'undercurl')

" ---- Markdown（本文・見出し・リンク）
call s:hl('markdownH1', s:heading, '', 'bold')
call s:hl('markdownH2', s:heading, '', 'bold')
call s:hl('markdownH3', s:subheading, '', 'bold')
call s:hl('markdownH4', s:subheading, '', 'bold')
call s:hl('markdownH5', s:subheading, '', 'bold')
call s:hl('markdownH6', s:subheading, '', 'bold')
call s:hl('markdownHeadingDelimiter', s:dim, '', '')
call s:hl('markdownBold', s:strong, '', 'bold')
call s:hl('markdownItalic', s:strong, '', 'italic')
call s:hl('markdownBoldItalic', s:strong, '', 'bold,italic')
" ** や * の記号は控えめな色（本文の文字と見分けやすく、強調した語が目立つ）
call s:hl('markdownBoldDelimiter', s:dim, '', '')
call s:hl('markdownItalicDelimiter', s:dim, '', '')
call s:hl('markdownBoldItalicDelimiter', s:dim, '', '')
call s:hl('markdownCode', s:fg, s:panel, '')
call s:hl('markdownCodeBlock', s:fg, s:panel, '')
call s:hl('markdownCodeDelimiter', s:dim, s:panel, '')
call s:hl('markdownListMarker', s:dim, '', '')
call s:hl('markdownOrderedListMarker', s:dim, '', '')
call s:hl('markdownBlockquote', s:dim, '', '')
call s:hl('markdownRule', s:dim, '', '')
call s:hl('markdownLinkText', s:link, '', 'underline')
call s:hl('markdownLinkTextDelimiter', s:dim, '', '')
call s:hl('markdownLinkDelimiter', s:dim, '', '')
call s:hl('markdownUrl', s:dim, '', '')
call s:hl('markdownId', s:dim, '', '')
call s:hl('markdownIdDeclaration', s:dim, '', '')
call s:hl('markdownError', s:fg, '', '')
call s:hl('htmlError', s:fg, '', '')
call s:hl('gnosisLinkText', s:link, '', 'underline')
call s:hl('yamlKey', s:dim, '', '')
call s:hl('yamlBlockMappingKey', s:dim, '', '')
call s:hl('yamlDocumentStart', s:dim, '', '')

" ---- 起動画面・設定画面
call s:hl('gnosisStartArt', s:accent, s:bg, '')
call s:hl('gnosisStartLogo', s:accent, s:bg, '')
call s:hl('gnosisStartTitle', s:strong, s:bg, 'bold')
call s:hl('gnosisStartText', s:fg, s:bg, '')
call s:hl('gnosisStartDim', s:dim, s:bg, '')
call s:hl('gnosisStartSel', s:strong, s:p.selection, 'bold')
call s:hl('gnosisStartKey', s:strong, s:panel, 'bold')
call s:hl('gnosisStartWarn', s:red, s:bg, 'bold')
call s:hl('gnosisSettingsTitle', s:heading, '', 'bold')
call s:hl('gnosisSettingsLabel', s:fg, '', '')
call s:hl('gnosisSettingsValue', s:strong, '', 'bold')
call s:hl('gnosisSettingsSel', s:strong, s:p.selection, 'bold')
call s:hl('gnosisSettingsDim', s:dim, '', '')
call s:hl('gnosisSettingsOk', s:green, '', 'bold')
call s:hl('gnosisSettingsWarn', s:yellow, '', 'bold')

" リンクの番号ヒント（1〜9・0・g1 …）。本文の文字と混ざらないよう、控えめな色の札にする
" 文字と札の色は、配色エディタで決められる（hintfg / hintbg）。無ければ 文字=背景色・札=補助の色。
call s:hl('GnosisLinkHint', get(s:p, 'hintfg', '') =~# '^#\x\{6}$' ? s:p.hintfg : s:bg, get(s:p, 'hintbg', '') =~# '^#\x\{6}$' ? s:p.hintbg : s:dim, 'bold')
