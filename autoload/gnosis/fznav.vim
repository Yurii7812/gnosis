" Folgezettel ビュー（CUI）。曼荼羅と同じ窓・同じバッファに、Ctrl-←/→ で切り替えて出す（曼荼羅・Folgezettel・リストの3つを切り替える）。
"
" 番号と題を縦に並べるだけ。番号は左揃えの固定幅の欄、題は常に同じ桁から。Group はアクセントの色、Note は通常の色。
" 同じ番号に BranchGroup がある Note は、Group の行が上・Note の行が下（どちらも別の項目として選べる）。
" 番号・並び・親子の位置・上位表示の計算は python/fznav.py（アプリも同じ結果を使う）。ここは描画とキーだけ。
" ノートは書き換えない。
"
" キー（Folgezettel ビューの窓）
"   j k / ↓ ↑     次・前の項目（最後まで。画面に出ていない分も）   gg G  先頭・末尾
"   h / ← →       上位・下位の番号へ（実在する番号だけ。無ければその場に留まる）
"   Enter         Group / Note を開く（右のノートの窓に出し、ここは現在位置に合わせる）
"   s l r m       リスト（検索・リンク・類似）のモードへ。リストの中で f で戻る
"   za zc zo zM zR 折りたたみ（開閉・閉じる・開く・全部閉じる・全部開く）
"   u             上位表示（祖先の番号の Group と、関連 Group）⇔ 通常    M  関連 Group をもっと見る
"   \o            アウトライン窓の表示 ⇔ 非表示（どこでも）。o は選ぶモード（\l）で元のノートを右に見る
"   Ctrl-← Ctrl-→ gv  ビューを切り替える        Space  ノートの窓へ      q  閉じる      ?  この一覧
let s:here = expand('<sfile>:p:h:h:h')
let s:F = {'collapsed': {}, 'mode': 'normal', 'more': 0, 'dirty': 1, 'gen': 0, 'rows': [], 'pidx': {},
      \ 'lines': [], 'cells': [], 'items': [], 'sel': [], 'selpos': {}, 'last_cur': '', 'up': {}, 'upkey': '', 'key': ''}
let s:RELATED_SHOWN = 8

function! s:S() abort
  return gnosis#mview#state()
endfunction

function! s:numw() abort
  return max([4, get(g:, 'gnosis_fznav_numw', 8)])
endfunction

