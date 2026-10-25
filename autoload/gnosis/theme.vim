" =============================================================================
" autoload/gnosis/theme.vim — テーマ（配色）
"
"   組み込み   … light / dark（assets/themes/builtin.json。Electron と同じ色）
"   カスタム   … 背景・本文・リンク・見出し・選択範囲・カーソル行 を vault の設定に保存
"   追加テーマ … GitHub の Vim テーマ。設定画面に `Plug '作者/リポジトリ'` の形で入れる。
"                入力は Vim script として実行せず、作者/リポジトリ の名前だけを取り出して
"                git clone する。置き場所は Gnosis ホームの themes/ だけ。
" テーマが読めない・壊れているときは、組み込みテーマに戻す（起動できなくならない）。
" =============================================================================

function! s:sep() abort
  return has('win32') ? '\' : '/'
endfunction

" 入力から 作者/リポジトリ を取り出す。受け付ける形:
"   Plug 'owner/repo'   Plug "owner/repo"   Plug 'owner/repo', { … }
"   owner/repo   https://github.com/owner/repo(.git)   git@github.com:owner/repo.git
" それ以外は ''。
function! gnosis#theme#parse(spec) abort
  let l:s = trim(a:spec)
  let l:m = matchlist(l:s, '\v^Plug\s+([''"])([^''"]+)\1\s*(,.*)?$')
  if !empty(l:m)
    let l:s = l:m[2]
  endif
  let l:s = substitute(l:s, '\v^%(https?://)?%(www\.)?github\.com/', '', '')
  let l:s = substitute(l:s, '\v^git\@github\.com:', '', '')
  let l:s = substitute(l:s, '\v\.git$', '', '')
  let l:s = substitute(l:s, '/\+$', '', '')
  if l:s =~# '\v^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$' && l:s !~# '\v/\.\.?$'
    return l:s
  endif
  return ''
endfunction

function! gnosis#theme#dir_for(repo) abort
  return gnosis#home#path('themes', substitute(a:repo, '/', '__', ''))
endfunction

