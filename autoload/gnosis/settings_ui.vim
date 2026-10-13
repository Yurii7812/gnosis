" =============================================================================
" autoload/gnosis/settings_ui.vim — Gnosis の設定画面（Vim 版。:GnosisSettings）
"
" vimrc を書き換えずに、vault ごとの設定（<vault>/.gnosis/settings.json）を変える。
"   言語 / 起動時に最大化 / 通常のウィンドウサイズ / 文字サイズ / ライト・ダーク /
"   テーマの選択・追加（Plug '作者/リポジトリ'）/ カスタム配色
" キー: j k 移動 / Enter・Space 変更 / q・Esc 閉じる
" Electron アプリは同じ設定を HTML の画面で変える（同じファイルを読み書きする）。
" =============================================================================

let s:items = ['language', 'maximized', 'window', 'fontSize', 'appearance', 'theme', 'theme_add', 'custom', 'theme_reset']

function! s:t(key, ...) abort
  return call('gnosis#i18n#t', [a:key] + a:000)
endfunction

" a:opts.vault … 設定する vault（省略時: 開いている vault、起動画面なら選択中の vault）
function! gnosis#settings_ui#open(...) abort
  let l:opts = a:0 ? a:1 : {}
  let l:vault = get(l:opts, 'vault', '')
  if empty(l:vault)
    let l:vault = gnosis#settings#current_vault()
  endif
  if empty(l:vault) && get(l:opts, 'from_start', 0)
    let l:vault = gnosis#vault#last()
    if empty(l:vault)
      let l:list = gnosis#vault#list()
      let l:vault = empty(l:list) ? '' : l:list[0].path
    endif
  endif
  if empty(l:vault) || !isdirectory(l:vault)
    echohl WarningMsg | echo 'Gnosis: ' . s:t('settings.need_vault') | echohl NONE
    return
  endif
  let s:vault = l:vault
  let s:settings = gnosis#settings#load(l:vault)
  let s:from_start = get(l:opts, 'from_start', 0)
  let s:sel = 0
  let s:message = ''
  let s:prev_buf = bufnr('%')
  enew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nonumber norelativenumber nowrap nolist
  silent! file Gnosis\ Settings
  let b:gnosis_settings = 1
  for l:k in ['<CR>', '<Space>', 'q', '<Esc>', 'j', 'k', '<Down>', '<Up>', 'h', 'l', '<Left>', '<Right>']
    execute printf('nnoremap <buffer><silent><nowait> %s <Cmd>call gnosis#settings_ui#key(%s)<CR>', l:k, substitute(string(l:k), '<', '<lt>', 'g'))
  endfor
  for l:k in ['i', 'I', 'o', 'O', 'a', 'A', 'x', 'p', 'P', 'c', 'C', 'u', 'd']
    execute 'nnoremap <buffer><silent><nowait> ' . l:k . ' <Nop>'
  endfor
  call gnosis#settings_ui#render()
endfunction

function! s:theme_label(s) abort
  let l:th = a:s.theme
  if l:th.kind ==# 'custom'
    return s:t('settings.theme_custom', get(l:th, 'name', ''))
  elseif l:th.kind ==# 'plugin'
    return get(l:th, 'colorscheme', '') . '  (' . get(l:th, 'repo', '') . ')'
  endif
  return s:t('settings.theme_builtin')
endfunction

function! s:value(item) abort
  let l:s = s:settings
  if a:item ==# 'language'
    return l:s.language ==# 'ja' ? '日本語' : 'English'
  elseif a:item ==# 'maximized'
    return l:s.window.maximized ? s:t('settings.on') : s:t('settings.off')
  elseif a:item ==# 'window'
    return l:s.window.width . ' × ' . l:s.window.height
  elseif a:item ==# 'fontSize'
    return string(l:s.fontSize)
  elseif a:item ==# 'appearance'
    return l:s.appearance ==# 'dark' ? s:t('settings.dark') : s:t('settings.light')
  elseif a:item ==# 'theme'
    return s:theme_label(l:s)
  endif
  return ''
endfunction

function! gnosis#settings_ui#render() abort
  if !get(b:, 'gnosis_settings', 0)
    return
  endif
  let l:lines = [' Gnosis — ' . s:t('settings.title'), ' ' . s:t('settings.vault') . ' ' . s:vault, '']
  let l:w = 0
  for l:it in s:items
    let l:w = max([l:w, strdisplaywidth(s:t('settings.item.' . l:it))])
  endfor
  for l:i in range(len(s:items))
    let l:it = s:items[l:i]
    let l:label = s:t('settings.item.' . l:it)
    let l:val = s:value(l:it)
    let l:row = (l:i == s:sel ? ' > ' : '   ') . l:label . repeat(' ', l:w - strdisplaywidth(l:label) + 2) . l:val
    call add(l:lines, l:row)
  endfor
  call extend(l:lines, ['', '   ' . s:t('settings.keys'), '   ' . s:t('settings.note_terminal')])
  if !empty(s:message)
    call extend(l:lines, ['', '   ' . s:message])
  endif
  setlocal modifiable
  silent %delete _
  call setline(1, l:lines)
  setlocal nomodifiable
  call clearmatches()
  call matchaddpos('Title', [1])
  call matchaddpos('Visual', [4 + s:sel])
  call cursor(4 + s:sel, 4)
  redraw
endfunction

function! s:save() abort
  let s:settings = gnosis#settings#validate(s:settings)
  call gnosis#settings#save(s:vault, s:settings)
  " 開いている vault の設定ならすぐ反映。起動画面からなら言語だけ反映（配色は白黒のまま）
  if gnosis#vault#same(gnosis#settings#current_vault(), s:vault) && !gnosis#start#active()
    call gnosis#settings#activate(s:vault)
  else
    call gnosis#i18n#set_lang(s:settings.language)
  endif