function! s:py(args) abort
  let l:cmd = join(map([gnosis#python_cmd(), s:here . '/python/fznav.py'] + a:args, 'shellescape(v:val)'), ' ') . ' 2>/dev/null'
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

" 曼荼羅のデータ（キャッシュ）が読み直されたとき
function! gnosis#fznav#invalidate() abort
  let s:F.dirty = 1
  let s:F.gen += 1
endfunction

" ---- データ -------------------------------------------------------------------------------------

function! s:load() abort
  if !s:F.dirty
    return
  endif
  let l:r = s:py(['rows', s:S().root, '--numw', s:numw()])
  let s:F.rows = type(l:r) == v:t_dict ? get(l:r, 'rows', []) : []
  let s:F.pidx = {}
  let l:i = 0
  for l:row in s:F.rows
    let s:F.pidx[l:row[1]] = l:i
    let l:i += 1
  endfor
  let s:F.dirty = 0
endfunction

" 今開いているノート（曼荼羅の中心。見出しのマスなら、そのノート）
function! s:cur_path() abort
  return matchstr(get(s:S(), 'center', ''), '^[^#]*')
endfunction

function! s:cur_row() abort
  return get(s:F.pidx, s:cur_path(), -1)
endfunction

" i 番目の行が見えるように、祖先の折りたたみを開く
function! s:reveal(i) abort
  let l:u = s:F.rows[a:i][5]
  while l:u >= 0
    silent! call remove(s:F.collapsed, s:F.rows[l:u][0])
    let l:u = s:F.rows[l:u][5]
  endwhile
endfunction

function! s:upper_data() abort
  let l:cp = s:cur_path()
  let l:key = l:cp . ':' . s:F.gen
  if s:F.upkey !=# l:key
    let l:r = empty(l:cp) ? v:null : s:py(['upper', s:S().root, l:cp, '--numw', s:numw(), '--max', 30])
    let s:F.up = type(l:r) == v:t_dict && get(l:r, 'ok', 0) ? l:r : {}
    let s:F.upkey = l:key
  endif
  return s:F.up
endfunction

" ---- 描画 ---------------------------------------------------------------------------------------

function! s:hl() abort
  " Group だけアクセントの色（曼荼羅の Group と同じ黄色。ライトは濃い茶）。Group ごとに色は変えない
  let l:dark = &background ==# 'dark'
  let l:fg = l:dark ? ['#f2d13d', 220] : ['#8a5a00', gnosis#theme#to_cterm('#8a5a00')]
  execute printf('highlight default GnosisFzGroup guifg=%s ctermfg=%d', l:fg[0], l:fg[1])
  highlight default link GnosisFzCursor Visual
  highlight default link GnosisFzHead Comment
  silent! call prop_type_add('gnosis_fz_group', {'highlight': 'GnosisFzGroup'})
  silent! call prop_type_add('gnosis_fz_head', {'highlight': 'GnosisFzHead'})
endfunction

" 配色が読み込み直されると色の定義が消える。定義し直す
augroup gnosis_fz_hl
  autocmd!
  autocmd ColorScheme * call s:hl()
augroup END

function! s:pad(s, w) abort
  return a:s . repeat(' ', max([0, a:w - strdisplaywidth(a:s)]))
endfunction

" 1 行: 現在位置の印（2 桁）+ 番号欄（固定幅）+ 2 桁の空き + 題。題は必ず同じ桁から始まる
function! s:line(mark, num, title, tail) abort
  return (a:mark ? '▸ ' : '  ') . s:pad(a:num, s:numw()) . '  ' . a:title . a:tail
endfunction

function! s:head_text() abort
  let l:head = s:F.mode ==# 'upper' ? 'FOLGEZETTEL / ' . gnosis#i18n#tr('上位表示') : 'FOLGEZETTEL'
  for l:k in ['search', 'filter', 'highlight']
    if !empty(get(s:F, l:k, '')) | let l:head .= ' / ' . {'search': 's', 'filter': 'x', 'highlight': 'm'}[l:k] . ': ' . s:F[l:k] | endif
  endfor
  let l:pick = gnosis#mview#pick_label()
  return empty(l:pick) ? l:head : l:head . '  ' . l:pick
endfunction

function! s:add(lines, cells, items, line, cell, item) abort
  call add(a:lines, a:line)
  call add(a:cells, a:cell)
  call add(a:items, a:item)
endfunction

" 見えている行（折りたたみの中は除く）のノートの vault 相対パス（上から順）
function! gnosis#fznav#shown_paths() abort
  call s:load()
  let l:out = []
  let l:i = 0
  let l:n = len(s:F.rows)
  while l:i < l:n
    let l:r = s:F.rows[l:i]
    call add(l:out, l:r[1])
    let l:i = (l:r[6] == l:i && has_key(s:F.collapsed, l:r[0]) && l:r[7] > l:i + 1) ? l:r[7] : l:i + 1
  endwhile
  return l:out
endfunction

function! s:build_normal() abort
  call s:load()
  let l:rows = s:F.rows
  let l:n = len(l:rows)
  let l:cur = s:cur_row()
  if l:cur >= 0 && get(s:F, 'last_path', '') !=# s:cur_path()
    call s:reveal(l:cur)    " 現在のノートが折りたたみの中なら開く（見失わない）
  endif
  let l:lines = []
  let l:cells = []
  let l:items = []
  call s:add(l:lines, l:cells, l:items, s:head_text(), {'k': 'h', 't': s:head_text()}, {'t': 'h'})
  call s:add(l:lines, l:cells, l:items, '', {'k': 'h', 't': ''}, {'t': 'h'})
  if l:n == 0
    let l:m = gnosis#i18n#tr('Folgezettel 番号を持つノートがありません')
    call s:add(l:lines, l:cells, l:items, '  ' . l:m, {'k': 'h', 't': l:m}, {'t': 'h'})
  endif
  let l:i = 0
  while l:i < l:n
    let l:r = l:rows[l:i]
    let l:mark = l:i == l:cur
    let l:tail = ''
    let l:next = l:i + 1
    " ブロックの最後の行で、その番号が折りたたまれていれば、子孫の行を飛ばす
    if l:r[6] == l:i && has_key(s:F.collapsed, l:r[0]) && l:r[7] > l:i + 1
      let l:tail = '  +' . (l:r[7] - l:i - 1)
      if l:cur > l:i && l:cur < l:r[7]
        let l:mark = 1
      endif
      let l:next = l:r[7]
    endif
    call s:add(l:lines, l:cells, l:items, s:line(l:mark, l:r[4], l:r[2], l:tail),
          \ {'k': l:r[3], 'n': l:r[4], 'id': l:r[0], 't': l:r[2], 'cur': l:mark, 'c': l:tail},
          \ {'t': 'r', 'i': l:i, 'path': l:r[1], 'k': l:r[3], 'id': l:r[0], 'title': l:r[2]})
    let l:i = l:next
  endwhile
  return [l:lines, l:cells, l:items]
endfunction

function! s:build_upper() abort
  let l:u = s:upper_data()
  let l:lines = []
  let l:cells = []
  let l:items = []
  call s:add(l:lines, l:cells, l:items, s:head_text(), {'k': 'h', 't': s:head_text()}, {'t': 'h'})
  call s:add(l:lines, l:cells, l:items, '', {'k': 'h', 't': ''}, {'t': 'h'})
  if empty(l:u)
    let l:m = gnosis#i18n#tr('このノートはまだ読み込まれていません')
    call s:add(l:lines, l:cells, l:items, '  ' . l:m, {'k': 'h', 't': l:m}, {'t': 'h'})
    return [l:lines, l:cells, l:items]
  endif
  for l:c in l:u.chain
    call s:add(l:lines, l:cells, l:items, s:line(0, l:c.num, l:c.title, ''), {'k': 'g', 'n': l:c.num, 'id': l:c.id, 't': l:c.title, 'cur': 0, 'c': ''},
          \ {'t': 'c', 'path': l:c.path, 'k': 'g', 'id': l:c.id, 'title': l:c.title})
  endfor
  let l:cu = l:u.cur
  call s:add(l:lines, l:cells, l:items, s:line(1, l:cu.num, l:cu.title, ''), {'k': l:cu.kind, 'n': l:cu.num, 'id': l:cu.id, 't': l:cu.title, 'cur': 1, 'c': ''},
        \ {'t': 'u', 'path': l:cu.path, 'k': l:cu.kind, 'id': l:cu.id, 'title': l:cu.title})
  call s:add(l:lines, l:cells, l:items, '', {'k': 's', 't': ''}, {'t': 'h'})
  let l:sep = repeat('─', 24)
  call s:add(l:lines, l:cells, l:items, l:sep, {'k': 's', 't': l:sep}, {'t': 'h'})
  let l:rh = gnosis#i18n#tr('関連グループ')
  call s:add(l:lines, l:cells, l:items, l:rh, {'k': 'h', 't': l:rh}, {'t': 'h'})
  call s:add(l:lines, l:cells, l:items, '', {'k': 's', 't': ''}, {'t': 'h'})
  let l:rel = l:u.related
  let l:show = s:F.more ? len(l:rel) : min([len(l:rel), s:RELATED_SHOWN])
  if empty(l:rel)
    let l:m = gnosis#i18n#tr('関連するグループは見つかりません')
    call s:add(l:lines, l:cells, l:items, '  ' . l:m, {'k': 'h', 't': l:m}, {'t': 'h'})
  endif
  for l:r in l:rel[0 : l:show - 1]
    call s:add(l:lines, l:cells, l:items, s:line(0, l:r.num, l:r.title, ''), {'k': 'g', 'n': l:r.num, 'id': l:r.id, 't': l:r.title, 'cur': 0, 'c': ''},
          \ {'t': 'g', 'path': l:r.path, 'k': 'g', 'id': l:r.id, 'title': l:r.title})
  endfor
  if len(l:rel) > l:show
    let l:m = printf(gnosis#i18n#tr('… ほか %d 件（M で全部）'), len(l:rel) - l:show)
    call s:add(l:lines, l:cells, l:items, '  ' . l:m, {'k': 'h', 't': l:m}, {'t': 'h'})
  elseif s:F.more && len(l:rel) > s:RELATED_SHOWN
    let l:m = gnosis#i18n#tr('（M で上位だけに戻す）')
    call s:add(l:lines, l:cells, l:items, '  ' . l:m, {'k': 'h', 't': l:m}, {'t': 'h'})
  endif
  return [l:lines, l:cells, l:items]
endfunction

function! s:item_key(item) abort
  return get(a:item, 'path', '') . '|' . get(a:item, 'k', '')
endfunction

function! s:cur_item() abort
  return get(s:F.items, line('.') - 1, {'t': 'h'})
endfunction

" 現在のノートの行（番号）。見つからなければ 0
function! s:current_lnum() abort
  let l:cp = s:cur_path()
  let l:best = 0
  let l:lnum = 0
  for l:it in s:F.items
    let l:lnum += 1
    if get(l:it, 'path', '') ==# l:cp && l:it.t !=# 'g' && l:it.t !=# 'c'
      return l:lnum
    endif
  endfor
  " 折りたたまれた枝の中なら、印を付けた行（折りたたんだ番号の行）
  let l:lnum = 0
  for l:c in s:F.cells
    let l:lnum += 1
    if get(l:c, 'cur', 0)
      return l:lnum
    endif
  endfor
  return l:best
endfunction

function! gnosis#fznav#render() abort
  call s:hl()
  let l:keep = s:item_key(s:cur_item())
  let [l:lines, l:cells, l:items] = s:F.mode ==# 'upper' ? s:build_upper() : s:build_normal()
  if !empty(get(s:F, 'search', '')) || !empty(get(s:F, 'filter', ''))
    let [l:qlines, l:qcells, l:qitems] = [[], [], []]
    for l:i in range(len(l:items))
      let l:it = l:items[l:i]
      if l:it.t ==# 'h' || ((empty(get(s:F, 'search', '')) || has_key(get(s:F, 'search_paths', {}), l:it.path))
            \ && (empty(get(s:F, 'filter', '')) || has_key(get(s:F, 'filter_paths', {}), l:it.path)))
        call add(l:qlines, l:lines[l:i]) | call add(l:qcells, l:cells[l:i]) | call add(l:qitems, l:it)
      endif
    endfor
    let [l:lines, l:cells, l:items] = [l:qlines, l:qcells, l:qitems]
    if empty(filter(copy(l:items), 'v:val.t !=# "h"'))
      call s:add(l:lines, l:cells, l:items, '  ' . gnosis#i18n#tr('該当なし'),
            \ {'k': 'h', 't': gnosis#i18n#tr('該当なし')}, {'t': 'h'})
    endif
  endif
  let s:F.cells = l:cells
  let s:F.items = l:items
  let s:F.sel = []
  let s:F.selpos = {}
  let l:i = 0
  for l:it in l:items
    let l:i += 1
    if l:it.t !=# 'h'
      let s:F.selpos[l:i] = len(s:F.sel)
      call add(s:F.sel, l:i)
    endif
  endfor
  " 全部消してから書き直すとちらつくので、変わった行だけ書き換える
  let l:lz = &lazyredraw
  set lazyredraw
  setlocal modifiable
  let l:old = s:F.lines
  if len(l:old) > len(l:lines)
    silent! execute (len(l:lines) + 1) . ',$delete _'
  endif
  let l:n = len(l:lines)
  let l:i = 0
  while l:i < l:n
    if l:i >= len(l:old) || l:old[l:i] !=# l:lines[l:i]
      call setline(l:i + 1, l:lines[l:i])
    endif
    let l:i += 1
  endwhile
  let s:F.lines = l:lines
  " 色: Group の行・見出しの行（プロパティ。変わった行だけでなく全部付け直す: 行の入れ替わりに強い）
  silent! call prop_clear(1, line('$'))
  let l:i = 0
  while l:i < l:n
    let l:c = l:cells[l:i]
    if l:c.k ==# 'g' || (l:c.k ==# 'n' && 0)
      call prop_add(l:i + 1, 1, {'length': max([1, strlen(l:lines[l:i])]), 'type': 'gnosis_fz_group'})
    elseif l:c.k ==# 'h' && l:i < 1
      call prop_add(l:i + 1, 1, {'length': max([1, strlen(l:lines[l:i])]), 'type': 'gnosis_fz_head'})
    endif
    let l:i += 1
  endwhile
  call gnosis#hint#put(s:hint_text())
  call gnosis#listnav#paint(get(s:F, 'highlight', ''), map(copy(l:items), 'get(v:val, "path", "")'), get(s:F, 'highlight_paths', {}))
  setlocal nomodifiable nomodified
  " カーソルと表示位置
  let l:focus = get(s:S(), 'focus', 1)
  let l:curl = s:current_lnum()
  let l:changed = s:F.last_cur !=# s:cur_path() . ':' . s:F.mode
  let l:want = 0
  if l:curl > 0 && (!l:focus || get(s:F, 'recenter', 0) || l:changed)
    let l:want = l:curl
  endif
  let s:F.recenter = 0
  if l:want == 0
    " 開いている間に行が入れ替わっても、今の項目に留まる
    let l:want = line('.')
    for l:j in range(len(l:items))
      if s:item_key(l:items[l:j]) ==# l:keep && l:items[l:j].t !=# 'h'
        let l:want = l:j + 1
        break
      endif
    endfor
  endif
  let l:want = s:snap(max([1, min([l:want, l:n])]))
  call cursor(l:want, 1)
  let s:F.lastpos = getpos('.')[1:2]
  if l:want == l:curl && l:curl > 0 && (!l:focus || l:changed)
    normal! zz
  elseif l:changed && l:curl == 0
    normal! zt
  endif
  let s:F.last_cur = s:cur_path() . ':' . s:F.mode
  let s:F.last_path = s:cur_path()
  let &lazyredraw = l:lz
  call gnosis#fznav#mark()
  call gnosis#mview#sync_leader()
  call s:sync_view()
endfunction

" 選べない行（見出し・空行）なら、いちばん近い選べる行へ
function! s:snap(lnum) abort
  if empty(s:F.sel) || has_key(s:F.selpos, a:lnum)
    return a:lnum
  endif
  for l:d in range(1, len(s:F.items))
    if has_key(s:F.selpos, a:lnum + l:d) | return a:lnum + l:d | endif
    if has_key(s:F.selpos, a:lnum - l:d) | return a:lnum - l:d | endif
  endfor
  return a:lnum
endfunction

" 選んでいる行のハイライト（窓にカーソルがあるときだけ。右のノートにカーソルがあるときは消す）と、番号の全体の表示
function! gnosis#fznav#mark() abort
  if !empty($GNOSIS_GUI_PORT)
    call s:detail()
    if exists('*GnosisGuiChanged') | call GnosisGuiChanged() | endif
    return
  endif
  if exists('w:mview_match')
    for l:m in w:mview_match
      silent! call matchdelete(l:m)
    endfor
  endif
  let w:mview_match = []
  if get(s:S(), 'focus', 1) && !empty(s:F.sel)
    call add(w:mview_match, matchaddpos('GnosisFzCursor', [line('.')], 10))
  endif
  call s:detail()
endfunction

" 選んでいる項目の、省かない番号と題（番号が ~ で省かれていても全体が分かる）
function! s:detail() abort
  if get(b:, 'gnosis_nav_input', 0) | return | endif
  if empty(s:F.items) || get(s:S(), 'view', 'mandala') !=# 'fz' || !get(s:S(), 'focus', 1) || get(s:S(), 'switching', 0)
    return
  endif
  let l:it = s:cur_item()
  if l:it.t ==# 'h'
    return
  endif
  " 窓に入り直しただけ（同じ項目のまま）なら出さない。曼荼羅の窓と同じく、何も出さずに切り替わる
  let l:key = l:it.path . '|' . l:it.id
  if get(s:F, 'shown', '') ==# l:key
    return
  endif
  let s:F.shown = l:key
  let l:kind = l:it.k ==# 'g' ? 'Group' : 'Note'
  let l:t = printf('%s  %s  %s  (%s)', empty(l:it.id) ? '-' : l:it.id, l:kind, l:it.title, l:it.path)
  let l:w = &columns - 12
  while strdisplaywidth(l:t) > l:w && !empty(l:t)
    let l:t = substitute(l:t, '.$', '', '')
  endwhile
  echo l:t
endfunction

" ---- 移動 ---------------------------------------------------------------------------------------

function! s:goto(lnum) abort
  call cursor(a:lnum, 1)
  call s:preview_later()
endfunction

" カーソルの項目を右の窓に出す（印・曼荼羅の中心は変えない）。続けて動かすときは、止まってから 1 回だけ
function! s:preview_later() abort
  if exists('s:ptimer')
    call timer_stop(s:ptimer)
  endif
  let s:ptimer = timer_start(80, {-> s:preview_now()})
endfunction

function! s:preview_now() abort
  unlet! s:ptimer
  if &filetype !=# 'gnosis-mandala' || get(s:S(), 'view', 'mandala') !=# 'fz' || empty(s:F.items)
    return
  endif
  let l:it = s:cur_item()
  if l:it.t ==# 'h' || empty(get(l:it, 'path', ''))
    return
  endif
  call gnosis#mview#preview_rel(l:it.path)
endfunction

" e / I: \l などの選ぶモードで、カーソルの項目に決める（e 入れるノート・グループに決定、I Index に載せる）
function! s:pick_decide(index) abort
  if !gnosis#mview#picking()
    return
  endif
  let l:it = s:cur_item()
  if l:it.t ==# 'h' || empty(get(l:it, 'path', ''))
    return
  endif
  call gnosis#mview#fz_decide(l:it.path, a:index)
endfunction

" c: 印のついたノート（今開いているもの）へカーソルを戻し、右の窓もそのノートに戻す
function! s:back() abort
  if exists('s:ptimer')
    call timer_stop(s:ptimer)
    unlet s:ptimer
  endif
  let l:l = s:current_lnum()
  if l:l > 0
    call cursor(l:l, 1)
  endif
  call gnosis#mview#preview_rel(s:cur_path())
endfunction

function! s:move(d) abort
  if empty(s:F.sel)
    return
  endif
  let l:p = get(s:F.selpos, line('.'), -1)
  if l:p < 0
    call s:goto(s:snap(line('.')))
    return
  endif
  let l:q = max([0, min([len(s:F.sel) - 1, l:p + a:d])])
  call s:goto(s:F.sel[l:q])
endfunction

" 先頭・末尾の項目へ
function! s:edge(last) abort
  if !empty(s:F.sel)
    call s:goto(a:last ? s:F.sel[-1] : s:F.sel[0])
  endif
endfunction

function! s:lnum_of_row(i) abort
  let l:lnum = 0
  for l:it in s:F.items
    let l:lnum += 1
    if l:it.t ==# 'r' && l:it.i == a:i
      return l:lnum
    endif
  endfor
  return 0
endfunction

" 行 a:i が見えるようにして（折りたたみは開く）、そこへカーソルを置く
function! s:goto_row(i) abort
  let l:l = s:lnum_of_row(a:i)
  if l:l == 0
    call s:reveal(a:i)
    call gnosis#fznav#render()
    let l:l = s:lnum_of_row(a:i)
  endif
  if l:l > 0
    call s:goto(l:l)
  endif
endfunction

function! s:left() abort
  let l:it = s:cur_item()
  if s:F.mode ==# 'upper'
    " 上位表示: 祖先の Group を 1 つ上へ。関連 Group の上なら現在のノートへ
    let l:lnum = line('.')
    if l:it.t ==# 'g'
      for l:j in range(len(s:F.items))
        if s:F.items[l:j].t ==# 'u' | call s:goto(l:j + 1) | return | endif
      endfor
    elseif l:it.t ==# 'u' || l:it.t ==# 'c'
      for l:j in range(l:lnum - 2, 0, -1)
        if s:F.items[l:j].t ==# 'c' | call s:goto(l:j + 1) | return | endif
      endfor
    endif
    return
  endif
  if l:it.t !=# 'r'
    return
  endif
  let l:u = s:F.rows[l:it.i][5]
  if l:u < 0
    return
  endif
  " Group の行からは上位の Group（無ければ Note）へ、Note の行からは上位の Note へ
  let l:to = l:it.k ==# 'g' && s:F.rows[l:u][3] ==# 'g' ? l:u : s:F.rows[l:u][6]
  call s:goto_row(l:to)
endfunction

function! s:right() abort
  let l:it = s:cur_item()
  if s:F.mode ==# 'upper'
    if l:it.t ==# 'c'
      let l:lnum = line('.')
      for l:j in range(l:lnum, len(s:F.items) - 1)
        if s:F.items[l:j].t ==# 'c' || s:F.items[l:j].t ==# 'u' | call s:goto(l:j + 1) | return | endif
      endfor
    endif
    return
  endif
  if l:it.t !=# 'r'
    return
  endif
  let l:d = s:F.rows[l:it.i][8]
  if l:d < 0
    return
  endif
  silent! call remove(s:F.collapsed, s:F.rows[l:it.i][0])
  " 今開いているノートがこの枝の下にあれば、そちらへ向かう子へ。無ければ下位の最初のブロックへ
  let l:d = s:toward_current(l:it.i, l:d)
  " 同じ種類の行へ（Note からは Note へ）
  let l:to = l:it.k ==# 'n' ? s:F.rows[l:d][6] : l:d
  call s:goto_row(l:to)
endfunction

" 同じ番号のブロックの先頭の行
function! s:block_head(i) abort
  let l:h = a:i
  while l:h > 0 && s:F.rows[l:h - 1][0] ==# s:F.rows[l:h][0]
    let l:h -= 1
  endwhile
  return l:h
endfunction

" 行 a:i の下で、今開いているノートへ向かう子ブロックの先頭。下に無ければ a:dflt
function! s:toward_current(i, dflt) abort
  let l:c = s:cur_row()
  let l:r = s:F.rows[a:i]
  if l:c <= l:r[6] || l:c >= l:r[7]
    return a:dflt
  endif
  let l:head = s:block_head(a:i)
  let l:x = l:c
  while s:F.rows[l:x][5] >= 0 && s:F.rows[l:x][5] != l:head
    let l:x = s:F.rows[l:x][5]
  endwhile
  return s:F.rows[l:x][5] == l:head ? s:block_head(l:x) : a:dflt
endfunction

" [ ]: 同じ親の下の、前・次の兄弟へ（Note の行からは Note へ、Group の行からは Group へ）
function! s:sibling(d) abort
  let l:it = s:cur_item()
  if s:F.mode ==# 'upper' || l:it.t !=# 'r'
    return
  endif
  let l:i = l:it.i
  let l:up = s:F.rows[l:i][5]
  let l:n = len(s:F.rows)
  let l:to = -1
  if a:d > 0
    let l:j = s:F.rows[l:i][7]
    if l:j < l:n && s:F.rows[l:j][5] == l:up
      let l:to = l:j
    endif
  else
    let l:j = s:block_head(l:i) - 1
    while l:j >= 0
      if s:F.rows[l:j][5] == l:up
        let l:to = s:block_head(l:j)
        break
      endif
      if l:up >= 0 && l:j <= l:up
        break
      endif
      let l:j -= 1
    endwhile
  endif
  if l:to < 0
    return
  endif
  call s:goto_row(l:it.k ==# 'n' ? s:F.rows[l:to][6] : l:to)
endfunction

function! s:enter() abort
  let l:it = s:cur_item()
  if l:it.t ==# 'h' || empty(get(l:it, 'path', ''))
    return
  endif
  let s:F.recenter = 1
  call gnosis#mview#open_rel(l:it.path)
  " 開いたノートの窓へカーソルを移す（画面は上から、カーソルは画面の一番下）。\l の選ぶモードの最中は、ビューに留まる
  if !gnosis#mview#picking()
    call gnosis#mview#toggle()
  endif
endfunction

" ---- モード ---------------------------------------------------------------------------------------

function! s:toggle_upper() abort
  let l:it = s:cur_item()
  let s:F.mode = s:F.mode ==# 'upper' ? 'normal' : 'upper'
  let s:F.recenter = 1
  call gnosis#fznav#render()
  if s:F.mode ==# 'normal' && get(l:it, 't', '') ==# 'r'
    " 戻ったとき、見ていた項目へ（上位表示のあいだに現在のノートが変わっていなければ現在位置）
  endif
endfunction

function! s:more() abort
  if s:F.mode !=# 'upper'
    return
  endif
  let s:F.more = !s:F.more
  call gnosis#fznav#render()
endfunction

" 窓の一番上に出す 1 行: 通常 / 上位表示と、リストへ入る最低限のキー
function! s:hint_text() abort
  return gnosis#hint#line([['l', 'リンク'], ['s', '検索'], ['r', '類似']], '',
        \ (s:F.mode ==# 'upper' ? '[u:' : 'u:') . gnosis#i18n#tr('上位表示') . (s:F.mode ==# 'upper' ? ']' : '')
        \ . ' m:' . gnosis#i18n#tr('メニュー') . ' ?:' . gnosis#i18n#tr('説明'))
endfunction

function! s:toggle_hint() abort
  call gnosis#hint#toggle({-> gnosis#fznav#render()})
endfunction

" m: やることを番号で選ぶメニュー
function! s:menu() abort
  let l:entries = [
        \ ['  ' . gnosis#i18n#tr('リンク（つながっているノート）'), {-> gnosis#listnav#enter_mode('links')}],
        \ ['  ' . gnosis#i18n#tr('検索'), {-> gnosis#listnav#enter_mode('search')}],
        \ ['  ' . gnosis#i18n#tr('類似（似ているノート）'), {-> gnosis#listnav#enter_mode('similar')}],
        \ [gnosis#hint#mark(s:F.mode ==# 'upper', '上位表示（祖先と関連グループ）'), {-> s:toggle_upper()}],
        \ ['  ' . gnosis#i18n#tr('関連グループをもっと見る（上位表示）'), {-> s:more()}],
        \ ['  ' . gnosis#i18n#tr('全画面 ⇔ 戻す'), {-> gnosis#mview#win_op('full')}],
        \ [gnosis#hint#mark(gnosis#hint#on(), '上のヒント行を出す'), {-> s:toggle_hint()}]]
  call gnosis#hint#menu('Folgezettel', l:entries)
endfunction

" ? のガイドは、Esc / q / ? / Enter / Space / クリックでだけ閉じる（タイマーが積むキーでは閉じない）
function! s:help_filter(id, key) abort
  if index(["\<Esc>", 'q', '?', "\<CR>", ' ', "\<LeftMouse>"], a:key) >= 0
    call popup_close(a:id)
  endif
  return 1
endfunction

function! s:help() abort
  let l:t = [
        \ 'FOLGEZETTEL',
        \ '',
        \ 'j k / ↓ ↑     ' . gnosis#i18n#tr('次・前の項目'),
        \ 'h / ←         ' . gnosis#i18n#tr('親の番号へ'),
        \ '→            ' . gnosis#i18n#tr('下位へ（今開いているノートが下にあれば、その方向へ）'),
        \ '[ ]          ' . gnosis#i18n#tr('前・次の兄弟へ'),
        \ 'Enter         ' . gnosis#i18n#tr('Group / Note を開く'),
        \ 'c             ' . gnosis#i18n#tr('印のついたノート（Enter で開いたもの）へ戻る'),
        \ 'u             ' . gnosis#i18n#tr('上位表示 ⇔ 通常'),
        \ 'M             ' . gnosis#i18n#tr('関連グループをもっと見る（上位表示）'),
        \ 's l r         ' . gnosis#i18n#tr('リスト: 検索・リンク・類似。リストの中で f で Folgezettel に戻る'),
        \ 'm             ' . gnosis#i18n#tr('メニュー（やることを番号で選ぶ）'),
        \ 'K             ' . gnosis#i18n#tr('上のヒント行を出す・隠す'),
        \ '\l            ' . gnosis#i18n#tr('入れるノートを選ぶモード（\l）。ビューを切り替えても続く'),
        \ 'e I o         ' . gnosis#i18n#tr('選ぶモード: e 決定・I Index に載せる・o 元のノートを右に見る（もう一度で戻る）・O 左の中心も元のノートに'),
        \ 'q             ' . gnosis#i18n#tr('選ぶモードなどをやめる（何も無ければ閉じる）'),
        \ '\o            ' . gnosis#i18n#tr('アウトラインを右に出す ⇔ しまう（どこでも）'),
        \ 'Ctrl-← Ctrl-→ gv  ' . gnosis#i18n#tr('前・次のビューへ'),
        \ 'Space         ' . gnosis#i18n#tr('ノートの窓へ'),
        \ 'F < > = p .   ' . gnosis#i18n#tr('全画面・幅・右の窓・読み直し'),
        \ 'Q             ' . gnosis#i18n#tr('閉じる')]
  call popup_dialog(l:t, {'title': ' ? ', 'padding': [0, 1, 0, 1], 'border': [], 'close': 'click', 'filter': function('s:help_filter')})
endfunction

" ---- 窓の出入り -----------------------------------------------------------------------------------

" カーソルが窓に戻った / 出た。出ているあいだは、現在のノートを縦の中央に置く
function! gnosis#fznav#focus(on) abort
  if a:on
    call gnosis#fznav#mark()
    return
  endif
  call gnosis#fznav#mark()
  if empty(s:F.sel) || &filetype !=# 'gnosis-mandala'
    return
  endif
  let l:c = s:current_lnum()
  if l:c > 0
    call cursor(l:c, 1)
    let s:F.lastpos = getpos('.')[1:2]
    normal! zz
  endif
endfunction

function! s:on_moved() abort
  if get(s:S(), 'view', 'mandala') !=# 'fz'
    return
  endif
  let l:s = s:snap(line('.'))
  if l:s != line('.')
    call cursor(l:s, 1)
  endif
  call gnosis#fznav#mark()
  if get(s:F, 'lastpos', []) !=# getpos('.')[1:2]
    let s:F.lastpos = getpos('.')[1:2]
    call s:preview_later()
  endif
  call s:sync_view()
endfunction

function! s:sync_view() abort
  if exists('*GnosisGuiChanged') | call GnosisGuiChanged() | endif
endfunction

function! gnosis#fznav#setup() abort
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted nowrap nolist nonumber norelativenumber
  setlocal nocursorline nospell nofoldenable colorcolumn= signcolumn=no filetype=gnosis-mandala scrolloff=3 sidescrolloff=0
  nnoremap <buffer><nowait><silent> j <Cmd>call <SID>move(v:count1)<CR>
  nnoremap <buffer><nowait><silent> <Down> <Cmd>call <SID>move(v:count1)<CR>
  nnoremap <buffer><nowait><silent> k <Cmd>call <SID>move(-v:count1)<CR>
  nnoremap <buffer><nowait><silent> <Up> <Cmd>call <SID>move(-v:count1)<CR>
  " 数字はふつうの数（5j など）。リンクの数字キーの全体設定を、この窓では外す
  for l:d in range(10)
    execute printf('nnoremap <buffer><nowait><silent> %d %d', l:d, l:d)
  endfor
  nnoremap <buffer><nowait><silent> gg <Cmd>call <SID>edge(0)<CR>
  nnoremap <buffer><nowait><silent> G <Cmd>call <SID>edge(1)<CR>
  nnoremap <buffer><nowait><silent> h <Cmd>call <SID>left()<CR>
  nnoremap <buffer><nowait><silent> <Left> <Cmd>call <SID>left()<CR>
  nnoremap <buffer><nowait><silent> ] <Cmd>call <SID>sibling(1)<CR>
  nnoremap <buffer><nowait><silent> [ <Cmd>call <SID>sibling(-1)<CR>
  nnoremap <buffer><nowait><silent> <Right> <Cmd>call <SID>right()<CR>
  nnoremap <buffer><nowait><silent> <CR> <Cmd>call <SID>enter()<CR>
  nnoremap <buffer><nowait><silent> <2-LeftMouse> <Cmd>call <SID>enter()<CR>
  nnoremap <buffer><nowait><silent> u <Cmd>call <SID>toggle_upper()<CR>
  nnoremap <buffer><nowait><silent> c <Cmd>call <SID>back()<CR>
  nnoremap <buffer><nowait><silent> M <Cmd>call <SID>more()<CR>
  " s l r m: リスト（検索・リンク・類似）のモードへ。リストでは f で Folgezettel に戻る
  nnoremap <buffer><nowait><silent> s <Cmd>call gnosis#listnav#enter_mode('search')<CR>
  nnoremap <buffer><nowait><silent> l <Cmd>call gnosis#listnav#enter_mode('links')<CR>
  nnoremap <buffer><nowait><silent> r <Cmd>call gnosis#listnav#enter_mode('similar')<CR>
  nnoremap <buffer><nowait><silent> m <Cmd>call <SID>menu()<CR>
  nnoremap <buffer><nowait><silent> K <Cmd>call <SID>toggle_hint()<CR>
  nnoremap <buffer><nowait><silent> o <Cmd>call gnosis#mview#toggle_origin()<CR>
  nnoremap <buffer><nowait><silent> O <Cmd>call gnosis#mview#goto_origin()<CR>
  nnoremap <buffer><nowait><silent> e <Cmd>call <SID>pick_decide(0)<CR>
  nnoremap <buffer><nowait><silent> I <Cmd>call <SID>pick_decide(1)<CR>
  nnoremap <buffer><nowait><silent> ? <Cmd>call <SID>help()<CR>
  nnoremap <buffer><nowait><silent> F <Cmd>call gnosis#mview#win_op('full')<CR>
  nnoremap <buffer><nowait><silent> <lt> <Cmd>call gnosis#mview#win_op('resize-')<CR>
  nnoremap <buffer><nowait><silent> > <Cmd>call gnosis#mview#win_op('resize+')<CR>
  nnoremap <buffer><nowait><silent> = <Cmd>call gnosis#mview#win_op('equalize')<CR>
  nnoremap <buffer><nowait><silent> p <Cmd>call gnosis#mview#win_op('preview')<CR>
  nnoremap <buffer><nowait><silent> . <Cmd>call gnosis#mview#win_op('reload')<CR>
  nnoremap <buffer><nowait><silent> q <Cmd>call gnosis#fznav#quit()<CR>
  nnoremap <buffer><nowait><silent> Q <Cmd>call gnosis#mview#win_op('quit')<CR>
  nnoremap <buffer><nowait><silent> <Space> <Cmd>call gnosis#mview#toggle()<CR>
  nnoremap <buffer><nowait><silent> <C-Left> <Cmd>call gnosis#mview#switch_view('previous')<CR>
  nnoremap <buffer><nowait><silent> <C-Right> <Cmd>call gnosis#mview#switch_view()<CR>
  nnoremap <buffer><nowait><silent> gv <Cmd>call gnosis#mview#switch_view()<CR>
  nnoremap <buffer><silent> \c <Cmd>call gnosis#open_web()<CR>
  nnoremap <buffer><silent> \C <Cmd>call gnosis#run#switch('cui')<CR>
  nnoremap <buffer><silent> \x <Cmd>call gnosis#run#close_here()<CR>
  nnoremap <buffer><silent> \X <Cmd>call gnosis#run#close_all()<CR>
  nnoremap <buffer><silent> \o <Cmd>call gnosis#panel#key('outline')<CR>
  nnoremap <buffer><silent> \W <Cmd>call gnosis#mview#only_note()<CR>
  nnoremap <buffer><silent> \l <Cmd>call gnosis#mview#link_pick()<CR>
  augroup gnosis_fz_buf
    autocmd! * <buffer>
    autocmd CursorMoved <buffer> call s:on_moved()
  augroup END
  " 曼荼羅から切り替えた直後は、まだ何も書いていない。次の描画で全部書く
  let s:F.lines = []
  let s:F.last_cur = ''
  let s:F.recenter = 1
  setlocal modifiable
  silent! %delete _
  setlocal nomodifiable nomodified
endfunction

function! gnosis#fznav#teardown() abort
  augroup gnosis_fz_buf
    autocmd! * <buffer>
  augroup END
  silent! call prop_clear(1, line('$'))
  if exists('w:mview_match')
    for l:m in w:mview_match
      silent! call matchdelete(l:m)
    endfor
  endif
  let w:mview_match = []
  let s:F.lines = []
  setlocal modifiable
  silent! %delete _
  setlocal nomodifiable nomodified
endfunction

" ---- アプリ（\c）へ渡す状態 / アプリからの操作 -------------------------------------------------------

" 窓に見えている行だけを渡す（大量のノートでも軽い）
function! gnosis#fznav#gui_state() abort
  let l:s = s:S()
  let l:wi = getwininfo(l:s.win)
  if empty(l:wi) || winbufnr(l:s.win) != get(l:s, 'buf', -1) || empty(s:F.cells)
    return {}
  endif
  let l:top = l:wi[0].topline
  let l:h = l:wi[0].height
  let l:cur = line('.')
  if win_getid() != l:s.win
    let l:cur = getcurpos(l:s.win)[1]
  endif
  let l:vis = []
  for l:i in range(l:top, min([len(s:F.cells), l:top + l:h - 1]))
    let l:c = copy(s:F.cells[l:i - 1])
    let l:c.sel = l:i == l:cur ? 1 : 0
    let l:c.hit = has_key(get(s:F, 'highlight_paths', {}), get(s:F.items[l:i - 1], 'path', ''))
    let l:c.ln = l:i
    call add(l:vis, l:c)
  endfor
  let l:it = get(s:F.items, l:cur - 1, {'t': 'h'})
  let l:detail = l:it.t ==# 'h' ? '' : printf('%s  %s  %s  (%s)', empty(l:it.id) ? '-' : l:it.id, l:it.k ==# 'g' ? 'Group' : 'Note', l:it.title, l:it.path)
  return {'view': 'fz', 'mode': s:F.mode, 'lines': l:vis, 'top': l:top, 'total': len(s:F.cells), 'height': l:h, 'cursor': l:cur,
        \ 'detail': l:detail, 'numw': s:numw(), 'win': l:s.win, 'noteWin': gnosis#mview#note_win(), 'wcols': winwidth(l:s.win),
        \ 'legend': 0}
endfunction

" アプリで項目をクリック（enter=1 なら開く）
function! gnosis#fznav#gui_click(lnum, enter) abort
  let l:s = s:S()
  if get(l:s, 'view', 'mandala') !=# 'fz' || a:lnum < 1 || a:lnum > len(s:F.items) || s:F.items[a:lnum - 1].t ==# 'h'
    return
  endif
  call win_gotoid(l:s.win)
  call cursor(a:lnum, 1)
  call gnosis#fznav#mark()
  call s:preview_later()
  if a:enter
    call s:enter()
  endif
endfunction

" アプリでホイール: 窓の表示だけを動かす（カーソルは見える範囲に残る）
function! gnosis#fznav#gui_scroll(n) abort
  let l:s = s:S()
  if get(l:s, 'view', 'mandala') !=# 'fz' || empty(getwininfo(get(l:s, 'win', -1)))
    return
  endif
  let l:keys = a:n > 0 ? repeat("\<C-e>", a:n) : repeat("\<C-y>", -a:n)
  call win_execute(l:s.win, 'normal! ' . l:keys)
  call s:sync_view()
endfunction

" 試験用
function! gnosis#fznav#state() abort
  return s:F
endfunction
" vault を切り替えるとき: 前の vault の行・折りたたみ・予約中の右の窓の更新を捨てる
function! gnosis#fznav#reset() abort
  if exists('s:ptimer')
    call timer_stop(s:ptimer)
    unlet s:ptimer
  endif
  call gnosis#fznav#reset_for_test()
endfunction

function! gnosis#fznav#reset_for_test() abort
  let s:F = {'collapsed': {}, 'mode': 'normal', 'more': 0, 'dirty': 1, 'gen': 0, 'rows': [], 'pidx': {},
        \ 'lines': [], 'cells': [], 'items': [], 'sel': [], 'selpos': {}, 'last_cur': '', 'up': {}, 'upkey': '', 'key': ''}
endfunction


function! gnosis#fznav#query(op, text) abort
  let s:F[a:op] = a:text
  let l:paths = {}
  if !empty(a:text)
    for l:r in gnosis#listnav#search_rows(s:S().root, a:text, 'all') | let l:paths[l:r.path] = 1 | endfor
  endif
  let s:F[a:op . '_paths'] = l:paths
  call gnosis#fznav#render()
endfunction

function! gnosis#fznav#quit() abort
  call gnosis#mview#quit_layers()
endfunction
