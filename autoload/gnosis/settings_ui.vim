" =============================================================================
" autoload/gnosis/settings_ui.vim — Gnosis の設定画面（Vim 版。:GnosisSettings）
"
" vimrc を書き換えずに、vault ごとの設定（<vault>/.gnosis/settings.json）を変える。
"   言語 / 起動時に最大化 / 通常のウィンドウサイズ / ライト・ダーク /
"   テーマの選択・追加（Plug '作者/リポジトリ'）/ カスタム配色
" 文字の大きさ・フォント・行間・Gnosis の窓に使う端末は vault ではなく Gnosis ホームの
" terminal.json（gnosis#termfont。どの vault でも同じ。ランチャーが窓を開くときに使う）。
" キー: j k 移動 / Enter・Space 変更 / 文字サイズの行で + - 0 / q・Esc 閉じる
" Electron アプリは同じ設定を HTML の画面で変える（同じファイルを読み書きする）。
" =============================================================================

let s:items = ['fontSize', 'fontFamily', 'lineSpacing', 'terminal', 'language', 'maximized', 'window', 'appearance', 'theme', 'theme_add', 'custom', 'theme_reset', 'app_theme', 'app_custom', 'app_theme_reset']
let s:font_items = ['fontSize', 'fontFamily', 'lineSpacing', 'terminal']

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
  let s:sel = max([0, min([get(l:opts, 'sel', 0), len(s:items) - 1])])
  let s:message = ''
  let s:prev_buf = get(l:opts, 'prev_buf', bufnr('%'))
  enew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nonumber norelativenumber nowrap nolist
  silent! file Gnosis\ Settings
  let b:gnosis_settings = 1
  augroup gnosis_settings_resize
    autocmd! * <buffer>
    autocmd VimResized <buffer> call gnosis#settings_ui#render()
  augroup END
  for l:k in ['<CR>', '<Space>', 'q', '<Esc>', 'j', 'k', '<Down>', '<Up>', 'h', 'l', '<Left>', '<Right>', '+', '-', '=', '0', '<kPlus>', '<kMinus>']
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

function! s:app_theme_label(s) abort
  let l:th = get(a:s, 'appTheme', {})
  if get(l:th, 'kind', 'builtin') ==# 'custom'
    return s:t('settings.theme_custom', get(l:th, 'name', ''))
  endif
  return s:t('settings.theme_app_builtin')
endfunction

function! s:value(item) abort
  let l:s = s:settings
  if index(s:font_items, a:item) >= 0
    let l:f = gnosis#termfont#load()
    if a:item ==# 'fontSize'
      return l:f.fontSize . ' pt    ( - / + / 0 )'
    elseif a:item ==# 'fontFamily'
      return empty(l:f.fontFamily) ? s:t('settings.font_auto') : l:f.fontFamily
    elseif a:item ==# 'lineSpacing'
      return l:f.lineSpacing . ' px'
    else
      return empty(l:f.terminal) ? s:t('settings.font_auto') : l:f.terminal
    endif
  elseif a:item ==# 'language'
    return l:s.language ==# 'ja' ? '日本語' : 'English'
  elseif a:item ==# 'maximized'
    return l:s.window.maximized ? s:t('settings.on') : s:t('settings.off')
  elseif a:item ==# 'window'
    return l:s.window.width . ' × ' . l:s.window.height
  elseif a:item ==# 'appearance'
    return l:s.appearance ==# 'light' ? s:t('settings.light') : s:t('settings.dark')
  elseif a:item ==# 'theme'
    return s:theme_label(l:s)
  elseif a:item ==# 'app_theme'
    return s:app_theme_label(l:s)
  endif
  return ''
endfunction

