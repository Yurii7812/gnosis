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
"   a i              モード: a 全体（標準）/ i グループ・索引だけ
"   c r              重ねる（オン/オフ。どのモードでも）: c 近いグループ / r 予測関連（関連の強い順。Related: の明示とは別の色）
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
let s:mode_label = {'all': '全体', 'groups': '索引'}
let s:mode_keys = [['a', 'all'], ['i', 'groups']]
" 重ねるもの（オン/オフ）: [キー, 状態の名前, 表示名]
let s:over_keys = [['c', 'near_on', '近いグループ'], ['r', 'rel_on', '予測関連']]

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

" python/mandala_cache.py（SQLite のキャッシュ）を呼んで JSON を返す。失敗は v:null
function! s:pyc(args) abort
  let l:cmd = join(map([gnosis#python_cmd(), s:here . '/python/mandala_cache.py'] + a:args, 'shellescape(v:val)'), ' ') . ' 2>/dev/null'
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

" キャッシュを更新して、読み込み済みのノートを捨てる。force=1 は全体を走査（u）。ふだんは直近に走査していれば省く
function! s:load(...) abort
  let l:root = s:root()
  if empty(l:root)
    return 0
  endif
  let l:first = !filereadable(l:root . '/.gnosis/cache/mandala.sqlite')
  let l:force = a:0 && a:1
  let l:st = l:first ? v:null : s:pyc(['status', l:root])
  " 古い版のキャッシュ（スキーマが違う）は空に見える: 作り直しになるので、初回と同じ案内を出す
  if !l:first && type(l:st) == v:t_dict && get(l:st, 'notes', 0) == 0
    let l:first = 1
  endif
  if l:first
    echo 'Gnosis: 曼荼羅の索引を作っています（初回だけ時間がかかります）…'
    redraw
  endif
  " 走査が重い vault（1 秒を超える）では、開くのを待たせず、走査は裏で行う。終わって変わっていれば描き直す
  if !l:first && !l:force && type(l:st) == v:t_dict && get(l:st, 'scan_sec', 0) > 1.0 && has('job')
    call s:refresh_async(l:root)
    let l:r = {}
  else
    let l:r = s:pyc(['refresh', l:root] + (l:force ? ['--force'] : []))
  endif
  if type(l:r) != v:t_dict
    echohl WarningMsg | echo 'Gnosis: 曼荼羅のデータを読めませんでした' | echohl NONE
    return 0
  endif
  let s:S.data = {'nodes': {}}
  let s:S.missing = {}
  let s:S.root = l:root
  return 1
endfunction

" 裏で更新する。終わって変わったノートがあれば、開いている曼荼羅を描き直す
function! s:refresh_async(root) abort
  if exists('s:S.job') && type(s:S.job) == v:t_job && job_status(s:S.job) ==# 'run'
    return
  endif
  let s:S.async_out = ''
  let s:S.job = job_start(split(gnosis#python_cmd()) + [s:here . '/python/mandala_cache.py', 'refresh', a:root],
        \ {'out_mode': 'raw', 'err_io': 'null', 'in_io': 'null',
        \  'out_cb': {_c, m -> execute('let s:S.async_out .= m', '')},
        \  'exit_cb': {_j, _s -> timer_start(0, {-> s:after_async()})}})
endfunction

function! s:after_async() abort
  try
    let l:r = json_decode(get(s:S, 'async_out', ''))
  catch
    return
  endtry
  if type(l:r) != v:t_dict || (get(l:r, 'changed', 0) + get(l:r, 'removed', 0)) == 0 || s:mwin() < 0
    return
  endif
  if !empty(getcmdtype()) || mode() =~# '^[iR]'
    return
  endif
  let l:back = win_getid()
  noautocmd call win_gotoid(s:mwin())
  let s:S.data = {'nodes': {}}
  let s:S.missing = {}
  let s:S.nearc = {}
  let s:S.relc = {}
  if !s:has(s:S.center)
    let s:S.center = 'index.md'
  endif
  call s:render()
  noautocmd call win_gotoid(l:back)
endfunction

" ids のうち full（周りへの辺を持つ形）でないものを、まとめて 1 回で取る。周りのノートは light（題と索引か）で入る
function! s:fetch(ids) abort
  let l:need = []
  for l:id in a:ids
    if !empty(l:id) && !has_key(s:S.missing, l:id) && !(has_key(s:S.data.nodes, l:id) && has_key(s:S.data.nodes[l:id], 'o'))
      call add(l:need, l:id)
    endif
  endfor
  if empty(l:need)
    return
  endif
  let l:need = uniq(sort(l:need))
  let l:d = s:pyc(['nodes', s:S.root] + l:need)
  if type(l:d) != v:t_dict
    return
  endif
  let l:got = get(l:d, 'nodes', {})
  for l:id in l:need
    if !has_key(l:got, l:id)
      let s:S.missing[l:id] = 1
    endif
  endfor
  for [l:id, l:nd] in items(l:got)
    if has_key(l:nd, 'o') || !has_key(s:S.data.nodes, l:id)
      let s:S.data.nodes[l:id] = l:nd
    endif
  endfor
endfunction

" ノートがあるか（なければ 0）。light でよければ読み込み済みのものを使う
function! s:has(id) abort
  if empty(a:id)
    return 0
  endif
  if !has_key(s:S.data.nodes, a:id)
    call s:fetch([a:id])
  endif
  return has_key(s:S.data.nodes, a:id)
endfunction

" ノート a:id の full（無ければ {}）
function! s:nd(id) abort
  call s:fetch([a:id])
  return get(s:S.data.nodes, a:id, {})
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
    " 親 → 文脈 → 引用 → 子 → 関連。向かってくる辺（相手にだけ書かれた親子・文脈・関連）も同じ種類として出す
    let l:in = get(l:c, 'i', {})
    if a:mode ==# 'notes' || a:mode ==# 'all'
      call add(l:plan, [get(l:o, 'parent_branch', []) + get(l:in, 'child_branch', []), -1])
      call add(l:plan, [get(l:o, 'context', []) + get(l:in, 'context', []), -1])
      call add(l:plan, [get(l:o, 'link', []), -1])
      call add(l:plan, [get(l:o, 'backlink', []), -1])
      call add(l:plan, [get(l:o, 'child_branch', []) + get(l:in, 'parent_branch', []), -1])
      call add(l:plan, [get(l:o, 'related', []) + get(l:in, 'related', []), -1])
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

" 近いグループ（python/mandala_view.py の near）。中心ごとに覚えておく（u で読み直し）。
" 返すのは「近いのにまだ載っていない索引」（理由は s:S.why[id]）。すでに載っているものは返さない
function! s:near_ids(c, have) abort
  if !has_key(s:S.nearc, a:c)
    let l:d = s:py(['near', s:S.root, a:c])
    if type(l:d) != v:t_list
      " 失敗は覚えない（次の描き直しでもう一度試す）
      return []
    endif
    let s:S.nearc[a:c] = l:d
  endif
  let l:out = []
  for l:d in s:S.nearc[a:c]
    if index(a:have, l:d.id) < 0 && index(l:out, l:d.id) < 0
      call add(l:out, l:d.id)
      let s:S.why[l:d.id] = join(l:d.why[0 : 2], '・')
    endif
  endfor
  if empty(s:S.nearc[a:c])
    " 手がかりが無いときは Index の直下の索引も足す
    call s:fetch(['index.md'])
    for l:id in gnosis#mview#items(s:S.data, 'index.md', 'groups')
      if l:id !=# a:c && index(a:have, l:id) < 0 && index(l:out, l:id) < 0
        call add(l:out, l:id)
        let s:S.why[l:id] = 'Index'
      endif
    endfor
  endif
  return l:out
endfunction

" 予測関連（python/mandala_view.py の related）。関連の強い順。理由は強い 2 つまで。Related: に書かれたものとは別の色
function! s:rel_ids(c, have) abort
  if !has_key(s:S.relc, a:c)
    let l:d = s:py(['related', s:S.root, a:c])
    if type(l:d) != v:t_list
      return []
    endif
    let s:S.relc[a:c] = l:d
  endif
  let l:out = []
  for l:d in s:S.relc[a:c]
    if index(a:have, l:d.id) < 0 && index(l:out, l:d.id) < 0
      call add(l:out, l:d.id)
      let s:S.pred[l:d.id] = 1
      let s:S.why[l:d.id] = join(l:d.why[0 : 2], '・')
    endif
  endfor
  return l:out
endfunction

" 周辺に出すもの（絞り込み前）。検索の結果があればそれ。中心でなければ（9×9 の周りのブロック）近い索引は使わず「すべて」
function! s:base(c) abort
  call s:fetch([a:c])
  if a:c ==# s:S.center
    let s:S.why = {}
    let s:S.pred = {}
    if !empty(s:S.rquery)
      let l:ids = copy(s:S.results)
      call s:fetch(l:ids)
      return map(l:ids, '[v:val, ""]')
    endif
  endif
  let l:out = gnosis#mview#entries(s:S.data, a:c, s:S.mode)
  if a:c ==# s:S.center
    " c / r は、どのモードにも重ねる（中心でないブロックには重ねない）
    let l:have = map(copy(l:out), 'v:val[0]')
    let l:extra = []
    if get(s:S, 'near_on', 0)
      call extend(l:extra, s:near_ids(a:c, l:have))
    endif
    if get(s:S, 'rel_on', 0)
      call extend(l:extra, s:rel_ids(a:c, l:have + l:extra))
    endif
    call s:fetch(l:extra)   " 題を出すのに要る。まとめて 1 回で取る
    call extend(l:out, map(l:extra, '[v:val, ""]'))
  endif
  return l:out
endfunction

" 絞り込みや検索で照らす文字: 索引に書かれた名前があればそれ、無ければ題
function! s:entry_text(e) abort
  if !empty(a:e[1])
    return tolower(a:e[1])
  endif
  return s:has(a:e[0]) ? tolower(s:S.data.nodes[a:e[0]].t) : ''
endfunction

" 絞り込み（/）: 索引を選ぶとき（\g）は題が合う索引を全部から、ふだんは今の周りの中から
" 近さ順（w）: basis のノートに近いもの（予測関連の点）を先に並べる。同じ点は元の並びのまま。
" 中心の周り・3×3 は中心に近い順。9×9 の外側のブロックは、既定は中心に近い順（d で、そのブロックの中心のノート自身に近い順）
function! s:rank_map(basis) abort
  if !has_key(s:S, 'rankc')
    let s:S.rankc = {}
  endif
  if !has_key(s:S.rankc, a:basis)
    let l:d = s:pyc(['rank', s:S.root, a:basis])
    let s:S.rankc[a:basis] = type(l:d) == v:t_dict ? l:d : {}
  endif
  return s:S.rankc[a:basis]
endfunction

function! s:order(list, c) abort
  if !get(s:S, 'rank_on', 0) || len(a:list) < 2
    return a:list
  endif
  let l:basis = (a:c ==# s:S.center || get(s:S, 'dbasis', 'center') ==# 'self') ? a:c : s:S.center
  let l:m = s:rank_map(l:basis)
  if empty(l:m)
    return a:list
  endif
  let l:dec = []
  let l:i = 0
  for l:e in a:list
    call add(l:dec, [get(l:m, l:e[0], 0.0), l:i, l:e])
    let l:i += 1
  endfor
  call sort(l:dec, {x, y -> x[0] == y[0] ? x[1] - y[1] : (y[0] > x[0] ? 1 : -1)})
  return map(l:dec, 'v:val[2]')
endfunction

function! s:items(c) abort
  return s:order(s:items_raw(a:c), a:c)
endfunction

function! s:items_raw(c) abort
  let l:b = s:base(a:c)
  if a:c !=# s:S.center || empty(s:S.query)
    return l:b
  endif
  let l:q = tolower(s:S.query)
  if get(s:S, 'pick', '') ==# 'group'
    let l:found = s:pyc(['find', s:S.root] + split(s:S.query, '\s\+'))
    return map(filter(type(l:found) == v:t_list ? l:found : [], 'v:val !=# a:c'), '[v:val, ""]')
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
  " 種類を決めるのに、マスのノートと、そのマスの中心のノートの full が要る。まとめて 1 回で取る
  let l:ids = []
  for l:row in l:b
    for l:cell in l:row
      call add(l:ids, get(l:cell, 'id', ''))
      call add(l:ids, get(l:cell, 'of', s:S.center))
    endfor
  endfor
  call s:fetch(l:ids)
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
      " r で重ねた予測関連（Related: に書かれていない。関連の強さで選ばれたもの）
      if l:cell.kind ==# 'note' && empty(s:S.rquery) && get(l:cell, 'role', '') ==# 'item' && has_key(s:S.pred, l:cell.id)
        let l:cell.kind = 'pred'
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
  if l:n == 9
    call s:fetch(map(copy(l:ring), 'v:val[0]'))
  endif
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
    let l:b[3 + s:pos[l:i][0]][3 + s:pos[l:i][1]] = {'id': l:id, 'name': l:ring[l:i][1], 'role': 'item', 'n': s:nums[l:i], 'bgi': l:i}
    let l:br = s:pos[l:i][0] * 3
    let l:bc = s:pos[l:i][1] * 3
    let l:b[l:br + 1][l:bc + 1] = {'id': l:id, 'name': l:ring[l:i][1], 'role': 'center', 'n': s:nums[l:i], 'bgi': l:i}
    let l:np = s:pages(l:id)
    let l:op = min([get(s:S, 'opage', 0), l:np - 1])
    let l:sub = s:ring(l:id, l:op)
    if l:np > 1
      let l:b[l:br + 1][l:bc + 1].ptxt = (l:op + 1) . '/' . l:np
    endif
    for l:j in range(8)
      if !empty(l:sub[l:j][0])
        let l:b[l:br + s:pos[l:j][0]][l:bc + s:pos[l:j][1]] = {'id': l:sub[l:j][0], 'name': l:sub[l:j][1], 'role': 'sub', 'n': 0, 'of': l:id,
              \ 'dup': l:sub[l:j][0] ==# s:S.center ? 1 : 0}
      endif
    endfor
  endfor
  " 真ん中のブロックの周り 8 マスは、周りのブロックの上書きで消えないように置き直す
  for l:i in range(8)
    if !empty(l:ring[l:i][0])
      let l:b[3 + s:pos[l:i][0]][3 + s:pos[l:i][1]] = {'id': l:ring[l:i][0], 'name': l:ring[l:i][1], 'role': 'item', 'n': s:nums[l:i], 'bgi': l:i}
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
      \ 'context': ['', '文脈', 'GnosisMvContext'], 'cite': ['', '引用', 'GnosisMvCite'], 'back': ['', 'BackLink', 'GnosisMvBack'],
      \ 'child': ['', '子', 'GnosisMvChild'], 'related': ['', '関連', 'GnosisMvRelated'], 'pred': ['', '予測関連', 'GnosisMvPred'],
      \ 'note': ['', 'ノート', 'GnosisMvNote']}
let s:kind_legend = ['index', 'group', 'parent', 'context', 'cite', 'back', 'child', 'related', 'pred', 'note']

" マス a:id が、a:of（そのマスの中心）から見てどういうものか
function! s:kind(id, of) abort
  let l:nd = s:nd(a:id)
  if empty(l:nd)
    return 'note'
  endif
  if l:nd.g
    return 'group'
  endif
  let l:ofd = s:nd(a:of)
  if empty(l:ofd)
    return 'note'
  endif
  " 索引 = グループに載っているノート（そのグループの項目）
  if l:ofd.g && index(get(l:ofd.o, 'link', []), a:id) >= 0
    return 'index'
  endif
  " この索引（トピック索引）を BranchGroup: に持つノートは、戻る道（親）
  if index(get(get(l:ofd, 'r', {}), 'branch_group', []), a:id) >= 0
    return 'parent'
  endif
  let l:o = l:ofd.o
  let l:r = l:nd.o
  let l:oi = get(l:ofd, 'i', {})
  if index(get(l:o, 'parent_branch', []), a:id) >= 0 || index(get(l:r, 'child_branch', []), a:of) >= 0 || index(get(l:oi, 'child_branch', []), a:id) >= 0
    return 'parent'
  elseif index(get(l:o, 'child_branch', []), a:id) >= 0 || index(get(l:r, 'parent_branch', []), a:of) >= 0 || index(get(l:oi, 'parent_branch', []), a:id) >= 0
    return 'child'
  elseif index(get(l:o, 'context', []), a:id) >= 0 || index(get(l:r, 'context', []), a:of) >= 0 || index(get(l:oi, 'context', []), a:id) >= 0
    return 'context'
  elseif index(get(l:o, 'related', []), a:id) >= 0 || index(get(l:r, 'related', []), a:of) >= 0 || index(get(l:oi, 'related', []), a:id) >= 0
    return 'related'
  elseif index(get(l:o, 'link', []), a:id) >= 0
    " 文中で引用している（リンクだけがあって、ブランチ・文脈・関連ではない）
    return 'cite'
  elseif index(get(l:o, 'backlink', []), a:id) >= 0 || index(get(l:r, 'link', []), a:of) >= 0
    " このノートを引用しているノート（BackLink:）
    return 'back'
  endif
  return 'note'
endfunction

function! s:label(cell) abort
  if has_key(a:cell, 'text')
    return a:cell.text
  endif
  if !s:has(a:cell.id)
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
  " ( ) で曼荼羅の盤面を横に伸ばす・縮める（3×3 も 9×9 も。= で正方形に戻す）
  let l:cw = min([l:wlim, max([1, float2nr(round(l:cw * get(s:S, 'stretch', 1.0)))])])
  return [max([1, l:cw]), l:ch]
endfunction

" カーソルのマスの説明を 1 行で（題・種類・理由）
function! s:info() abort
  if get(s:S, 'info_line', 0) <= 0
    return
  endif
  let l:cell = s:cur_cell()
  let l:txt = ''
  if s:has(l:cell.id)
    let l:why = (empty(s:S.rquery) && has_key(s:S.why, l:cell.id)) ? '  ' . s:S.why[l:cell.id] : ''
    let l:txt = ' ▶ ' . s:S.data.nodes[l:cell.id].t . '  [' . s:kinds[l:cell.kind][1] . ']' . l:why
  endif
  setlocal modifiable
  call setline(s:S.info_line, s:fit(l:txt, winwidth(0)))
  setlocal nomodifiable nomodified
endfunction

" モードの行: ' モード: [全体:a] 索引:i   近いグループ:c[オン] 予測関連:r[オフ]'（今のモードを目立たせる位置も返す）
function! s:mode_bar(W) abort
  let l:lines = []
  let l:cur = ' モード:'
  let l:span = []
  for [l:k, l:m] in s:mode_keys
    let l:cell = s:mode_label[l:m] . ':' . l:k
    let l:on = l:m ==# s:S.mode
    if l:on
      let l:cell = '[' . l:cell . ']'
    endif
    let l:cur .= ' '
    if l:on
      let l:span = [len(l:lines) + 2, strlen(l:cur) + 1, strlen(l:cell)]
    endif
    let l:cur .= l:cell
  endfor
  let l:cur .= '  '
  for [l:k, l:st, l:name] in s:over_keys
    let l:cell = l:name . ':' . l:k . '[' . (get(s:S, l:st, 0) ? 'オン' : 'オフ') . ']'
    if strdisplaywidth(l:cur . ' ' . l:cell) > a:W && l:cur !~# '^ モード:$'
      call add(l:lines, l:cur)
      let l:cur = '        '
    endif
    let l:cur .= ' ' . l:cell
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

" ---- q: かかっているもの（ハイライト・絞り込み・検索結果・索引選び）を、新しいほうから 1 つずつやめる ----------
" 何もかかっていなければ曼荼羅を閉じる。Q は何がかかっていても閉じる

function! s:tick(name) abort
  let s:S.stamp = get(s:S, 'stamp', {})
  let s:S.tick = get(s:S, 'tick', 0) + 1
  let s:S.stamp[a:name] = s:S.tick
endfunction

let s:layer_label = {'find': 'ハイライト', 'query': '絞り込み', 'rquery': '検索結果', 'pick': '選ぶモード'}

function! s:newest() abort
  let l:act = []
  if !empty(get(s:S, 'find', '')) | call add(l:act, 'find') | endif
  if !empty(get(s:S, 'query', '')) | call add(l:act, 'query') | endif
  if !empty(get(s:S, 'rquery', '')) | call add(l:act, 'rquery') | endif
  if get(s:S, 'pick', 0) | call add(l:act, 'pick') | endif
  let l:best = ''
  let l:bt = -1
  for l:n in l:act
    let l:t = get(get(s:S, 'stamp', {}), l:n, 0)
    if l:t >= l:bt
      let l:best = l:n
      let l:bt = l:t
    endif
  endfor
  return l:best
endfunction

function! s:cancel_hint() abort
  let l:n = s:newest()
  return empty(l:n) ? '' : 'q で' . s:layer_label[l:n] . 'をやめる'
endfunction

function! s:end_pick() abort
  let s:S.pick = ''
  let s:S.origin_view = 0
  if has_key(s:S, 'saved_mode')
    let [s:S.mode, s:S.near_on] = remove(s:S, 'saved_mode')
  endif
endfunction

function! s:quit() abort
  let l:n = s:newest()
  if empty(l:n)
    call gnosis#mview#close()
    return
  endif
  if l:n ==# 'find'
    let s:S.find = ''
  elseif l:n ==# 'query'
    let s:S.query = ''
    let s:S.page = 0
    let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  elseif l:n ==# 'rquery'
    let s:S.rquery = ''
    let s:S.results = []
    let s:S.page = 0
    let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  elseif l:n ==# 'pick'
    call s:end_pick()
    call s:render()
    call s:show_note(s:S.center)
    return
  endif
  call s:render()
endfunction

" ---- Tab / Shift-Tab: 順次表示。1 2 3 4 6 7 8 9（5 の中心は飛ばす）、次の曼荼羅の 1 へ、最後まで行ったら最初に戻る ----------
function! s:seq(dir) abort
  let l:total = len(s:items(s:S.center))
  if l:total == 0
    return
  endif
  let l:o = s:S.size == 3 ? 0 : 3
  let l:here = -1
  for l:i in range(8)
    if s:S.cur == [l:o + s:pos[l:i][0], l:o + s:pos[l:i][1]]
      let l:here = s:S.page * 8 + l:i
    endif
  endfor
  let l:next = l:here < 0 ? (a:dir > 0 ? 0 : l:total - 1) : (l:here + a:dir + l:total) % l:total
  let s:S.page = l:next / 8
  let l:p = s:pos[l:next % 8]
  let s:S.cur = [l:o + l:p[0], l:o + l:p[1]]
  call s:render()
  call s:preview()
endfunction

" ---- ? : 案内のポップアップ（画面の中央。q で閉じる） ----------------------------------------------
function! s:help_lines() abort
  let l:t = [
        \ '曼荼羅ビュー',
        \ '',
        \ ' 動く      h j k l / 矢印    1-9 そのマスへ(5 が中心)   t 数字の動き切替   z 中央に',
        \ ' 中心にする Enter    gs 全文検索で選んだノートを中心に    b / BS 一つ前   [ ] 前後の曼荼羅',
        \ ' 順に見る   Tab / S-Tab  1 2 3 4 6 7 8 9 → 次の曼荼羅の 1 …(最後は最初へ)',
        \ ' モード     a 全体   i グループ・索引だけ',
        \ ' 重ねる     c 近いグループ   r 予測関連   (オン/オフ。どのモードでも)',
        \ ' 探す       s 検索(結果が周りに並ぶ)   x 文字で絞り込む   m ハイライト → n / N で次・前',
        \ ' 索引に入れる  e これにする(選んでいる最中)   o 入れるノートを見る/戻る',
        \ ' 並べる     w 近さ順(中心に近いものを先に)   d 9×9の外側の基準(中心 / 自分)   { } 外側のページ   # 数字の表示/非表示',
        \ ' 画面       f 全画面(9×9)⇔分割   p 全画面の右に本文   < > 画面の幅   ( ) 盤面の幅   = 半々・正方形に戻す   u 読み直し   Space ノートへ',
        \ ' やめる     q かかっているものを 1 つやめる(何もなければ閉じる)   Q 全部閉じる',
        \ '',
        \ ' 色         ']
  return l:t
endfunction

function! s:help_filter(id, key) abort
  if a:key ==# 'q' || a:key ==# "\<Esc>" || a:key ==# '?'
    call popup_close(a:id)
    unlet! s:S.popup
    return 1
  endif
  return 1
endfunction

function! s:toggle_help() abort
  if exists('s:S.popup') && !empty(popup_getpos(s:S.popup))
    call popup_close(s:S.popup)
    unlet! s:S.popup
    return
  endif
  let l:lines = s:help_lines()
  " 色の凡例（色つき）を最後の行に
  let l:str = l:lines[-1]
  let l:props = []
  for l:k in s:kind_legend
    let l:cell = s:kinds[l:k][1]
    if !empty(s:kinds[l:k][2])
      call s:ensure_prop(l:k)
      call add(l:props, {'col': strlen(l:str) + 1, 'length': strlen(l:cell), 'type': 'gnosis_mv_' . l:k})
    endif
    let l:str .= l:cell . '  '
  endfor
  let l:lines[-1] = l:str
  let l:items = map(copy(l:lines[0 : -2]), '{"text": v:val}') + [{'text': l:str, 'props': l:props}]
  let s:S.popup = popup_create(l:items, {'title': ' ガイド（q で閉じる） ', 'pos': 'center', 'border': [], 'padding': [1, 2, 1, 2],
        \ 'zindex': 300, 'mapping': 0, 'filter': function('s:help_filter'), 'wrap': 0,
        \ 'maxheight': max([6, &lines - 4]), 'maxwidth': max([20, &columns - 4])})
endfunction

function! s:ensure_prop(kind) abort
  if empty(prop_type_get('gnosis_mv_' . a:kind))
    call prop_type_add('gnosis_mv_' . a:kind, {'highlight': s:kinds[a:kind][2]})
  endif
endfunction

" 選ぶモードの案内（上の状態の行の頭）
function! s:pick_label() abort
  let l:p = get(s:S, 'pick', '')
  if l:p ==# 'link'
    return '入れるノートを選ぶ（e で決定・o 元のノート）: '
  elseif l:p ==# 'group'
    return 'グループを選ぶ（e 決定・I Index・t 見出し・o 元のノート）: '
  endif
  return ''
endfunction

" 上の状態の 1 行: 中心・何枚目・盤面の大きさ・モードと重ねるもの・かかっているもの（q でやめる）
function! s:status(ctitle, pages, ptop, extra) abort
  let l:ov = join(map(copy(s:over_keys), 'v:val[0] . ":" . (get(s:S, v:val[1], 0) ? "オン" : "オフ")'), ' ')
        \ . (get(s:S, 'rank_on', 0) ? ' w:' . (s:S.size == 9 ? (get(s:S, 'dbasis', 'center') ==# 'self' ? '近さ(外側は自分)' : '近さ(中心)') : '近さ') : '')
  let l:cancel = s:cancel_hint()
  return printf(' %s%s  %s%s  [%s] %s%s%s', s:pick_label(), a:ctitle,
        \ (a:pages > 1 && empty(a:ptop) && get(s:S, 'nums', 1)) ? (s:S.page + 1) . '/' . a:pages . '  ' : '', s:S.size == 3 ? '3×3' : '9×9',
        \ s:S.mode ==# 'all' ? 'a' : 'i', l:ov, empty(l:cancel) ? '' : '   ' . l:cancel, a:extra)
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
  " 上に状態の 1 行（中心・モード・重ねるもの・かかっているもの）、下にカーソルのマスの説明 1 行。案内は ? のポップアップ
  let l:foot = []
  let l:show_ref = 1
  let s:S.modespan = []
  let l:fixed = 2
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
  let l:ctitle = s:has(s:S.center) ? s:S.data.nodes[s:S.center].t : s:S.center
  let l:pages = s:pages(s:S.center)
  " ページ（1/2）は中央のマスの一番上に。マスが小さくて入らないときだけ見出しに出す
  let l:mid = l:n == 3 ? 1 : 4
  let l:ptop = (l:pages > 1 && l:ch >= 3 && get(s:S, 'nums', 1)) ? (s:S.page + 1) . '/' . l:pages : ''
  let l:extra = (empty(s:S.rquery) ? '' : '   検索: ' . s:S.rquery . '（' . len(s:S.results) . '件）')
        \ . (empty(s:S.query) ? '' : '   絞り込み: ' . s:S.query)
        \ . (empty(get(s:S, 'find', '')) ? '' : '   /' . s:S.find . (get(s:S, 'hit_n', 0) > 0 ? ' ' . s:S.hit_i . '/' . s:S.hit_n : ' (ヒットなし)'))
  call add(l:lines, s:fit(s:status(l:ctitle, l:pages, l:ptop, l:extra), l:W))
  let s:S.legend_spans = []
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
      if l:cell.n > 0 && !empty(l:txt) && get(s:S, 'nums', 1)
        let l:txt = l:cell.n . ' ' . l:txt
      endif
      let l:tp = (l:r == l:mid && l:c == l:mid) ? l:ptop : ((get(s:S, 'nums', 1) && l:ch >= 3) ? get(l:cell, 'ptxt', '') : '')
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
  while len(l:lines) < l:H - 1
    call add(l:lines, '')
  endwhile
  call add(l:lines, '')
  let s:S.info_line = len(l:lines)
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
        let l:bi = get(l:cell, 'bgi', -1)
        if l:bi >= 0
          call s:addpos(empty(l:hg) ? 'GnosisMvCBg' . l:bi : l:hg . 'CB' . l:bi, l:sp, 10)
        else
          call s:addpos(empty(l:hg) ? 'GnosisMviewCenter' : l:hg . 'C', l:sp, 10)
        endif
      elseif get(l:cell, 'dup', 0)
        " 中心と同じノートが外側にも出ている: 種類の色を背景にして目立たせる（その種類＝中心との関係も分かる）
        call s:addpos(s:kinds[get(l:cell, 'kind', 'note')][2] . 'D', l:sp, 9)
      elseif get(l:cell, 'bgi', -1) >= 0
        let l:hg = s:kinds[get(l:cell, 'kind', 'note')][2]
        call s:addpos(empty(l:hg) ? 'GnosisMvBg' . l:cell.bgi : l:hg . 'B' . l:cell.bgi, l:sp, 8)
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
  if !has_key(s:S, 'tenths') && !has_key(s:S, 'stretch')
    return
  endif
  try
    call gnosis#home#write_json(gnosis#home#path('mandala.json'), {'tenths': get(s:S, 'tenths', 5), 'stretch': get(s:S, 'stretch', 1.0)})
  catch
  endtry
endfunction

function! s:toggle_digit() abort
  let s:S.digit = s:S.digit ==# 'jump' ? 'cursor' : 'jump'
  call s:render()
endfunction

function! s:set_center(id, page) abort
  let s:S.opage = 0
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
  if l:cell.id ==# s:S.center
    call s:show_note(l:cell.id)
    return
  endif
  let s:S.query = ''
  let s:S.rquery = ''
  call add(s:S.hist, [s:S.center, s:S.page])
  call s:set_center(l:cell.id, 0)
endfunction

" ---- gs : 全文検索（fzf）で選んだノートを中心にする ------------------------------------------
" ふつうの gs は今の窓にノートを開くので、曼荼羅の窓の中では壊してしまう。ここでは「中心にする」に差し替える
" （索引選び・q でやめるものなど、今のモードは途切れさせない）
function! s:gs() abort
  if !exists('*gnosis_search#search_global')
    return
  endif
  call gnosis_search#search_global(function('s:gs_done'))
endfunction

function! s:gs_done(path, line) abort
  call timer_start(0, function('s:gs_center', [a:path]))
endfunction

function! s:gs_center(path, timer) abort
  let l:mw = s:mwin()
  if l:mw < 0 || !has_key(s:S, 'root')
    return
  endif
  call win_gotoid(l:mw)
  let l:root = s:S.root
  if stridx(a:path, l:root . '/') != 0
    return
  endif
  let l:id = strpart(a:path, len(l:root) + 1)
  if !s:has(l:id)
    " 作ったばかりのノートかもしれない: 読み直してもう一度
    call s:pyc(['refresh', l:root, '--only', l:id])
    let s:S.missing = {}
    silent! call remove(s:S.data.nodes, l:id)
  endif
  if !s:has(l:id)
    echohl WarningMsg | echo 'Gnosis: 曼荼羅に載っていないノートです: ' . l:id | echohl NONE
    return
  endif
  if l:id !=# s:S.center
    let s:S.query = ''
    let s:S.rquery = ''
    let s:S.results = []
    call add(s:S.hist, [s:S.center, s:S.page])
    call s:set_center(l:id, 0)
  endif
endfunction

" ---- / : ふつうの検索のように、語をハイライトしてヒットしたマスへ飛ぶ ----------------------

function! s:title_of(id) abort
  return s:has(a:id) ? tolower(s:S.data.nodes[a:id].t) : ''
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
  echo 'ハイライト: ' . s:S.find . '  ' . s:S.hit_i . '/' . s:S.hit_n
endfunction

function! s:find_prompt() abort
  let s:S.find = trim(input('ハイライト: ', get(s:S, 'find', '')))
  call s:tick('find')
  let s:S.hit_n = 0
  let s:S.hit_i = 0
  if empty(s:S.find)
    call s:render()
  else
    call s:jump(1, 1)
  endif
endfunction

" x: 題で絞り込む（空にすると解除）。索引を選ぶとき（\l）は索引を全部から、ふだんは今の周りの中から
function! s:filter() abort
  let l:q = input(get(s:S, 'pick', '') ==# 'group' ? '索引を絞り込む（空で解除）: ' : '今の周りを絞り込む（空で解除）: ', s:S.query)
  let s:S.query = trim(l:q)
  call s:tick('query')
  let s:S.page = 0
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  call s:render()
endfunction

" e: 選んでいる最中に、中心に決める。link は「入れるノート」（続けて置き場所を聞く）、group は「入れ先のグループ」
function! s:decide_here() abort
  let l:p = get(s:S, 'pick', '')
  if empty(l:p)
    return
  endif
  if !empty(s:S.query) || !empty(s:S.rquery)
    echohl WarningMsg | echo 'Gnosis: 絞り込み・検索をやめてから決めてください（q）' | echohl NONE
    return
  endif
  if l:p ==# 'link'
    call s:link_decide()
    return
  endif
  if !s:nd(s:S.center).g
    echohl WarningMsg | echo 'Gnosis: 索引（グループ）ではありません' | echohl NONE
    return
  endif
  call s:decide(s:S.center)
endfunction

" 右の窓（ノートの窓）に移る。全画面（9×9）のときは分割に戻してから
function! s:goto_note_win() abort
  if s:S.size != 3
    call s:full()
  endif
  call s:ensure_note_win()
  let l:nw = s:note_win()
  if l:nw > 0
    call win_execute(l:nw, 'if &modified && &buftype ==# "" | silent! update | endif')
    call win_gotoid(l:nw)
  endif
  return l:nw
endfunction

" 選ぶモードが終わったあと、曼荼羅の窓に戻って、変わったノートだけ読み直す
function! s:back_to_mandala(rels) abort
  let l:mw = s:mwin()
  if l:mw > 0
    call win_gotoid(l:mw)
  endif
  for l:r in a:rels
    if !empty(l:r) && index(get(s:S, 'dirty', []), l:r) < 0
      let s:S.dirty = get(s:S, 'dirty', []) + [l:r]
    endif
  endfor
  call s:reload_dirty()
  call s:show_note(s:S.center)
endfunction

function! s:rel_of_root(abs) abort
  let l:r = s:root()
  return stridx(a:abs, l:r . '/') == 0 ? strpart(a:abs, len(l:r) + 1) : ''
endfunction

function! s:rel_of(abs) abort
  return stridx(a:abs, s:S.root . '/') == 0 ? strpart(a:abs, len(s:S.root) + 1) : ''
endfunction

" 元のノート（\l を押したノート）を右の窓に出す
function! s:show_origin() abort
  let l:o = get(s:S, 'origin', {})
  if empty(l:o) || !filereadable(l:o.path)
    return
  endif
  let l:nw = s:note_win()
  if l:nw < 0
    return
  endif
  call win_execute(l:nw, 'if &modified && &buftype ==# "" | silent! update | endif')
  call win_execute(l:nw, 'silent! hide edit ' . fnameescape(l:o.path))
  call win_execute(l:nw, 'keepjumps normal! ggL')
endfunction

" o: 入れるノート（\l を押したときのノート）を右に見る。もう一度で中心のノートに戻る
function! s:toggle_origin() abort
  if empty(get(s:S, 'pick', ''))
    return
  endif
  if get(s:S, 'origin_view', 0)
    call s:show_note(s:S.center)
    return
  endif
  call s:show_origin()
  let s:S.origin_view = 1
endfunction

" \l: e で、中心のノートを入れるノートに決める。続けて置き場所のキーを聞く（元のノートの窓で）
function! s:link_decide() abort
  let l:o = get(s:S, 'origin', {})
  let l:path = s:S.root . '/' . s:S.center
  if empty(l:o) || !filereadable(l:path)
    return
  endif
  let l:title = s:nd(s:S.center).t
  call s:end_pick()
  if s:goto_note_win() < 0
    return
  endif
  execute 'silent! hide edit ' . fnameescape(l:o.path)
  call setpos('.', l:o.pos)
  let l:link = gnosis#make_link(l:path, l:title)
  call gnosis#insert_links_pick([l:link], l:o.pos)
  " g が選ぶモードを始めていれば、そのまま続ける
  if empty(get(s:S, 'pick', ''))
    call s:back_to_mandala([s:rel_of(l:o.path)])
  else
    call win_gotoid(s:mwin())
  endif
endfunction

" 中心のグループに決める: 曼荼羅は閉じず、選ぶモードだけ終わる。a:1 は見出しのスラッグ（アウトラインを索引にする）
function! s:decide(id, ...) abort
  let l:slug = a:0 ? a:1 : ''
  let l:src = s:S.src
  let l:group = s:S.root . '/' . a:id
  let l:o = get(s:S, 'origin', {})
  call s:end_pick()
  if s:goto_note_win() < 0
    return
  endif
  call gnosis#index_add(l:src, l:group, l:slug)
  if !empty(l:o) && filereadable(l:o.path) && fnamemodify(expand('%:p'), ':p') !=# fnamemodify(l:o.path, ':p')
    execute 'silent! hide edit ' . fnameescape(l:o.path)
    call setpos('.', l:o.pos)
  endif
  call s:back_to_mandala([a:id, s:rel_of(l:src)])
endfunction

" I: 選んでいるノートを Index に追加する（そのトピックの入り口にする）
function! s:decide_index() abort
  if get(s:S, 'pick', '') !=# 'group'
    return
  endif
  if !s:has('index.md')
    echohl WarningMsg | echo 'Gnosis: index.md がありません' | echohl NONE
    return
  endif
  call s:decide('index.md')
endfunction

" t（グループを選ぶ最中）: 入れるノートの見出しを選んで、その見出しへ飛ぶリンクで中心のグループに入れる（表示名はそのまま）
function! s:t_key() abort
  if get(s:S, 'pick', '') !=# 'group'
    call s:toggle_digit()
    return
  endif
  if !s:nd(s:S.center).g
    echohl WarningMsg | echo 'Gnosis: 索引（グループ）ではありません' | echohl NONE
    return
  endif
  call gnosis#pick_heading(s:S.src, function('s:heading_chosen', [s:S.center]))
endfunction

function! s:heading_chosen(group_id, slug) abort
  if get(s:S, 'pick', '') !=# 'group' || s:S.center !=# a:group_id
    return
  endif
  call s:decide(a:group_id, a:slug)
endfunction

function! s:back() abort
  if empty(s:S.hist)
    return
  endif
  let [l:id, l:pg] = remove(s:S.hist, -1)
  while !s:has(l:id) && !empty(s:S.hist)
    let [l:id, l:pg] = remove(s:S.hist, -1)
  endwhile
  if !s:has(l:id)
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

" 重ねる（c 近いグループ / r 予測関連）のオン/オフ。どのモードでも効く
function! s:toggle_over(st) abort
  let s:S[a:st] = !get(s:S, a:st, 0)
  let s:S.find = ''
  let s:S.page = 0
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  call s:render()
endfunction

" モード（英字）: a 全体 / i 索引だけ
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
    call s:tick('rquery')
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
    if !get(s:S, 'pv', 0)
      silent! only
    endif
  else
    let s:S.size = 3
    call s:ensure_note_win()
  endif
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  call s:render()
  " 全画面で閉じた右のノートを、分割に戻したときに出し直す（中心のノート）。p が入っていれば、右の窓をそのまま使う
  if s:S.size == 3 || get(s:S, 'pv', 0)
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
  " < > : 画面の幅（曼荼羅の窓と右のノートの窓の境目）。3×3 も、右の窓があるときの 9×9 も
  if s:note_win() < 0
    echo 'Gnosis: 右の窓が無いので画面の幅は動かせません（9×9 では p で右の窓を出す）'
    return
  endif
  " 割合は 10 分率の整数で持つ（5 = 半々）。小数と整数を混ぜると Vim はエラーにする
  let s:S.tenths = min([8, max([2, get(s:S, 'tenths', 5) + a:d])])
  execute 'vertical resize ' . s:win_width()
  call s:render()
  call s:save_state()
endfunction

" ( ) : 曼荼羅の盤面そのものの幅（横に伸ばす・縮める）。3×3 も 9×9 も
function! s:stretch(d) abort
  " （min() / max() は小数を整数にしてしまうので、使わない）
  let l:v = float2nr(round((get(s:S, 'stretch', 1.0) + a:d * 0.15) * 100)) / 100.0
  let s:S.stretch = l:v > 3.0 ? 3.0 : (l:v < 0.5 ? 0.5 : l:v)
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

" =: 盤面の伸ばしを正方形に戻し、画面の幅も半々に戻す（3×3 も 9×9 も）
function! s:equalize() abort
  " = : 盤面の伸ばしを戻して正方形に、画面の幅は半々に
  let s:S.stretch = 1.0
  let s:S.tenths = 5
  if s:note_win() > 0
    execute 'vertical resize ' . s:win_width()
  endif
  call s:render()
  call s:save_state()
endfunction

" p: 全画面（9×9）の右に、中心のノートの題と本文を出す / 消す（右の窓。Space で入って、ふつうに動かせる）
function! s:toggle_preview() abort
  if s:S.size == 3
    echo 'Gnosis: 3×3 では右のノートがいつも出ています（p は全画面 9×9 用）'
    return
  endif
  let s:S.pv = !get(s:S, 'pv', 0)
  if s:S.pv
    call s:ensure_note_win()
    call s:render()
    call s:show_note(s:S.center)
  else
    let l:nw = s:note_win()
    if l:nw > 0
      call win_execute(l:nw, 'if &modified && &buftype ==# "" | silent! update | endif')
    endif
    silent! only
    call s:render()
  endif
endfunction

" w: 近さ順（中心に近いものを先に）のオン/オフ。d: 9×9 の外側の並びの基準（中心に近い / そのブロックのノート自身に近い）
function! s:toggle_rank() abort
  let s:S.rank_on = !get(s:S, 'rank_on', 0)
  let s:S.page = 0
  let s:S.opage = 0
  let s:S.cur = s:S.size == 3 ? [1, 1] : [4, 4]
  call s:render()
endfunction

function! s:toggle_dbasis() abort
  if s:S.size != 9 || !get(s:S, 'rank_on', 0)
    echo 'Gnosis: d は 9×9 で近さ順（w）がオンのときの、外側の並びの切り替えです'
    return
  endif
  let s:S.dbasis = get(s:S, 'dbasis', 'center') ==# 'center' ? 'self' : 'center'
  let s:S.opage = 0
  call s:render()
endfunction

" { }: 外側のブロックのページを前後に（[ ] は中心の周り）
function! s:opage(d) abort
  if s:S.size != 9
    return
  endif
  let l:max = 0
  for l:e in s:ring(s:S.center, s:S.page)
    if !empty(l:e[0])
      let l:max = max([l:max, s:pages(l:e[0]) - 1])
    endif
  endfor
  let l:p = get(s:S, 'opage', 0) + a:d
  if l:p < 0 || l:p > l:max
    return
  endif
  let s:S.opage = l:p
  call s:render()
endfunction

" #: 数字（マスの番号・ページの n/m）を出す / 隠す
function! s:toggle_nums() abort
  let s:S.nums = !get(s:S, 'nums', 1)
  call s:render()
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
  " 右のノートでは、YAML と上下の「名前:」系を、\zz の設定に関わらず隠す
  let w:gnosis_hide_force = 1
  " 窓を分けると曼荼羅の色づけ（matchaddpos）も新しい窓に写るので、ノートの窓には残さない
  call clearmatches(l:nw)
  unlet! w:mview_match
  call win_gotoid(l:mw)
  execute 'vertical resize ' . s:win_width()
  return l:nw
endfunction

function! s:show_note(id) abort
  let s:S.origin_view = 0
  let l:path = s:S.root . '/' . a:id
  if !filereadable(l:path)
    return
  endif
  if s:S.size != 3 && !get(s:S, 'pv', 0)
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
  " 上から表示して、カーソルは画面のいちばん下の行に置く
  call win_execute(l:nw, 'keepjumps normal! ggL')
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
  nnoremap <buffer><nowait><silent> { <Cmd>call <SID>opage(-1)<CR>
  nnoremap <buffer><nowait><silent> } <Cmd>call <SID>opage(1)<CR>
  nnoremap <buffer><nowait><silent> = <Cmd>call <SID>equalize()<CR>
  nnoremap <buffer><nowait><silent> ( <Cmd>call <SID>stretch(-1)<CR>
  nnoremap <buffer><nowait><silent> ) <Cmd>call <SID>stretch(1)<CR>
  nnoremap <buffer><nowait><silent> p <Cmd>call <SID>toggle_preview()<CR>
  nnoremap <buffer><nowait><silent> w <Cmd>call <SID>toggle_rank()<CR>
  nnoremap <buffer><nowait><silent> d <Cmd>call <SID>toggle_dbasis()<CR>
  nnoremap <buffer><nowait><silent> # <Cmd>call <SID>toggle_nums()<CR>
  nnoremap <buffer><nowait><silent> ] <Cmd>call <SID>page(1)<CR>
  nnoremap <buffer><nowait><silent> [ <Cmd>call <SID>page(-1)<CR>
  nnoremap <buffer><nowait><silent> b <Cmd>call <SID>back()<CR>
  nnoremap <buffer><nowait><silent> <BS> <Cmd>call <SID>back()<CR>
  nnoremap <buffer><nowait><silent> a <Cmd>call <SID>setmode('all')<CR>
  nnoremap <buffer><nowait><silent> i <Cmd>call <SID>setmode('groups')<CR>
  nnoremap <buffer><nowait><silent> c <Cmd>call <SID>toggle_over('near_on')<CR>
  nnoremap <buffer><nowait><silent> r <Cmd>call <SID>toggle_over('rel_on')<CR>
  nnoremap <buffer><nowait><silent> s <Cmd>call <SID>search()<CR>
  nnoremap <buffer><nowait><silent> gs <Cmd>call <SID>gs()<CR>
  nnoremap <buffer><nowait><silent> m <Cmd>call <SID>find_prompt()<CR>
  nnoremap <buffer><nowait><silent> n <Cmd>call <SID>jump(1)<CR>
  nnoremap <buffer><nowait><silent> N <Cmd>call <SID>jump(-1)<CR>
  nnoremap <buffer><nowait><silent> x <Cmd>call <SID>filter()<CR>
  nnoremap <buffer><nowait><silent> e <Cmd>call <SID>decide_here()<CR>
  nnoremap <buffer><nowait><silent> t <Cmd>call <SID>t_key()<CR>
  nnoremap <buffer><nowait><silent> I <Cmd>call <SID>decide_index()<CR>
  nnoremap <buffer><nowait><silent> o <Cmd>call <SID>toggle_origin()<CR>
  nnoremap <buffer><nowait><silent> ? <Cmd>call <SID>toggle_help()<CR>
  nnoremap <buffer><nowait><silent> <Tab> <Cmd>call <SID>seq(1)<CR>
  nnoremap <buffer><nowait><silent> <S-Tab> <Cmd>call <SID>seq(-1)<CR>
  nnoremap <buffer><nowait><silent> f <Cmd>call <SID>full()<CR>
  nnoremap <buffer><nowait><silent> z <Cmd>call <SID>recenter()<CR>
  nnoremap <buffer><nowait><silent> <lt> <Cmd>call <SID>resize(-1)<CR>
  nnoremap <buffer><nowait><silent> > <Cmd>call <SID>resize(1)<CR>
  nnoremap <buffer><nowait><silent> u <Cmd>call <SID>reload(1)<CR>
  nnoremap <buffer><nowait><silent> q <Cmd>call <SID>quit()<CR>
  nnoremap <buffer><nowait><silent> Q <Cmd>call gnosis#mview#close()<CR>
  nnoremap <buffer><nowait><silent> <Space> <Cmd>call gnosis#mview#toggle()<CR>
  augroup gnosis_mview_buf
    autocmd! * <buffer>
    autocmd VimResized,WinResized * call gnosis#mview#rerender()
    autocmd BufEnter,WinEnter <buffer> call gnosis#mview#cursor(0)
    autocmd BufLeave,WinLeave <buffer> call gnosis#mview#cursor(1)
    autocmd VimLeavePre <buffer> call gnosis#mview#cursor(1)
  augroup END
endfunction

" ノートを保存したら、曼荼羅が開いていなくても、キャッシュに「読み直すノート」として控える
" （次に曼荼羅を開くとき、vault 全体を走査せずに追いつく）
function! gnosis#mview#saved(path) abort
  let l:root = s:root()
  if empty(l:root) || stridx(a:path, l:root . '/') != 0 || !isdirectory(l:root . '/.gnosis/cache')
    return
  endif
  try
    call writefile([strpart(a:path, len(l:root) + 1)], l:root . '/.gnosis/cache/dirty', 'a')
  catch
  endtry
endfunction

" ノートを保存・読み込みしたら（題を zr で変えたときなど）、曼荼羅が開いていれば少し待って読み直す
function! s:touched(path) abort
  if empty(get(s:S, 'buf', 0)) || s:mwin() < 0 || &filetype ==# 'gnosis-mandala'
    return
  endif
  " 保存したノートだけをキャッシュで読み直す（vault 全体は走査しない）
  let l:root = get(s:S, 'root', '')
  if !empty(l:root) && stridx(a:path, l:root . '/') == 0
    let l:rel = strpart(a:path, len(l:root) + 1)
    if index(get(s:S, 'dirty', []), l:rel) < 0
      let s:S.dirty = get(s:S, 'dirty', []) + [l:rel]
    endif
  endif
  if exists('s:sync_timer')
    call timer_stop(s:sync_timer)
  endif
  let s:sync_timer = timer_start(600, {-> gnosis#mview#refresh()})
endfunction

" ---- 曼荼羅の窓にほかのバッファが入ろうとしたら、右のノートの窓に開く -------------------------------------
" \i（Index を開く）など、今の窓にノートを開く操作はたくさんある。曼荼羅の窓が選ばれたまま実行されても、
" 曼荼羅の窓を壊さず、開いたノートは右の窓に出す（曼荼羅の中心もそのノートに合わせる）
function! s:guard() abort
  if empty(get(s:S, 'buf', 0)) || &filetype ==# 'gnosis-mandala' || &buftype !=# ''
    return
  endif
  if win_getid() != get(s:S, 'win', -1)
    return
  endif
  call timer_start(0, function('s:guard_move', [bufnr('%')]))
endfunction

function! s:guard_move(buf, timer) abort
  let l:mw = get(s:S, 'win', -1)
  if l:mw < 0 || empty(getwininfo(l:mw)) || winbufnr(l:mw) != a:buf
    return
  endif
  let l:path = fnamemodify(bufname(a:buf), ':p')
  call win_execute(l:mw, 'silent! buffer ' . s:S.buf)
  if s:S.size != 3
    call s:full()
  endif
  call s:ensure_note_win()
  let l:nw = s:note_win()
  if l:nw < 0
    return
  endif
  call win_gotoid(l:nw)
  execute 'silent! buffer ' . a:buf
  " 曼荼羅の中心も、開いたノートに合わせる（選ぶモードの最中は動かさない）
  let l:rel = s:rel_of(l:path)
  if !empty(l:rel) && empty(get(s:S, 'pick', '')) && l:rel !=# s:S.center && s:has(l:rel)
    call add(s:S.hist, [s:S.center, s:S.page])
    let s:S.center = l:rel
    let s:S.page = 0
    let s:S.cur = [1, 1]
    call win_execute(l:mw, 'call gnosis#mview#render_here()')
  endif
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
  call s:reload_dirty()
  noautocmd call win_gotoid(l:back)
endfunction

" 保存されたノートだけ読み直して描き直す
function! s:reload_dirty() abort
  let l:rels = get(s:S, 'dirty', [])
  let s:S.dirty = []
  if empty(l:rels)
    " 控えが無いまま呼ばれたとき（外から書き換えたなど）は、vault を走査して変わったものを読み直す
    call s:reload(1)
    return
  endif
  call s:pyc(['refresh', s:S.root, '--only'] + l:rels)
  let s:S.data = {'nodes': {}}
  let s:S.missing = {}
  let s:S.nearc = {}
  let s:S.relc = {}
  if !s:has(s:S.center)
    let s:S.center = 'index.md'
  endif
  call s:render()
endfunction

function! s:reload(...) abort
  let s:S.nearc = {}
  let s:S.relc = {}
  if s:load(a:0 ? a:1 : 0)
    if !s:has(s:S.center)
      let s:S.center = 'index.md'
    endif
    call s:render()
  endif
endfunction

function! s:hl() abort
  " 種類の色（gui の色, 256 色の番号）。中心のマスは同じ色を太字にした C つき
  " 種類ごとに、はっきり違う色（索引=ピンク・グループ=黄・親=青・文脈=紫・引用=橙・バックリンク=灰白・子=青緑・関連=緑・予測関連=ベージュ・ノート=灰）
  let l:cols = {'Index': ['#ff6b81', 204], 'Group': ['#f2d13d', 220], 'Parent': ['#61afef', 75], 'Child': ['#2ec4b6', 43],
        \ 'Context': ['#c678dd', 176], 'Cite': ['#ff9e4a', 215], 'Back': ['#d8dee9', 253], 'Related': ['#8fd14f', 113],
        \ 'Pred': ['#d2b48c', 180], 'Note': ['#9aa0aa', 247]}
  for [l:k, l:c] in items(l:cols)
    execute printf('highlight default GnosisMv%s guifg=%s ctermfg=%d', l:k, l:c[0], l:c[1])
    " 中心のマスは太字だけ（下線はマスの全部の行に引かれて、しましまになる）
    execute printf('highlight default GnosisMv%sC guifg=%s ctermfg=%d gui=bold cterm=bold', l:k, l:c[0], l:c[1])
    execute printf('highlight default GnosisMv%sS guifg=%s ctermfg=%d guibg=#3a3f4b ctermbg=238 gui=bold cterm=bold', l:k, l:c[0], l:c[1])
    " 中心と同じノート（外側）: 種類の色を背景に、文字は暗く
    execute printf('highlight default GnosisMv%sD guifg=#1a1a1a ctermfg=234 guibg=%s ctermbg=%d gui=bold cterm=bold', l:k, l:c[0], l:c[1])
  endfor
  " 9×9 の背景: 真ん中の周りの 8 マスと、それぞれの曼荼羅の中心のマスを、同じ薄い色で塗る（8 色）。種類の色（文字）はそのまま
  let l:bgs = [['#2d3b52', 24], ['#43304f', 53], ['#2f4a3a', 22], ['#4f3f2b', 94], ['#4f2f36', 52], ['#2b4a4d', 23], ['#4a4a2b', 58], ['#3d3d4a', 60]]
  for l:i in range(8)
    let [l:gb, l:cb] = l:bgs[l:i]
    execute printf('highlight default GnosisMvBg%d guibg=%s ctermbg=%d', l:i, l:gb, l:cb)
    execute printf('highlight default GnosisMvCBg%d guibg=%s ctermbg=%d gui=bold cterm=bold', l:i, l:gb, l:cb)
    for [l:k, l:c] in items(l:cols)
      execute printf('highlight default GnosisMv%sB%d guifg=%s ctermfg=%d guibg=%s ctermbg=%d', l:k, l:i, l:c[0], l:c[1], l:gb, l:cb)
      execute printf('highlight default GnosisMv%sCB%d guifg=%s ctermfg=%d guibg=%s ctermbg=%d gui=bold cterm=bold', l:k, l:i, l:c[0], l:c[1], l:gb, l:cb)
    endfor
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
    autocmd BufWritePost,FileChangedShellPost *.md call s:touched(expand('<afile>:p'))
    autocmd VimLeavePre * call s:save_state()
    " 配色が読み込み直されると（ノートを開き直したときなど）色の定義が全部消えるので、定義し直す
    autocmd ColorScheme * call s:hl()
    autocmd BufWinEnter * call s:guard()
  augroup END
  let l:pick = a:0 ? a:1 : ''
  " 閉じたときに戻るノート（全画面で閉じると窓が 1 つだけになるため）
  if filereadable(expand('%:p'))
    let s:S.note = expand('%:p')
  endif
  let s:S.digit = get(s:S, 'digit', 'jump')
  let s:S.pick = empty(l:pick) ? '' : 'group'
  call s:tick('pick')
  let s:S.src = l:pick
  let s:S.origin_view = 0
  let s:S.query = ''
  let s:S.rquery = ''
  let s:S.results = []
  let s:S.find = ''
  let s:S.nearc = {}
  let s:S.relc = {}
  let s:S.why = {}
  let s:S.pred = {}
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
    let s:S.saved_mode = [l:mode, get(s:S, 'near_on', 0)]
    let s:S.near_on = 1
  endif
  let s:S.mode = empty(l:pick) ? l:mode : 'groups'
  let s:S.size = 3
  let s:S.hist = l:hist
  let s:S.page = 0
  let l:c = a:center
  " 曼荼羅の幅は前回のまま（< > で変えた幅）。中心は今のノート
  if !has_key(s:S, 'tenths') && get(g:, 'gnosis_mview_restore', 1)
    let l:all = s:state_all()
    let l:t = get(l:all, 'tenths', 0)
    if type(l:t) == v:t_number && l:t >= 2 && l:t <= 8
      let s:S.tenths = l:t
    endif
    let l:sv = get(l:all, 'stretch', 0)
    if (type(l:sv) == v:t_float || type(l:sv) == v:t_number) && l:sv >= 0.5 && l:sv <= 3.0 && !has_key(s:S, 'stretch')
      let s:S.stretch = l:sv + 0.0
    endif
  endif
  if !s:has(l:c)
    let l:c = s:has('index.md') ? 'index.md' : ''
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
  let s:S.win = win_getid()
  call s:render()
  call s:show_note(l:c)
  call win_gotoid(s:mwin())
  " 窓の出入りで戻ってしまうことがあるので、開いた最後にもう一度隠す
  call gnosis#mview#cursor(0)
endfunction

" <Space>: ノートから曼荼羅へ、曼荼羅からノートへ
function! gnosis#mview#toggle() abort
  if &filetype ==# 'gnosis-mandala'
    if s:S.size != 3 && !get(s:S, 'pv', 0)
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

" 起動したとき、曼荼羅ビューを左半分に出す（開いているのは Index）。設定 mandalaOnStart（既定オン）か
" g:gnosis_mandala_on_start で止められる
function! gnosis#mview#start() abort
  let l:on = get(g:, 'gnosis_mandala_on_start', -1)
  if l:on < 0
    try
      let l:on = get(gnosis#settings#current(), 'mandalaOnStart', v:true) ? 1 : 0
    catch
      let l:on = 1
    endtry
  endif
  if !l:on || empty(s:root()) || &filetype ==# 'gnosis-mandala' || s:mwin() > 0 || empty(expand('%:p'))
    return
  endif
  call gnosis#mview#toggle()
endfunction

" \l: 入れるノートを曼荼羅で選ぶ。曼荼羅が開いていればそこへ（開いていなければ開く）。e で決めると、置き場所のキーを聞く
function! gnosis#mview#link_pick() abort
  let l:file = expand('%:p')
  if empty(l:file) || &filetype ==# 'gnosis-mandala' || l:file !~? '\.md$'
    echohl WarningMsg | echo 'Gnosis: リンクを入れるノートを開いて実行して' | echohl NONE
    return
  endif
  let l:root = s:root()
  let l:rel = stridx(l:file, l:root . '/') == 0 ? strpart(l:file, len(l:root) + 1) : ''
  let l:origin = {'path': l:file, 'pos': getpos('.')}
  if s:mwin() < 0
    call s:open(l:rel)
  else
    call win_gotoid(s:mwin())
  endif
  if s:mwin() < 0
    return
  endif
  let s:S.origin = l:origin
  let s:S.pick = 'link'
  call s:tick('pick')
  call s:set_center(s:has(l:rel) ? l:rel : s:S.center, 0)
endfunction

" g（置き場所のキー）: 入れるノート（links の先頭）を入れるグループを、曼荼羅で選ぶ
function! gnosis#mview#group_pick(links) abort
  if empty(a:links) || empty(s:root())
    return 0
  endif
  let l:t = substitute(matchstr(a:links[0], '](\zs[^)]*\ze)'), '#.*$', '', '')
  let l:src = fnamemodify(gnosis#resolve_link(l:t), ':p')
  if empty(l:t) || !filereadable(l:src)
    return 0
  endif
  " 呼ばれたときのノート（置き場所を聞いている最中のノート）が、入れ終わったあとに戻る先
  let l:origin = {'path': expand('%:p'), 'pos': getpos('.')}
  if s:mwin() < 0
    call s:open(s:rel_of_root(l:src))
  endif
  if s:mwin() < 0
    return 0
  endif
  let s:S.origin = l:origin
  call win_gotoid(s:mwin())
  if !has_key(s:S, 'saved_mode')
    let s:S.saved_mode = [s:S.mode, get(s:S, 'near_on', 0)]
  endif
  let s:S.near_on = 1
  let s:S.mode = 'groups'
  let s:S.pick = 'group'
  let s:S.src = l:src
  call s:tick('pick')
  let l:rel = s:rel_of(l:src)
  call s:set_center(s:has(l:rel) ? l:rel : s:S.center, 0)
  return 1
endfunction

function! gnosis#mview#close() abort
  call s:save_state()
  if has_key(s:S, 'saved_mode')
    let [s:S.mode, s:S.near_on] = remove(s:S, 'saved_mode')
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

" ---- アプリ（\c）の曼荼羅: 盤面の状態を渡す・クリックを受ける ----------------------------------------------
" アプリは曼荼羅を自分で描く（Vim の窓のバッファは罫線の文字なので、マークダウンとしては描けない）。
" 操作は Vim の曼荼羅のキーがそのまま効く（アプリは見た目だけ）。マウスのクリックは gui_click で受ける。
function! gnosis#mview#gui_state() abort
  if !exists('s:S') || !has_key(s:S, 'cells') || get(s:S, 'win', -1) < 0 || empty(getwininfo(get(s:S, 'win', -1)))
    return {}
  endif
  if winbufnr(s:S.win) != get(s:S, 'buf', -1)
    return {}
  endif
  let l:cells = []
  for l:row in s:S.cells
    let l:r = []
    for l:c in l:row
      call add(l:r, {'t': s:label(l:c), 'k': get(l:c, 'kind', 'note'), 'n': get(l:c, 'n', 0), 'role': get(l:c, 'role', 'empty'),
            \ 'bgi': get(l:c, 'bgi', -1), 'dup': get(l:c, 'dup', 0), 'pt': get(l:c, 'ptxt', '')})
    endfor
    call add(l:cells, l:r)
  endfor
  let l:cur = s:cur_cell()
  return {'size': s:S.size, 'cur': s:S.cur, 'cells': l:cells, 'nums': get(s:S, 'nums', 1),
        \ 'center': s:S.center, 'title': s:has(s:S.center) ? s:S.data.nodes[s:S.center].t : s:S.center,
        \ 'page': s:S.page, 'pages': s:pages(s:S.center),
        \ 'status': trim(s:status(s:has(s:S.center) ? s:S.data.nodes[s:S.center].t : s:S.center, 1, '', '')),
        \ 'pickLabel': s:pick_label(), 'cancel': s:cancel_hint(),
        \ 'info': s:has(l:cur.id) ? (s:S.data.nodes[l:cur.id].t . '  [' . s:kinds[get(l:cur, 'kind', 'note')][1] . ']' . (has_key(s:S.why, l:cur.id) ? '  ' . s:S.why[l:cur.id] : '')) : '',
        \ 'flags': {'near': get(s:S, 'near_on', 0), 'rel': get(s:S, 'rel_on', 0), 'rank': get(s:S, 'rank_on', 0),
        \           'mode': s:S.mode, 'pv': get(s:S, 'pv', 0), 'dbasis': get(s:S, 'dbasis', 'center')},
        \ 'win': s:S.win, 'noteWin': s:note_win()}
endfunction

" アプリでマスをクリック: そのマスへカーソルを動かし、a:enter が 1 なら中心にする（Enter と同じ）
function! gnosis#mview#gui_click(r, c, enter) abort
  if !exists('s:S') || !has_key(s:S, 'cells') || a:r < 0 || a:r >= s:S.size || a:c < 0 || a:c >= s:S.size
    return
  endif
  call win_gotoid(s:S.win)
  let s:S.cur = [a:r, a:c]
  call s:mark()
  call s:preview()
  if a:enter
    call s:enter()
  endif
endfunction

" 試験用: gs で選んだあとの処理を直接呼ぶ
function! gnosis#mview#gs_done(path, line) abort
  call s:gs_done(a:path, a:line)
endfunction

" 試験用: 状態を返す
function! gnosis#mview#state() abort
  return s:S
endfunction