" 追加済みのテーマ: [{repo, dir, colorschemes: [...]}]
function! gnosis#theme#installed() abort
  let l:out = []
  for l:d in glob(gnosis#home#path('themes', '*'), 1, 1)
    if !isdirectory(l:d)
      continue
    endif
    let l:name = fnamemodify(l:d, ':t')
    let l:repo = substitute(l:name, '__', '/', '')
    let l:cs = map(glob(l:d . s:sep() . 'colors' . s:sep() . '*.vim', 1, 1), 'fnamemodify(v:val, ":t:r")')
    call add(l:out, {'repo': l:repo, 'dir': l:d, 'colorschemes': sort(l:cs)})
  endfor
  return l:out
endfunction

" テーマを追加する（git clone --depth 1）。戻り値 {ok, repo, message, colorschemes}
function! gnosis#theme#install(spec) abort
  let l:repo = gnosis#theme#parse(a:spec)
  if empty(l:repo)
    return {'ok': 0, 'repo': '', 'message': gnosis#i18n#t('theme.bad_spec', a:spec), 'colorschemes': []}
  endif
  if !executable('git')
    return {'ok': 0, 'repo': l:repo, 'message': gnosis#i18n#t('theme.no_git'), 'colorschemes': []}
  endif
  let l:dir = gnosis#theme#dir_for(l:repo)
  if !isdirectory(l:dir)
    call gnosis#home#init()
    let l:url = 'https://github.com/' . l:repo . '.git'
    let l:out = gnosis#sh#system('git clone --depth 1 -- ' . shellescape(l:url) . ' ' . shellescape(l:dir))
    if gnosis#sh#error() != 0 || !isdirectory(l:dir)
      call delete(l:dir, 'rf')
      return {'ok': 0, 'repo': l:repo, 'message': gnosis#i18n#t('theme.clone_failed', l:repo, trim(l:out)), 'colorschemes': []}
    endif
  endif
  let l:cs = map(glob(l:dir . s:sep() . 'colors' . s:sep() . '*.vim', 1, 1), 'fnamemodify(v:val, ":t:r")')
  if empty(l:cs)
    call delete(l:dir, 'rf')
    return {'ok': 0, 'repo': l:repo, 'message': gnosis#i18n#t('theme.no_colors', l:repo), 'colorschemes': []}
  endif
  if index(split(&runtimepath, ','), l:dir) < 0
    execute 'set runtimepath+=' . fnameescape(l:dir)
  endif
  return {'ok': 1, 'repo': l:repo, 'message': gnosis#i18n#t('theme.installed', l:repo), 'colorschemes': sort(l:cs)}
endfunction

function! gnosis#theme#remove(repo) abort
  let l:dir = gnosis#theme#dir_for(a:repo)
  if isdirectory(l:dir)
    execute 'set runtimepath-=' . fnameescape(l:dir)
    return delete(l:dir, 'rf') == 0
  endif
  return 0
endfunction

" 設定から使うパレット（組み込み・カスタム）を求める
function! gnosis#theme#palette(s) abort
  let l:pals = gnosis#settings#builtin_palettes()
  let l:kind = get(a:s.theme, 'kind', 'builtin')
  if l:kind ==# 'custom'
    let l:c = get(get(a:s, 'customThemes', {}), get(a:s.theme, 'name', ''), {})
    if !empty(l:c)
      let l:base = get(l:c, 'base', gnosis#settings#background(a:s))
      let l:p = copy(get(l:pals, l:base, l:pals.light))
      " 背景か本文の色を変えたカスタム配色では、補助の色（muted）は組み込みのものを使わず
      " その配色の本文と背景から作る（明るい背景に暗い補助色、のような食い違いを防ぐ）
      if has_key(l:c, 'bg') || has_key(l:c, 'fg')
        call remove(l:p, 'muted')
      endif
      " 見出しの色を変えた配色では、### 以下も同じ色にする（組み込みの副見出しの色を残さない）
      if has_key(l:c, 'heading') && !has_key(l:c, 'subheading') && has_key(l:p, 'subheading')
        call remove(l:p, 'subheading')
      endif
      call extend(l:p, filter(copy(l:c), 'v:val =~# "^#\\x\\{6}$" || v:key ==# "base"'))
      let l:p.base = l:base
      return l:p
    endif
  endif
  let l:p = copy(get(l:pals, a:s.appearance, l:pals.dark))
  let l:p.base = gnosis#settings#background(a:s)
  return l:p
endfunction

" \c のアプリ（Electron）の配色。通常の Vim の配色（palette）とは別の設定（appTheme / appCustomThemes）。
"   既定は通常の Vim と同じ見た目（ダーク・ライト）。自分で作った配色は 背景・本文・リンク・見出し・選択範囲・カーソル行 を自由に変えられる。
"   背景か本文を変えた配色では、補助の色（muted / accent）を組み込みのものから引き継がず作り直す。
function! gnosis#theme#app_palette(s) abort
  let l:pals = gnosis#settings#builtin_palettes()
  " 組み込みは通常の Vim と同じ見た目（ダーク・ライト）。\c 用のカスタム配色を選んだときだけ別の色
  " 外観（ダーク／ライト）は GUI 用の appAppearance（無ければ CUI の appearance と同じ）。ダークは CUI と同じ色、
  " ライトは GitHub（Brave の Markdown Viewer）の白（CUI のライトは目に優しいよう少し灰色に下げている）
  let l:ap = get(a:s, 'appAppearance', get(a:s, 'appearance', 'dark'))
  let l:p = copy(l:ap ==# 'light' ? get(l:pals, 'gui_light', l:pals.light) : l:pals.dark)
  let l:th = get(a:s, 'appTheme', {})
  if get(l:th, 'kind', 'builtin') ==# 'custom'
    let l:c = get(get(a:s, 'appCustomThemes', {}), get(l:th, 'name', ''), {})
    if !empty(l:c)
      if has_key(l:c, 'bg') || has_key(l:c, 'fg')
        call remove(l:p, 'muted')
        call remove(l:p, 'accent')
      endif
      call extend(l:p, filter(copy(l:c), 'v:val =~# "^#\\x\\{6}$"'))
      let l:p.base = get(l:c, 'base', '') =~# '^\(light\|dark\)$' ? l:c.base : gnosis#color#base_of(l:p.bg)
      return l:p
    endif
  endif
  let l:p.base = l:ap ==# 'light' ? 'light' : 'dark'
  return l:p
endfunction

" いまの Vim が \c のアプリ（Electron）の中で動いているか
function! gnosis#theme#in_app() abort
  return !empty($GNOSIS_GUI_PORT)
endfunction

" 起動画面はダークの背景に、Chnoubis をダークのリンクの色で描く。色は builtin.json の start から読む。
function! gnosis#theme#apply_start() abort
  " 起動画面の前の配色（旧 vimrc の kalisi など）を覚えておく（vault に設定が無いときに戻す）
  if get(g:, 'colors_name', '') !=# 'gnosis' && !exists('s:before_start')
    let s:before_start = {'name': get(g:, 'colors_name', ''), 'bg': &background}
  endif
  let g:gnosis_palette = copy(gnosis#settings#builtin_palettes().start)
  let g:gnosis_palette.base = get(g:gnosis_palette, 'base', 'dark')
  let &background = g:gnosis_palette.base
  call s:load_gnosis_colors()
  let g:gnosis_theme_state = {'kind': 'start', 'palette': g:gnosis_palette}
endfunction

function! s:load_gnosis_colors() abort
  if has('termguicolors') && !has('gui_running') && get(g:, 'gnosis_termguicolors', s:truecolor_terminal())
    set termguicolors
  endif
  try
    colorscheme gnosis
  catch
  endtry
  call s:apply_link_highlight()
endfunction

function! s:truecolor_terminal() abort
  return $COLORTERM =~? 'truecolor\|24bit' || exists('$GNOSIS_GUI_PORT') || has('win32')
endfunction

" 旧 vimrc（Gnosis のランチャーを使わない起動）で、vault にまだ Gnosis の設定が無いときは、
" vimrc の配色（起動画面の前のもの）をそのまま使う。
function! gnosis#theme#restore_vimrc_colors() abort
  let l:b = get(s:, 'before_start', {})
  if empty(l:b)
    return 0
  endif
  let &background = l:b.bg
  if !empty(l:b.name)
    try
      execute 'colorscheme ' . fnameescape(l:b.name)
    catch
    endtry
  endif
  let g:gnosis_palette = s:palette_from_highlights(l:b.bg)
  let g:gnosis_theme_state = {'kind': 'vimrc', 'name': l:b.name, 'palette': g:gnosis_palette}
  return 1
endfunction

" 設定のテーマを反映する。失敗したら組み込みテーマへ戻し、メッセージを出す。
function! gnosis#theme#apply(s) abort
  let l:kind = get(a:s.theme, 'kind', 'builtin')
  let &background = gnosis#settings#background(a:s)
  " \c のアプリの中の Vim は、アプリ用の配色（appTheme。既定は通常の Vim と同じ見た目）を使う。
  " 通常の Vim 用のテーマ（theme / customThemes / 追加テーマ）はアプリには効かない。
  if gnosis#theme#in_app()
    let g:gnosis_palette = gnosis#theme#app_palette(a:s)
    let &background = g:gnosis_palette.base
    call s:load_gnosis_colors()
    let g:gnosis_theme_state = {'kind': 'app', 'palette': g:gnosis_palette}
    return 1
  endif
  if l:kind ==# 'plugin'
    let l:name = get(a:s.theme, 'colorscheme', '')
    let l:repo = get(a:s.theme, 'repo', '')
    let l:dir = empty(l:repo) ? '' : gnosis#theme#dir_for(l:repo)
    if !empty(l:dir) && isdirectory(l:dir) && index(split(&runtimepath, ','), l:dir) < 0
      execute 'set runtimepath+=' . fnameescape(l:dir)
    endif
    let l:ok = 0
    if !empty(l:name) && !empty(globpath(&runtimepath, 'colors/' . l:name . '.vim', 1, 1))
      try
        if has('termguicolors') && !has('gui_running') && get(g:, 'gnosis_termguicolors', s:truecolor_terminal())
          set termguicolors
        endif
        execute 'colorscheme ' . fnameescape(l:name)
        let &background = gnosis#settings#background(a:s)
        " 読み込めたか（端末の色数などで途中で止まるテーマもある）
        let l:ok = get(g:, 'colors_name', '') ==# l:name
      catch
        let l:ok = 0
      endtry
    endif
    if l:ok
      let g:gnosis_palette = s:palette_from_highlights(gnosis#settings#background(a:s))
      call s:apply_link_highlight()
      let g:gnosis_theme_state = {'kind': 'plugin', 'name': l:name, 'palette': g:gnosis_palette}
      return 1
    endif
    echohl WarningMsg
    echom 'Gnosis: ' . gnosis#i18n#t('theme.fallback', l:name)
    echohl NONE
  endif
  let g:gnosis_palette = gnosis#theme#palette(a:s)
  let &background = g:gnosis_palette.base
  call s:load_gnosis_colors()
  let g:gnosis_theme_state = {'kind': l:kind ==# 'custom' ? 'custom' : 'builtin', 'palette': g:gnosis_palette}
  return l:kind !=# 'plugin'
endfunction

" 追加テーマの色から、Electron 側の画面に渡す色を作る
function! s:palette_from_highlights(base) abort
  let l:def = get(gnosis#settings#builtin_palettes(), a:base, gnosis#settings#builtin_palettes().light)
  let l:Get = {grp, what, dflt -> s:hl_color(grp, what, dflt)}
  return {
        \ 'base': a:base,
        \ 'bg': l:Get('Normal', 'bg', l:def.bg),
        \ 'fg': l:Get('Normal', 'fg', l:def.fg),
        \ 'link': l:Get('Underlined', 'fg', l:Get('Identifier', 'fg', l:def.link)),
        \ 'heading': l:Get('Title', 'fg', l:def.heading),
        \ 'selection': l:Get('Visual', 'bg', l:def.selection),
        \ 'cursorline': l:Get('CursorLine', 'bg', l:def.cursorline),
        \ }
endfunction

function! s:hl_color(group, what, dflt) abort
  let l:id = synIDtrans(hlID(a:group))
  let l:c = synIDattr(l:id, a:what . '#', 'gui')
  if l:c =~# '^#\x\{6}$'
    return l:c
  endif
  " 反転表示の Visual などは、反対側の色を使う
  if synIDattr(l:id, 'reverse', 'gui') ==# '1'
    let l:c = synIDattr(l:id, (a:what ==# 'bg' ? 'fg' : 'bg') . '#', 'gui')
    if l:c =~# '^#\x\{6}$'
      return l:c
    endif
  endif
  return a:dflt
endfunction

" リンク（gnosisLinkText）の色をパレットに合わせる
function! s:apply_link_highlight() abort
  let l:p = get(g:, 'gnosis_palette', {})
  if empty(l:p)
    return
  endif
  let g:gnosis_link_color_gui = l:p.link
  let g:gnosis_link_color_cterm = string(gnosis#theme#to_cterm(l:p.link))
  execute 'highlight gnosisLinkText term=underline cterm=underline gui=underline ctermfg='
        \ . g:gnosis_link_color_cterm . ' guifg=' . g:gnosis_link_color_gui
endfunction

" #rrggbb を 256 色の番号に近づける（termguicolors が使えない端末用）
function! gnosis#theme#to_cterm(hex) abort
  let l:r = str2nr(a:hex[1:2], 16)
  let l:g = str2nr(a:hex[3:4], 16)
  let l:b = str2nr(a:hex[5:6], 16)
  let l:levels = [0, 95, 135, 175, 215, 255]
  let l:idx = []
  for l:v in [l:r, l:g, l:b]
    let l:best = 0
    for l:i in range(6)
      if abs(l:levels[l:i] - l:v) < abs(l:levels[l:best] - l:v)
        let l:best = l:i
      endif
    endfor
    call add(l:idx, l:best)
  endfor
  let l:cube = 16 + 36 * l:idx[0] + 6 * l:idx[1] + l:idx[2]
  let l:cd = pow(l:levels[l:idx[0]] - l:r, 2) + pow(l:levels[l:idx[1]] - l:g, 2) + pow(l:levels[l:idx[2]] - l:b, 2)
  let l:gray = (l:r + l:g + l:b) / 3
  let l:gi = max([0, min([23, (l:gray - 8) / 10])])
  let l:gv = 8 + 10 * l:gi
  let l:gd = pow(l:gv - l:r, 2) + pow(l:gv - l:g, 2) + pow(l:gv - l:b, 2)
  return l:gd < l:cd ? 232 + l:gi : l:cube
endfunction

" :GnosisThemeAdd Plug 'owner/repo' … 追加して、この vault のテーマにする
function! gnosis#theme#add_command(spec) abort
  let l:res = gnosis#theme#install(a:spec)
  echo 'Gnosis: ' . l:res.message
  if l:res.ok
    call gnosis#settings#set('theme', {'kind': 'plugin', 'repo': l:res.repo, 'colorscheme': l:res.colorschemes[0]})
  endif
endfunction
