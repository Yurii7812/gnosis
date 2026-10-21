" 曼荼羅ビュー（CUI）。<Space> で、曼荼羅（左）とふつうのノート（右）を行き来する。
"
" 中心のノートの周りに、つながっているノートを 8 つずつ並べる。
"   中心が索引（グループ） … 載っているノート。8 つを超えたら 2 枚目以降の曼荼羅（[ ] で前後）
"   中心がノート           … 所属する索引（Group: / BranchGroup:）。モードでノート同士のつながりも出せる
" 画面の大きさは、分割しているときは 3×3、全画面（f）では 9×9（周りの 8 マスがそれぞれ自分の曼荼羅を持つ）。
"
" キー（曼荼羅のウィンドウ）
"   h j k l / 矢印   マスを動く      1-8 そのマス（時計回り）・0 中心      Enter  そのマスを中心にする
"   ノートのマスで Enter           右にそのノートを開く（カーソルは曼荼羅に残る）
"   [ ]              前後の曼荼羅    - / <BS> 一つ前に戻る
"   m                モード（すべて → 索引だけ → ノートだけ）    f 全画面（9×9）⇔ 分割（3×3）
"   Space            ノートのウィンドウへ    r 読み直す    q 閉じる
" 元データは python/mandala_view.py（読み取り専用）。ノートは書き換えない。

