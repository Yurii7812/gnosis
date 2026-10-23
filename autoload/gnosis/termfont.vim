" =============================================================================
" autoload/gnosis/termfont.vim — Gnosis の文字サイズ（端末のフォント）
"
" 文字を描いているのは Bash でも Vim でもなく端末エミュレーター。端末ごとにできることが違う:
"
"   端末            その場で変える                       Gnosis の窓を開くとき（ランチャー）
"   Konsole         Gnosis が開いた窓だけ（D-Bus で       Gnosis 専用プロファイル Gnosis-<大きさ>
"                   Gnosis 専用プロファイルに切り替え）   （XDG_DATA_DIRS でその窓にだけ見せる）
"   kitty           kitty @ set-font-size（遠隔操作が     -o font_size（Gnosis の窓は遠隔操作を許可）
"                   許可されているとき）
"   Alacritty       alacritty msg config（0.13 以降）     -o font.size
"   WezTerm         できない                             --config font_size
"   XFCE Terminal   できない                             --font "名前 大きさ"
"   xterm           できない                             -fa 名前 -fs 大きさ
"   GNOME Terminal  できない                             できない（端末のプロファイルのまま）
"   GUI 版 Vim      guifont                              guifont
"
" 保存先は Gnosis ホームの terminal.json（vault の外。暗号化 vault を開く前のランチャーも読める）:
"   {"fontSize": 16, "fontFamily": "", "lineSpacing": 2, "terminal": ""}
"   fontFamily が空なら、その端末の等幅フォント（fc-match monospace）
"   terminal が空なら、デスクトップに合った端末を自動で選ぶ（ランチャー）
" ふだんの端末の設定・プロファイルは書き換えない。
"
" 端末側の Ctrl + + / Ctrl + - / Ctrl + 0 は端末が処理してしまい Vim には届かない。
" 変えた大きさを Vim から読み取る方法も無いので、保存はしない（推測で保存しない）。
" 保存される大きさは、設定画面の + / - / 0 / Enter か :GnosisFontSize で変える。
" =============================================================================

let s:min = 6
let s:max = 48

function! gnosis#termfont#defaults() abort
  return {'fontSize': 16, 'fontFamily': '', 'lineSpacing': 2, 'terminal': ''}
endfunction

