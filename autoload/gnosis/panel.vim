" =============================================================================
" autoload/gnosis/panel.vim — 右側のパネル（アウトライン・タブのボード・ハブ。1 つに統合）と、窓の行き来
"
"   \s        … 右のパネルを出す（前に使った中身。最初はアウトライン）。\o \q \h は、その中身で出す近道。
"              パネルは右に 1 つだけ。同じキーをもう一度押すと、ノートの窓 ⇔ パネル を行き来する。パネルの中の q で閉じる。
"              （\q のボードの中の D で、全部のタブを消す）
"   パネルの中のキー（3 つの中身どれでも同じ）
"     Tab / Shift+Tab（または Ctrl+→ / Ctrl+←）  アウトライン → タブ → ハブ と切り替える（o t h で直接その中身へ）
"     s 検索  n N 次・前のヒット   x 絞り込み（合わない行を畳む）   H ハイライト   m メニュー   K ヒント行のオン・オフ   Esc 全部やめる
"       書き方は gs・曼荼羅の s / x / m と同じ（空白 AND・語の前の - で NOT・| で OR・"…" で句）
"     e   \l で入れるノートを選んでいる最中に、カーソルの行のノートに決める（決めずに動き回ってもよい）
"   Shift+← Shift+→ （または gh gl）… 窓を 1 つ左・右へ。左のビュー（曼荼羅 / Folgezettel）・ノート・右のパネルの順で、端では止まる。
" =============================================================================

let s:P = {'kind': '', 'win': -1, 'src': -1, 'last': 'outline'}
let s:KINDS = ['outline', 'tabs', 'hub']

function! s:width() abort
  return get(g:, 'gnosis_panel_width', get(g:, 'gnosis_outline_width', 30))
endfunction

" 右のパネルが今どれか。'' / 'outline' / 'hub' / 'tabs'
function! gnosis#panel#kind() abort
  if gnosis#outline#is_open()
    return 'outline'
  endif
  if s:P.win > 0 && !empty(getwininfo(s:P.win)) && !empty(s:P.kind)
    return s:P.kind
  endif
  let s:P.kind = ''
  let s:P.win = -1
  return ''
endfunction

function! s:panel_win() abort
  let l:k = gnosis#panel#kind()
  return l:k ==# 'outline' ? gnosis#outline#win() : (l:k ==# '' ? -1 : s:P.win)
endfunction

" ノートの窓（パネルでも、曼荼羅 / Folgezettel でもない、ふつうの窓）
function! s:note_win() abort
  let l:nw = gnosis#mview#note_win()
  if l:nw > 0 && l:nw != s:P.win
    return l:nw
  endif
  for l:w in range(1, winnr('$'))
    let l:id = win_getid(l:w)
    if l:id != s:P.win && l:id != gnosis#outline#win() && getbufvar(winbufnr(l:id), '&buftype') ==# '' && getbufvar(winbufnr(l:id), '&filetype') !~# '^gnosis-'
      return l:id
    endif
  endfor
  return -1
endfunction

" \o \h \q: kind は 'outline' / 'hub' / 'tabs'
function! gnosis#panel#key(kind) abort
  let l:cur = gnosis#panel#kind()
  if l:cur ==# a:kind
    " 同じキー: ノートの窓 ⇔ パネル
    let l:pw = s:panel_win()
    if win_getid() == l:pw
      let l:nw = s:note_win()
      if l:nw > 0 | call win_gotoid(l:nw) | endif
    else
      call win_gotoid(l:pw)
    endif
    return
  endif
  if !empty(l:cur)
    " 別の中身が出ている: 閉じて、押したキーの中身に差し替える（パネルは 1 つだけ）
    call s:close_quiet()
  endif
  call s:open(a:kind)
endfunction

function! s:close_quiet() abort
  if gnosis#outline#is_open()
    call gnosis#outline#close()
  elseif s:P.win > 0 && !empty(getwininfo(s:P.win))
    call win_execute(s:P.win, 'close')
  endif
  let s:P.kind = ''
  let s:P.win = -1
endfunction

