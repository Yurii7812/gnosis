" =============================================================================
" autoload/gnosis/settings.vim — vault ごとの設定（<vault>/.gnosis/settings.json）
"
"   {
"     "version": 1,
"     "language": "ja" | "en",
"     "window": {"maximized": true, "width": 1200, "height": 860},
"     "fontSize": 16,
"     "appearance": "light" | "dark",
"     "theme": {"kind": "builtin"}
"            | {"kind": "custom", "name": "名前"}
"            | {"kind": "plugin", "repo": "作者/リポジトリ", "colorscheme": "名前"},
"     "customThemes": {"名前": {"base": "light|dark", "bg": "#rrggbb", "fg": …,
"                               "link": …, "heading": …, "selection": …, "cursorline": …}}
"   }
"
" 設定の優先順位（上ほど強い）:
"   1. その vault の .gnosis/settings.json（設定画面で変えるもの: 言語・見た目・
"      起動サイズ・文字サイズ・テーマ）
"   2. Gnosis の既定値（gnosis#settings#defaults()）
"   vault を選ぶ前（起動画面）は既定値。vault を選ぶと、その vault の設定を読む。
"   vimrc の g:gnosis_* / 旧 g:simple_yurii_note_* は、設定画面に無い細かな動作の設定
"   （g:gnosis_* が優先、無ければ旧名）。言語だけは、vault に設定が無いときの初期値に
"   g:gnosis_language を使える。
" =============================================================================

function! s:sep() abort
  return has('win32') ? '\' : '/'
endfunction

let s:palette_file = expand('<sfile>:p:h:h:h') . '/assets/themes/builtin.json'

function! gnosis#settings#defaults() abort
  let l:lang = get(g:, 'gnosis_language', '')
  if l:lang !~# '^\(ja\|en\)$'
    let l:lang = gnosis#i18n#system_lang()
  endif
  return {
        \ 'version': 1,
        \ 'language': l:lang,
        \ 'window': {'maximized': v:true, 'width': 1200, 'height': 860},
        \ 'fontSize': 16,
        \ 'appearance': 'light',
        \ 'theme': {'kind': 'builtin'},
        \ 'customThemes': {},
        \ }
endfunction

" 設定ファイルの場所（vault のパス A の .gnosis/settings.json）
function! gnosis#settings#file(vault) abort
  return gnosis#vault#normalize(a:vault) . s:sep() . '.gnosis' . s:sep() . 'settings.json'
endfunction

" 既定値に、読んだ値を重ねる（型の違う値・知らない値は既定値のまま）
function! gnosis#settings#merge(base, over) abort
  return gnosis#settings#validate(s:merge(a:base, a:over))
endfunction

function! s:merge(base, over) abort
  let l:out = deepcopy(a:base)
  for [l:k, l:v] in items(a:over)
    if !has_key(l:out, l:k)
      let l:out[l:k] = l:v
    elseif type(l:out[l:k]) == v:t_dict && type(l:v) == v:t_dict && l:k !=# 'theme' && l:k !=# 'customThemes'
      let l:out[l:k] = s:merge(l:out[l:k], l:v)
    elseif type(l:out[l:k]) == type(l:v)
          \ || (index([v:t_number, v:t_bool, v:t_float], type(l:out[l:k])) >= 0 && index([v:t_number, v:t_bool, v:t_float], type(l:v)) >= 0)
      let l:out[l:k] = l:v
    endif
  endfor
  return l:out
endfunction

function! gnosis#settings#validate(s) abort
  let l:s = a:s
  if l:s.language !~# '^\(ja\|en\)$'
    let l:s.language = gnosis#settings#defaults().language
  endif
  if l:s.appearance !~# '^\(light\|dark\)$'
    let l:s.appearance = 'light'
  endif
  let l:fs = type(l:s.fontSize) == v:t_number ? l:s.fontSize : float2nr(l:s.fontSize)
  let l:s.fontSize = max([8, min([48, l:fs])])
  let l:w = l:s.window
  let l:w.width = max([480, min([10000, type(l:w.width) == v:t_number ? l:w.width : float2nr(l:w.width)])])
  let l:w.height = max([360, min([10000, type(l:w.height) == v:t_number ? l:w.height : float2nr(l:w.height)])])
  let l:w.maximized = l:w.maximized ? v:true : v:false
  if type(l:s.theme) != v:t_dict || index(['builtin', 'custom', 'plugin'], get(l:s.theme, 'kind', '')) < 0
    let l:s.theme = {'kind': 'builtin'}
  endif
  return l:s
endfunction

" vault の設定を読む（無ければ既定値）。a:vault が空なら既定値。
function! gnosis#settings#load(vault) abort
  let l:def = gnosis#settings#defaults()
  if empty(a:vault)
    return l:def
  endif
  let l:raw = gnosis#home#read_json(gnosis#settings#file(a:vault), {})
  return gnosis#settings#merge(l:def, l:raw)
endfunction

function! gnosis#settings#save(vault, settings) abort
  call gnosis#home#write_json(gnosis#settings#file(a:vault), gnosis#settings#validate(a:settings))
endfunction

" いま開いている vault（g:gnosis_root から求める。無ければ登録簿の最後の vault）
function! gnosis#settings#current_vault() abort
  if exists('g:gnosis_active_vault') && !empty(g:gnosis_active_vault)
    return g:gnosis_active_vault
  endif
  let l:root = get(g:, 'gnosis_root', '')
  if !empty(trim(l:root))
    return gnosis#vault#of_root(l:root)
  endif
  return ''
