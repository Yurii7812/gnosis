" 曼荼羅ビュー（CUI）。<Space> で、曼荼羅（左）とふつうのノート（右）を行き来する。
"
" 中心のノートの周りに、つながっているノートを 8 つずつ並べる。
"   中心が索引（グループ） … 載っているノート。8 つを超えたら 2 枚目以降の曼荼羅（[ ] で前後）
"   中心がノート           … 所属する索引（Group: / BranchGroup:）。モードでノート同士のつながりも出せる
" 画面の大きさは、分割しているときは 3×3、全画面（f）では 9×9（周りの 8 マスがそれぞれ自分の曼荼羅を持つ）。
" 分割は左右半々。マスは見た目が正方形で、盤面は窓の中央に置く。
"
" キー（曼荼羅のウィンドウ）
"   h j k l / 矢印   マスを動く      1-8 そのマスを中心にする（1 2 3 / 4 _ 5 / 6 7 8）・0 中心のノートを開く
"                    Enter  カーソルのマスを中心にする（9×9 では 1-8 はそのブロックへカーソルを置くだけ）
"   ノートのマスで Enter           右にそのノートを開く（カーソルは曼荼羅に残る）
"   [ ]              前後の曼荼羅    - / <BS> 一つ前に戻る
"   a g n c r        モード: a 全体 / g 索引 / n ノート / c 近い索引（所属が先、近い未所属が後）/ r 関連（索引もノートも関連の強い順）
"   s                検索（題・本文を vault 全体から。結果が周りに並び、真ん中に「検索: 語」）
"   /                ふつうの検索のように語をハイライトしてヒットのマスへ飛ぶ（複数枚あれば別の枚へも）。Tab / S-Tab で次・前、Esc で解除
"   F                今の周りを題で絞り込む（\g では索引を全部から）    f 全画面（9×9）⇔ 分割（3×3）
"   Space            ノートのウィンドウへ    R 読み直す    q 閉じる
" 元データは python/mandala_view.py（読み取り専用）。ノートは書き換えない。