function! s:open(kind) abort
  let s:P.last = a:kind
  if a:kind ==# 'outline'
    call gnosis#outline#open()
    return
  endif
  let l:file = gnosis#hub_panel_file(a:kind ==# 'tabs' ? 'tabs' : '')
  let l:src = s:note_win()
  if l:src > 0 && win_getid() != l:src
    call win_gotoid(l:src)
  endif
  call gnosis#save_current_note()
  execute 'botright vertical ' . s:width() . 'new'
  let s:P.win = win_getid()
  let s:P.kind = a:kind
  silent! execute 'edit ' . fnameescape(l:file)
  setlocal bufhidden=hide noundofile nowrap winfixwidth
  nnoremap <buffer><nowait><silent> q <Cmd>call gnosis#panel#close()<CR>
  " < > は境目を動かす向き（右のパネルでは < で境目が左へ＝広がる、> で右へ＝狭まる）
  nnoremap <buffer><nowait><silent> <lt> <Cmd>call gnosis#panel#width(4)<CR>
  nnoremap <buffer><nowait><silent> > <Cmd>call gnosis#panel#width(-4)<CR>
  nnoremap <buffer><nowait><silent> \W <Cmd>call gnosis#mview#only_note()<CR>
  if a:kind ==# 'tabs'
    nnoremap <buffer><nowait><silent> D <Cmd>call gnosis#panel#tabs_clear()<CR>
  endif
  call gnosis#panel#attach()
  augroup gnosis_panel_buf
    autocmd! * <buffer>
    autocmd BufWinLeave <buffer> let s:P.win = -1 | let s:P.kind = ''
  augroup END
endfunction

" \s: 右のパネルを出す（前に使った中身。無ければアウトライン）。出ていれば ノートの窓 ⇔ パネル
function! gnosis#panel#open_last() abort
  call gnosis#panel#key(empty(gnosis#panel#kind()) ? s:P.last : gnosis#panel#kind())
endfunction

