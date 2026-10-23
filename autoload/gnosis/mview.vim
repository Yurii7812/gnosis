" 曼荼羅ビュー（CUI）。<Space> で、曼荼羅（左）とふつうのノート（右）を行き来する。
"
" 中心のノートの周りに、つながっているノートを 8 つずつ並べる。
"   中心が索引（グループ） … 載っているノート。8 つを超えたら 2 枚目以降の曼荼羅（[ ] で前後）
"   中心がノート           … 所属する索引（Group: / BranchGroup:）。モードでノート同士のつながりも出せる
" 画面の大きさは、分割しているときは 3×3、全画面（f）では 9×9（周りの 8 マスがそれぞれ自分の曼荼羅を持つ）。
" 分割は左右半々（< > で曼荼羅の幅を変えられる）。マスは見た目が正方形で、盤面は窓の中央に置く。
"
" キー（曼荼羅のウィンドウ）
"   h j k l / 矢印   マスを動く（右のノートがそのマスのノートに切り替わる。中心は変わらない）
"   1-9              そのマスへ（1 2 3 / 4 5 6 / 7 8 9。5 が中心）。t で「移動して中心に」⇔「カーソルだけ」
"                    Enter  カーソルのマスを中心にする
"   ノートのマスで Enter           右にそのノートを開く（カーソルは曼荼羅に残る）
"   [ ]              前後の曼荼羅（ページ (1/2) は中央のマスの上）    b / <BS> 一つ前に戻る
"   a i n c r        モード: a 全体 / i 索引 / n ノート / c 近い索引（所属が先、近い未所属が後）/ r 関連（索引もノートも関連の強い順）
"   s                検索（題・本文を vault 全体から。結果が周りに並び、真ん中に「検索: 語」）
"   /                ふつうの検索のように語をハイライトしてヒットのマスへ飛ぶ（複数枚あれば別の枚へも）。Tab / S-Tab で次・前、Esc で解除
"   e                今の周りを題で絞り込む（\g では索引を全部から）    f 全画面（9×9）⇔ 分割（3×3）
"   Space            ノートのウィンドウへ    u 読み直す    q 閉じる
" 罫線は既定で文字。空白の背景色で描くなら let g:gnosis_mview_border = 'color'
" 元データは python/mandala_view.py（読み取り専用）。ノートは書き換えない。

let s:S = {}
let s:here = expand('<sfile>:p:h:h:h')
" 周りの 8 マス（読む順）
let s:pos = [[0, 0], [0, 1], [0, 2], [1, 0], [1, 2], [2, 0], [2, 1], [2, 2]]
" 番号はテンキーと同じ並び（1 2 3 / 4 5 6 / 7 8 9）。真ん中が 5
let s:nums = [1, 2, 3, 4, 6, 7, 8, 9]
let s:mode_label = {'all': '全体', 'groups': '索引', 'notes': 'ノート', 'near': '近い索引', 'rel': '関連'}
let s:mode_keys = [['a', 'all'], ['i', 'groups'], ['n', 'notes'], ['c', 'near'], ['r', 'rel']]

" 罫線の描き方。既定 'line' は罫線の文字。'color' は罫線の文字を使わず、空白に背景色を付けて線にする
" （端末のフォントや大きさで罫線の文字がずれるのを避けたいとき用）
function! s:bar_color() abort
  return get(g:, 'gnosis_mview_border', 'line') ==# 'color'
endfunction

function! s:root() abort
  let l:r = trim(get(g:, 'gnosis_root', ''))
  return empty(l:r) ? '' : substitute(fnamemodify(l:r, ':p'), '/$', '', '')
endfunction

" ---- データ -----------------------------------------------------------------