let s:S = {}
let s:here = expand('<sfile>:p:h:h:h')
" 周りの 8 マス（番号 1-8）。読む順:  1 2 3 / 4 _ 5 / 6 7 8
let s:pos = [[0, 0], [0, 1], [0, 2], [1, 0], [1, 2], [2, 0], [2, 1], [2, 2]]
let s:mode_label = {'all': '全体', 'groups': '索引', 'notes': 'ノート', 'near': '近い索引', 'rel': '関連'}
let s:mode_keys = [['a', 'all'], ['g', 'groups'], ['n', 'notes'], ['c', 'near'], ['r', 'rel']]

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
    " 索引の周り: 所属する索引（Index も）→ 載っているノート
    let l:kinds = []
    if a:mode !=# 'notes'
      let l:kinds += [['group', -1], ['branch_group', -1]]
    endif
    let l:kinds += [['link', a:mode ==# 'all' ? -1 : (a:mode ==# 'groups' ? 1 : 0)]]
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

" 近い索引（python/mandala_view.py の near）。中心ごとに覚えておく（r で読み直し）
function! s:near(c) abort
  if !has_key(s:S.nearc, a:c)
    let l:cmd = join(map([gnosis#python_cmd(), s:here . '/python/mandala_view.py', 'near', s:S.root, a:c], 'shellescape(v:val)'), ' ')
    try
      let s:S.nearc[a:c] = json_decode(system(l:cmd))
    catch
      let s:S.nearc[a:c] = []
    endtry
  endif
  " 先にすでに所属している索引（Index も）、そのあとに「近いのにまだ載っていない」索引
  let s:S.why = {}
  let l:out = gnosis#mview#items(s:S.data, a:c, 'groups')
  for l:id in l:out
    let s:S.why[l:id] = '所属'
  endfor
  for l:d in s:S.nearc[a:c]
    if index(l:out, l:d.id) < 0
      call add(l:out, l:d.id)
      let s:S.why[l:d.id] = join(l:d.why[0 : 1], '・')
    endif
  endfor
  if empty(s:S.nearc[a:c])
    " 手がかりが無いときは Index の直下の索引も足す
    for l:id in gnosis#mview#items(s:S.data, 'index.md', 'groups')
      if l:id !=# a:c && index(l:out, l:id) < 0
        call add(l:out, l:id)
        let s:S.why[l:id] = 'Index'
      endif
    endfor
  endif
  return l:out
endfunction

" 関連（python/mandala_view.py の related）。索引でもノートでも、関連の強い順。理由は強い 2 つまで
function! s:rel(c) abort
  if !has_key(s:S.relc, a:c)
    let l:cmd = join(map([gnosis#python_cmd(), s:here . '/python/mandala_view.py', 'related', s:S.root, a:c], 'shellescape(v:val)'), ' ')
    try
      let s:S.relc[a:c] = json_decode(system(l:cmd))
    catch
      let s:S.relc[a:c] = []
    endtry
  endif
  let s:S.why = {}
  for l:d in s:S.relc[a:c]
    let s:S.why[l:d.id] = join(l:d.why[0 : 1], '・')
  endfor
  return map(copy(s:S.relc[a:c]), 'v:val.id')
endfunction

" 周辺に出すもの（絞り込み前）。検索の結果があればそれ。中心でなければ（9×9 の周りのブロック）近い索引は使わず「すべて」
function! s:base(c) abort
  if a:c ==# s:S.center
    if !empty(s:S.rquery)
      return copy(s:S.results)
    endif
    if s:S.mode ==# 'near'
      return s:near(a:c)
    elseif s:S.mode ==# 'rel'
      return s:rel(a:c)
    endif
  endif
  return gnosis#mview#items(s:S.data, a:c, index(['near', 'rel'], s:S.mode) >= 0 ? 'all' : s:S.mode)
endfunction

" 絞り込み（/）: 索引を選ぶとき（\g）は題が合う索引を全部から、ふだんは今の周りの中から
function! s:items(c) abort
  let l:b = s:base(a:c)
  if a:c !=# s:S.center || empty(s:S.query)
    return l:b
  endif
  let l:q = tolower(s:S.query)
  if get(s:S, 'pick', 0)
    let l:out = []
    for l:id in sort(keys(s:S.data.nodes))
      if s:S.data.nodes[l:id].g && l:id !=# a:c && stridx(tolower(s:S.data.nodes[l:id].t), l:q) >= 0
        call add(l:out, l:id)
      endif
    endfor
    return l:out
  endif
  return filter(l:b, 'stridx(tolower(s:S.data.nodes[v:val].t), l:q) >= 0')
endfunction

function! s:pages(center) abort
  return max([1, (len(s:items(a:center)) + 7) / 8])
endfunction

" 中心 c の page 枚目の周辺 8 マス（足りない所は ''）
function! s:ring(c, page) abort
  let l:all = s:items(a:c)
  let l:r = l:all[a:page * 8 : a:page * 8 + 7]
  while len(l:r) < 8
    call add(l:r, '')
  endwhile
  return l:r
endfunction

" ---- 盤面 -------------------------------------------------------------------
" 盤面は n×n（n は 3 か 9）。マス = {'id': ノート, 'role': 'center'|'item'|'sub'|'empty'}

function! s:board() abort
  let l:b = s:board_cells()
  if !empty(s:S.rquery)
    let l:c = s:S.size == 3 ? 1 : 4
    let l:b[l:c][l:c] = {'id': '', 'role': 'center', 'n': 0, 'text': '検索: ' . s:S.rquery}
  endif
  return l:b
endfunction

function! s:board_cells() abort
  let l:n = s:S.size
  let l:b = []
  for l:i in range(l:n)
    call add(l:b, repeat([{'id': '', 'role': 'empty', 'n': 0}], l:n))
  endfor
  let l:ring = s:ring(s:S.center, s:S.page)
  if l:n == 3
    let l:b[1][1] = {'id': s:S.center, 'role': 'center', 'n': 0}
    for l:i in range(8)
      if !empty(l:ring[l:i])
        let l:b[s:pos[l:i][0]][s:pos[l:i][1]] = {'id': l:ring[l:i], 'role': 'item', 'n': l:i + 1}
      endif
    endfor
    return l:b
  endif
  " 9×9: 真ん中の 3×3 が今の曼荼羅。周りの 8 ブロックは、その周辺の各ノートを中心にした曼荼羅の 1 枚目。
  " ブロックの真ん中のマスにも、周りのマスと同じ番号を付ける
  let l:b[4][4] = {'id': s:S.center, 'role': 'center', 'n': 0}
  for l:i in range(8)
    let l:id = l:ring[l:i]
    if empty(l:id)
      continue
    endif
    let l:b[3 + s:pos[l:i][0]][3 + s:pos[l:i][1]] = {'id': l:id, 'role': 'item', 'n': l:i + 1}
    let l:br = s:pos[l:i][0] * 3
    let l:bc = s:pos[l:i][1] * 3
    let l:b[l:br + 1][l:bc + 1] = {'id': l:id, 'role': 'center', 'n': l:i + 1}
    let l:sub = s:ring(l:id, 0)
    for l:j in range(8)
      if !empty(l:sub[l:j])
        let l:b[l:br + s:pos[l:j][0]][l:bc + s:pos[l:j][1]] = {'id': l:sub[l:j], 'role': 'sub', 'n': 0}
      endif
    endfor
  endfor
  " 真ん中のブロックの周り 8 マスは、周りのブロックの上書きで消えないように置き直す
  for l:i in range(8)
    if !empty(l:ring[l:i])
      let l:b[3 + s:pos[l:i][0]][3 + s:pos[l:i][1]] = {'id': l:ring[l:i], 'role': 'item', 'n': l:i + 1}
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

function! s:label(cell) abort
  if has_key(a:cell, 'text')
    return a:cell.text
  endif
  if empty(a:cell.id) || !has_key(s:S.data.nodes, a:cell.id)
    return ''
  endif
  let l:nd = s:S.data.nodes[a:cell.id]
  return (l:nd.g ? '◆' : '') . l:nd.t
endfunction

" 盤面の大きさ。マスは見た目が正方形になるようにする（端末の文字は縦:横 = 2:1 くらいなので、
" 1 マスの内側の幅 cw = 2 * 高さ ch + 1）。窓に入りきらなければ ch を小さくする。
function! s:geometry(n, W, H, chrome) abort
  let l:avail_h = a:H - a:chrome - (a:n + 1)   " 見出し・モードの行・案内の行・横線 n+1 本を除く
  let l:ch_h = l:avail_h / a:n
  let l:wlim = (a:W - (a:n + 1)) / a:n        " 縦線 n+1 本を除いた 1 マスの最大の幅
  let l:ch_w = (l:wlim - 1) / 2
  let l:ch = max([1, min([l:ch_h, l:ch_w, 9])])
  let l:cw = min([l:wlim, 2 * l:ch + 1])
  " 9×9 は題が読めないほど狭くなるなら、正方形をあきらめて幅を確保する
  if a:n == 9
    let l:cw = max([l:cw, min([l:wlim, 8])])
  endif
  return [max([3, l:cw]), l:ch]
endfunction

" 案内を幅に収まるように折り返す（見切れないように）
function! s:footer_lines(W) abort
  let l:items = get(s:S, 'pick', 0)
        \ ? ['hjkl 移動', '1-8 そのマスへ', 'Enter 中心に（索引が中心で Enter=ここに追加）', 'a g n c r モード', 's 検索', '/ ヒットへ（Tab 次）', 'F 絞り込み', '[ ] 前後', '- 戻る', 'f 全画面', 'R 読み直し', 'q 取消']
        \ : ['hjkl 移動', '1-8 そのマスへ', 'Enter 中心に', 'a g n c r モード', 's 検索', '/ ヒットへ（Tab 次）', 'F 絞り込み', '[ ] 前後', '- 戻る', 'f 全画面', 'R 読み直し', 'Space ノート', 'q 閉じる']
  let l:lines = []
  let l:cur = ''
  for l:it in l:items
    let l:try = empty(l:cur) ? ' ' . l:it : l:cur . '  ' . l:it
    if strdisplaywidth(l:try) > a:W && !empty(l:cur)
      call add(l:lines, l:cur)
      let l:cur = ' ' . l:it
    else
      let l:cur = l:try
    endif
  endfor
  call add(l:lines, l:cur)
  return l:lines
endfunction

" モードの行: ' モード: [a:全体]  g:索引  n:ノート  c:近い索引  r:関連'（今のモードを目立たせる位置も返す）
function! s:mode_bar(W) abort
  let l:str = ' モード:'
  let l:span = []
  for [l:k, l:m] in s:mode_keys
    let l:str .= ' '
    let l:cell = l:k . ':' . s:mode_label[l:m]
    if l:m ==# s:S.mode
      let l:cell = '[' . l:cell . ']'
      let l:span = [2, strlen(l:str) + 1, strlen(l:cell)]
    endif
    let l:str .= l:cell . ' '
  endfor
  if strdisplaywidth(l:str) > a:W
    " 幅が足りないときは、今のモードだけ名前を出す
    let l:str = ' '
    for [l:k, l:m] in s:mode_keys
      if l:m ==# s:S.mode
        let l:cell = '[' . l:k . ':' . s:mode_label[l:m] . ']'
        let l:span = [2, strlen(l:str) + 1, strlen(l:cell)]
        let l:str .= l:cell . ' '
      else
        let l:str .= l:k . ' '
      endif
    endfor
  endif
  return [l:str, l:span]
endfunction

function! s:render() abort
  let l:n = s:S.size
  let l:b = s:board()
  let s:S.cells = l:b
  let l:W = winwidth(0)
  let l:H = winheight(0)
  let l:foot = s:footer_lines(l:W)
  let [l:cw, l:ch] = s:geometry(l:n, l:W, l:H, 2 + len(l:foot))
  let l:heavy = {0: 1, 3: 1, 6: 1, 9: 1}
  let l:gridw = l:n * (l:cw + 1) + 1
  let l:left = repeat(' ', max([0, (l:W - l:gridw) / 2]))
  let l:gridh = l:n * (l:ch + 1) + 1
  let l:top = max([0, (l:H - 2 - len(l:foot) - l:gridh) / 2])
  let l:lines = []
  let s:S.spans = {}   " 'r,c' => [行, 開始バイト(1 始まり), バイト長]
  " 上の見出し（今の中心・何枚目・モード）
  let l:ctitle = has_key(s:S.data.nodes, s:S.center) ? s:S.data.nodes[s:S.center].t : s:S.center
  let l:pages = s:pages(s:S.center)
  let l:extra = (empty(s:S.rquery) ? '' : '   検索: ' . s:S.rquery . '（' . len(s:S.results) . '件）')
        \ . (empty(s:S.query) ? '' : '   絞り込み: ' . s:S.query)
        \ . (empty(get(s:S, 'find', '')) ? '' : '   /' . s:S.find . (get(s:S, 'hit_n', 0) > 0 ? ' ' . s:S.hit_i . '/' . s:S.hit_n : ' (ヒットなし)'))
  call add(l:lines, s:fit(printf(' %s%s   %d/%d   %s%s', get(s:S, 'pick', 0) ? '追加先を選ぶ: ' : '', l:ctitle,
        \ s:S.page + 1, l:pages, l:n == 3 ? '3×3' : '9×9', l:extra), l:W))
  let [l:bar, s:S.modespan] = s:mode_bar(l:W)
  call add(l:lines, s:fit(l:bar, l:W))
  for l:k in range(l:top)
    call add(l:lines, '')
  endfor
  for l:r in range(l:n)
    call add(l:lines, l:left . s:hline(l:n, l:cw, l:r, l:heavy))
    let l:cellines = []
    for l:c in range(l:n)
      let l:cell = l:b[l:r][l:c]
      let l:txt = s:label(l:cell)
      if l:cell.n > 0 && !empty(l:txt)
        let l:txt = l:cell.n . ' ' . l:txt
      endif
      let l:tl = empty(l:txt) ? [] : s:wrap(l:txt, l:cw - 1, l:ch)
      if !empty(l:tl) && l:ch >= 3 && l:cell.role ==# 'item' && index(['near', 'rel'], s:S.mode) >= 0 && empty(s:S.rquery) && has_key(s:S.why, l:cell.id)
        let l:rn = l:ch >= 5 ? 2 : 1
        let l:tl = l:tl[0 : l:ch - 1 - l:rn] + s:wrap('‹' . s:S.why[l:cell.id] . '›', l:cw - 1, l:rn)
      endif
      call add(l:cellines, l:tl)
    endfor
    for l:k in range(l:ch)
      let l:line = l:left
      for l:c in range(l:n)
        let l:sep = (l:n == 3 || has_key(l:heavy, l:c)) ? '┃' : '│'
        let l:line .= l:sep
        " 文字はマスの真ん中（縦も横も）に置く
        let l:tl = l:cellines[l:c]
        let l:txt = get(l:tl, l:k - (l:ch - len(l:tl)) / 2, '')
        if l:k < (l:ch - len(l:tl)) / 2
          let l:txt = ''
        endif
        let l:lead = max([0, (l:cw - strdisplaywidth(l:txt)) / 2])
        let l:cellstr = s:pad(repeat(' ', l:lead) . l:txt, l:cw)
        let l:key = l:r . ',' . l:c
        if !has_key(s:S.spans, l:key)
          let s:S.spans[l:key] = []
        endif
        call add(s:S.spans[l:key], [len(l:lines) + 1, strlen(l:line) + 1, strlen(l:cellstr)])
        let l:line .= l:cellstr
      endfor
      call add(l:lines, l:line . '┃')
    endfor
  endfor
  call add(l:lines, l:left . s:hline(l:n, l:cw, l:n, l:heavy))
  while len(l:lines) < l:H - len(l:foot)
    call add(l:lines, '')
  endwhile
  call extend(l:lines, map(l:foot, 's:fit(v:val, l:W)'))
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
      if empty(l:sp) || (empty(l:cell.id) && !has_key(l:cell, 'text'))
        continue
      endif
      if l:r == s:S.cur[0] && l:c == s:S.cur[1]
        call add(w:mview_match, matchaddpos('GnosisMviewSel', l:sp, 20))
      elseif l:cell.role ==# 'center'
        call add(w:mview_match, matchaddpos('GnosisMviewCenter', l:sp, 10))
      endif
    endfor
  endfor
  if !empty(get(s:S, 'modespan', []))
    call add(w:mview_match, matchaddpos('GnosisMviewSel', [s:S.modespan], 15))
  endif
  " / の語は、ふつうの検索のようにハイライト
  if !empty(get(s:S, 'find', ''))
    call add(w:mview_match, matchadd('Search', '\c\V' . escape(s:S.find, '\'), 5))
  endif
  let l:sp = get(s:S.spans, s:S.cur[0] . ',' . s:S.cur[1], [])
  if !empty(l:sp)
    call cursor(l:sp[0][0], l:sp[0][1])
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

" 数字キー（1 2 3 / 4 _ 5 / 6 7 8）: 3×3 ではそのマスへ移って中心にする（0 は中心のノートを右に出す）。
" 9×9 ではそのブロックの真ん中にカーソルを置くだけ（中心は変えない）
function! s:digit(d) abort
  if s:S.size == 9
    let s:S.cur = a:d == 0 ? [4, 4] : [s:pos[a:d - 1][0] * 3 + 1, s:pos[a:d - 1][1] * 3 + 1]
    call s:mark()
    return
  endif
  let s:S.cur = a:d == 0 ? [1, 1] : copy(s:pos[a:d - 1])
  call s:mark()
  call s:enter()
endfunction

function! s:set_center(id, page) abort
  let s:S.find = ''
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
  if l:cell.id ==# s:S.center && get(s:S, 'pick', 0)
    if s:S.data.nodes[l:cell.id].g && empty(s:S.query) && empty(s:S.rquery)
      call s:decide(l:cell.id)
    endif
    return
  endif
  if l:cell.id ==# s:S.center
    call s:show_note(l:cell.id)
    return
  endif
  let s:S.query = ''
  let s:S.rquery = ''
  call add(s:S.hist, [s:S.center, s:S.page])
  call s:set_center(l:cell.id, 0)
endfunction

" ---- / : ふつうの検索のように、語をハイライトしてヒットしたマスへ飛ぶ ----------------------

function! s:title_of(id) abort
  return has_key(s:S.data.nodes, a:id) ? tolower(s:S.data.nodes[a:id].t) : ''
endfunction

" ヒットの一覧 [[枚, 行, 列], …]（読む順）。ほかの枚は周りの 8 マスだけ、今の枚は見えているマス全部
function! s:hit_list() abort
  let l:q = tolower(s:S.find)
  let l:out = []
  let l:ring = s:items(s:S.center)
  for l:i in range(len(l:ring))
    if stridx(s:title_of(l:ring[l:i]), l:q) >= 0
      let l:p = s:pos[l:i % 8]
      let l:o = s:S.size == 3 ? 0 : 3
      call add(l:out, [l:i / 8, l:o + l:p[0], l:o + l:p[1]])
    endif
  endfor
  let l:mid = s:S.size == 3 ? 1 : 4
  for l:r in range(s:S.size)
    for l:c in range(s:S.size)
      let l:cell = s:S.cells[l:r][l:c]
      if (l:cell.role ==# 'sub' || (l:r == l:mid && l:c == l:mid)) && !empty(l:cell.id) && stridx(s:title_of(l:cell.id), l:q) >= 0
        call add(l:out, [s:S.page, l:r, l:c])
      endif
    endfor
  endfor
  return sort(l:out, {a, b -> a[0] != b[0] ? a[0] - b[0] : (a[1] != b[1] ? a[1] - b[1] : a[2] - b[2])})
endfunction

function! s:cmp3(a, b) abort
  for l:k in range(3)
    if a:a[l:k] != a:b[l:k]
      return a:a[l:k] - a:b[l:k]
    endif
  endfor
  return 0
endfunction

" ヒットへ飛ぶ。dir=1 は次、-1 は前（端で折り返す）。first=1 は今の位置も含めて探す
function! s:jump(dir, ...) abort
  if empty(get(s:S, 'find', ''))
    return
  endif
  let l:hits = s:hit_list()
  let s:S.hit_n = len(l:hits)
  if empty(l:hits)
    let s:S.hit_i = 0
    call s:render()
    return
  endif
  let l:here = [s:S.page, s:S.cur[0], s:S.cur[1]]
  let l:target = -1
  if a:dir > 0
    for l:i in range(len(l:hits))
      if s:cmp3(l:hits[l:i], l:here) > (a:0 && a:1 ? -1 : 0)
        let l:target = l:i
        break
      endif
    endfor
    if l:target < 0 | let l:target = 0 | endif
  else
    for l:i in range(len(l:hits) - 1, 0, -1)
      if s:cmp3(l:hits[l:i], l:here) < 0
        let l:target = l:i
        break
      endif
    endfor
    if l:target < 0 | let l:target = len(l:hits) - 1 | endif
  endif
  let s:S.hit_i = l:target + 1
  let s:S.page = l:hits[l:target][0]
  let s:S.cur = [l:hits[l:target][1], l:hits[l:target][2]]
  call s:render()
endfunction

function! s:find_prompt() abort
  let s:S.find = trim(input('/', get(s:S, 'find', '')))
  let s:S.hit_n = 0
  let s:S.hit_i = 0
  if empty(s:S.find)
    call s:render()
  else
    call s:jump(1, 1)
  endif
endfunction

function! s:find_clear() abort
  if !empty(get(s:S, 'find', ''))
    let s:S.find = ''
    call s:render()
  endif
endfunction

" 索引を選ぶ: F で題を絞り込む（空にすると解除）
function! s:filter() abort
  let l:q = input(get(s:S, 'pick', 0) ? '索引を絞り込む（空で解除）: ' : '今の周りを絞り込む（空で解除）: ', s:S.query)
  let s:S.query = trim(l:q)
  let s:S.page = 0
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  call s:render()
endfunction

" 中心の索引に決める: 曼荼羅を閉じ、元のノートを載せる
function! s:decide(id) abort
  let l:src = s:S.src
  let l:group = s:S.root . '/' . a:id
  call gnosis#mview#close()
  let s:S.pick = 0
  call gnosis#index_add(l:src, l:group)
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

" モード（英字）: a すべて / g 索引だけ / n ノートだけ / c 近い索引
function! s:setmode(m) abort
  let s:S.mode = a:m
  let s:S.find = ''
  let s:S.query = ''
  let s:S.rquery = ''
  let s:S.page = 0
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  call s:render()
endfunction

" 検索（s）: 題か本文に語を全部含むノートを、vault 全体から探して周りに並べる
function! s:search() abort
  let l:q = trim(input('検索（題・本文。空で解除）: ', s:S.rquery))
  let s:S.query = ''
  if empty(l:q)
    let s:S.rquery = ''
  else
    let l:cmd = join(map([gnosis#python_cmd(), s:here . '/python/mandala_view.py', 'search', s:S.root] + split(l:q, '\s\+'), 'shellescape(v:val)'), ' ')
    try
      let s:S.results = json_decode(system(l:cmd))
    catch
      let s:S.results = []
    endtry
    let s:S.rquery = l:q
  endif
  let s:S.page = 0
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
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
  execute 'vertical resize ' . (&columns / 2)
  return l:nw
endfunction

function! s:show_note(id) abort
  if get(s:S, 'pick', 0)
    return
  endif
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
  nnoremap <buffer><silent> a <Cmd>call <SID>setmode('all')<CR>
  nnoremap <buffer><silent> g <Cmd>call <SID>setmode('groups')<CR>
  nnoremap <buffer><silent> n <Cmd>call <SID>setmode('notes')<CR>
  nnoremap <buffer><silent> c <Cmd>call <SID>setmode('near')<CR>
  nnoremap <buffer><silent> r <Cmd>call <SID>setmode('rel')<CR>
  nnoremap <buffer><silent> s <Cmd>call <SID>search()<CR>
  nnoremap <buffer><silent> / <Cmd>call <SID>find_prompt()<CR>
  nnoremap <buffer><silent> F <Cmd>call <SID>filter()<CR>
  nnoremap <buffer><silent> <Tab> <Cmd>call <SID>jump(1)<CR>
  nnoremap <buffer><silent> <S-Tab> <Cmd>call <SID>jump(-1)<CR>
  nnoremap <buffer><silent> <Esc> <Cmd>call <SID>find_clear()<CR>
  nnoremap <buffer><silent> f <Cmd>call <SID>full()<CR>
  nnoremap <buffer><silent> R <Cmd>call <SID>reload()<CR>
  nnoremap <buffer><silent> q <Cmd>call gnosis#mview#close()<CR>
  nnoremap <buffer><silent> <Space> <Cmd>call gnosis#mview#toggle()<CR>
  augroup gnosis_mview_buf
    autocmd! * <buffer>
    autocmd VimResized,WinResized * if &filetype ==# 'gnosis-mandala' | call s:render() | endif
  augroup END
endfunction

function! s:reload() abort
  let s:S.nearc = {}
  let s:S.relc = {}
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

function! s:open(center, ...) abort
  call s:hl()
  let l:pick = a:0 ? a:1 : ''
  let s:S.pick = !empty(l:pick)
  let s:S.src = l:pick
  let s:S.query = ''
  let s:S.rquery = ''
  let s:S.results = []
  let s:S.find = ''
  let s:S.nearc = {}
  let s:S.relc = {}
  let s:S.why = {}
  if !s:load()
    echohl WarningMsg | echo 'Gnosis: vault が選ばれていません' | echohl NONE
    return
  endif
  let l:root = s:S.root . '/'
  let l:mode = get(s:S, 'mode', 'all')
  let l:size = get(s:S, 'size', 3)
  let l:hist = get(s:S, 'hist', [])
  let l:buf = get(s:S, 'buf', -1)
  if !empty(l:pick)
    let s:S.saved_mode = l:mode
  endif
  let s:S.mode = empty(l:pick) ? l:mode : 'near'
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
    execute 'vertical resize ' . (&columns / 2)
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

" \g: 今のノートを載せる索引を、曼荼羅で選ぶ（/ で絞り込み → 移動 → 中心で Enter）
function! gnosis#mview#pick() abort
  let l:file = expand('%:p')
  if empty(l:file) || &filetype ==# 'gnosis-mandala' || l:file !~? '\.md$'
    echohl WarningMsg | echo 'Gnosis: 索引に載せるノートを開いて実行して' | echohl NONE
    return
  endif
  let l:root = s:root()
  let l:rel = stridx(l:file, l:root . '/') == 0 ? strpart(l:file, len(l:root) + 1) : ''
  call s:open(l:rel, l:file)
endfunction

function! gnosis#mview#close() abort
  if has_key(s:S, 'saved_mode')
    let s:S.mode = remove(s:S, 'saved_mode')
  endif
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
