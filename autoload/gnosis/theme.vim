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
    let l:out = system('git clone --depth 1 -- ' . shellescape(l:url) . ' ' . shellescape(l:dir))
    if v:shell_error != 0 || !isdirectory(l:dir)
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
      let l:base = get(l:c, 'base', a:s.appearance)
      let l:p = extend(copy(get(l:pals, l:base, l:pals.light)), filter(copy(l:c), 'v:val =~# "^#\\x\\{6}$" || v:key ==# "base"'))
      let l:p.base = l:base
      return l:p
    endif
  endif
  let l:p = copy(get(l:pals, a:s.appearance, l:pals.light))
  let l:p.base = a:s.appearance
  return l:p
endfunction

" 起動画面の配色（白背景・黒文字）
function! gnosis#theme#apply_start() abort
  let g:gnosis_palette = copy(gnosis#settings#builtin_palettes().start)
  let g:gnosis_palette.base = 'light'
  set background=light
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

" 設定のテーマを反映する。失敗したら組み込みテーマへ戻し、メッセージを出す。
function! gnosis#theme#apply(s) abort
  let l:kind = get(a:s.theme, 'kind', 'builtin')
  let &background = a:s.appearance
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
        let &background = a:s.appearance
        let l:ok = 1
      catch
        let l:ok = 0
      endtry
    endif
    if l:ok
      let g:gnosis_palette = s:palette_from_highlights(a:s.appearance)
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
  let l:get = {grp, what, dflt -> s:hl_color(grp, what, dflt)}
  return {
        \ 'base': a:base,
        \ 'bg': l:get('Normal', 'bg', l:def.bg),
        \ 'fg': l:get('Normal', 'fg', l:def.fg),
        \ 'link': l:get('Underlined', 'fg', l:get('Identifier', 'fg', l:def.link)),
        \ 'heading': l:get('Title', 'fg', l:def.heading),
        \ 'selection': l:get('Visual', 'bg', l:def.selection),
        \ 'cursorline': l:get('CursorLine', 'bg', l:def.cursorline),
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
