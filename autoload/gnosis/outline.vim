" アウトライン窓。今開いている Markdown ノートの見出し（# ## ###…）を、独立した窓に出す。
" 曼荼羅・Folgezettel ビューの代わりではなく、それらと同時に出せる（ふつうの Vim の分割窓なので、位置と幅は <C-w> の操作でも変えられる）。
"
"   \o（曼荼羅・Folgezettel ビューでは o）  表示 ⇔ 非表示          :GnosisOutline も同じ
" アウトライン窓のキー
"   j k / ↓ ↑      見出しを選ぶ        Enter  本文のその見出しへ（カーソルも本文へ移る）
"   za zc zo zM zR 折りたたみ（開閉・閉じる・開く・全部閉じる・全部開く）
"   < >            幅を狭く・広く      s  左右を入れ替える      Space  本文の窓へ      q  閉じる
" 本文を編集すると自動で更新し、本文のカーソルがある見出しを強調する。ノートは書き換えない。
let s:O = {'win': -1, 'buf': -1, 'src': -1, 'collapsed': {}, 'items': [], 'lines': [], 'cells': [], 'sel': {}, 'tick': '', 'active': 0,
      \ 'side': 'right', 'mid': -1, 'timer': -1}

" ---- 見出しの解析（python/fznav.py の outline_items と同じ規則）------------------------------------------

" 行のリストから見出しを取る。コードブロックの中・front matter は除く。深さは「浅いほうの見出しの数」（レベルが飛んでも詰める）
function! gnosis#outline#parse(lines) abort
  let l:items = []
  let l:i = 0
  let l:n = len(a:lines)
  if l:n > 0 && trim(a:lines[0]) ==# '---'
    for l:j in range(1, l:n - 1)
      if trim(a:lines[l:j]) ==# '---'
        let l:i = l:j + 1
        break
      endif
    endfor
  endif
  let l:fence = 0
  let l:stack = []     " [[レベル, 鍵]…]
  while l:i < l:n
    let l:ln = a:lines[l:i]
    let l:i += 1
    if l:ln =~# '^\s*\(```\|\~\~\~\)'
      let l:fence = !l:fence
      continue
    endif
    if l:fence
      continue
    endif
    let l:m = matchlist(l:ln, '^\(#\{1,6}\)\s\+\(.\{-}\)\s*#*\s*$')
    if empty(l:m) || empty(l:m[2])
      continue
    endif
    let l:lv = len(l:m[1])
    while !empty(l:stack) && l:stack[-1][0] >= l:lv
      call remove(l:stack, -1)
    endwhile
    let l:key = (empty(l:stack) ? '' : l:stack[-1][1] . "\x1f") . l:m[2]
    call add(l:stack, [l:lv, l:key])
    call add(l:items, {'level': l:lv, 'text': l:m[2], 'lnum': l:i, 'depth': len(l:stack) - 1, 'key': l:key})
  endwhile
  return l:items
endfunction

" ---- 本文の窓 -----------------------------------------------------------------------------------

function! s:eligible(win) abort
  let l:b = winbufnr(a:win)
  return l:b > 0 && getbufvar(l:b, '&buftype') ==# '' && (getbufvar(l:b, '&filetype') =~# 'markdown' || bufname(l:b) =~# '\.md$')
endfunction

function! s:src_win() abort
  let l:cw = win_getid()
  if l:cw != s:O.win && s:eligible(l:cw)
    let s:O.src = l:cw
  endif
  if s:O.src > 0 && !empty(getwininfo(s:O.src)) && s:eligible(s:O.src)
    return s:O.src
  endif
  let l:nw = gnosis#mview#note_win()
  if l:nw > 0 && s:eligible(l:nw)
    let s:O.src = l:nw
    return l:nw
  endif
  for l:w in range(1, winnr('$'))
    if s:eligible(win_getid(l:w))
      let s:O.src = win_getid(l:w)
      return s:O.src
    endif
  endfor
  return -1
endfunction

function! gnosis#outline#is_open() abort
  return s:O.win > 0 && !empty(getwininfo(s:O.win)) && winbufnr(s:O.win) == s:O.buf
endfunction

" ---- 開閉 ---------------------------------------------------------------------------------------

function! gnosis#outline#toggle() abort
  if gnosis#outline#is_open()
    call gnosis#outline#close()
    return
  endif
  call gnosis#outline#open()
endfunction