endfunction

function! gnosis#settings#current() abort
  if !exists('s:current')
    let s:current = gnosis#settings#load(gnosis#settings#current_vault())
  endif
  return s:current
endfunction

" 値を 1 つ変えて保存し、すぐ反映する（a:key は 'language' / 'window.maximized' のような点区切り）
function! gnosis#settings#set(key, value) abort
  let l:vault = gnosis#settings#current_vault()
  let l:s = deepcopy(gnosis#settings#current())
  let l:parts = split(a:key, '\.')
  let l:d = l:s
  for l:p in l:parts[:-2]
    if !has_key(l:d, l:p) || type(l:d[l:p]) != v:t_dict
      let l:d[l:p] = {}
    endif
    let l:d = l:d[l:p]
  endfor
  let l:d[l:parts[-1]] = a:value
  let l:s = gnosis#settings#validate(l:s)
  if !empty(l:vault)
    call gnosis#settings#save(l:vault, l:s)
  endif
  let s:current = l:s
  call gnosis#settings#apply(l:s)
  return l:s
endfunction

" vault を切り替えたとき: その vault の設定を読み直して反映する
function! gnosis#settings#activate(vault) abort
  let g:gnosis_active_vault = gnosis#vault#normalize(a:vault)
  let s:current = gnosis#settings#load(g:gnosis_active_vault)
  call gnosis#settings#apply(s:current)
endfunction

" 起動画面に戻るとき: 既定値（白背景・黒文字）
function! gnosis#settings#deactivate() abort
  let g:gnosis_active_vault = ''
  unlet! s:current
endfunction

" 設定を Vim に反映する（言語・テーマ・GUI の文字サイズ・GUI のウィンドウ）
function! gnosis#settings#apply(s) abort
  call gnosis#i18n#set_lang(a:s.language)
  call gnosis#theme#apply(a:s)
  call gnosis#settings#apply_gui(a:s)
  if exists('#User#GnosisSettingsChanged')
    doautocmd <nomodeline> User GnosisSettingsChanged
  endif
endfunction

" GUI 版 Vim（gvim / MacVim）: 文字サイズは guifont、起動サイズは lines/columns。
" 端末版 Vim は端末の文字やウィンドウを変えられないので何もしない（ランチャーが対応端末だけ設定する）。
function! gnosis#settings#apply_gui(s) abort
  if !has('gui_running')
    return
  endif
  let l:size = a:s.fontSize
  if has('win32')
    let &guifont = get(g:, 'gnosis_gui_font_name', 'Consolas') . ':h' . l:size
  elseif has('mac') || has('macunix')
    let &guifont = get(g:, 'gnosis_gui_font_name', 'Menlo-Regular') . ':h' . l:size
  else
    let &guifont = get(g:, 'gnosis_gui_font_name', 'Monospace') . ' ' . l:size
  endif
  if get(s:, 'gui_window_done', 0)
    return
  endif
  let s:gui_window_done = 1
  if a:s.window.maximized
    if has('win32')
      simalt ~x
    else
      set lines=999 columns=999
    endif
  else
    " ピクセルから行・桁を見積もる（文字の幅 ≒ 0.6 × 文字サイズ、行の高さ ≒ 1.4 × 文字サイズ）
    let &columns = max([40, float2nr(a:s.window.width / (l:size * 0.6 + 0.0))])
    let &lines = max([12, float2nr(a:s.window.height / (l:size * 1.4 + 0.0))])
  endif
endfunction

" 組み込みテーマの色（assets/themes/builtin.json。Electron と共通）
function! gnosis#settings#builtin_palettes() abort
  if !exists('s:palettes')
    let s:palettes = gnosis#home#read_json(s:palette_file, {})
    if empty(s:palettes)
      let s:palettes = {
            \ 'start': {'bg': '#ffffff', 'fg': '#000000', 'link': '#000000', 'heading': '#000000', 'selection': '#d0d0d0', 'cursorline': '#f0f0f0'},
            \ 'light': {'bg': '#ffffff', 'fg': '#1f2328', 'link': '#0969da', 'heading': '#1f2328', 'selection': '#b6d6ff', 'cursorline': '#f6f8fa'},
            \ 'dark': {'bg': '#0d1117', 'fg': '#e6edf3', 'link': '#4493f8', 'heading': '#f0f6fc', 'selection': '#264f78', 'cursorline': '#161b22'},
            \ }
    endif
  endif
  return s:palettes
endfunction

" GUI 版 Vim の Ctrl + / Ctrl - / Ctrl 0: 文字の大きさをその場だけ変える（保存しない）。
" 保存される「文字サイズ」の設定は設定画面で変える。Ctrl 0 で設定の大きさに戻る。
function! gnosis#settings#gui_zoom(delta) abort
  if !has('gui_running')
    return
  endif
  let l:base = gnosis#settings#current().fontSize
  let s:gui_zoom = a:delta == 0 ? 0 : get(s:, 'gui_zoom', 0) + a:delta
  let l:size = max([6, min([72, l:base + s:gui_zoom])])
  let l:s = deepcopy(gnosis#settings#current())
  let l:s.fontSize = l:size
  let s:gui_window_done = 1
  call gnosis#settings#apply_gui(l:s)
endfunction