function! gnosis#settings_ui#render() abort
  if !get(b:, 'gnosis_settings', 0)
    return
  endif
  let l:width = winwidth(0)
  let l:lines = [' Gnosis — ' . s:t('settings.title'), ' ' . s:t('settings.vault') . ' ' . s:vault, '']
  let l:hls = [['gnosisSettingsTitle', 1, 0], ['gnosisSettingsDim', 2, 0]]
  let l:w = 0
  for l:it in s:items
    let l:w = max([l:w, strdisplaywidth(s:t('settings.item.' . l:it))])
  endfor
  " 画面が狭いときは、値を項目名の次の行に出す
  let l:narrow = l:w + 8 + 24 > l:width
  let s:rows = []
  for l:i in range(len(s:items))
    let l:it = s:items[l:i]
    if l:it ==# 'language'
      call add(l:lines, '')
    endif
    let l:label = s:t('settings.item.' . l:it)
    let l:val = s:value(l:it)
    let l:mark = l:i == s:sel ? ' > ' : '   '
    call add(s:rows, len(l:lines) + 1)
    if l:narrow
      call add(l:lines, l:mark . l:label)
      if !empty(l:val)
        call add(l:lines, '      ' . l:val)
        call add(l:hls, ['gnosisSettingsValue', len(l:lines), 0])
      endif
    else
      let l:row = l:mark . l:label . repeat(' ', l:w - strdisplaywidth(l:label) + 3) . l:val
      call add(l:lines, l:row)
      if !empty(l:val)
        call add(l:hls, ['gnosisSettingsValue', len(l:lines), strlen(l:row) - strlen(l:val) + 1, strlen(l:val)])
      endif
    endif
    if l:i == s:sel
      call add(l:hls, ['gnosisSettingsSel', s:rows[-1], 0])
    endif
    if l:it ==# 'terminal'
      " いまの端末で文字サイズをその場で変えられるか（保存と反映を分けて示す）
      let l:t = gnosis#termfont#detect()
      call add(l:lines, '      ' . gnosis#termfont#status())
      call add(l:hls, [l:t.live ? 'gnosisSettingsOk' : 'gnosisSettingsWarn', len(l:lines), 0])
    endif
  endfor
  call extend(l:lines, ['', '   ' . s:t('settings.keys')])
  call add(l:hls, ['gnosisSettingsDim', len(l:lines), 0])
  if s:items[s:sel] ==# 'fontSize'
    call add(l:lines, '   ' . s:t('settings.font_keys'))
    call add(l:hls, ['gnosisSettingsDim', len(l:lines), 0])
  endif
  if !empty(s:message)
    call extend(l:lines, ['', '   ' . s:message])
    call add(l:hls, [get(s:, 'message_ok', 0) ? 'gnosisSettingsOk' : 'gnosisSettingsWarn', len(l:lines), 0])
  endif
  setlocal modifiable
  silent %delete _
  call setline(1, l:lines)
  setlocal nomodifiable
  call clearmatches()
  for l:h in l:hls
    if len(l:h) == 4
      call matchaddpos(l:h[0], [[l:h[1], l:h[2], l:h[3]]], 10)
    else
      call matchaddpos(l:h[0], [l:h[1]], l:h[0] ==# 'gnosisSettingsSel' ? 5 : 10)
    endif
  endfor
  call cursor(s:rows[s:sel], 4)
  redraw
endfunction

function! s:save() abort
  let s:settings = gnosis#settings#validate(s:settings)
  call gnosis#settings#save(s:vault, s:settings)
  " 開いている vault の設定を即時反映。起動画面は起動画面の配色を維持。
  if gnosis#vault#same(gnosis#settings#current_vault(), s:vault) && !gnosis#start#active()
    call gnosis#settings#activate(s:vault)
  else
    call gnosis#i18n#set_lang(s:settings.language)
  endif
endfunction

" 文字サイズを変えた結果を伝える（保存できたか・その場で変わったかを分けて）
function! s:font_result(r) abort
  let s:message = gnosis#termfont#describe(a:r)
  let s:message_ok = a:r.saved && a:r.applied
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
  let s:message_ok = 0
  if a:k ==# 'j' || a:k ==# '<Down>'
    let s:sel = min([s:sel + 1, len(s:items) - 1])
  elseif a:k ==# 'k' || a:k ==# '<Up>'
    let s:sel = max([s:sel - 1, 0])
  elseif a:k ==# 'q' || a:k ==# '<Esc>'
    call gnosis#settings_ui#close()
    return
  elseif index(['+', '=', '-', '0', '<kPlus>', '<kMinus>'], a:k) >= 0 && s:items[s:sel] ==# 'fontSize'
    " + / - / 0 で保存し、その場で変えられる端末ではすぐ反映（設定画面の文字も変わる）
    let l:cur = gnosis#termfont#load().fontSize
    let l:n = a:k ==# '0' ? gnosis#termfont#defaults().fontSize
          \ : l:cur + (a:k ==# '-' || a:k ==# '<kMinus>' ? -1 : 1)
    call s:font_result(gnosis#termfont#set_size(l:n))
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
    let l:r = s:ask(s:t('settings.prompt_font'), string(gnosis#termfont#load().fontSize))
    if l:r ==# "\x01" | return | endif
    if l:r !~# '^\s*\d\+\s*$'
      let s:message = s:t('settings.bad_font')
      return
    endif
    call s:font_result(gnosis#termfont#set_size(str2nr(l:r)))
    return
  elseif a:item ==# 'fontFamily'
    " 入っているフォントの一覧から選ぶ（先頭は自動、最後は名前を自分で入力）
    let l:fonts = gnosis#termfont#font_choices()
    let l:cur = gnosis#termfont#load().fontFamily
    let l:labels = [s:t('settings.choose_font')]
    call add(l:labels, '1. ' . s:t('settings.font_auto') . (empty(l:cur) ? '  ←' : ''))
    for l:i in range(len(l:fonts))
      call add(l:labels, (l:i + 2) . '. ' . l:fonts[l:i].name . (empty(l:fonts[l:i].note) ? '' : '  … ' . l:fonts[l:i].note)
            \ . (l:fonts[l:i].name ==# l:cur ? '  ←' : ''))
    endfor
    call add(l:labels, (len(l:fonts) + 2) . '. ' . s:t('settings.font_type_name'))
    let l:n = gnosis#ui#inputlist(l:labels)
    if l:n < 1 || l:n > len(l:fonts) + 2 | return | endif
    if l:n == 1
      let l:name = ''
    elseif l:n <= len(l:fonts) + 1
      let l:name = l:fonts[l:n - 2].name
    else
      let l:r = s:ask(s:t('settings.prompt_font_family'), l:cur)
      if l:r ==# "\x01" | return | endif
      let l:name = trim(l:r)
    endif
    call s:font_result(gnosis#termfont#set('fontFamily', l:name))
    let s:message = s:t('settings.font_family_saved')
    return
  elseif a:item ==# 'lineSpacing'
    let l:r = s:ask(s:t('settings.prompt_line_spacing'), string(gnosis#termfont#load().lineSpacing))
    if l:r ==# "\x01" | return | endif
    if l:r !~# '^\s*\d\+\s*$'
      let s:message = s:t('settings.bad_font')
      return
    endif
    call gnosis#termfont#set('lineSpacing', max([0, min([12, str2nr(l:r)])]))
    let s:message = s:t('settings.font_family_saved')
    return
  elseif a:item ==# 'terminal'
    let l:choices = [''] + filter(['konsole', 'xfce4-terminal', 'gnome-terminal', 'kitty', 'alacritty', 'wezterm', 'xterm'], 'executable(v:val)')
    let l:labels = [s:t('settings.choose_terminal')]
    for l:i in range(len(l:choices))
      call add(l:labels, (l:i + 1) . '. ' . (empty(l:choices[l:i]) ? s:t('settings.font_auto') : l:choices[l:i]))
    endfor
    let l:n = gnosis#ui#inputlist(l:labels)
    if l:n >= 1 && l:n <= len(l:choices)
      call gnosis#termfont#set('terminal', l:choices[l:n - 1])
      let s:message = s:t('settings.font_family_saved')
    endif
    return
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
    call s:open_editor('vim')
    return
  elseif a:item ==# 'theme_reset'
    let l:s.theme = {'kind': 'builtin'}
  elseif a:item ==# 'app_theme'
    call s:choose_app_theme()
  elseif a:item ==# 'app_custom'
    call s:open_editor('app')
    return
  elseif a:item ==# 'app_theme_reset'
    let l:s.appTheme = {'kind': 'builtin'}
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
  let l:n = gnosis#ui#inputlist(l:labels)
  if l:n >= 1 && l:n <= len(l:choices)
    let s:settings.theme = l:choices[l:n - 1]
  endif
endfunction

" \c のアプリの配色を選ぶ（組み込み＝白 か、自分で作ったもの）
function! s:choose_app_theme() abort
  let l:choices = [{'kind': 'builtin'}]
  for l:name in sort(keys(get(s:settings, 'appCustomThemes', {})))
    call add(l:choices, {'kind': 'custom', 'name': l:name})
  endfor
  let l:labels = [s:t('settings.choose_app_theme')]
  for l:i in range(len(l:choices))
    call add(l:labels, (l:i + 1) . '. ' . s:app_theme_label({'appTheme': l:choices[l:i]}))
  endfor
  let l:n = gnosis#ui#inputlist(l:labels)
  if l:n >= 1 && l:n <= len(l:choices)
    let s:settings.appTheme = l:choices[l:n - 1]
  endif
endfunction

" カスタム配色の編集（カラーパレットとリアルタイムプレビュー。gnosis#theme_edit）。
" a:target … 'vim'（通常の Vim の配色）か 'app'（\c のアプリの配色）。2 つは別の設定で、互いに影響しない。
" 保存するまで設定は書き換えない。取り消せば何も変わらない。
function! s:open_editor(target) abort
  let l:app = a:target ==# 'app'
  let l:th = l:app ? get(s:settings, 'appTheme', {}) : s:settings.theme
  let l:store = l:app ? get(s:settings, 'appCustomThemes', {}) : get(s:settings, 'customThemes', {})
  let l:name = get(l:th, 'kind', '') ==# 'custom' ? get(l:th, 'name', '') : ''
  let l:cur = get(l:store, l:name, {})
  let l:fallback = l:name
  if empty(l:name)
    let l:name = l:app ? 'my-app-theme' : 'my-theme'
  endif
  " 今の色（選んでいるテーマの色）から始める
  let l:colors = !empty(l:cur) ? extend(copy(l:app ? gnosis#theme#app_palette(s:settings) : gnosis#theme#palette(s:settings)), l:cur)
        \ : (l:app ? gnosis#theme#app_palette(s:settings) : gnosis#theme#palette(s:settings))
  let s:editor_sel = s:sel
  call gnosis#theme_edit#open({'target': a:target, 'name': l:name, 'colors': l:colors,
        \ 'on_close': function('s:editor_closed', [a:target])})
endfunction

function! s:editor_closed(target, result) abort
  if !empty(a:result)
    if a:target ==# 'app'
      let s:settings.appCustomThemes = get(s:settings, 'appCustomThemes', {})
      let s:settings.appCustomThemes[a:result.name] = a:result.theme
      let s:settings.appTheme = {'kind': 'custom', 'name': a:result.name}
    else
      let s:settings.customThemes[a:result.name] = a:result.theme
      let s:settings.theme = {'kind': 'custom', 'name': a:result.name}
    endif
    call s:save()
  endif
  " 設定画面に戻る（保存したテーマを読み直して表示）
  call gnosis#settings_ui#open({'vault': s:vault, 'from_start': s:from_start, 'sel': s:editor_sel, 'prev_buf': s:prev_buf})
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
