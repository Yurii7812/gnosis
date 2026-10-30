" =============================================================================
" autoload/gnosis/hint.vim — リストビューと右のパネルの共通部品
"
"   ヒント行 … 窓の一番上に「今のモード」と最低限のキーを 1 行で出す（バッファの行は増やさない仮想テキスト）。
"              K、またはメニューの最後の項目でオン・オフ（設定は hint.json に残る）。
"   メニュー … m で開く。選択肢を番号付きで並べ、番号か j k Enter で選ぶ。
" =============================================================================

let s:type = 'gnosis_hint'

function! gnosis#hint#on() abort
  if !exists('s:on')
    let l:d = gnosis#home#read_json(gnosis#home#path('hint.json'), {})
    " CUI は起動時に必ずヒントを表示。以前の hint.json の OFF は起動時に引き継がない。
    " 明示的な g:gnosis_hint=0 / GNOSIS_HINT=0 は尊重（テスト・管理者向け）。
    " GUI は従来の保存設定を維持する。
    if empty($GNOSIS_GUI_PORT)
      let s:on = get(g:, 'gnosis_hint', $GNOSIS_HINT ==# '0' ? 0 : 1)
    else
      let s:on = type(get(l:d, 'on', '')) == v:t_number ? !!l:d.on : get(g:, 'gnosis_hint', $GNOSIS_HINT ==# '0' ? 0 : 1)
    endif
  endif
  return s:on
endfunction

function! s:ensure_type() abort
  if empty(prop_type_get(s:type))
    highlight default link GnosisHint Comment
    call prop_type_add(s:type, {'highlight': 'GnosisHint'})
  endif
endfunction

" 現在の窓のバッファの先頭に、ヒント行を付け直す（オフなら外すだけ）。text が空でも外す。
function! gnosis#hint#put(text) abort
  " CUI はメッセージ行だけを使い、上の仮想ヒント行は作らない。
  if empty($GNOSIS_GUI_PORT)
    if !empty(prop_type_get(s:type))
      silent! call prop_remove({'type': s:type, 'all': 1}, 1, line('$'))
    endif
    return
  endif
  call s:ensure_type()
  silent! call prop_remove({'type': s:type, 'all': 1}, 1, line('$'))
  if gnosis#hint#on() && !empty(a:text) && line('$') >= 1
    call prop_add(1, 0, {'type': s:type, 'text': a:text, 'text_align': 'above'})
  endif
endfunction

" 内容が違っていたら付け直す（アウトラインのように、中身ごと書き換えられるバッファ用）
function! gnosis#hint#ensure(text) abort
  call s:ensure_type()
  let l:now = prop_list(1, {'types': [s:type]})
  if gnosis#hint#on() ? (!empty(l:now) && l:now[0].text ==# a:text) : empty(l:now) | return | endif
  call gnosis#hint#put(a:text)
endfunction

" 「キー:名前」を並べ、今のものを [ ] で囲む。items = [[キー, 名前], …]
function! gnosis#hint#line(items, current, tail) abort
  let l:parts = []
  for [l:key, l:name] in a:items
    let l:s = l:key . ':' . gnosis#i18n#tr(l:name)
    call add(l:parts, l:key ==# a:current ? '[' . l:s . ']' : l:s)
  endfor
  return ' ' . join(l:parts, ' ') . '  |  ' . a:tail
endfunction

" ヒント行のオン・オフ。after は、付け直しに呼ぶ関数（無ければ何もしない）
function! gnosis#hint#toggle(After) abort
  let s:on = !gnosis#hint#on()
  call gnosis#home#write_json(gnosis#home#path('hint.json'), {'on': s:on})
  if type(a:After) == v:t_func | call a:After() | endif
  if s:on
    call gnosis#hint#cmdline_schedule()
  else
    call gnosis#hint#cmdline_hide()
  endif
  echo gnosis#i18n#tr(s:on ? 'ヒント行: オン' : 'ヒント行: オフ')
endfunction

" メニュー。entries = [[見出し, Funcref または {'sub': entries, 'title': …}], …]。選んだものを実行する
" 見出しが空の項目は区切りとして出さない。
function! gnosis#hint#menu(title, entries) abort
  let l:lines = [a:title]
  for l:i in range(len(a:entries))
    call add(l:lines, a:entries[l:i][0])
  endfor
  let l:n = gnosis#ui#inputlist(l:lines)
  if l:n < 1 || l:n > len(a:entries) | return | endif
  let l:Act = a:entries[l:n - 1][1]
  if type(l:Act) == v:t_dict
    call gnosis#hint#menu(get(l:Act, 'title', a:entries[l:n - 1][0]), l:Act.sub)
  elseif type(l:Act) == v:t_func
    call l:Act()
  endif
endfunction

" メニューの見出し: 今の選択に ● を付ける
function! gnosis#hint#mark(on, text) abort
  return (a:on ? '● ' : '  ') . gnosis#i18n#tr(a:text)
endfunction

" ---- CUI 全幅のコマンド行ヒント（ノートや入力中には表示しない） ----
let s:cmdline_timer = -1
let s:cmdline_shown = ''

" ウィンドウ幅に合わせ、項目を丸ごと取捨選択する。途中で切らない。
function! gnosis#hint#fit_items(items, width) abort
  let l:text = ''
  for l:item in a:items
    let l:next = empty(l:text) ? l:item : l:text . '  ' . l:item
    if strdisplaywidth(l:next) <= a:width
      let l:text = l:next
    endif
  endfor
  return l:text
endfunction

" リストの最上行。通常幅では名称と直通キー、極小幅では短縮表記。
function! gnosis#hint#tabs(current, width) abort
  let l:keys = ['fz', 'links', 'search', 'similar']
  let l:long = ['F:番号', 'L:リンク', 'S:検索', 'R:類似']
  let l:short = ['F番号', 'Lリンク', 'S検索', 'R類似']
  let l:tiny = ['F', 'L', 'S', 'R']
  for l:labels in [l:long, l:short, l:tiny]
    let l:parts = []
    for l:i in range(4)
      let l:part = l:labels[l:i]
      call add(l:parts, l:keys[l:i] ==# a:current ? '[' . l:part . ']' : l:part)
    endfor
    let l:result = join(l:parts, ' ')
    if strdisplaywidth(l:result) <= a:width
      return l:result
    endif
  endfor
  return strdisplaywidth('[Tab]') <= a:width ? '[Tab]' : ''
endfunction

function! s:cmdline_active() abort
  if !empty($GNOSIS_GUI_PORT) || !gnosis#hint#on()
    return 0
  endif
  if &filetype !=# 'gnosis-mandala' || mode(1) !~# '^n'
    return 0
  endif
  if get(b:, 'gnosis_nav_input', 0) || !empty(getcmdtype()) || !empty(popup_list())
    return 0
  endif
  return 1
endfunction

function! s:cmdline_items() abort
  let l:view = gnosis#mview#view()
  if l:view ==# 'mandala'
    return ['w:順位', 'r/R:関連', 'v:外向き', 'u/U:見出し', 'f:9×9',
          \ 'Z:設定', '?:ヘルプ', 'm:メニュー', 'x:絞込', 's:検索',
          \ 'c/C:近接', 'D:配下', 'a/i/d:表示', 'P:保存設定',
          \ 'H:強調', 't:時間', 'p:本文', 'L:凡例', '+:深さ']
  elseif l:view ==# 'fz'
    return ['Tab:切替', 'u:上位', 'm:メニュー', '?:ヘルプ', 's:検索',
          \ 'l:リンク', 'r:類似', 'za:折畳', 'o:起点', 'F:全画面']
  endif
  let l:mode = get(gnosis#listnav#state(), 'mode', 'links')
  if l:mode ==# 'search'
    return ['Tab:切替', 's:検索語', 'S:範囲', 'x:絞込', 'H:強調', 'n/N:次前',
          \ 'm:メニュー', '?:ヘルプ', 'w:順位', 'f:番号']
  elseif l:mode ==# 'similar'
    return ['Tab:切替', 'r:類似', 'x:絞込', 'w:順位', 'H:強調',
          \ 'm:メニュー', '?:ヘルプ', 'o:起点', 'f:番号']
  endif
  return ['Tab:切替', 'x:絞込', 'm:メニュー', '?:ヘルプ',
        \ 'b:子', 'p:親', 'g:群', 'R:関連', '+:深さ',
        \ 'w:順位', 'f:番号', 'o:起点']
endfunction

function! gnosis#hint#cmdline_hide() abort
  if s:cmdline_timer >= 0
    call timer_stop(s:cmdline_timer)
    let s:cmdline_timer = -1
  endif
  if !empty(s:cmdline_shown)
    let s:cmdline_shown = ''
    " 入力開始時には ':' や '/' のプロンプトを消さない。
    if empty(getcmdtype()) && mode(1) ==# 'n'
      echo ''
    endif
  endif
endfunction

function! gnosis#hint#cmdline_show(...) abort
  let s:cmdline_timer = -1
  if !s:cmdline_active()
    return
  endif
  let l:text = gnosis#hint#fit_items(s:cmdline_items(), max([0, &columns - 1]))
  if empty(l:text)
    return
  endif
  redraw
  echo l:text
  let s:cmdline_shown = l:text
endfunction

function! gnosis#hint#cmdline_schedule() abort
  if !empty($GNOSIS_GUI_PORT) | return | endif
  if s:cmdline_timer >= 0 | call timer_stop(s:cmdline_timer) | endif
  let s:cmdline_timer = timer_start(45, function('gnosis#hint#cmdline_show'))
endfunction

function! gnosis#hint#cmdline_install() abort
  if !empty($GNOSIS_GUI_PORT) || exists('s:cmdline_installed') | return | endif
  let s:cmdline_installed = 1
  augroup gnosis_cui_command_hints
    autocmd!
    " 起動直後は通常の再描画が続くので、VimEnter だけでなく SafeState でも
    " 初回のヒント表示を保証する（通常の表示更新でループさせない）。
    autocmd VimEnter * call gnosis#hint#cmdline_schedule()
    if exists('##SafeState')
      autocmd SafeState * if empty(s:cmdline_shown) | call gnosis#hint#cmdline_schedule() | endif
    endif
    autocmd BufEnter,WinEnter,CursorMoved,VimResized * call gnosis#hint#cmdline_schedule()
    autocmd WinLeave * call gnosis#hint#cmdline_hide()
    autocmd CmdlineEnter * call gnosis#hint#cmdline_hide()
    autocmd CmdlineLeave * call gnosis#hint#cmdline_schedule()
    autocmd ModeChanged * call gnosis#hint#cmdline_schedule()
  augroup END
  call gnosis#hint#cmdline_schedule()
endfunction