endfunction

function! s:ask(prompt, default) abort
  try
    let l:r = inputdialog(a:prompt, a:default, "\x01")
  catch /^Vim:Interrupt$/
    let l:r = "\x01"
  endtry
  redraw
  return l:r
endfunction

function! s:valid_color(c) abort
  return a:c =~# '^#\x\{6}$'
endfunction

function! gnosis#settings_ui#key(k) abort
  let s:message = ''
  if a:k ==# 'j' || a:k ==# '<Down>'
    let s:sel = min([s:sel + 1, len(s:items) - 1])
  elseif a:k ==# 'k' || a:k ==# '<Up>'
    let s:sel = max([s:sel - 1, 0])
  elseif a:k ==# 'q' || a:k ==# '<Esc>'
    call gnosis#settings_ui#close()
    return
  elseif index(['<CR>', '<Space>', 'h', 'l', '<Left>', '<Right>'], a:k) >= 0
    call s:change(s:items[s:sel])
  endif
  call gnosis#settings_ui#render()
endfunction

function! s:change(item) abort
  let l:s = s:settings
  if a:item ==# 'language'
    let l:s.language = l:s.language ==# 'ja' ? 'en' : 'ja'
  elseif a:item ==# 'maximized'
    let l:s.window.maximized = l:s.window.maximized ? v:false : v:true
  elseif a:item ==# 'window'
    let l:r = s:ask(s:t('settings.prompt_window'), l:s.window.width . 'x' . l:s.window.height)
    if l:r ==# "\x01" | return | endif
    let l:m = matchlist(l:r, '^\s*\(\d\+\)\s*[xX×*,]\s*\(\d\+\)\s*$')
    if empty(l:m)
      let s:message = s:t('settings.bad_window')
      return
    endif
    let l:s.window.width = str2nr(l:m[1])
    let l:s.window.height = str2nr(l:m[2])
  elseif a:item ==# 'fontSize'
    let l:r = s:ask(s:t('settings.prompt_font'), string(l:s.fontSize))
    if l:r ==# "\x01" | return | endif
    if l:r !~# '^\s*\d\+\s*$'
      let s:message = s:t('settings.bad_font')
      return
    endif
    let l:s.fontSize = str2nr(l:r)
  elseif a:item ==# 'appearance'
    let l:s.appearance = l:s.appearance ==# 'light' ? 'dark' : 'light'
  elseif a:item ==# 'theme'
    call s:choose_theme()
  elseif a:item ==# 'theme_add'
    let l:r = s:ask(s:t('settings.prompt_plug'), "Plug ''")
    if l:r ==# "\x01" || empty(trim(l:r)) | return | endif
    echo s:t('settings.installing')
    let l:res = gnosis#theme#install(l:r)
    let s:message = l:res.message
    if l:res.ok
      let l:s.theme = {'kind': 'plugin', 'repo': l:res.repo, 'colorscheme': l:res.colorschemes[0]}
    endif
  elseif a:item ==# 'custom'
    call s:edit_custom()
  elseif a:item ==# 'theme_reset'
    let l:s.theme = {'kind': 'builtin'}
  endif
  call s:save()
endfunction

function! s:choose_theme() abort
  let l:choices = [{'kind': 'builtin'}]
  for l:name in sort(keys(get(s:settings, 'customThemes', {})))
    call add(l:choices, {'kind': 'custom', 'name': l:name})
  endfor
  for l:t in gnosis#theme#installed()
    for l:cs in l:t.colorschemes
      call add(l:choices, {'kind': 'plugin', 'repo': l:t.repo, 'colorscheme': l:cs})
    endfor
  endfor
  let l:labels = [s:t('settings.choose_theme')]
  for l:i in range(len(l:choices))
    call add(l:labels, (l:i + 1) . '. ' . s:theme_label({'theme': l:choices[l:i]}))
  endfor
  let l:n = inputlist(l:labels)
  if l:n >= 1 && l:n <= len(l:choices)
    let s:settings.theme = l:choices[l:n - 1]
  endif
endfunction

function! s:edit_custom() abort
  let l:name = s:ask(s:t('settings.prompt_custom_name'), get(s:settings.theme, 'kind', '') ==# 'custom' ? s:settings.theme.name : 'my-theme')
  if l:name ==# "\x01" || empty(trim(l:name)) | return | endif
  let l:name = trim(l:name)
  let l:cur = get(s:settings.customThemes, l:name, {})
  let l:base_pal = get(gnosis#settings#builtin_palettes(), get(l:cur, 'base', s:settings.appearance), gnosis#settings#builtin_palettes().light)
  let l:new = {'base': get(l:cur, 'base', s:settings.appearance)}
  for l:key in ['bg', 'fg', 'link', 'heading', 'selection', 'cursorline']
    let l:r = s:ask(s:t('settings.prompt_color', s:t('settings.color.' . l:key)), get(l:cur, l:key, l:base_pal[l:key]))
    if l:r ==# "\x01" | return | endif
    let l:r = trim(l:r)
    if !s:valid_color(l:r)
      let s:message = s:t('settings.bad_color', l:r)
      return
    endif
    let l:new[l:key] = tolower(l:r)
  endfor
  let s:settings.customThemes[l:name] = l:new
  let s:settings.theme = {'kind': 'custom', 'name': l:name}
endfunction

function! gnosis#settings_ui#close() abort
  if gnosis#start#active() || get(s:, 'from_start', 0) && gnosis#start#active()
    call gnosis#start#open()
    return
  endif
  if bufexists(get(s:, 'prev_buf', -1))
    execute 'buffer ' . s:prev_buf
  else
    bwipeout
  endif
endfunction