" python/mandala_view.py を呼んで JSON を返す。失敗（終了コード≠0・JSON でない）は v:null。
" 標準エラーは混ぜない（警告が混ざると JSON として読めず、時々だけ失敗する）
function! s:py(args) abort
  let l:cmd = join(map([gnosis#python_cmd(), s:here . '/python/mandala_view.py'] + a:args, 'shellescape(v:val)'), ' ') . ' 2>/dev/null'
  let l:out = system(l:cmd)
  if v:shell_error
    return v:null
  endif
  try
    return json_decode(l:out)
  catch
    return v:null
  endtry
endfunction

function! s:load() abort
  let l:root = s:root()
  if empty(l:root)
    return 0
  endif
  let l:d = s:py(['dump', l:root])
  if type(l:d) != v:t_dict || type(get(l:d, 'nodes', 0)) != v:t_dict
    echohl WarningMsg | echo 'Gnosis: 曼荼羅のデータを読めませんでした' | echohl NONE
    return 0
  endif
  let s:S.data = l:d
  let s:S.root = l:root
  return 1
endfunction

" python/mandala_view.py の items() と同じ規則（ダブルインデックスの道に沿う）
"   ノートが中心 … 進む先のトピック索引（BranchGroup:）→ 所属する索引（Group:）→ ほかのつながり
"   索引が中心   … この索引を持つノート（BranchGroup: を逆に）→ 所属する索引（Group:）→ 索引の項目すべて（i）
" 周りに出すもの [[ノートの相対パス, 表示名（索引に書かれた索引語。題と同じなら ""）], …]。
" 同じノートが同じ索引に別の名前で何回載っていても、載っている回数だけ入る
function! gnosis#mview#items(data, center, mode) abort
  return map(gnosis#mview#entries(a:data, a:center, a:mode), 'v:val[0]')
endfunction

function! gnosis#mview#entries(data, center, mode) abort
  let l:nodes = a:data.nodes
  if !has_key(l:nodes, a:center)
    return []
  endif
  let l:c = l:nodes[a:center]
  let l:o = l:c.o
  let l:origin = get(get(l:c, 'r', {}), 'branch_group', [])
  let l:out = []
  let l:seen = {}
  " [ids, want] の並び。want: -1 すべて / 0 索引でないものだけ
  let l:plan = []
  if l:c.g
    if a:mode ==# 'notes' || a:mode ==# 'all'
      call add(l:plan, [l:origin, -1])
    endif
    if a:mode !=# 'notes'
      call add(l:plan, [get(l:o, 'group', []), -1])
    endif
    " 索引の項目: 同じノートが別の名前で何回載っていても全部。n は索引でない普通のノートだけ
    call add(l:plan, [map(copy(get(l:c, 'en', map(copy(get(l:o, 'link', [])), '[v:val, ""]'))), 'v:val'), a:mode ==# 'notes' ? 0 : -1])
  else
    if a:mode ==# 'groups' || a:mode ==# 'all'
      call add(l:plan, [get(l:o, 'branch_group', []), -1])
      call add(l:plan, [get(l:o, 'group', []), -1])
    endif
    if a:mode ==# 'notes' || a:mode ==# 'all'
      for l:k in ['parent_branch', 'child_branch', 'context', 'related', 'backlink', 'link']
        call add(l:plan, [get(l:o, l:k, []), -1])
      endfor
    endif
  endif
  for [l:ids, l:want] in l:plan
    for l:t in l:ids
      " 項目は [ノート, 名前]、それ以外はノートだけ
      let l:id = type(l:t) == v:t_list ? l:t[0] : l:t
      let l:name = type(l:t) == v:t_list ? l:t[1] : ''
      let l:key = l:id . "\x01" . l:name
      if l:id ==# a:center || has_key(l:seen, l:key) || !has_key(l:nodes, l:id)
        continue
      endif
      " ノートだけ（名前なし）の重複は 1 つにする
      if empty(l:name) && !empty(filter(copy(l:out), 'v:val[0] ==# l:id && empty(v:val[1])'))
        continue
      endif
      if l:want >= 0 && l:nodes[l:id].g != l:want
        continue
      endif
      let l:seen[l:key] = 1
      call add(l:out, [l:id, l:name])
    endfor
  endfor
  return l:out
endfunction

" 近い索引（python/mandala_view.py の near）。中心ごとに覚えておく（r で読み直し）
function! s:near(c) abort
  if !has_key(s:S.nearc, a:c)
    let l:d = s:py(['near', s:S.root, a:c])
    if type(l:d) != v:t_list
      " 失敗は覚えない（次の描き直しでもう一度試す）
      let s:S.why = {}
      return gnosis#mview#items(s:S.data, a:c, 'groups')
    endif
    let s:S.nearc[a:c] = l:d
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
      let s:S.why[l:d.id] = join(l:d.why[0 : 2], '・')
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
    let l:d = s:py(['related', s:S.root, a:c])
    if type(l:d) != v:t_list
      let s:S.why = {}
      return []
    endif
    let s:S.relc[a:c] = l:d
  endif
  let s:S.why = {}
  for l:d in s:S.relc[a:c]
    let s:S.why[l:d.id] = join(l:d.why[0 : 2], '・')
  endfor
  return map(copy(s:S.relc[a:c]), 'v:val.id')
endfunction

" 周辺に出すもの（絞り込み前）。検索の結果があればそれ。中心でなければ（9×9 の周りのブロック）近い索引は使わず「すべて」
function! s:base(c) abort
  if a:c ==# s:S.center
    if !empty(s:S.rquery)
      return map(copy(s:S.results), '[v:val, ""]')
    endif
    if s:S.mode ==# 'near'
      return map(s:near(a:c), '[v:val, ""]')
    elseif s:S.mode ==# 'rel'
      return map(s:rel(a:c), '[v:val, ""]')
    endif
  endif
  return gnosis#mview#entries(s:S.data, a:c, index(['near', 'rel'], s:S.mode) >= 0 ? 'all' : s:S.mode)
endfunction

" 絞り込みや検索で照らす文字: 索引に書かれた名前があればそれ、無ければ題
function! s:entry_text(e) abort
  if !empty(a:e[1])
    return tolower(a:e[1])
  endif
  return has_key(s:S.data.nodes, a:e[0]) ? tolower(s:S.data.nodes[a:e[0]].t) : ''
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
        call add(l:out, [l:id, ''])
      endif
    endfor
    return l:out
  endif
  return filter(l:b, 'stridx(s:entry_text(v:val), l:q) >= 0')
endfunction

function! s:pages(center) abort
  return max([1, (len(s:items(a:center)) + 7) / 8])
endfunction

" 中心 c の page 枚目の周辺 8 マス（足りない所は ''）
function! s:ring(c, page) abort
  let l:all = s:items(a:c)
  let l:r = l:all[a:page * 8 : a:page * 8 + 7]
  while len(l:r) < 8
    call add(l:r, ['', ''])
  endwhile
  return l:r
endfunction

" ---- 盤面 -------------------------------------------------------------------
" 盤面は n×n（n は 3 か 9）。マス = {'id': ノート, 'role': 'center'|'item'|'sub'|'empty'}

function! s:board() abort
  let l:b = s:board_cells()
  call s:set_kinds(l:b)
  if !empty(s:S.rquery)
    let l:c = s:S.size == 3 ? 1 : 4
    let l:b[l:c][l:c] = {'id': '', 'role': 'center', 'n': 0, 'text': '検索: ' . s:S.rquery}
  endif
  return l:b
endfunction

function! s:set_kinds(b) abort
  let l:n = s:S.size
  for l:r in range(l:n)
    for l:c in range(l:n)
      let l:cell = a:b[l:r][l:c]
      let l:of = get(l:cell, 'of', s:S.center)
      let l:cell.kind = empty(l:cell.id) ? 'note' : s:kind(l:cell.id, l:of)
      " 関連モードで出た、直接のつながりのないもの（Related: の欄ではなく、関連の強さで選ばれたもの）
      if l:cell.kind ==# 'note' && s:S.mode ==# 'rel' && empty(s:S.rquery) && get(l:cell, 'role', '') ==# 'item' && has_key(s:S.why, l:cell.id)
        let l:cell.kind = 'related'
      endif
    endfor
  endfor
endfunction

function! s:board_cells() abort
  let l:n = s:S.size
  let l:b = []
  for l:i in range(l:n)
    call add(l:b, repeat([{'id': '', 'role': 'empty', 'n': 0}], l:n))
  endfor
  let l:ring = s:ring(s:S.center, s:S.page)
  if l:n == 3
    let l:b[1][1] = {'id': s:S.center, 'role': 'center', 'n': 5}
    for l:i in range(8)
      if !empty(l:ring[l:i][0])
        let l:b[s:pos[l:i][0]][s:pos[l:i][1]] = {'id': l:ring[l:i][0], 'name': l:ring[l:i][1], 'role': 'item', 'n': s:nums[l:i]}
      endif
    endfor
    return l:b
  endif
  " 9×9: 真ん中の 3×3 が今の曼荼羅。周りの 8 ブロックは、その周辺の各ノートを中心にした曼荼羅の 1 枚目。
  " ブロックの真ん中のマスにも、周りのマスと同じ番号を付ける
  let l:b[4][4] = {'id': s:S.center, 'role': 'center', 'n': 5}
  for l:i in range(8)
    let l:id = l:ring[l:i][0]
    if empty(l:id)
      continue
    endif
    let l:b[3 + s:pos[l:i][0]][3 + s:pos[l:i][1]] = {'id': l:id, 'name': l:ring[l:i][1], 'role': 'item', 'n': s:nums[l:i]}
    let l:br = s:pos[l:i][0] * 3
    let l:bc = s:pos[l:i][1] * 3
    let l:b[l:br + 1][l:bc + 1] = {'id': l:id, 'name': l:ring[l:i][1], 'role': 'center', 'n': s:nums[l:i]}
    let l:sub = s:ring(l:id, 0)
    for l:j in range(8)
      if !empty(l:sub[l:j][0])
        let l:b[l:br + s:pos[l:j][0]][l:bc + s:pos[l:j][1]] = {'id': l:sub[l:j][0], 'name': l:sub[l:j][1], 'role': 'sub', 'n': 0, 'of': l:id}
      endif
    endfor
  endfor
  " 真ん中のブロックの周り 8 マスは、周りのブロックの上書きで消えないように置き直す
  for l:i in range(8)
    if !empty(l:ring[l:i][0])
      let l:b[3 + s:pos[l:i][0]][3 + s:pos[l:i][1]] = {'id': l:ring[l:i][0], 'name': l:ring[l:i][1], 'role': 'item', 'n': s:nums[l:i]}
    endif
  endfor
  return l:b
endfunction

" 文字列を表示幅 w の行に折り返す（最大 h 行。あふれたら … ）。空白で区切れるところは空白で折り返し
" （「Gnosis 操作ガイド」が「ガイ／ド」と語の途中で切れない）、1 語が w より長いときだけ文字で折り返す
function! s:wrap(text, w, h) abort
  let l:lines = []
  let l:cur = ''
  let l:cw = 0
  for l:word in split(a:text, ' ')
    let l:ww = strdisplaywidth(l:word)
    if !empty(l:cur) && l:cw + 1 + l:ww <= a:w
      let l:cur .= ' ' . l:word
      let l:cw += 1 + l:ww
      continue
    endif
    if !empty(l:cur) && l:ww <= a:w
      call add(l:lines, l:cur)
      let l:cur = l:word
      let l:cw = l:ww
      continue
    endif
    " 長い語は、今の行の続きに文字で詰めて折り返す
    if !empty(l:cur)
      let l:cur .= ' '
      let l:cw += 1
    endif
    for l:ch in split(l:word, '\zs')
      let l:d = strdisplaywidth(l:ch)
      if l:cw + l:d > a:w
        call add(l:lines, l:cur)
        let l:cur = ''
        let l:cw = 0
      endif
      let l:cur .= l:ch
      let l:cw += l:d
    endfor
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

" マスの種類（色と記号で一目で分かるように）: 索引・親・子・Context・関連・BackLink・ふつうのノート
let s:kinds = {'index': ['', '索引', 'GnosisMvIndex'], 'group': ['', 'グループ', 'GnosisMvGroup'], 'parent': ['', '親', 'GnosisMvParent'],
      \ 'child': ['', '子', 'GnosisMvChild'], 'context': ['', '文脈', 'GnosisMvContext'], 'related': ['', '関連', 'GnosisMvRelated'],
      \ 'back': ['', 'BackLink', 'GnosisMvBack'], 'note': ['', 'ノート', '']}
let s:kind_legend = ['index', 'group', 'parent', 'child', 'context', 'related', 'back', 'note']

" マス a:id が、a:of（そのマスの中心）から見てどういうものか
function! s:kind(id, of) abort
  if empty(a:id) || !has_key(s:S.data.nodes, a:id)
    return 'note'
  endif
  let l:nd = s:S.data.nodes[a:id]
  if l:nd.g
    return 'group'
  endif
  if empty(a:of) || !has_key(s:S.data.nodes, a:of)
    return 'note'
  endif
  " 索引 = グループに載っているノート（そのグループの項目）
  if s:S.data.nodes[a:of].g && index(get(s:S.data.nodes[a:of].o, 'link', []), a:id) >= 0
    return 'index'
  endif
  " この索引（トピック索引）を BranchGroup: に持つノートは、戻る道（親）
  if index(get(get(s:S.data.nodes[a:of], 'r', {}), 'branch_group', []), a:id) >= 0
    return 'parent'
  endif
  let l:o = s:S.data.nodes[a:of].o
  let l:r = l:nd.o
  if index(get(l:o, 'parent_branch', []), a:id) >= 0 || index(get(l:r, 'child_branch', []), a:of) >= 0
    return 'parent'
  elseif index(get(l:o, 'child_branch', []), a:id) >= 0 || index(get(l:r, 'parent_branch', []), a:of) >= 0
    return 'child'
  elseif index(get(l:o, 'context', []), a:id) >= 0 || index(get(l:r, 'context', []), a:of) >= 0
    return 'context'
  elseif index(get(l:o, 'backlink', []), a:id) >= 0
    return 'back'
  endif
  return 'note'
endfunction

function! s:label(cell) abort
  if has_key(a:cell, 'text')
    return a:cell.text
  endif
  if empty(a:cell.id) || !has_key(s:S.data.nodes, a:cell.id)
    return ''
  endif
  " 索引に載っている表示名（索引語）があればそれを名前にする
  let l:name = get(a:cell, 'name', '')
  return s:kinds[a:cell.kind][0] . (empty(l:name) ? s:S.data.nodes[a:cell.id].t : l:name)
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
  return [max([1, l:cw]), l:ch]
endfunction

" 凡例（色つき）: ' ◆索引 ▲親 ▼子 ◇Context ≈関連 ←BackLink ノート'。色を付ける位置も返す
function! s:legend(W) abort
  let l:str = ' '
  let l:spans = []
  for l:k in s:kind_legend
    let l:cell = (empty(s:kinds[l:k][0]) ? '' : s:kinds[l:k][0]) . s:kinds[l:k][1]
    call add(l:spans, [l:k, strlen(l:str) + 1, strlen(l:cell)])
    let l:str .= l:cell . '  '
  endfor
  return {'text': s:fit(l:str, a:W), 'spans': l:spans}
endfunction

" カーソルのマスの説明を 1 行で（題・種類・理由）
function! s:info() abort
  if get(s:S, 'info_line', 0) <= 0
    return
  endif
  let l:cell = s:cur_cell()
  let l:txt = ''
  if !empty(l:cell.id) && has_key(s:S.data.nodes, l:cell.id)
    let l:why = (index(['near', 'rel'], s:S.mode) >= 0 && empty(s:S.rquery) && has_key(s:S.why, l:cell.id)) ? '  ' . s:S.why[l:cell.id] : ''
    let l:txt = ' ▶ ' . s:S.data.nodes[l:cell.id].t . '  [' . s:kinds[l:cell.kind][1] . ']' . l:why
  endif
  setlocal modifiable
  call setline(s:S.info_line, s:fit(l:txt, winwidth(0)))
  setlocal nomodifiable nomodified
endfunction

" 案内を幅に収まるように折り返す（見切れないように）
function! s:footer_lines(W) abort
  let l:items = get(s:S, 'pick', 0)
        \ ? ['hjkl 移動', '1-9 そのマスへ（5 が中心。t で移動⇔カーソルだけ）', 'Enter 中心に（索引が中心で Enter=ここに追加）', 'モード切替（全体:a 索引:i ノート:n 近い索引:c 関連:r）', 's 検索', '/ ヒットへ（Tab 次）', 'e 絞り込み', '[ ] 前後', 'b 戻る', 'f 全画面', '< > 曼荼羅の幅', 'z 中央に', '? 隠す（曼荼羅だけに戻す）', 'u 読み直し', 'q 取消']
        \ : ['hjkl 移動', '1-9 そのマスへ（5 が中心。t で移動⇔カーソルだけ）', 'Enter 中心に', 'モード切替（全体:a 索引:i ノート:n 近い索引:c 関連:r）', 's 検索', '/ ヒットへ（Tab 次）', 'e 絞り込み', '[ ] 前後', 'b 戻る', 'f 全画面', '< > 曼荼羅の幅', 'z 中央に', '? 隠す（曼荼羅だけに戻す）', 'u 読み直し', 'Space ノート', 'q 閉じる']
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

" モードの行: ' モード: [全体:a] 索引:i ノート:n 近い索引:c 関連:r'（今のモードを目立たせる位置も返す）
function! s:mode_bar(W) abort
  " ' モード: [a:全体] g:索引 …' を幅に収まるように折り返す。[行, 色を付ける位置] を返す
  let l:lines = []
  let l:cur = ' モード:'
  let l:span = []
  for [l:k, l:m] in s:mode_keys
    let l:cell = s:mode_label[l:m] . ':' . l:k
    let l:on = l:m ==# s:S.mode
    if l:on
      let l:cell = '[' . l:cell . ']'
    endif
    if strdisplaywidth(l:cur . ' ' . l:cell) > a:W && l:cur !~# '^ モード:$'
      call add(l:lines, l:cur)
      let l:cur = '        '
    endif
    let l:cur .= ' '
    if l:on
      let l:span = [len(l:lines) + 2, strlen(l:cur) + 1, strlen(l:cell)]
    endif
    let l:cur .= l:cell
  endfor
  " 数字キーの動き（t で切り替え）
  let l:d = '数字:' . (s:S.digit ==# 'jump' ? '移動' : 'カーソルだけ') . '(t)'
  if strdisplaywidth(l:cur . '  ' . l:d) > a:W
    call add(l:lines, l:cur)
    let l:cur = '        '
  endif
  let l:cur .= '  ' . l:d
  call add(l:lines, l:cur)
  return [l:lines, l:span]
endfunction

function! s:render() abort
  " 色の定義が消えていたら戻す（default なので、利用者の指定は上書きしない）
  call s:hl()
  let l:n = s:S.size
  " 読み直しや絞り込みで枚数・盤面が変わっても範囲外にならないように
  let s:S.page = max([0, min([s:S.page, s:pages(s:S.center) - 1])])
  if s:S.cur[0] < 0 || s:S.cur[0] >= l:n || s:S.cur[1] < 0 || s:S.cur[1] >= l:n
    let s:S.cur = l:n == 3 ? [1, 1] : [4, 4]
  endif
  let l:b = s:board()
  let s:S.cells = l:b
  let l:W = winwidth(0)
  let l:H = winheight(0)
  " ふだんは曼荼羅（盤面）だけ。? を押したときだけ、見出し・モード・凡例・説明・案内を出す。
  " 出すときも、窓が低ければ盤面を優先して 案内→凡例と説明→モードの行 の順に減らす（どんな大きさでも盤面が窓に収まる）
  let l:help = get(s:S, 'help', 0)
  let l:show_ref = 0
  let l:foot = []
  let l:bar = []
  let s:S.modespan = []
  if l:help
    let l:foot = s:footer_lines(l:W)
    let [l:bar, s:S.modespan] = s:mode_bar(l:W)
    let l:show_ref = 1
    let l:min_grid = l:n * 2 + 1
    if 1 + len(l:bar) + 2 + len(l:foot) + l:min_grid > l:H
      let l:foot = l:foot[0 : 0]
    endif
    if 1 + len(l:bar) + 2 + len(l:foot) + l:min_grid > l:H
      let l:show_ref = 0
    endif
    if 1 + len(l:bar) + (l:show_ref ? 2 : 0) + len(l:foot) + l:min_grid > l:H
      let l:bar = l:bar[0 : 0]
    endif
  endif
  let l:fixed = (l:help ? 1 : 0) + len(l:bar) + (l:show_ref ? 2 : 0) + len(l:foot)
  let l:legend = l:show_ref ? s:legend(l:W) : {'text': '', 'spans': []}
  let s:S.legend_line = 0
  let [l:cw, l:ch] = s:geometry(l:n, l:W, l:H, l:fixed)
  let l:heavy = {0: 1, 3: 1, 6: 1, 9: 1}
  let l:gridw = l:n * (l:cw + 1) + 1
  let l:left = repeat(' ', max([0, (l:W - l:gridw) / 2]))
  let l:gridh = l:n * (l:ch + 1) + 1
  let l:top = max([0, (l:H - l:fixed - l:gridh) / 2])
  let l:lines = []
  let s:S.bars = []   " 色の線にする位置 [グループ, 行, 開始バイト, バイト長]
  let s:S.spans = {}   " 'r,c' => [行, 開始バイト(1 始まり), バイト長]
  " 上の見出し（今の中心・何枚目・モード）
  let l:ctitle = has_key(s:S.data.nodes, s:S.center) ? s:S.data.nodes[s:S.center].t : s:S.center
  let l:pages = s:pages(s:S.center)
  " ページ（1/2）は中央のマスの一番上に。マスが小さくて入らないときだけ見出しに出す
  let l:mid = l:n == 3 ? 1 : 4
  let l:ptop = (l:pages > 1 && l:ch >= 3) ? '(' . (s:S.page + 1) . '/' . l:pages . ')' : ''
  let l:extra = (empty(s:S.rquery) ? '' : '   検索: ' . s:S.rquery . '（' . len(s:S.results) . '件）')
        \ . (empty(s:S.query) ? '' : '   絞り込み: ' . s:S.query)
        \ . (empty(get(s:S, 'find', '')) ? '' : '   /' . s:S.find . (get(s:S, 'hit_n', 0) > 0 ? ' ' . s:S.hit_i . '/' . s:S.hit_n : ' (ヒットなし)'))
  if l:help
    call add(l:lines, s:fit(printf(' %s%s   %s%s%s', get(s:S, 'pick', 0) ? '追加先を選ぶ: ' : '', l:ctitle,
          \ (l:pages > 1 && empty(l:ptop)) ? (s:S.page + 1) . '/' . l:pages . '   ' : '', l:n == 3 ? '3×3' : '9×9', l:extra), l:W))
    call extend(l:lines, map(copy(l:bar), 's:fit(v:val, l:W)'))
  endif
  if l:show_ref
    call add(l:lines, l:legend.text)
    let s:S.legend_line = len(l:lines)
  endif
  let s:S.legend_spans = l:show_ref ? l:legend.spans : []
  for l:k in range(l:top)
    call add(l:lines, '')
  endfor
  for l:r in range(l:n)
    call add(l:lines, l:left . s:hline(l:n, l:cw, l:r, l:heavy))
    call add(s:S.bars, [(l:n == 3 || has_key(l:heavy, l:r)) ? 'GnosisMviewBarH' : 'GnosisMviewBarL', len(l:lines), strlen(l:left) + 1, l:gridw])
    let l:cellines = []
    for l:c in range(l:n)
      let l:cell = l:b[l:r][l:c]
      let l:txt = s:label(l:cell)
      if l:cell.n > 0 && !empty(l:txt)
        let l:txt = l:cell.n . ' ' . l:txt
      endif
      let l:tp = (l:r == l:mid && l:c == l:mid) ? l:ptop : ''
      call add(l:cellines, {'t': empty(l:txt) ? [] : s:wrap(l:txt, max([1, l:cw - 1]), empty(l:tp) ? l:ch : l:ch - 1), 'r': '', 'p': l:tp})
    endfor
    for l:k in range(l:ch)
      let l:line = l:left
      for l:c in range(l:n)
        let l:sep = s:bar_color() ? ' ' : ((l:n == 3 || has_key(l:heavy, l:c)) ? '┃' : '│')
        call add(s:S.bars, [(l:n == 3 || has_key(l:heavy, l:c)) ? 'GnosisMviewBarH' : 'GnosisMviewBarL', len(l:lines) + 1, strlen(l:line) + 1, strlen(l:sep)])
        let l:line .= l:sep
        " 題はマスの真ん中（縦も横も）、理由は一番下の行
        let l:tl = l:cellines[l:c].t
        let l:ph = empty(l:cellines[l:c].p) ? 0 : 1
        let l:body_h = l:ch - l:ph - (empty(l:cellines[l:c].r) ? 0 : 1)
        let l:off = l:ph + (l:body_h - len(l:tl)) / 2
        let l:txt = (l:k >= l:off && l:k - l:off < len(l:tl)) ? l:tl[l:k - l:off] : ''
        if l:ph && l:k == 0
          let l:txt = l:cellines[l:c].p
        endif
        if l:k == l:ch - 1 && !empty(l:cellines[l:c].r)
          let l:txt = l:cellines[l:c].r
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
      let l:vend = s:bar_color() ? ' ' : '┃'
      call add(s:S.bars, ['GnosisMviewBarH', len(l:lines) + 1, strlen(l:line) + 1, strlen(l:vend)])
      call add(l:lines, l:line . l:vend)
    endfor
  endfor
  call add(l:lines, l:left . s:hline(l:n, l:cw, l:n, l:heavy))
  call add(s:S.bars, ['GnosisMviewBarH', len(l:lines), strlen(l:left) + 1, l:gridw])
  while len(l:lines) < l:H - len(l:foot) - (l:show_ref ? 1 : 0)
    call add(l:lines, '')
  endwhile
  if l:show_ref
    call add(l:lines, '')
    let s:S.info_line = len(l:lines)
  else
    let s:S.info_line = 0
  endif
  call extend(l:lines, map(l:foot, 's:fit(v:val, l:W)'))
  setlocal modifiable
  silent! %delete _
  call setline(1, l:lines)
  setlocal nomodifiable nomodified
  call winrestview({'topline': 1, 'leftcol': 0})
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
  return s:bar_color() ? repeat(' ', strdisplaywidth(l:line)) : l:line
endfunction

" 選んでいるマスと、中心を色で示す
" matchaddpos は 1 回に 8 か所までなので分けて足す
function! s:addpos(group, pos, prio) abort
  for l:i in range(0, len(a:pos) - 1, 8)
    call add(w:mview_match, matchaddpos(a:group, a:pos[l:i : l:i + 7], a:prio))
  endfor
endfunction

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
        " 選んでいるマス: 種類の色を残して背景だけ変える
        let l:hg = s:kinds[get(l:cell, 'kind', 'note')][2]
        call s:addpos(empty(l:hg) ? 'GnosisMviewSel' : l:hg . 'S', l:sp, 20)
      elseif l:cell.role ==# 'center'
        let l:hg = s:kinds[get(l:cell, 'kind', 'note')][2]
        call s:addpos(empty(l:hg) ? 'GnosisMviewCenter' : l:hg . 'C', l:sp, 10)
      elseif !empty(get(s:kinds, get(l:cell, 'kind', 'note'), ['', '', ''])[2])
        call s:addpos(s:kinds[l:cell.kind][2], l:sp, 8)
      endif
    endfor
  endfor
  if s:bar_color()
    for l:g in ['GnosisMviewBarH', 'GnosisMviewBarL']
      call s:addpos(l:g, map(filter(copy(get(s:S, 'bars', [])), 'v:val[0] ==# l:g'), 'v:val[1 : 3]'), 3)
    endfor
  endif
  if !empty(get(s:S, 'modespan', []))
    call s:addpos('GnosisMviewSel', [s:S.modespan], 15)
  endif
  for [l:k, l:col, l:len] in get(s:S, 'legend_spans', [])
    if !empty(s:kinds[l:k][2])
      call s:addpos(s:kinds[l:k][2], [[s:S.legend_line, l:col, l:len]], 15)
    endif
  endfor
  " / の語は、ふつうの検索のようにハイライト
  if !empty(get(s:S, 'find', ''))
    call add(w:mview_match, matchadd('Search', '\c\V' . escape(s:S.find, '\'), 5))
  endif
  let l:sp = get(s:S.spans, s:S.cur[0] . ',' . s:S.cur[1], [])
  if !empty(l:sp)
    call cursor(l:sp[0][0], l:sp[0][1])
  endif
  call s:info()
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
  call s:preview()
endfunction

" カーソルのマスのノートを右に出す（曼荼羅の中心は変えない）
function! s:preview() abort
  let l:cell = s:cur_cell()
  if !empty(l:cell.id)
    call s:show_note(l:cell.id)
  endif
endfunction

" 数字キー（テンキーと同じ 1 2 3 / 4 5 6 / 7 8 9。5 が中心）。t で切り替える:
"   移動     … そのマスへ移って中心にする（0 は中心のノートを開く）
"   カーソル … そのマスにカーソルを置くだけ（右のノートは切り替わる。中心は変わらない）
" 9×9 ではそのブロックの真ん中のマスが対象
function! s:digit(d) abort
  let l:i = index(s:nums, a:d)
  if s:S.size == 9
    let s:S.cur = l:i < 0 ? [4, 4] : [s:pos[l:i][0] * 3 + 1, s:pos[l:i][1] * 3 + 1]
  else
    let s:S.cur = l:i < 0 ? [1, 1] : copy(s:pos[l:i])
  endif
  call s:mark()
  if s:S.digit ==# 'jump'
    call s:enter()
  else
    call s:preview()
  endif
endfunction

" z: 中央にする（盤面を今の窓の大きさに合わせて中央に描き直し、スクロールのずれを戻し、カーソルを中心のマスへ）
function! s:recenter() abort
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  call s:render()
  call s:preview()
endfunction

" ---- 曼荼羅の幅を覚える（< > で変えた幅が、次に開いたときもそのまま） -----------------------
" Gnosis ホームの mandala.json: {"tenths": 画面の何割か（2-8。5 = 半々）}。中心のノート・ページ・カーソル・モードは覚えない
" （開くたびに今のノートが中心）。試験では g:gnosis_mview_restore = 0 で、覚えた幅を使わない。

function! s:state_all() abort
  try
    let l:d = gnosis#home#read_json(gnosis#home#path('mandala.json'), {})
    return type(l:d) == v:t_dict ? l:d : {}
  catch
    return {}
  endtry
endfunction

function! s:save_state() abort
  if !has_key(s:S, 'tenths')
    return
  endif
  try
    call gnosis#home#write_json(gnosis#home#path('mandala.json'), {'tenths': s:S.tenths})
  catch
  endtry
endfunction

function! s:toggle_help() abort
  let s:S.help = !get(s:S, 'help', 0)
  call s:render()
  call s:save_state()
endfunction

function! s:toggle_digit() abort
  let s:S.digit = s:S.digit ==# 'jump' ? 'cursor' : 'jump'
  call s:render()
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

function! s:cell_text(cell) abort
  return s:entry_text([a:cell.id, get(a:cell, 'name', '')])
endfunction

" ヒットの一覧 [[枚, 行, 列], …]（読む順）。ほかの枚は周りの 8 マスだけ、今の枚は見えているマス全部
function! s:hit_list() abort
  let l:q = tolower(s:S.find)
  let l:out = []
  let l:ring = s:items(s:S.center)
  for l:i in range(len(l:ring))
    if stridx(s:entry_text(l:ring[l:i]), l:q) >= 0
      let l:p = s:pos[l:i % 8]
      let l:o = s:S.size == 3 ? 0 : 3
      call add(l:out, [l:i / 8, l:o + l:p[0], l:o + l:p[1]])
    endif
  endfor
  let l:mid = s:S.size == 3 ? 1 : 4
  for l:r in range(s:S.size)
    for l:c in range(s:S.size)
      let l:cell = s:S.cells[l:r][l:c]
      if (l:cell.role ==# 'sub' || (l:r == l:mid && l:c == l:mid)) && !empty(l:cell.id) && stridx(s:cell_text(l:cell), l:q) >= 0
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
  echo '/' . s:S.find . '  ' . s:S.hit_i . '/' . s:S.hit_n
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
  while !has_key(s:S.data.nodes, l:id) && !empty(s:S.hist)
    let [l:id, l:pg] = remove(s:S.hist, -1)
  endwhile
  if !has_key(s:S.data.nodes, l:id)
    return
  endif
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

" モード（英字）: a 全体 / i 索引 / n ノート / c 近い索引 / r 関連
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
    let l:d = s:py(['search', s:S.root] + split(l:q, '\s\+'))
    let s:S.results = type(l:d) == v:t_list ? l:d : []
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
    let l:nw = s:note_win()
    if l:nw > 0
      call win_execute(l:nw, 'if &modified && &buftype ==# "" | silent! update | endif')
    endif
    silent! only
  else
    let s:S.size = 3
    call s:ensure_note_win()
  endif
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  call s:render()
  " 全画面で閉じた右のノートを、分割に戻したときに出し直す（中心のノート）
  if s:S.size == 3
    call s:show_note(s:S.center)
  endif
endfunction

" ---- ウィンドウ -------------------------------------------------------------

" 曼荼羅のウィンドウの幅（画面の何割か。< > で変える。既定は半々）
function! s:win_width() abort
  return &columns * get(s:S, 'tenths', 5) / 10
endfunction

" < で曼荼羅を狭く、> で広く（1 回で画面の幅の 1/10）。分割しているときだけ
function! s:resize(d) abort
  if s:S.size != 3 || s:note_win() < 0
    return
  endif
  " 割合は 10 分率の整数で持つ（5 = 半々）。小数と整数を混ぜると Vim はエラーにする
  let s:S.tenths = min([8, max([2, get(s:S, 'tenths', 5) + a:d])])
  execute 'vertical resize ' . s:win_width()
  call s:render()
  call s:save_state()
endfunction

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
  if l:mw < 0
    return -1
  endif
  call win_gotoid(l:mw)
  vertical rightbelow new
  let l:nw = win_getid()
  " 窓を分けると曼荼羅の色づけ（matchaddpos）も新しい窓に写るので、ノートの窓には残さない
  call clearmatches(l:nw)
  unlet! w:mview_match
  call win_gotoid(l:mw)
  execute 'vertical resize ' . s:win_width()
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
  if fnamemodify(bufname(winbufnr(l:nw)), ':p') ==# fnamemodify(l:path, ':p')
    return
  endif
  call win_execute(l:nw, 'if &modified && &buftype ==# "" | silent! update | endif')
  call win_execute(l:nw, 'silent! hide edit ' . fnameescape(l:path))
  let s:S.note = l:path
endfunction

" ---- 入口 -------------------------------------------------------------------

function! s:setup_buffer() abort
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted nowrap nolist nonumber norelativenumber
  setlocal nocursorline nospell nofoldenable colorcolumn= signcolumn=no filetype=gnosis-mandala scrolloff=0 sidescrolloff=0
  nnoremap <buffer><nowait><silent> h <Cmd>call <SID>move(0, -1)<CR>
  nnoremap <buffer><nowait><silent> <Left> <Cmd>call <SID>move(0, -1)<CR>
  nnoremap <buffer><nowait><silent> l <Cmd>call <SID>move(0, 1)<CR>
  nnoremap <buffer><nowait><silent> <Right> <Cmd>call <SID>move(0, 1)<CR>
  nnoremap <buffer><nowait><silent> k <Cmd>call <SID>move(-1, 0)<CR>
  nnoremap <buffer><nowait><silent> <Up> <Cmd>call <SID>move(-1, 0)<CR>
  nnoremap <buffer><nowait><silent> j <Cmd>call <SID>move(1, 0)<CR>
  nnoremap <buffer><nowait><silent> <Down> <Cmd>call <SID>move(1, 0)<CR>
  for l:d in range(10)
    execute printf('nnoremap <buffer><nowait><silent> %d <Cmd>call <SID>digit(%d)<CR>', l:d, l:d)
  endfor
  nnoremap <buffer><nowait><silent> <CR> <Cmd>call <SID>enter()<CR>
  nnoremap <buffer><nowait><silent> ] <Cmd>call <SID>page(1)<CR>
  nnoremap <buffer><nowait><silent> [ <Cmd>call <SID>page(-1)<CR>
  nnoremap <buffer><nowait><silent> b <Cmd>call <SID>back()<CR>
  nnoremap <buffer><nowait><silent> <BS> <Cmd>call <SID>back()<CR>
  nnoremap <buffer><nowait><silent> a <Cmd>call <SID>setmode('all')<CR>
  nnoremap <buffer><nowait><silent> i <Cmd>call <SID>setmode('groups')<CR>
  nnoremap <buffer><nowait><silent> n <Cmd>call <SID>setmode('notes')<CR>
  nnoremap <buffer><nowait><silent> c <Cmd>call <SID>setmode('near')<CR>
  nnoremap <buffer><nowait><silent> r <Cmd>call <SID>setmode('rel')<CR>
  nnoremap <buffer><nowait><silent> s <Cmd>call <SID>search()<CR>
  nnoremap <buffer><nowait><silent> / <Cmd>call <SID>find_prompt()<CR>
  nnoremap <buffer><nowait><silent> e <Cmd>call <SID>filter()<CR>
  nnoremap <buffer><nowait><silent> t <Cmd>call <SID>toggle_digit()<CR>
  nnoremap <buffer><nowait><silent> ? <Cmd>call <SID>toggle_help()<CR>
  nnoremap <buffer><nowait><silent> <Tab> <Cmd>call <SID>jump(1)<CR>
  nnoremap <buffer><nowait><silent> <S-Tab> <Cmd>call <SID>jump(-1)<CR>
  nnoremap <buffer><nowait><silent> <Esc> <Cmd>call <SID>find_clear()<CR>
  nnoremap <buffer><nowait><silent> f <Cmd>call <SID>full()<CR>
  nnoremap <buffer><nowait><silent> z <Cmd>call <SID>recenter()<CR>
  nnoremap <buffer><nowait><silent> <lt> <Cmd>call <SID>resize(-1)<CR>
  nnoremap <buffer><nowait><silent> > <Cmd>call <SID>resize(1)<CR>
  nnoremap <buffer><nowait><silent> u <Cmd>call <SID>reload()<CR>
  nnoremap <buffer><nowait><silent> q <Cmd>call gnosis#mview#close()<CR>
  nnoremap <buffer><nowait><silent> <Space> <Cmd>call gnosis#mview#toggle()<CR>
  augroup gnosis_mview_buf
    autocmd! * <buffer>
    autocmd VimResized,WinResized * call gnosis#mview#rerender()
    autocmd BufEnter,WinEnter <buffer> call gnosis#mview#cursor(0)
    autocmd BufLeave,WinLeave <buffer> call gnosis#mview#cursor(1)
    autocmd VimLeavePre <buffer> call gnosis#mview#cursor(1)
  augroup END
endfunction

" ノートを保存・読み込みしたら（題を zr で変えたときなど）、曼荼羅が開いていれば少し待って読み直す
function! s:touched() abort
  if empty(get(s:S, 'buf', 0)) || s:mwin() < 0 || &filetype ==# 'gnosis-mandala'
    return
  endif
  if exists('s:sync_timer')
    call timer_stop(s:sync_timer)
  endif
  let s:sync_timer = timer_start(600, {-> gnosis#mview#refresh()})
endfunction

" 端末のカーソルの表示。曼荼羅では出さない（選んでいるマスは背景色で分かる）。show=0 で隠し、1 で戻す
function! gnosis#mview#cursor(show) abort
  if has('gui_running')
    return
  endif
  if a:show
    if exists('s:t_ve')
      let &t_ve = s:t_ve
      unlet s:t_ve
    endif
    call echoraw("\<Esc>[?25h")
  else
    if !exists('s:t_ve')
      let s:t_ve = &t_ve
    endif
    let &t_ve = "\<Esc>[?25l"
    call echoraw("\<Esc>[?25l")
  endif
endfunction

" 窓の大きさが変わったとき、曼荼羅の窓を今の大きさで描き直す（今いる窓は変えない）
function! gnosis#mview#rerender() abort
  let l:mw = s:mwin()
  if l:mw < 0 || !has_key(s:S, 'data') || !has_key(s:S, 'cells')
    return
  endif
  try
    call win_execute(l:mw, 'call gnosis#mview#render_here()')
  catch
  endtry
  redraw!
endfunction

function! gnosis#mview#render_here() abort
  call s:render()
endfunction

" 読み直す（開いている曼荼羅の中身・近さを今の vault から作り直す。今の中心・枚・カーソルはそのまま）
function! gnosis#mview#refresh() abort
  if exists('s:sync_timer')
    unlet s:sync_timer
  endif
  let l:mw = s:mwin()
  if l:mw < 0
    return
  endif
  " input() やコマンド行の最中に窓を動かさない。少し待ってもう一度
  if !empty(getcmdtype()) || (mode() =~# '^[iR]' || mode() =~# '^c[^ve]')
    let s:sync_timer = timer_start(600, {-> gnosis#mview#refresh()})
    return
  endif
  let l:back = win_getid()
  noautocmd call win_gotoid(l:mw)
  call s:reload()
  noautocmd call win_gotoid(l:back)
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
  " 種類の色（gui の色, 256 色の番号）。中心のマスは同じ色を太字にした C つき
  let l:cols = {'Index': ['#ff6b81', 204], 'Group': ['#e5a64a', 178], 'Parent': ['#61afef', 75], 'Child': ['#56b6c2', 73],
        \ 'Context': ['#c678dd', 176], 'Related': ['#98c379', 108], 'Back': ['#7f848e', 245]}
  for [l:k, l:c] in items(l:cols)
    execute printf('highlight default GnosisMv%s guifg=%s ctermfg=%d', l:k, l:c[0], l:c[1])
    " 中心のマスは太字だけ（下線はマスの全部の行に引かれて、しましまになる）
    execute printf('highlight default GnosisMv%sC guifg=%s ctermfg=%d gui=bold cterm=bold', l:k, l:c[0], l:c[1])
    execute printf('highlight default GnosisMv%sS guifg=%s ctermfg=%d guibg=#3a3f4b ctermbg=238 gui=bold cterm=bold', l:k, l:c[0], l:c[1])
  endfor
  " 罫線の色（空白の背景色で線にする）。太い線（3×3 の境目）と細い線
  highlight default GnosisMviewBarH guibg=#6b7280 ctermbg=243
  highlight default GnosisMviewBarL guibg=#3f4551 ctermbg=239
  highlight default link GnosisMviewSel Visual
  highlight default link GnosisMviewCenter Title
endfunction

function! s:open(center, ...) abort
  call s:hl()
  augroup gnosis_mview_sync
    autocmd!
    autocmd BufWritePost,FileChangedShellPost *.md call s:touched()
    autocmd VimLeavePre * call s:save_state()
    " 配色が読み込み直されると（ノートを開き直したときなど）色の定義が全部消えるので、定義し直す
    autocmd ColorScheme * call s:hl()
  augroup END
  let l:pick = a:0 ? a:1 : ''
  " 閉じたときに戻るノート（全画面で閉じると窓が 1 つだけになるため）
  if filereadable(expand('%:p'))
    let s:S.note = expand('%:p')
  endif
  let s:S.digit = get(s:S, 'digit', 'jump')
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
  " 曼荼羅の幅は前回のまま（< > で変えた幅）。中心は今のノート
  if !has_key(s:S, 'tenths') && get(g:, 'gnosis_mview_restore', 1)
    let l:t = get(s:state_all(), 'tenths', 0)
    if type(l:t) == v:t_number && l:t >= 2 && l:t <= 8
      let s:S.tenths = l:t
    endif
  endif
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
    execute 'vertical resize ' . s:win_width()
  endif
  let s:S.buf = bufnr('%')
  call s:render()
  call s:show_note(l:c)
  call win_gotoid(s:mwin())
  " 窓の出入りで戻ってしまうことがあるので、開いた最後にもう一度隠す
  call gnosis#mview#cursor(0)
endfunction

" <Space>: ノートから曼荼羅へ、曼荼羅からノートへ
function! gnosis#mview#toggle() abort
  if &filetype ==# 'gnosis-mandala'
    if s:S.size != 3
      " 全画面（9×9）にノートの窓は無い。分割に戻して、そのマスのノートを右に出す
      let s:S.size = 3
      let s:S.cur = [1, 1]
      call s:ensure_note_win()
      call s:render()
      call s:show_note(s:S.center)
    endif
    let l:nw = s:note_win()
    if l:nw > 0
      call win_gotoid(l:nw)
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
  call s:save_state()
  if has_key(s:S, 'saved_mode')
    let s:S.mode = remove(s:S, 'saved_mode')
  endif
  let l:mw = s:mwin()
  if l:mw > 0
    call win_gotoid(l:mw)
    " 窓ごとの色づけ・設定を残さない（残ると次に開く物が変な見た目になる）
    for l:m in get(w:, 'mview_match', [])
      silent! call matchdelete(l:m)
    endfor
    let w:mview_match = []
    if winnr('$') > 1
      close
    else
      " 全画面（窓が 1 つ）のとき: 曼荼羅の設定を元に戻して、開いていたノートに戻る
      setlocal wrap< list< number< relativenumber< cursorline< spell< foldenable< colorcolumn< signcolumn< scrolloff< sidescrolloff<
      let l:n = get(s:S, 'note', '')
      if !empty(l:n) && filereadable(l:n)
        execute 'silent! edit ' . fnameescape(l:n)
      else
        enew
      endif
    endif
  endif
  if s:note_win() > 0
    call win_gotoid(s:note_win())
  endif
  redraw!
endfunction

" 試験用: 状態を返す
function! gnosis#mview#state() abort
  return s:S
endfunction