function! gnosis#outline#open() abort
  let l:src = s:src_win()
  let l:w = get(g:, 'gnosis_outline_width', 30)
  let l:back = win_getid()
  if l:src > 0
    call win_gotoid(l:src)
  endif
  execute (s:O.side ==# 'left' ? 'topleft' : 'botright') . ' vertical ' . l:w . 'new'
  let s:O.win = win_getid()
  let s:O.buf = bufnr('%')
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nowrap nolist nonumber norelativenumber nospell nofoldenable
  setlocal colorcolumn= signcolumn=no filetype=gnosis-outline scrolloff=2 winfixwidth nocursorline
  silent! file [Gnosis\ Outline]
  call s:maps()
  call s:hl()
  augroup gnosis_outline_buf
    autocmd! * <buffer>
    autocmd WinEnter <buffer> setlocal cursorline
    autocmd WinLeave <buffer> setlocal nocursorline
    autocmd BufWipeout <buffer> call s:gone()
  augroup END
  augroup gnosis_outline
    autocmd!
    autocmd TextChanged,TextChangedI,BufWritePost,BufEnter,WinEnter,CursorMoved,CursorMovedI,InsertLeave * call s:schedule()
  augroup END
  call win_gotoid(l:back)
  call s:refresh(1)
  " 開いたら、アウトライン窓を操作できるようにそこへ移る
  call win_gotoid(s:O.win)
endfunction

function! gnosis#outline#close() abort
  if gnosis#outline#is_open()
    let l:back = s:src_win()
    call win_execute(s:O.win, 'close')
    if l:back > 0 && !empty(getwininfo(l:back))
      call win_gotoid(l:back)
    endif
  endif
  call s:gone()
endfunction

function! s:gone() abort
  let s:O.win = -1
  let s:O.buf = -1
  augroup gnosis_outline
    autocmd!
  augroup END
  if s:O.timer > 0
    call timer_stop(s:O.timer)
    let s:O.timer = -1
  endif
  if exists('*GnosisGuiChanged') | call GnosisGuiChanged() | endif
endfunction

function! s:hl() abort
  highlight default link GnosisOutlineActive Title
  highlight default link GnosisOutlineHead Comment
endfunction

function! s:maps() abort
  nnoremap <buffer><nowait><silent> <CR> <Cmd>call <SID>jump()<CR>
  nnoremap <buffer><nowait><silent> <2-LeftMouse> <Cmd>call <SID>jump()<CR>
  nnoremap <buffer><nowait><silent> za <Cmd>call <SID>fold('a')<CR>
  nnoremap <buffer><nowait><silent> zc <Cmd>call <SID>fold('c')<CR>
  nnoremap <buffer><nowait><silent> zo <Cmd>call <SID>fold('o')<CR>
  nnoremap <buffer><nowait><silent> zM <Cmd>call <SID>fold('M')<CR>
  nnoremap <buffer><nowait><silent> zR <Cmd>call <SID>fold('R')<CR>
  nnoremap <buffer><nowait><silent> <lt> <Cmd>call <SID>width(-4)<CR>
  nnoremap <buffer><nowait><silent> > <Cmd>call <SID>width(4)<CR>
  nnoremap <buffer><nowait><silent> s <Cmd>call <SID>swap_side()<CR>
  nnoremap <buffer><nowait><silent> q <Cmd>call gnosis#outline#close()<CR>
  nnoremap <buffer><nowait><silent> <Space> <Cmd>call <SID>to_src()<CR>
endfunction

function! s:width(d) abort
  if gnosis#outline#is_open()
    call win_execute(s:O.win, 'vertical resize ' . max([12, winwidth(0) + a:d]))
    call s:sync()
  endif
endfunction

function! s:swap_side() abort
  if !gnosis#outline#is_open()
    return
  endif
  let s:O.side = s:O.side ==# 'left' ? 'right' : 'left'
  call win_execute(s:O.win, 'wincmd ' . (s:O.side ==# 'left' ? 'H' : 'L'))
  call s:sync()
endfunction

function! s:to_src() abort
  let l:w = s:src_win()
  if l:w > 0
    call win_gotoid(l:w)
  endif
endfunction

" ---- 更新 ---------------------------------------------------------------------------------------

function! s:schedule() abort
  if !gnosis#outline#is_open()
    call s:gone()
    return
  endif
  if s:O.timer > 0
    call timer_stop(s:O.timer)
  endif
  let s:O.timer = timer_start(60, {-> s:refresh(0)})
endfunction

" 見出しの一覧に出る行（折りたたみの中は除く）と、それぞれの見出し
function! s:visible() abort
  let l:vis = []
  let l:skip = -1
  let l:n = len(s:O.items)
  let l:i = 0
  while l:i < l:n
    let l:it = s:O.items[l:i]
    call add(l:vis, l:i)
    if has_key(s:O.collapsed, l:it.key)
      let l:j = l:i + 1
      while l:j < l:n && s:O.items[l:j].depth > l:it.depth
        let l:j += 1
      endwhile
      let l:i = l:j
    else
      let l:i += 1
    endif
  endwhile
  return l:vis
endfunction

function! s:refresh(force) abort
  let s:O.timer = -1
  if !gnosis#outline#is_open()
    return
  endif
  let l:sw = s:src_win()
  let l:lines = ['OUTLINE', '']
  let l:cells = [{'t': 'OUTLINE', 'k': 'h'}, {'t': '', 'k': 'h'}]
  let s:O.sel = {}
  if l:sw > 0
    let l:b = winbufnr(l:sw)
    let l:tick = l:b . ':' . getbufvar(l:b, 'changedtick')
    if a:force || l:tick !=# s:O.tick || l:b != get(s:O, 'sbuf', -1)
      let s:O.items = gnosis#outline#parse(getbufline(l:b, 1, '$'))
      let s:O.tick = l:tick
      let s:O.sbuf = l:b
    endif
    " 本文のカーソルがある見出し
    let l:cl = getcurpos(l:sw)[1]
    let l:act = -1
    for l:i in range(len(s:O.items))
      if s:O.items[l:i].lnum <= l:cl
        let l:act = l:i
      else
        break
      endif
    endfor
    let l:vis = s:visible()
    let l:actv = -1
    for l:i in l:vis
      if l:i <= l:act
        let l:actv = l:i
      endif
    endfor
    let l:lnum = 2
    for l:i in l:vis
      let l:it = s:O.items[l:i]
      let l:hid = ''
      if has_key(s:O.collapsed, l:it.key)
        let l:j = l:i + 1
        while l:j < len(s:O.items) && s:O.items[l:j].depth > l:it.depth
          let l:j += 1
        endwhile
        let l:hid = '  +' . (l:j - l:i - 1)
      endif
      call add(l:lines, repeat('  ', l:it.depth) . l:it.text . l:hid)
      let l:lnum += 1
      let s:O.sel[l:lnum] = l:i
      call add(l:cells, {'t': l:it.text, 'd': l:it.depth, 'a': l:i == l:actv ? 1 : 0, 'c': l:hid, 'k': 'o'})
    endfor
    let s:O.active = l:actv
    if empty(l:vis)
      let l:m = gnosis#i18n#tr('見出しがありません')
      call add(l:lines, '  ' . l:m)
      call add(l:cells, {'t': l:m, 'k': 'h'})
    endif
  endif
  let s:O.cells = l:cells
  let l:ow = s:O.win
  if l:lines !=# s:O.lines
    call win_execute(l:ow, 'setlocal modifiable')
    let l:old = s:O.lines
    if len(l:old) > len(l:lines)
      call win_execute(l:ow, 'silent! ' . (len(l:lines) + 1) . ',$delete _')
    endif
    for l:i in range(len(l:lines))
      if l:i >= len(l:old) || l:old[l:i] !=# l:lines[l:i]
        call setbufline(s:O.buf, l:i + 1, l:lines[l:i])
      endif
    endfor
    call win_execute(l:ow, 'setlocal nomodifiable nomodified')
    let s:O.lines = l:lines
  endif
  " 強調（本文のカーソルがある見出し）。アウトライン窓にカーソルが無いときは、そこが見えるように動かす
  if s:O.mid > 0
    silent! call matchdelete(s:O.mid, l:ow)
    let s:O.mid = -1
  endif
  let l:al = 0
  for [l:ln, l:idx] in items(s:O.sel)
    if l:idx == s:O.active
      let l:al = str2nr(l:ln)
    endif
  endfor
  if l:al > 0
    let s:O.mid = matchaddpos('GnosisOutlineActive', [l:al], 10, -1, {'window': l:ow})
    if win_getid() != l:ow
      call win_execute(l:ow, 'call cursor(' . l:al . ', 1) | normal! zz')
    endif
  endif
  call s:sync()
endfunction

function! s:sync() abort
  if exists('*GnosisGuiChanged') | call GnosisGuiChanged() | endif
endfunction

" ---- 操作 ---------------------------------------------------------------------------------------

function! s:item_at(lnum) abort
  let l:i = get(s:O.sel, a:lnum, -1)
  return l:i >= 0 ? s:O.items[l:i] : {}
endfunction

" 本文のその見出しへ（本文の窓にカーソルが移る）
function! s:jump() abort
  let l:it = s:item_at(line('.'))
  if empty(l:it)
    return
  endif
  call gnosis#outline#goto(l:it.lnum)
endfunction

function! gnosis#outline#goto(lnum) abort
  let l:w = s:src_win()
  if l:w < 0
    return
  endif
  call win_gotoid(l:w)
  call cursor(a:lnum, 1)
  normal! zt
  call s:schedule()
endfunction

function! s:fold(op) abort
  let l:it = s:item_at(line('.'))
  if a:op ==# 'M'
    for l:x in s:O.items
      let s:O.collapsed[l:x.key] = 1
    endfor
  elseif a:op ==# 'R'
    let s:O.collapsed = {}
  elseif !empty(l:it)
    let l:i = index(s:O.items, l:it)
    let l:kids = l:i + 1 < len(s:O.items) && s:O.items[l:i + 1].depth > l:it.depth
    if a:op ==# 'o'
      silent! call remove(s:O.collapsed, l:it.key)
    elseif a:op ==# 'c'
      if l:kids
        let s:O.collapsed[l:it.key] = 1
      endif
    elseif a:op ==# 'a' && l:kids
      if has_key(s:O.collapsed, l:it.key)
        call remove(s:O.collapsed, l:it.key)
      else
        let s:O.collapsed[l:it.key] = 1
      endif
    endif
  endif
  call s:refresh(0)
endfunction

" ---- アプリ（\c）へ ------------------------------------------------------------------------------------

function! gnosis#outline#gui_state() abort
  if !gnosis#outline#is_open() || empty(s:O.cells)
    return {}
  endif
  let l:wi = getwininfo(s:O.win)
  let l:top = l:wi[0].topline
  let l:h = l:wi[0].height
  let l:cur = win_getid() == s:O.win ? line('.') : getcurpos(s:O.win)[1]
  let l:vis = []
  for l:i in range(l:top, min([len(s:O.cells), l:top + l:h - 1]))
    let l:c = copy(s:O.cells[l:i - 1])
    let l:c.sel = l:i == l:cur ? 1 : 0
    let l:c.n = l:i
    call add(l:vis, l:c)
  endfor
  let l:sw = s:O.src > 0 && !empty(getwininfo(s:O.src)) ? getwininfo(s:O.src)[0].wincol : 0
  return {'lines': l:vis, 'top': l:top, 'total': len(s:O.cells), 'height': l:h, 'cursor': l:cur, 'win': s:O.win, 'srcWin': s:O.src,
        \ 'wcols': winwidth(s:O.win), 'pos': l:wi[0].wincol < l:sw ? 'left' : 'right', 'focus': win_getid() == s:O.win ? 1 : 0}
endfunction

function! gnosis#outline#src_win() abort
  return gnosis#outline#is_open() ? s:O.src : -1
endfunction

function! gnosis#outline#win() abort
  return gnosis#outline#is_open() ? s:O.win : -1
endfunction

" アプリで見出しをクリック（jump=1 なら本文へ）
function! gnosis#outline#gui_click(lnum, jump) abort
  if !gnosis#outline#is_open() || empty(s:item_at(a:lnum))
    return
  endif
  call win_gotoid(s:O.win)
  call cursor(a:lnum, 1)
  if a:jump
    call s:jump()
  endif
  call s:sync()
endfunction

function! gnosis#outline#gui_scroll(n) abort
  if !gnosis#outline#is_open()
    return
  endif
  call win_execute(s:O.win, 'normal! ' . (a:n > 0 ? repeat("\<C-e>", a:n) : repeat("\<C-y>", -a:n)))
  call s:sync()
endfunction

" アプリで折りたたみ（見出しの行の + をクリック）
function! gnosis#outline#gui_fold(lnum) abort
  if !gnosis#outline#is_open() || empty(s:item_at(a:lnum))
    return
  endif
  call win_gotoid(s:O.win)
  call cursor(a:lnum, 1)
  call s:fold('a')
endfunction

" 試験用
function! gnosis#outline#state() abort
  return s:O
endfunction