" フォントの選択肢（設定画面の一覧）: 入っているものだけ。おすすめ（読みやすい・日本語向け）を先に、
" 続けてほかの等幅フォント。各要素は {'name': フォント名, 'note': 説明}。fc-list が無ければ空。
function! gnosis#termfont#font_choices() abort
  if !executable('fc-list')
    return []
  endif
  let l:rec = [
        \ ['Hack', '英字が読みやすい・起動画面の図案がきれい（既定）'],
        \ ['BIZ UDGothic', '日本語向け・読みやすさを検証したユニバーサルデザイン書体'],
        \ ['UDEV Gothic', '日本語向け（BIZ UDゴシック＋JetBrains Mono）'],
        \ ['PlemolJP', '日本語向け（IBM Plex Sans JP＋IBM Plex Mono）'],
        \ ['HackGen', '日本語向け（Hack＋源柔ゴシック）'],
        \ ['Noto Sans Mono CJK JP', '日本語向け（ブラウザと同じ Noto の字形・行が高め）'],
        \ ['DejaVu Sans Mono', ''],
        \ ['Source Code Pro', ''],
        \ ['JetBrains Mono', ''],
        \ ]
  let l:all = split(gnosis#sh#system('fc-list :spacing=mono family; fc-list :spacing=dual:lang=ja family'), "\n")
  let l:names = {}
  for l:line in l:all
    " 「名前,別名」の形は最初の名前だけ
    let l:n = substitute(trim(split(l:line, ',')[0]), '\\\(.\)', '\1', 'g')
    if !empty(l:n) && l:n !~? 'emoji\|signwriting\|symbol'
      let l:names[l:n] = 1
    endif
  endfor
  let l:out = []
  for [l:n, l:note] in l:rec
    " 日本語用の等幅フォントは spacing の値がまちまちなので、名前で入っているかを確かめる
    if has_key(l:names, l:n) || !empty(trim(gnosis#sh#system('fc-list ' . shellescape(l:n) . ' family')))
      call add(l:out, {'name': l:n, 'note': l:note})
      silent! call remove(l:names, l:n)
    endif
  endfor
  for l:n in sort(keys(l:names))
    call add(l:out, {'name': l:n, 'note': ''})
  endfor
  return l:out
endfunction

function! gnosis#termfont#file() abort
  return gnosis#home#path('terminal.json')
endfunction

function! gnosis#termfont#clamp(n) abort
  return max([s:min, min([s:max, a:n])])
endfunction

function! gnosis#termfont#load() abort
  let l:d = gnosis#termfont#defaults()
  let l:raw = gnosis#home#read_json(gnosis#termfont#file(), {})
  if empty(l:raw)
    " 以前の版は文字サイズを vault の設定（.gnosis/settings.json）にだけ保存していた
    let l:vault = gnosis#settings#current_vault()
    if empty(l:vault)
      let l:vault = gnosis#vault#last()
    endif
    if !empty(l:vault) && filereadable(gnosis#settings#file(l:vault))
      let l:old = gnosis#home#read_json(gnosis#settings#file(l:vault), {})
      if type(get(l:old, 'fontSize', '')) == v:t_number
        let l:d.fontSize = l:old.fontSize
      endif
    endif
  endif
  for [l:k, l:v] in items(l:raw)
    if has_key(l:d, l:k) && type(l:v) == type(l:d[l:k])
      let l:d[l:k] = l:v
    endif
  endfor
  let l:d.fontSize = gnosis#termfont#clamp(l:d.fontSize)
  let l:d.lineSpacing = max([0, min([12, l:d.lineSpacing])])
  return l:d
endfunction

function! gnosis#termfont#save(d) abort
  call gnosis#home#write_json(gnosis#termfont#file(), a:d)
endfunction

" ---------------------------------------------------------------------------
" いま Vim を表示している端末
"   {'name': 'konsole' など, 'label': 表示名, 'live': その場で変えられるか,
"    'launch': Gnosis の窓を開くときに大きさを渡せるか, 'own': Gnosis が開いた窓か}
" ---------------------------------------------------------------------------
function! gnosis#termfont#detect() abort
  let l:own = !empty($GNOSIS_TERMINAL_KIND)
  let l:name = l:own ? $GNOSIS_TERMINAL_KIND : s:guess_terminal()
  if has('gui_running')
    let l:name = 'gui'
  endif
  let l:labels = {'konsole': 'Konsole', 'kitty': 'kitty', 'alacritty': 'Alacritty', 'wezterm': 'WezTerm',
        \ 'xfce4-terminal': 'XFCE Terminal', 'gnome-terminal': 'GNOME Terminal', 'xterm': 'xterm',
        \ 'foot': 'foot', 'ghostty': 'Ghostty',
        \ 'gui': 'GUI Vim', 'unknown': '?'}
  let l:live = 0
  if l:name ==# 'gui'
    let l:live = 1
  elseif l:name ==# 'konsole'
    " Gnosis 専用プロファイルが見えるのは、Gnosis が開いた Konsole の窓だけ
    let l:live = l:own && !empty($KONSOLE_DBUS_SERVICE) && !empty($KONSOLE_DBUS_SESSION) && !empty(s:dbus_tool())
  elseif l:name ==# 'kitty'
    let l:live = !empty($KITTY_WINDOW_ID) && executable('kitty')
  elseif l:name ==# 'alacritty'
    let l:live = !empty($ALACRITTY_SOCKET) && executable('alacritty')
  elseif l:name ==# 'gnome-terminal'
    let l:live = l:own && executable('gsettings') && executable('python3')
          \ && filereadable(gnosis#home#path('terminal', 'gnome-profile-id'))
  endif
  return {'name': l:name, 'label': get(l:labels, l:name, l:name), 'live': l:live,
        \ 'launch': index(['konsole', 'kitty', 'alacritty', 'wezterm', 'xfce4-terminal', 'xterm', 'gnome-terminal', 'foot', 'ghostty', 'gui'], l:name) >= 0,
        \ 'own': l:own}
endfunction

function! s:guess_terminal() abort
  if !empty($KONSOLE_DBUS_SESSION) || !empty($KONSOLE_VERSION)
    return 'konsole'
  elseif !empty($KITTY_WINDOW_ID)
    return 'kitty'
  elseif !empty($ALACRITTY_SOCKET) || !empty($ALACRITTY_WINDOW_ID) || !empty($ALACRITTY_LOG)
    return 'alacritty'
  elseif !empty($WEZTERM_PANE) || $TERM_PROGRAM ==# 'WezTerm'
    return 'wezterm'
  elseif !empty($XTERM_VERSION)
    return 'xterm'
  elseif !empty($VTE_VERSION)
    " VTE を使う端末（XFCE Terminal・GNOME Terminal など）。親プロセスの名前で見分ける
    let l:p = s:ancestor_names()
    for l:n in ['xfce4-terminal', 'gnome-terminal']
      if !empty(filter(copy(l:p), 'v:val =~# "^" . l:n'))
        return l:n
      endif
    endfor
    return 'vte'
  endif
  return 'unknown'
endfunction

" 親プロセスの名前（Linux の /proc だけ。無ければ []）
function! s:ancestor_names() abort
  let l:out = []
  if !isdirectory('/proc')
    return l:out
  endif
  let l:pid = getpid()
  for l:i in range(12)
    let l:stat = '/proc/' . l:pid . '/stat'
    if !filereadable(l:stat)
      break
    endif
    let l:s = get(readfile(l:stat), 0, '')
    let l:m = matchlist(l:s, '^\d\+ (\(.*\)) \S \(\d\+\)')
    if empty(l:m)
      break
    endif
    call add(l:out, l:m[1])
    let l:pid = str2nr(l:m[2])
    if l:pid <= 1
      break
    endif
  endfor
  return l:out
endfunction

function! s:dbus_tool() abort
  for l:t in ['qdbus6', 'qdbus', 'gdbus']
    if executable(l:t)
      return l:t
    endif
  endfor
  return ''
endfunction

function! s:konsole_call(method, ...) abort
  let l:tool = s:dbus_tool()
  if l:tool ==# 'gdbus'
    let l:cmd = ['gdbus', 'call', '--session', '--dest', $KONSOLE_DBUS_SERVICE, '--object-path', $KONSOLE_DBUS_SESSION,
          \ '--method', 'org.kde.konsole.Session.' . a:method] + a:000
  else
    let l:cmd = [l:tool, $KONSOLE_DBUS_SERVICE, $KONSOLE_DBUS_SESSION, 'org.kde.konsole.Session.' . a:method] + a:000
  endif
  let l:out = gnosis#sh#system(join(map(l:cmd, 'shellescape(v:val)'), ' ') . ' 2>/dev/null')
  if gnosis#sh#error() != 0
    return v:null
  endif
  " gdbus は ('名前',) の形で返す
  return trim(substitute(l:out, '^(''\(.*\)'',)\s*$', '\1', ''))
endfunction

" ---------------------------------------------------------------------------
" その場で反映する。戻り値は反映できたか（確かめられたときだけ 1）。
" ---------------------------------------------------------------------------
function! gnosis#termfont#apply_live(d) abort
  let l:t = gnosis#termfont#detect()
  if !l:t.live
    return 0
  endif
  let l:size = a:d.fontSize
  if l:t.name ==# 'gui'
    let l:family = !empty(a:d.fontFamily) ? a:d.fontFamily : get(g:, 'gnosis_gui_font_name', '')
    if has('win32')
      let &guifont = (empty(l:family) ? 'Consolas' : l:family) . ':h' . l:size
    elseif has('mac') || has('macunix')
      let &guifont = (empty(l:family) ? 'Menlo-Regular' : l:family) . ':h' . l:size
    else
      let &guifont = (empty(l:family) ? 'Monospace' : l:family) . ' ' . l:size
    endif
    return 1
  elseif l:t.name ==# 'konsole'
    let l:want = 'Gnosis-' . l:size
    call s:konsole_call('setProfile', l:want)
    " 切り替わったかを Konsole に聞いて確かめる（プロファイルが見えない窓では変わらない）
    return s:konsole_call('profile') ==# l:want
  elseif l:t.name ==# 'kitty'
    silent call gnosis#sh#system('kitty @ set-font-size ' . l:size . ' 2>/dev/null')
    if gnosis#sh#error() == 0
      let s:restore_kitty = !l:t.own
      return 1
    endif
  elseif l:t.name ==# 'alacritty'
    let l:w = empty($ALACRITTY_WINDOW_ID) ? '' : ' -w ' . shellescape($ALACRITTY_WINDOW_ID)
    silent call gnosis#sh#system('alacritty msg config' . l:w . ' font.size=' . l:size . ' 2>/dev/null')
    if gnosis#sh#error() == 0
      let s:restore_alacritty = !l:t.own
      return 1
    endif
  elseif l:t.name ==# 'gnome-terminal'
    " GNOME Terminal は Gnosis 専用プロファイルを更新すると現在の窓にも反映する。
    " 非 Gnosis ウィンドウ、既定プロファイルは一切変更しない。
    let l:dir = get(g:, 'gnosis_dir', '')
    if !empty(l:dir)
      let l:family = empty(a:d.fontFamily) ? 'Monospace' : a:d.fontFamily
      let l:cmd = ['python3', l:dir . '/python/gnome_font_profile.py',
            \ $GNOSIS_HOME, l:family, string(l:size)]
      call gnosis#sh#system(join(map(copy(l:cmd), 'shellescape(v:val)'), ' ') . ' >/dev/null 2>&1')
      return gnosis#sh#error() == 0
    endif
  endif
  return 0
endfunction

" ふだんの端末の窓（Gnosis が開いていない窓）の大きさを変えたときは、終了時に元へ戻す
function! gnosis#termfont#restore_on_exit() abort
  if get(s:, 'restore_kitty', 0)
    silent call gnosis#sh#system('kitty @ set-font-size 0 2>/dev/null')
  endif
  if get(s:, 'restore_alacritty', 0)
    let l:w = empty($ALACRITTY_WINDOW_ID) ? '' : ' -w ' . shellescape($ALACRITTY_WINDOW_ID)
    silent call gnosis#sh#system('alacritty msg config --reset' . l:w . ' 2>/dev/null')
  endif
endfunction

" 文字サイズを変えて保存し、できればその場で反映する。
" 戻り値 {'size': 大きさ, 'saved': 保存できたか, 'applied': その場で変わったか, 'terminal': detect()}
" 一時的な大きさ（保存しない）。\+ \- で変え、\= で保存してある大きさに戻す。
" 端末側の Ctrl + + / Ctrl + - で変えたあとでも、\= は保存した大きさを端末に送り直すので、戻る（その場で変えられる端末のとき）
let s:temp = 0

function! gnosis#termfont#bump(d) abort
  let l:d = gnosis#termfont#load()
  let s:temp += a:d
  let l:d.fontSize = gnosis#termfont#clamp(l:d.fontSize + s:temp)
  if gnosis#termfont#apply_live(l:d)
    echo 'Gnosis: ' . printf(gnosis#i18n#tr('文字サイズ %d（一時的。\= で保存してある大きさに戻す）'), l:d.fontSize)
  else
    let s:temp -= a:d
    echohl WarningMsg | echo 'Gnosis: ' . gnosis#i18n#tr('この端末では、その場で文字の大きさを変えられません（端末の設定で変える）') | echohl NONE
  endif
endfunction

function! gnosis#termfont#restore() abort
  let s:temp = 0
  let l:d = gnosis#termfont#load()
  if gnosis#termfont#apply_live(l:d)
    echo 'Gnosis: ' . printf(gnosis#i18n#tr('文字サイズを保存してある大きさ（%d）に戻しました'), l:d.fontSize)
  else
    echohl WarningMsg | echo 'Gnosis: ' . gnosis#i18n#tr('この端末では、その場で文字の大きさを変えられません（端末の Ctrl + 0 で戻す）') | echohl NONE
  endif
endfunction

function! gnosis#termfont#set_size(n) abort
  let l:d = gnosis#termfont#load()
  let l:d.fontSize = gnosis#termfont#clamp(a:n)
  return s:store_and_apply(l:d)
endfunction

function! gnosis#termfont#set(key, value) abort
  let l:d = gnosis#termfont#load()
  let l:d[a:key] = a:value
  return s:store_and_apply(l:d)
endfunction

function! s:store_and_apply(d) abort
  let l:saved = 1
  try
    call gnosis#termfont#save(a:d)
  catch
    let l:saved = 0
  endtry
  " 以前の版・アプリ（Electron）向けに、開いている vault の設定にも同じ大きさを書く
  let l:vault = gnosis#settings#current_vault()
  if !empty(l:vault) && isdirectory(l:vault)
    try
      let l:s = gnosis#settings#load(l:vault)
      if l:s.fontSize != a:d.fontSize
        let l:s.fontSize = a:d.fontSize
        call gnosis#settings#save(l:vault, l:s)
      endif
    catch
    endtry
  endif
  let l:applied = gnosis#termfont#apply_live(a:d)
  let g:gnosis_font_live_applied = l:applied
  return {'size': a:d.fontSize, 'saved': l:saved, 'applied': l:applied, 'terminal': gnosis#termfont#detect()}
endfunction

" 結果の説明（設定画面・:GnosisFontSize が出す）。保存と反映を分けて伝える。
function! gnosis#termfont#describe(r) abort
  if !a:r.saved
    return gnosis#i18n#t('font.save_failed', gnosis#termfont#file())
  endif
  if a:r.applied
    return gnosis#i18n#t('font.applied', a:r.size, a:r.terminal.label)
  endif
  return gnosis#i18n#t(s:reason_key(a:r.terminal), a:r.size, a:r.terminal.label)
endfunction

" その場で変えられない理由の説明のキー
function! s:reason_key(t) abort
  if a:t.name ==# 'konsole'
    return a:t.own ? 'font.konsole_no_dbus' : 'font.konsole_other_window'
  elseif a:t.name ==# 'kitty'
    return 'font.kitty_no_remote'
  elseif a:t.launch
    return 'font.next_window'
  endif
  return 'font.unsupported'
endfunction

" 設定画面に出す、いまの端末でできること
function! gnosis#termfont#status() abort
  let l:t = gnosis#termfont#detect()
  if l:t.live
    return gnosis#i18n#t('font.status_live', l:t.label)
  endif
  return gnosis#i18n#t(s:reason_key(l:t), gnosis#termfont#load().fontSize, l:t.label)
endfunction

" :GnosisFontSize [大きさ | +1 | -1 | reset]
function! gnosis#termfont#command(arg) abort
  let l:a = trim(a:arg)
  let l:cur = gnosis#termfont#load().fontSize
  if empty(l:a)
    echo 'Gnosis: ' . gnosis#i18n#t('font.current', l:cur) . '  ' . gnosis#termfont#status()
    return
  endif
  if l:a ==# 'reset'
    let l:n = gnosis#termfont#defaults().fontSize
  elseif l:a =~# '^[+-]\d\+$'
    let l:n = l:cur + str2nr(l:a)
  elseif l:a =~# '^\d\+$'
    let l:n = str2nr(l:a)
  else
    echohl WarningMsg | echo 'Gnosis: ' . gnosis#i18n#t('settings.bad_font') | echohl NONE
    return
  endif
  let l:r = gnosis#termfont#set_size(l:n)
  redraw
  echo 'Gnosis: ' . gnosis#termfont#describe(l:r)
endfunction