" パネルの中から別の中身へ（パネルの窓にカーソルを置いたまま）
function! gnosis#panel#switch(kind) abort
  if index(s:KINDS, a:kind) < 0 || gnosis#panel#kind() ==# a:kind
    return
  endif
  if !empty(gnosis#panel#kind())
    call s:close_quiet()
  endif
  call s:open(a:kind)
endfunction

" Tab（1）/ Shift+Tab（-1）: アウトライン → タブ → ハブ → アウトライン
function! gnosis#panel#cycle(d) abort
  let l:i = index(s:KINDS, gnosis#panel#kind())
  if l:i < 0
    return
  endif
  call gnosis#panel#switch(s:KINDS[(l:i + a:d + len(s:KINDS)) % len(s:KINDS)])
endfunction

" 何を出しているか（試験用）。{'kind', 'query', 'filter', 'highlight'}
function! gnosis#panel#info() abort
  let l:w = s:panel_win()
  let l:g = {k -> l:w > 0 ? getwinvar(l:w, k, '') : ''}
  return {'kind': gnosis#panel#kind(), 'query': l:g('gnosis_panel_q'), 'filter': l:g('gnosis_panel_f'), 'highlight': l:g('gnosis_panel_h')}
endfunction

" ---- パネルの窓の共通の動き（3 つの中身どれでも）----------------------------------------------------

" 今の窓（パネル）に、共通のキーと見出し（状態行）を付ける。中身の窓を作った直後に呼ぶ
function! gnosis#panel#attach() abort
  nnoremap <buffer><nowait><silent> <Tab>   <Cmd>call gnosis#panel#cycle(1)<CR>
  nnoremap <buffer><nowait><silent> <S-Tab> <Cmd>call gnosis#panel#cycle(-1)<CR>
  " Ctrl+→ / Ctrl+←: 左のビューの切り替えと同じ向きで、アウトライン → タブ → ハブ（端末が Ctrl+矢印を送らないときは Tab）
  nnoremap <buffer><nowait><silent> <C-Right> <Cmd>call gnosis#panel#cycle(1)<CR>
  nnoremap <buffer><nowait><silent> <C-Left>  <Cmd>call gnosis#panel#cycle(-1)<CR>
  nnoremap <buffer><nowait><silent> o <Cmd>call gnosis#panel#switch('outline')<CR>
  nnoremap <buffer><nowait><silent> t <Cmd>call gnosis#panel#switch('tabs')<CR>
  nnoremap <buffer><nowait><silent> h <Cmd>call gnosis#panel#switch('hub')<CR>
  nnoremap <buffer><nowait><silent> s <Cmd>call gnosis#panel#search()<CR>
  nnoremap <buffer><nowait><silent> n <Cmd>call gnosis#panel#next(1)<CR>
  nnoremap <buffer><nowait><silent> N <Cmd>call gnosis#panel#next(-1)<CR>
  nnoremap <buffer><nowait><silent> x <Cmd>call gnosis#panel#filter()<CR>
  nnoremap <buffer><nowait><silent> H <Cmd>call gnosis#panel#highlight()<CR>
  nnoremap <buffer><nowait><silent> m <Cmd>call gnosis#panel#menu()<CR>
  nnoremap <buffer><nowait><silent> K <Cmd>call gnosis#panel#toggle_hint()<CR>
  nnoremap <buffer><nowait><silent> <Esc> <Cmd>call gnosis#panel#clear()<CR>
  nnoremap <buffer><nowait><silent> e <Cmd>call gnosis#panel#decide()<CR>
  nnoremap <buffer><nowait><silent> ? <Cmd>call gnosis#panel#help()<CR>
  setlocal statusline=%!gnosis#panel#status()
  call gnosis#panel#hint()
  augroup gnosis_panel_hint
    autocmd! * <buffer>
    " アウトラインのように中身ごと書き換わるバッファでも、ヒント行を付け直す
    autocmd CursorMoved,BufWinEnter,TextChanged <buffer> call gnosis#panel#hint()
  augroup END
endfunction

" 窓の一番上のヒント行: 今の中身（[ ]）と、最低限のキー
function! s:hint_text() abort
  let l:k = win_getid() == s:P.win ? s:P.kind : (gnosis#outline#is_open() && win_getid() == gnosis#outline#win() ? 'outline' : s:P.kind)
  let l:cur = get({'outline': 'o', 'tabs': 't', 'hub': 'h'}, l:k, '')
  return gnosis#hint#line([['o', 'アウトライン'], ['t', 'タブ'], ['h', 'ハブ']], l:cur,
        \ 'm:' . gnosis#i18n#tr('メニュー') . ' ?:' . gnosis#i18n#tr('説明'))
endfunction

function! gnosis#panel#hint() abort
  call gnosis#hint#ensure(s:hint_text())
endfunction

function! gnosis#panel#toggle_hint() abort
  call gnosis#hint#toggle({-> gnosis#hint#put(s:hint_text())})
endfunction

" m: やることを番号で選ぶメニュー
function! gnosis#panel#menu() abort
  let l:k = s:hint_kind()
  let l:entries = [
        \ [gnosis#hint#mark(l:k ==# 'outline', 'アウトライン（見出しの一覧）'), function('gnosis#panel#switch', ['outline'])],
        \ [gnosis#hint#mark(l:k ==# 'tabs', 'タブ（開いているノートのボード）'), function('gnosis#panel#switch', ['tabs'])],
        \ [gnosis#hint#mark(l:k ==# 'hub', 'ハブ（リンクの一覧）'), function('gnosis#panel#switch', ['hub'])],
        \ ['  ' . gnosis#i18n#tr('検索') . ' …', function('gnosis#panel#search')],
        \ ['  ' . gnosis#i18n#tr('絞り込み') . ' …', function('gnosis#panel#filter')],
        \ ['  ' . gnosis#i18n#tr('ハイライト') . ' …', function('gnosis#panel#highlight')],
        \ ['  ' . gnosis#i18n#tr('検索・絞り込み・ハイライトをやめる'), function('gnosis#panel#clear')],
        \ [gnosis#hint#mark(gnosis#hint#on(), '上のヒント行を出す'), function('gnosis#panel#toggle_hint')],
        \ ['  ' . gnosis#i18n#tr('パネルを閉じる'), function('gnosis#panel#close')]]
  call gnosis#hint#menu(gnosis#i18n#tr('右のパネル'), l:entries)
endfunction

function! s:hint_kind() abort
  return win_getid() == s:P.win ? s:P.kind : (gnosis#outline#is_open() && win_getid() == gnosis#outline#win() ? 'outline' : s:P.kind)
endfunction

" ? のヘルプの行（試験用に外へも出す）
function! gnosis#panel#help_lines() abort
  return [
        \ gnosis#i18n#tr('右のパネル（アウトライン・タブ・ハブを 1 つに統合）'),
        \ '',
        \ 'Tab / Ctrl+→   ' . gnosis#i18n#tr('アウトライン → タブ → ハブ と切り替える（逆回りは Shift+Tab / Ctrl+←）'),
        \ 'o  t  h          ' . gnosis#i18n#tr('アウトライン・タブ・ハブへ直接'),
        \ 's  n  N          ' . gnosis#i18n#tr('検索・次のヒット・前のヒット（書き方は gs と同じ）'),
        \ 'x                ' . gnosis#i18n#tr('絞り込み（合わない行を畳む。中身は変えない）'),
        \ 'H                ' . gnosis#i18n#tr('ハイライト'),
        \ 'm                ' . gnosis#i18n#tr('メニュー（やることを番号で選ぶ）'),
        \ 'K                ' . gnosis#i18n#tr('上のヒント行を出す・隠す'),
        \ 'Esc              ' . gnosis#i18n#tr('検索・絞り込み・ハイライトを全部やめる'),
        \ 'e                ' . gnosis#i18n#tr('\l で入れるノートを選んでいるとき、カーソルの行のノートに決める'),
        \ 'j k  Enter       ' . gnosis#i18n#tr('行を動く・開く（アウトラインでは本文のその見出しへ）'),
        \ 'D                ' . gnosis#i18n#tr('タブのボードで、全部のタブを消す（確認あり）'),
        \ '< >              ' . gnosis#i18n#tr('パネルの幅（< で広く、> で狭く）'),
        \ 'S                ' . gnosis#i18n#tr('アウトラインで、左右を入れ替える'),
        \ 'Shift+← Shift+→  ' . gnosis#i18n#tr('窓を左・右へ。端なら、無い方（左のビュー・右のパネル）を開く'),
        \ '\s \o \q \h      ' . gnosis#i18n#tr('パネルを出す・中身を切り替える（同じキーでノート ⇔ パネル）'),
        \ '\W               ' . gnosis#i18n#tr('ノートだけを表示する'),
        \ 'q                ' . gnosis#i18n#tr('パネルを閉じる'),
        \ '?                ' . gnosis#i18n#tr('この説明')]
endfunction

" ? のガイドは、Esc / q / ? / Enter / Space / クリックでだけ閉じる（タイマーが積むキーでは閉じない）
function! s:help_filter(id, key) abort
  if index(["\<Esc>", 'q', '?', "\<CR>", ' ', "\<LeftMouse>"], a:key) >= 0
    call popup_close(a:id)
  endif
  return 1
endfunction

function! gnosis#panel#help() abort
  call popup_dialog(gnosis#panel#help_lines(), {'title': ' ? ', 'padding': [0, 1, 0, 1], 'border': [], 'close': 'click', 'filter': function('s:help_filter')})
endfunction

" 状態行: 3 つの中身（今のものを [ ] で囲む）と、検索・絞り込み・ハイライトの語
function! gnosis#panel#status() abort
  let l:w = g:statusline_winid
  let l:k = l:w == s:P.win ? s:P.kind : (gnosis#outline#is_open() && l:w == gnosis#outline#win() ? 'outline' : s:P.kind)
  let l:names = {'outline': gnosis#i18n#tr('アウトライン'), 'tabs': gnosis#i18n#tr('タブ'), 'hub': gnosis#i18n#tr('ハブ')}
  let l:s = ' '
  for l:x in s:KINDS
    let l:s .= (l:x ==# l:k ? '[' . l:names[l:x] . ']' : ' ' . l:names[l:x] . ' ') . ' '
  endfor
  let l:parts = []
  for [l:key, l:mark] in [['gnosis_panel_q', 's:'], ['gnosis_panel_f', 'x:'], ['gnosis_panel_h', 'H:']]
    let l:v = getwinvar(l:w, l:key, '')
    if !empty(l:v)
      call add(l:parts, l:mark . substitute(l:v, '%', '%%', 'g'))
    endif
  endfor
  return l:s . (empty(l:parts) ? '' : ' ' . join(l:parts, '  '))
endfunction

function! s:matches(groups, lnum) abort
  return gnosis#query#match(a:groups, getline(a:lnum))
endfunction

" s: 検索。入れた語に合う行へ動く（n N で次・前）。空で Enter なら検索をやめる
function! gnosis#panel#search() abort
  call gnosis#panel#set('q', input(gnosis#i18n#tr('パネルの検索: '), get(w:, 'gnosis_panel_q', '')))
  redraw
endfunction

" 検索（q）・絞り込み（f）・ハイライト（h）の語を、今の窓（パネル）に決めて反映する。s x m の入力のあとに呼ばれる（試験もここを呼ぶ）
function! gnosis#panel#set(which, query) abort
  let l:q = trim(a:query)
  if a:which ==# 'q'
    let w:gnosis_panel_q = l:q
    call s:apply_hl()
    if !empty(l:q)
      call gnosis#panel#next(1, 1)
    endif
  elseif a:which ==# 'f'
    let w:gnosis_panel_f = l:q
    call s:apply_filter()
  else
    let w:gnosis_panel_h = l:q
    call s:apply_hl()
  endif
endfunction

" n / N: 検索のヒットへ（見つからなければ動かない）。a:2 = 1 なら今の行も候補に入れる
function! gnosis#panel#next(dir, ...) abort
  let l:q = get(w:, 'gnosis_panel_q', '')
  if empty(l:q)
    echo gnosis#i18n#tr('s で検索してから使います')
    return
  endif
  let l:groups = gnosis#query#parse(l:q)
  let l:n = line('$')
  let l:cur = line('.')
  let l:all = filter(range(1, l:n), {_, v -> s:matches(l:groups, v)})
  if empty(l:all)
    echo gnosis#i18n#tr('見つかりません: ') . l:q
    return
  endif
  let l:incl = a:0 && a:1
  let l:pick = a:dir > 0
        \ ? get(filter(copy(l:all), {_, v -> l:incl ? v >= l:cur : v > l:cur}), 0, l:all[0])
        \ : get(reverse(filter(copy(l:all), {_, v -> v < l:cur})), 0, l:all[-1])
  call cursor(l:pick, 1)
  echo printf('%d/%d  %s', index(l:all, l:pick) + 1, len(l:all), l:q)
endfunction

" 絞り込みの畳みの式（foldexpr）。合う行は 0、合わない行は 1（畳まれる）
function! gnosis#panel#foldlevel(lnum) abort
  return gnosis#query#match(get(w:, 'gnosis_panel_fg', []), getline(a:lnum)) ? 0 : 1
endfunction

" x: 絞り込み。合わない行を畳む（バッファの中身は変えない）。空で Enter なら解除
function! gnosis#panel#filter() abort
  call gnosis#panel#set('f', input(gnosis#i18n#tr('パネルの絞り込み: '), get(w:, 'gnosis_panel_f', '')))
  redraw
endfunction

function! s:apply_filter() abort
  if empty(get(w:, 'gnosis_panel_f', ''))
    unlet! w:gnosis_panel_fg
    setlocal foldmethod=manual nofoldenable foldtext=foldtext()
    normal! zE
    return
  endif
  let w:gnosis_panel_fg = gnosis#query#parse(w:gnosis_panel_f)
  setlocal foldmethod=expr foldexpr=gnosis#panel#foldlevel(v:lnum) foldlevel=0 foldminlines=0 foldenable
  let &l:foldtext = "' ⋯'"
endfunction

" H: ハイライト。語に合う文字に色を付ける（行は動かさない）。空で Enter なら解除
function! gnosis#panel#highlight() abort
  call gnosis#panel#set('h', input(gnosis#i18n#tr('パネルのハイライト: '), get(w:, 'gnosis_panel_h', '')))
  redraw
endfunction

function! s:apply_hl() abort
  for l:id in get(w:, 'gnosis_panel_ids', [])
    silent! call matchdelete(l:id)
  endfor
  let w:gnosis_panel_ids = []
  let l:words = []
  for l:key in ['gnosis_panel_h', 'gnosis_panel_q']
    let l:words += gnosis#query#terms(get(w:, l:key, ''))
  endfor
  for l:wd in uniq(sort(l:words))
    if !empty(l:wd)
      call add(w:gnosis_panel_ids, matchadd('Search', '\c\V' . escape(l:wd, '\')))
    endif
  endfor
endfunction

" Esc: 検索・絞り込み・ハイライトを全部やめる
function! gnosis#panel#clear() abort
  let w:gnosis_panel_q = ''
  let w:gnosis_panel_f = ''
  let w:gnosis_panel_h = ''
  call s:apply_hl()
  call s:apply_filter()
endfunction

" e: \l で入れるノートを選んでいる最中に、カーソルの行のノートに決める
function! gnosis#panel#decide() abort
  if !gnosis#mview#pick_active()
    echo gnosis#i18n#tr('e は、\l で入れるノートを選んでいるときに使います')
    return
  endif
  let l:path = ''
  if gnosis#panel#kind() ==# 'outline'
    " アウトラインの行は、今開いているノートの見出し。そのノートに決める
    let l:path = gnosis#outline#source_path()
  else
    let l:t = substitute(matchstr(getline('.'), '\](\zs[^)]*\ze)'), '#.*$', '', '')
    let l:path = empty(l:t) ? '' : fnamemodify(gnosis#resolve_link(l:t), ':p')
  endif
  if empty(l:path) || !filereadable(l:path)
    echo gnosis#i18n#tr('この行にはノートのリンクがありません')
    return
  endif
  call gnosis#mview#decide_path(l:path)
endfunction

" パネルの幅を d だけ変える（< > から）
function! gnosis#panel#width(d) abort
  let l:w = s:panel_win()
  if l:w > 0
    call win_execute(l:w, 'vertical resize ' . max([12, winwidth(0) + a:d]))
  endif
endfunction

" パネルを閉じて、ノートの窓に戻る（パネルの中の q）
function! gnosis#panel#close() abort
  let l:k = gnosis#panel#kind()
  if empty(l:k)
    return
  endif
  call gnosis#save_current_note()
  call s:close_quiet()
  let l:nw = s:note_win()
  if l:nw > 0 | call win_gotoid(l:nw) | endif
endfunction

" \q のボードの中の D: 全部のタブを消す（確認を 1 回聞く）
function! gnosis#panel#tabs_clear() abort
  if gnosis#panel#kind() !=# 'tabs' || win_getid() != s:P.win
    return
  endif
  let l:n = len(filter(getline(1, '$'), 'v:val =~# "\\](.*)"'))
  if l:n == 0
    echo 'Gnosis: ' . gnosis#i18n#tr('タブはありません')
    return
  endif
  let l:ans = exists('g:gnosis_test_tabs_clear') ? g:gnosis_test_tabs_clear : tolower(trim(input(printf(gnosis#i18n#tr('全部のタブ（%d 件）を消しますか？ (y/n): '), l:n))))
  if l:ans !=# 'y'
    echo gnosis#i18n#tr('やめました（何も消していません）')
    return
  endif
  silent! %delete _
  silent! write
  echo printf(gnosis#i18n#tr('Gnosis: 全部のタブ（%d 件）を消しました'), l:n)
endfunction

" ---- 窓の行き来 ----------------------------------------------------------------------------------

" 動き先にする窓: 左のビュー（曼荼羅 / Folgezettel）・ノートの窓・右のパネル。左から右の順
function! s:ordered_wins() abort
  let l:out = []
  for l:w in range(1, winnr('$'))
    let l:id = win_getid(l:w)
    let l:b = winbufnr(l:id)
    let l:ft = getbufvar(l:b, '&filetype')
    if l:ft ==# 'gnosis-mandala' || l:ft ==# 'gnosis-outline' || l:id == s:P.win || (getbufvar(l:b, '&buftype') ==# '' && l:ft !~# '^gnosis-')
      call add(l:out, l:id)
    endif
  endfor
  return sort(l:out, {a, b -> win_screenpos(a)[1] - win_screenpos(b)[1]})
endfunction

" Shift+← / Shift+→（gh / gl）: 窓を 1 つ左(-1)・右(1)へ。端では動かない
function! gnosis#panel#move(dir) abort
  let l:wins = s:ordered_wins()
  if empty(l:wins)
    return
  endif
  let l:i = index(l:wins, win_getid())
  if l:i < 0
    let l:nw = s:note_win()
    if l:nw > 0 | call win_gotoid(l:nw) | endif
    return
  endif
  let l:j = l:i + a:dir
  if l:j < 0 || l:j >= len(l:wins)
    " 端: その向きに窓が無いときは、開く（右 = 右のパネル、左 = 左のビュー）。すでにそれの中にいるなら動かない
    call s:open_edge(a:dir)
    return
  endif
  call win_gotoid(l:wins[l:j])
endfunction

" Shift+→ で右に何も無ければ右のパネル（前に使った中身）、Shift+← で左に何も無ければ左のビュー（曼荼羅など）を開いて、そこへ移る
function! s:open_edge(dir) abort
  if a:dir > 0
    if empty(gnosis#panel#kind())
      call gnosis#panel#open_last()
    endif
  else
    if !gnosis#mview#is_open()
      call gnosis#mview#toggle()
    endif
  endif
endfunction
