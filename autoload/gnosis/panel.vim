" =============================================================================
" autoload/gnosis/panel.vim — 右側のパネル（アウトライン \o・ハブ \h・タブのボード \q）と、窓の行き来
"
"   \o \h \q … 右のパネルを出す。パネルは右に 1 つだけで、押したキーの中身に差し替える。
"              同じキーをもう一度押すと、ノートの窓 ⇔ パネル を行き来する。パネルの中の q で閉じる。
"              （\q のボードの中の D で、全部のタブを消す）
"   Shift+← Shift+→ （または gh gl）… 窓を 1 つ左・右へ。左のビュー（曼荼羅 / Folgezettel）・ノート・右のパネルの順で、端では止まる。
" =============================================================================

let s:P = {'kind': '', 'win': -1, 'src': -1}

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
  nnoremap <buffer><nowait><silent> \W <Cmd>call gnosis#mview#only_note()<CR>
  if a:kind ==# 'tabs'
    nnoremap <buffer><nowait><silent> D <Cmd>call gnosis#panel#tabs_clear()<CR>
  endif
  augroup gnosis_panel_buf
    autocmd! * <buffer>
    autocmd BufWinLeave <buffer> let s:P.win = -1 | let s:P.kind = ''
  augroup END
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
  let l:j = max([0, min([len(l:wins) - 1, l:i + a:dir])])
  if l:j != l:i
    call win_gotoid(l:wins[l:j])
  endif
endfunction