let s:S = {}
let s:here = expand('<sfile>:p:h:h:h')
let s:pos = [[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [2, 1], [2, 0], [1, 0]]
let s:modes = ['all', 'groups', 'notes']
let s:mode_label = {'all': 'すべて', 'groups': '索引だけ', 'notes': 'ノートだけ'}

function! s:root() abort
  let l:r = trim(get(g:, 'gnosis_root', ''))
  return empty(l:r) ? '' : substitute(fnamemodify(l:r, ':p'), '/$', '', '')
endfunction

" ---- データ -----------------------------------------------------------------

function! s:load() abort
  let l:root = s:root()
  if empty(l:root)
    return 0
  endif
  let l:cmd = join(map([gnosis#python_cmd(), s:here . '/python/mandala_view.py', 'dump', l:root], 'shellescape(v:val)'), ' ')
  let l:out = system(l:cmd)
  try
    let s:S.data = json_decode(l:out)
  catch
    echohl WarningMsg | echo 'Gnosis: 曼荼羅のデータを読めませんでした' | echohl NONE
    return 0
  endtry
  let s:S.root = l:root
  return 1
endfunction

" python/mandala_view.py の items() と同じ規則
function! gnosis#mview#items(data, center, mode) abort
  let l:nodes = a:data.nodes
  if !has_key(l:nodes, a:center)
    return []
  endif
  let l:c = l:nodes[a:center]
  let l:o = l:c.o
  let l:out = []
  if l:c.g
    let l:kinds = [['link', a:mode ==# 'all' ? -1 : (a:mode ==# 'groups' ? 1 : 0)]]
  else
    let l:kinds = []
    if a:mode ==# 'groups' || a:mode ==# 'all'
      let l:kinds += [['group', -1], ['branch_group', -1]]
    endif
    if a:mode ==# 'notes' || a:mode ==# 'all'
      let l:kinds += map(['parent_branch', 'child_branch', 'context', 'related', 'backlink', 'link'], '[v:val, -1]')
    endif
  endif
  for [l:k, l:want] in l:kinds
    for l:t in get(l:o, l:k, [])
      if l:t ==# a:center || index(l:out, l:t) >= 0 || !has_key(l:nodes, l:t)
        continue
      endif
      if l:want >= 0 && l:nodes[l:t].g != l:want
        continue
      endif
      call add(l:out, l:t)
    endfor
  endfor
  return l:out
endfunction

function! s:pages(center) abort
  let l:all = gnosis#mview#items(s:S.data, a:center, s:S.mode)
  return max([1, (len(l:all) + 7) / 8])
endfunction

" 中心 c の page 枚目の周辺 8 マス（足りない所は ''）
function! s:ring(c, page) abort
  let l:all = gnosis#mview#items(s:S.data, a:c, s:S.mode)
  let l:r = l:all[a:page * 8 : a:page * 8 + 7]
  while len(l:r) < 8
    call add(l:r, '')
  endwhile
  return l:r
endfunction

" ---- 盤面 -------------------------------------------------------------------
" 盤面は n×n（n は 3 か 9）。マス = {'id': ノート, 'role': 'center'|'item'|'sub'|'empty'}

function! s:board() abort
  let l:n = s:S.size
  let l:b = []
  for l:i in range(l:n)
    call add(l:b, repeat([{'id': '', 'role': 'empty'}], l:n))
  endfor
  let l:ring = s:ring(s:S.center, s:S.page)
  if l:n == 3
    let l:b[1][1] = {'id': s:S.center, 'role': 'center'}
    for l:i in range(8)
      if !empty(l:ring[l:i])
        let l:b[s:pos[l:i][0]][s:pos[l:i][1]] = {'id': l:ring[l:i], 'role': 'item'}
      endif
    endfor
    return l:b
  endif
  " 9×9: 真ん中の 3×3 が今の曼荼羅。周りの 8 ブロックは、その周辺の各ノートを中心にした曼荼羅の 1 枚目
  let l:b[4][4] = {'id': s:S.center, 'role': 'center'}
  for l:i in range(8)
    let l:id = l:ring[l:i]
    if empty(l:id)
      continue
    endif
    let l:b[3 + s:pos[l:i][0]][3 + s:pos[l:i][1]] = {'id': l:id, 'role': 'item'}
    let l:br = s:pos[l:i][0] * 3
    let l:bc = s:pos[l:i][1] * 3
    let l:b[l:br + 1][l:bc + 1] = {'id': l:id, 'role': 'center'}
    let l:sub = s:ring(l:id, 0)
    for l:j in range(8)
      if !empty(l:sub[l:j])
        let l:b[l:br + s:pos[l:j][0]][l:bc + s:pos[l:j][1]] = {'id': l:sub[l:j], 'role': 'sub'}
      endif
    endfor
  endfor
  " 真ん中のブロックの周りの 8 マスは、上で 'item' として置いた（ブロックの中心 (1,1) 以外は周辺そのもの）
  for l:i in range(8)
    if !empty(l:ring[l:i])
      let l:b[3 + s:pos[l:i][0]][3 + s:pos[l:i][1]] = {'id': l:ring[l:i], 'role': 'item'}
    endif
  endfor
  return l:b
endfunction

" 文字列を表示幅 w の行に折り返す（最大 h 行。あふれたら … ）
function! s:wrap(text, w, h) abort
  let l:lines = []
  let l:cur = ''
  let l:cw = 0
  for l:ch in split(a:text, '\zs')
    let l:d = strdisplaywidth(l:ch)
    if l:cw + l:d > a:w
      call add(l:lines, l:cur)
      let l:cur = ''
      let l:cw = 0
    endif
    let l:cur .= l:ch
    let l:cw += l:d
  endfor
  call add(l:lines, l:cur)
  if len(l:lines) > a:h
    let l:lines = l:lines[0 : a:h - 1]
    let l:last = l:lines[-1]
    while !empty(l:last) && strdisplaywidth(l:last) + 1 > a:w
      let l:last = substitute(l:last, '.$', '', '')
    endwhile
    let l:lines[-1] = l:last . '…'
  endif
  return l:lines
endfunction

function! s:pad(s, w) abort
  return a:s . repeat(' ', max([0, a:w - strdisplaywidth(a:s)]))
endfunction

function! s:label(cell, n) abort
  if empty(a:cell.id) || !has_key(s:S.data.nodes, a:cell.id)
    return ''
  endif
  let l:nd = s:S.data.nodes[a:cell.id]
  return (l:nd.g ? '◆' : '') . l:nd.t
endfunction

function! s:render() abort
  let l:n = s:S.size
  let l:b = s:board()
  let s:S.cells = l:b
  let l:W = winwidth(0)
  let l:cw = max([4, (l:W - (l:n + 1)) / l:n])
  let l:ch = l:n == 3 ? 3 : 2
  let l:heavy = {0: 1, 3: 1, 6: 1, 9: 1}
  let l:lines = []
  let s:S.spans = {}   " 'r,c' => [行, 開始バイト(1 始まり), バイト長]
  " 上の見出し（今の中心・何枚目・モード）
  let l:ctitle = has_key(s:S.data.nodes, s:S.center) ? s:S.data.nodes[s:S.center].t : s:S.center
  let l:pages = s:pages(s:S.center)
  call add(l:lines, s:fit(printf(' %s   %d/%d   [%s]   %s', l:ctitle, s:S.page + 1, l:pages,
        \ s:mode_label[s:S.mode], l:n == 3 ? '3×3' : '9×9'), l:W))
  for l:r in range(l:n)
    call add(l:lines, s:hline(l:n, l:cw, l:r, l:heavy))
    let l:cellines = []
    for l:c in range(l:n)
      let l:cell = l:b[l:r][l:c]
      let l:txt = s:label(l:cell, l:n)
      if l:n == 3 && l:cell.role ==# 'item'
        let l:idx = index(map(copy(s:pos), 'v:val[0] == l:r && v:val[1] == l:c'), 1) + 1
        let l:txt = l:idx . ' ' . l:txt
      endif
      call add(l:cellines, empty(l:txt) ? repeat([''], l:ch) : s:wrap(l:txt, l:cw - 1, l:ch))
    endfor
    for l:k in range(l:ch)
      let l:line = ''
      for l:c in range(l:n)
        let l:sep = (l:n == 3 || has_key(l:heavy, l:c)) ? '┃' : '│'
        let l:line .= l:sep
        let l:txt = get(l:cellines[l:c], l:k, '')
        let l:cellstr = ' ' . s:pad(l:txt, l:cw - 1)
        if l:k == 0
          let s:S.spans[l:r . ',' . l:c] = [len(l:lines) + 1, strlen(l:line) + 1, strlen(l:cellstr)]
        endif
        let l:line .= l:cellstr
      endfor
      call add(l:lines, l:line . '┃')
    endfor
  endfor
  call add(l:lines, s:hline(l:n, l:cw, l:n, l:heavy))
  call add(l:lines, s:fit(' hjkl 移動 Enter 中心に [] 前後 - 戻る m モード f 全画面 Space ノート q 閉じる', l:W))
  setlocal modifiable
  silent! %delete _
  call setline(1, l:lines)
  setlocal nomodifiable nomodified
  call s:mark()
endfunction

function! s:fit(s, w) abort
  let l:s = a:s
  while strdisplaywidth(l:s) > a:w && !empty(l:s)
    let l:s = substitute(l:s, '.$', '', '')
  endwhile
  return l:s
endfunction

function! s:hline(n, cw, r, heavy) abort
  let l:rh = (a:n == 3 || has_key(a:heavy, a:r))
  let l:h = l:rh ? '━' : '─'
  let l:top = a:r == 0
  let l:bot = a:r == a:n
  let l:line = ''
  for l:c in range(a:n + 1)
    let l:ch = (a:n == 3 || has_key(a:heavy, l:c))
    if l:c == 0
      let l:j = l:top ? '┏' : (l:bot ? '┗' : (l:rh ? '┣' : '┠'))
    elseif l:c == a:n
      let l:j = l:top ? '┓' : (l:bot ? '┛' : (l:rh ? '┫' : '┨'))
    elseif l:top
      let l:j = l:ch ? '┳' : '┯'
    elseif l:bot
      let l:j = l:ch ? '┻' : '┷'
    else
      let l:j = l:rh ? (l:ch ? '╋' : '┿') : (l:ch ? '╂' : '┼')
    endif
    let l:line .= l:j . (l:c < a:n ? repeat(l:h, a:cw) : '')
  endfor
  return l:line
endfunction

" 選んでいるマスと、中心を色で示す
function! s:mark() abort
  if exists('w:mview_match')
    for l:m in w:mview_match
      silent! call matchdelete(l:m)
    endfor
  endif
  let w:mview_match = []
  let l:n = s:S.size
  for l:r in range(l:n)
    for l:c in range(l:n)
      let l:cell = s:S.cells[l:r][l:c]
      let l:sp = get(s:S.spans, l:r . ',' . l:c, [])
      if empty(l:sp) || empty(l:cell.id)
        continue
      endif
      if l:r == s:S.cur[0] && l:c == s:S.cur[1]
        call add(w:mview_match, matchaddpos('GnosisMviewSel', [[l:sp[0], l:sp[1], l:sp[2]]], 20))
      elseif l:cell.role ==# 'center'
        call add(w:mview_match, matchaddpos('GnosisMviewCenter', [[l:sp[0], l:sp[1], l:sp[2]]], 10))
      endif
    endfor
  endfor
  let l:sp = get(s:S.spans, s:S.cur[0] . ',' . s:S.cur[1], [])
  if !empty(l:sp)
    call cursor(l:sp[0], l:sp[1])
  endif
endfunction

" ---- 操作 -------------------------------------------------------------------

function! s:cur_cell() abort
  return s:S.cells[s:S.cur[0]][s:S.cur[1]]
endfunction

function! s:move(dr, dc) abort
  let l:n = s:S.size
  let l:r = s:S.cur[0] + a:dr
  let l:c = s:S.cur[1] + a:dc
  if l:r < 0 || l:r >= l:n || l:c < 0 || l:c >= l:n
    return
  endif
  let s:S.cur = [l:r, l:c]
  call s:mark()
endfunction

" 数字キー: 3×3 では周辺のマス（1-8 時計回り）と中心（0）、9×9 ではそのブロックの中心
function! s:digit(d) abort
  if a:d == 0
    let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  else
    let l:p = s:pos[a:d - 1]
    let s:S.cur = s:S.size == 3 ? copy(l:p) : [l:p[0] * 3 + 1, l:p[1] * 3 + 1]
  endif
  call s:mark()
endfunction

function! s:set_center(id, page) abort
  let s:S.center = a:id
  let s:S.page = a:page
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  call s:show_note(a:id)
  call s:render()
endfunction

function! s:enter() abort
  let l:cell = s:cur_cell()
  if empty(l:cell.id)
    return
  endif
  if l:cell.id ==# s:S.center
    call s:show_note(l:cell.id)
    return
  endif
  call add(s:S.hist, [s:S.center, s:S.page])
  call s:set_center(l:cell.id, 0)
endfunction

function! s:back() abort
  if empty(s:S.hist)
    return
  endif
  let [l:id, l:pg] = remove(s:S.hist, -1)
  call s:set_center(l:id, l:pg)
endfunction

function! s:page(d) abort
  let l:p = s:S.page + a:d
  let l:max = s:pages(s:S.center)
  if l:p < 0 || l:p >= l:max
    return
  endif
  let s:S.page = l:p
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  call s:render()
endfunction

function! s:mode() abort
  let s:S.mode = s:modes[(index(s:modes, s:S.mode) + 1) % len(s:modes)]
  let s:S.page = 0
  call s:render()
endfunction

" 全画面（9×9）⇔ 分割（3×3）
function! s:full() abort
  if s:S.size == 3
    let s:S.size = 9
    let s:S.width = winwidth(0)
    only
  else
    let s:S.size = 3
    call s:ensure_note_win()
  endif
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  call s:render()
endfunction

" ---- ウィンドウ -------------------------------------------------------------

function! s:mwin() abort
  let l:b = get(s:S, 'buf', -1)
  return l:b > 0 ? bufwinid(l:b) : -1
endfunction

function! s:note_win() abort
  for l:w in range(1, winnr('$'))
    if getbufvar(winbufnr(l:w), '&filetype') !=# 'gnosis-mandala' && getbufvar(winbufnr(l:w), '&buftype') ==# ''
      return win_getid(l:w)
    endif
  endfor
  return -1
endfunction

function! s:ensure_note_win() abort
  if s:note_win() > 0
    return
  endif
  let l:mw = s:mwin()
  call win_gotoid(l:mw)
  vertical rightbelow new
  let l:nw = win_getid()
  call win_gotoid(l:mw)
  execute 'vertical resize ' . (&columns * 2 / 5)
  return l:nw
endfunction

function! s:show_note(id) abort
  let l:path = s:S.root . '/' . a:id
  if !filereadable(l:path)
    return
  endif
  if s:S.size != 3
    return
  endif
  call s:ensure_note_win()
  let l:nw = s:note_win()
  if l:nw < 0
    return
  endif
  call win_execute(l:nw, 'silent! hide edit ' . fnameescape(l:path))
endfunction

" ---- 入口 -------------------------------------------------------------------

function! s:setup_buffer() abort
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted nowrap nolist nonumber norelativenumber
  setlocal nocursorline nospell nofoldenable colorcolumn= signcolumn=no filetype=gnosis-mandala
  nnoremap <buffer><silent> h <Cmd>call <SID>move(0, -1)<CR>
  nnoremap <buffer><silent> <Left> <Cmd>call <SID>move(0, -1)<CR>
  nnoremap <buffer><silent> l <Cmd>call <SID>move(0, 1)<CR>
  nnoremap <buffer><silent> <Right> <Cmd>call <SID>move(0, 1)<CR>
  nnoremap <buffer><silent> k <Cmd>call <SID>move(-1, 0)<CR>
  nnoremap <buffer><silent> <Up> <Cmd>call <SID>move(-1, 0)<CR>
  nnoremap <buffer><silent> j <Cmd>call <SID>move(1, 0)<CR>
  nnoremap <buffer><silent> <Down> <Cmd>call <SID>move(1, 0)<CR>
  for l:d in range(10)
    execute printf('nnoremap <buffer><silent> %d <Cmd>call <SID>digit(%d)<CR>', l:d, l:d)
  endfor
  nnoremap <buffer><silent> <CR> <Cmd>call <SID>enter()<CR>
  nnoremap <buffer><silent> ] <Cmd>call <SID>page(1)<CR>
  nnoremap <buffer><silent> [ <Cmd>call <SID>page(-1)<CR>
  nnoremap <buffer><silent> - <Cmd>call <SID>back()<CR>
  nnoremap <buffer><silent> <BS> <Cmd>call <SID>back()<CR>
  nnoremap <buffer><silent> m <Cmd>call <SID>mode()<CR>
  nnoremap <buffer><silent> f <Cmd>call <SID>full()<CR>
  nnoremap <buffer><silent> r <Cmd>call <SID>reload()<CR>
  nnoremap <buffer><silent> q <Cmd>call gnosis#mview#close()<CR>
  nnoremap <buffer><silent> <Space> <Cmd>call gnosis#mview#toggle()<CR>
  augroup gnosis_mview_buf
    autocmd! * <buffer>
    autocmd VimResized,WinResized * if &filetype ==# 'gnosis-mandala' | call s:render() | endif
  augroup END
endfunction

function! s:reload() abort
  if s:load()
    if !has_key(s:S.data.nodes, s:S.center)
      let s:S.center = 'index.md'
    endif
    call s:render()
  endif
endfunction

function! s:hl() abort
  highlight default link GnosisMviewSel Visual
  highlight default link GnosisMviewCenter Title
endfunction

function! s:open(center) abort
  call s:hl()
  if !s:load()
    echohl WarningMsg | echo 'Gnosis: vault が選ばれていません' | echohl NONE
    return
  endif
  let l:root = s:S.root . '/'
  let l:mode = get(s:S, 'mode', 'all')
  let l:size = get(s:S, 'size', 3)
  let l:hist = get(s:S, 'hist', [])
  let l:buf = get(s:S, 'buf', -1)
  let s:S.mode = l:mode
  let s:S.size = 3
  let s:S.hist = l:hist
  let s:S.page = 0
  let l:c = a:center
  if !has_key(s:S.data.nodes, l:c)
    let l:c = has_key(s:S.data.nodes, 'index.md') ? 'index.md' : ''
  endif
  if empty(l:c)
    echohl WarningMsg | echo 'Gnosis: 曼荼羅にできるノートがありません' | echohl NONE
    return
  endif
  let s:S.center = l:c
  let s:S.cur = [1, 1]
  " 曼荼羅のウィンドウ（左）。あれば使い回す
  if l:buf > 0 && bufwinid(l:buf) > 0
    call win_gotoid(bufwinid(l:buf))
  else
    if l:buf > 0 && bufexists(l:buf)
      execute 'topleft vertical sbuffer ' . l:buf
    else
      topleft vertical new
      let s:S.buf = bufnr('%')
      call s:setup_buffer()
    endif
    execute 'vertical resize ' . (&columns * 3 / 5)
  endif
  let s:S.buf = bufnr('%')
  call s:render()
  call s:show_note(l:c)
  call win_gotoid(s:mwin())
endfunction

" <Space>: ノートから曼荼羅へ、曼荼羅からノートへ
function! gnosis#mview#toggle() abort
  if &filetype ==# 'gnosis-mandala'
    let l:nw = s:note_win()
    if l:nw > 0
      call win_gotoid(l:nw)
    else
      call s:ensure_note_win()
      call win_gotoid(s:note_win())
    endif
    return
  endif
  let l:mw = s:mwin()
  if l:mw > 0
    call win_gotoid(l:mw)
    return
  endif
  let l:root = s:root()
  let l:file = expand('%:p')
  let l:rel = ''
  if !empty(l:root) && stridx(l:file, l:root . '/') == 0
    let l:rel = strpart(l:file, len(l:root) + 1)
  endif
  call s:open(l:rel)
endfunction

function! gnosis#mview#close() abort
  let l:mw = s:mwin()
  if l:mw > 0
    call win_gotoid(l:mw)
    if winnr('$') > 1
      close
    else
      enew
    endif
  endif
  if s:note_win() > 0
    call win_gotoid(s:note_win())
  endif
endfunction

" 試験用: 状態を返す
function! gnosis#mview#state() abort
  return s:S
endfunction
