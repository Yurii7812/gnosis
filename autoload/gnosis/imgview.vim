" ノートの画像をポップアップで見る（gz）。
"   ノートにある画像の一覧（popup_menu）→ Enter で端末に sixel で重ねて表示 → q で一覧に戻る → もう一度 q で閉じる。
"   キーボードだけで動く。閉じたあとは redraw! で画像を消し、カーソルは元のまま Vim にある。
"   既定は外部のビューア（xdg-open）で開く。ズームや画質はビューアに任せる。
"   imageViewer（\zz の窓で選ぶ。既定は external）または g:gnosis_image_viewer（こちらが先）= 'external' | 'sixel'（この端末の中に sixel で出す。対応する端末だけ）| 'auto'（sixel に対応していれば sixel）。
"   ノートの中に画像を出すもの（下のほう）は、この設定とは別に、端末が sixel に対応していれば出す。
"   Python 側: python/sixel_view.py

let s:root = expand('<sfile>:p:h:h:h')
let s:esc = "\<Esc>"

function! s:py(args) abort
  let l:cmd = gnosis#python_cmd() . ' ' . shellescape(s:root . '/python/sixel_view.py')
        \ . ' ' . join(map(copy(a:args), 'shellescape(v:val)'), ' ') . ' 2>/dev/null'
  return system(l:cmd)
endfunction

" gz で開く方法: 'external'（xdg-open）か 'sixel'。g:gnosis_image_viewer があればそちらが先（'auto' は端末が対応していれば sixel）。
" 無ければ \zz の窓で選んだ設定（imageViewer）
function! gnosis#imgview#viewer() abort
  if exists('g:gnosis_image_viewer')
    return g:gnosis_image_viewer
  endif
  try
    return get(gnosis#settings#current(), 'imageViewer', 'external')
  catch
    return 'external'
  endtry
endfunction

" gz で、この端末の中に sixel で出すか
function! s:sixel_ok() abort
  let l:mode = gnosis#imgview#viewer()
  if l:mode ==# 'sixel' | return 1 | endif
  if l:mode ==# 'external' | return 0 | endif
  return s:term_sixel()
endfunction

" 端末が sixel に対応しているか（ノートの中に画像を出すかどうかもこれで決める）
function! s:term_sixel() abort
  if !empty($TMUX) || !empty($STY) | return 0 | endif
  if !empty($GNOSIS_SIXEL) | return 1 | endif
  if !empty($KONSOLE_VERSION) && str2nr($KONSOLE_VERSION) >= 220400 | return 1 | endif
  return $TERM =~# 'foot\|mlterm\|contour\|sixel' || $TERM_PROGRAM ==# 'WezTerm'
endfunction

function! s:images() abort
  let l:tmp = tempname()
  call writefile(getline(1, '$'), l:tmp)
  let l:out = s:py(['list', expand('%:p'), l:tmp])
  call delete(l:tmp)
  try
    return json_decode(l:out)
  catch
    return []
  endtry
endfunction

function! s:caption(i, items, hint) abort
  let l:txt = printf(' %d/%d  %s   %s', a:i + 1, len(a:items), a:items[a:i].label, a:hint)
  echo strcharpart(l:txt, 0, &columns - 12)
endfunction

" 画像を 1 枚出して、キーを待つ。戻り値: 表示を終えたときの添字（j/k で動いたあと）
function! s:view(items, i) abort
  let l:i = a:i
  while 1
    let l:it = a:items[l:i]
    redraw!
    if !l:it.exists
      echo ' 画像が見つかりません: ' . l:it.path . '   q: 戻る'
    else
      echo ' 読み込み中...'
      redraw
      let l:res = s:py(['render', l:it.path, &columns - 2, &lines - 4])
      let l:nl = stridx(l:res, "\n")
      let l:size = l:nl > 0 ? split(l:res[: l:nl - 1]) : []
      if len(l:size) != 2
        echo ' 画像を読めません: ' . l:it.path . '   q: 戻る'
      else
        let l:w = str2nr(l:size[0])
        let l:h = str2nr(l:size[1])
        let l:top = max([1, (&lines - 2 - l:h) / 2 + 1])
        let l:left = max([1, (&columns - l:w) / 2 + 1])
        call echoraw("\<Esc>7\<Esc>[" . l:top . ';' . l:left . 'H' . l:res[l:nl + 1 :] . "\<Esc>8")
        call s:caption(l:i, a:items, 'j/k・n/p: 前後  q/Esc: 戻る')
      endif
    endif
    let l:k = gnosis#ui#getcharstr()
    if l:k ==# 'j' || l:k ==# 'n' || l:k ==# 'l' || l:k ==# ' ' || l:k ==# "\<Right>" || l:k ==# "\<Down>"
      if l:i < len(a:items) - 1 | let l:i += 1 | endif
    elseif l:k ==# 'k' || l:k ==# 'p' || l:k ==# 'h' || l:k ==# "\<Left>" || l:k ==# "\<Up>"
      if l:i > 0 | let l:i -= 1 | endif
    else
      break
    endif
  endwhile
  redraw!
  echo ''
  return l:i
endfunction

" 外のビューアに渡すため、このノートの画像だけを ~/.cache/gnosis/view/<ノートごと>/ に 01-名前 02-名前 … と並べる。
" ビューア（Gwenview など）は開いた画像と同じフォルダの画像を前後に出すので、元のフォルダのままだと
" このノートにない画像まで出てしまう。ここでは、このノートの画像（見つかるものだけ）しか入らない
function! s:stage(items, i) abort
  let l:base = (!empty($XDG_CACHE_HOME) ? $XDG_CACHE_HOME : expand('~/.cache')) . '/gnosis/view/' . sha256(expand('%:p'))[: 15]
  if isdirectory(l:base)
    call delete(l:base, 'rf')
  endif
  call mkdir(l:base, 'p')
  let l:want = ''
  let l:n = 0
  for l:k in range(len(a:items))
    if !a:items[l:k].exists | continue | endif
    let l:n += 1
    let l:dst = l:base . '/' . printf('%02d-%s', l:n, fnamemodify(a:items[l:k].path, ':t'))
    try
      call writefile(readfile(a:items[l:k].path, 'B'), l:dst, 'b')
    catch
      continue
    endtry
    if l:k == a:i | let l:want = l:dst | endif
  endfor
  return l:want
endfunction

" 画像を 1 枚見せる。外部のビューアで開く（既定）か、この端末の中に sixel で出す。戻り値: 添字
function! s:show(items, i) abort
  if s:sixel_ok()
    return s:view(a:items, a:i)
  endif
  let l:it = a:items[a:i]
  if !l:it.exists
    echo ' 画像が見つかりません: ' . l:it.path
  elseif executable('xdg-open')
    let l:path = s:stage(a:items, a:i)
    call job_start(['xdg-open', empty(l:path) ? l:it.path : l:path], {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
    echo ' 開きました: ' . l:it.label
  else
    echo ' xdg-open がありません。g:gnosis_image_viewer を設定してください'
  endif
  return a:i
endfunction

" 一覧（popup_menu）。Enter で表示、q / Esc で閉じる。表示のあとは同じ位置の一覧に戻る
function! s:menu(items, sel) abort
  let l:lines = []
  for l:k in range(len(a:items))
    call add(l:lines, printf('%2d  %s%s', l:k + 1, a:items[l:k].label, a:items[l:k].exists ? '' : '  （見つかりません）'))
  endfor
  let s:menu_items = a:items
  let l:id = popup_menu(l:lines, {
        \ 'title': ' 画像（Enter: 見る  j/k: 選ぶ  q: 閉じる） ',
        \ 'minwidth': 36, 'maxheight': max([3, &lines - 8]), 'padding': [0, 1, 0, 1],
        \ 'zindex': 300, 'mapping': 0,
        \ 'filter': function('s:menu_key'), 'callback': function('s:menu_done'),
        \ })
  call win_execute(l:id, 'call cursor(' . (a:sel + 1) . ', 1)')
endfunction

function! s:menu_key(id, key) abort
  if a:key ==# 'q' || a:key ==# s:esc || a:key ==# "\<C-c>"
    call popup_close(a:id, -1)
    return 1
  endif
  if a:key ==# 'l' || a:key ==# "\<CR>" || a:key ==# "\<Right>"
    call popup_filter_menu(a:id, "\<CR>")
    return 1
  endif
  if a:key =~# '^[1-9]$' && str2nr(a:key) <= len(s:menu_items)
    call win_execute(a:id, 'call cursor(' . a:key . ', 1)')
    call popup_filter_menu(a:id, "\<CR>")
    return 1
  endif
  " j / k は端で止める（ループしない）
  let l:n = len(s:menu_items)
  let l:cur = line('.', a:id)
  if (a:key ==# 'j' || a:key ==# "\<Down>" || a:key ==# "\<C-n>") && l:cur >= l:n
    return 1
  endif
  if (a:key ==# 'k' || a:key ==# "\<Up>" || a:key ==# "\<C-p>") && l:cur <= 1
    return 1
  endif
  return popup_filter_menu(a:id, a:key)
endfunction

function! s:menu_done(id, result) abort
  if a:result < 1 || a:result > len(s:menu_items)
    return
  endif
  let l:items = s:menu_items
  let l:i = s:show(l:items, a:result - 1)
  call s:menu(l:items, l:i)
endfunction

function! gnosis#imgview#open() abort
  if expand('%:e') !~? '^md$'
    echo 'Markdown のノートで使います'
    return
  endif
  let l:items = s:images()
  if empty(l:items)
    echo 'このノートに画像はありません'
    return
  endif
  " カーソルの行に画像があれば、その画像を最初に選んでおく
  let l:sel = 0
  let l:cur = getline('.')
  for l:k in range(len(l:items))
    if stridx(l:cur, l:items[l:k].label) >= 0 || stridx(l:cur, substitute(l:items[l:k].label, ' ', '%20', 'g')) >= 0
      let l:sel = l:k
      break
    endif
  endfor
  if len(l:items) == 1
    call s:show(l:items, 0)
    return
  endif
  call s:menu(l:items, l:sel)
endfunction

" =============================================================================
" ノートの中に画像を出す（\zz の「画像を隠す」がオフのとき）
"   ![](画像) だけの行の下に、画像の高さぶんの空きの行（テキストプロパティの仮想テキスト）を確保し、
"   その位置に sixel を端末へ直接重ねる。画像は ~/.cache/gnosis/sixel に作って使い回す（python/sixel_view.py inline）。
"   スクロール・編集・窓の変更のあとは、少し待って描き直す。ポップアップが開いている間は描かない（上に重なってしまうため）。
"   ファイルの中身は変えない（空きの行は表示だけ）。
" =============================================================================
let s:ptype = 'gnosis_img'
let s:meta = {}       " 画像のパス → {cols, rows, file}
let s:six = {}        " sixel のファイル → 中身
let s:job = 0
let s:pending = {}    " 作成待ちの画像
let s:sig = ''        " 今、端末に出している画像の位置の署名
let s:timer = 0
let s:popup_open = 0
let s:own_tick = {}   " バッファ → こちらがプロパティを付け替えた直後の changedtick（編集と見なさない）

function! s:hidden() abort
  try
    return get(get(gnosis#settings#current(), 'hide', {}), 'image', 0) ? 1 : 0
  catch
    return 0
  endtry
endfunction

function! s:inline_on() abort
  return has('textprop') && exists('*echoraw') && !has('gui_running') && !s:hidden() && s:term_sixel()
endfunction

function! s:eligible(buf) abort
  return getbufvar(a:buf, '&buftype') ==# '' && fnamemodify(bufname(a:buf), ':e') ==? 'md' && getbufvar(a:buf, '&filetype') !=# 'gnosis-mandala'
endfunction

function! s:cache_dir() abort
  let l:base = !empty($XDG_CACHE_HOME) ? $XDG_CACHE_HOME : expand('~/.cache')
  return l:base . '/gnosis/sixel'
endfunction

" バッファの「画像だけの行」→ [{lnum, path}]（相対パスはそのノートのフォルダから。遠隔 URL と存在しないものは除く）
function! s:scan(buf) abort
  let l:out = []
  let l:dir = fnamemodify(bufname(a:buf), ':p:h')
  let l:fence = 0
  let l:n = 0
  for l:ln in getbufline(a:buf, 1, '$')
    let l:n += 1
    if l:ln =~# '^\s*\(```\|\~\~\~\)'
      let l:fence = !l:fence
      continue
    endif
    if l:fence | continue | endif
    let l:m = matchlist(l:ln, '^\s*!\[[^\]]*\](\s*<\?\([^)>]\+\)>\?\s*)\s*$')
    " <img src="…" width="25%"> の行も画像（アプリと同じ。大きさの指定は、この端末の表示では使わない）
    if empty(l:m) | let l:m = matchlist(l:ln, '^\s*<img\s\%([^>]*\s\)\?src\s*=\s*["'']\([^"'']\+\)["''][^>]*>\s*$') | endif
    if empty(l:m) | continue | endif
    let l:u = substitute(l:m[1], '\s\+"[^"]*"$', '', '')
    if l:u =~# '^\a\+://' | continue | endif
    let l:u = substitute(l:u, '%\(\x\x\)', '\=nr2char(str2nr(submatch(1), 16))', 'g')
    let l:p = l:u =~# '^/' ? l:u : l:dir . '/' . l:u
    let l:p = simplify(l:p)
    if filereadable(l:p)
      call add(l:out, {'lnum': l:n, 'path': l:p})
    endif
  endfor
  return l:out
endfunction

function! s:max_cols() abort
  return max([16, min([70, &columns / 2 - 4])])
endfunction

function! s:max_rows() abort
  return max([4, min([16, &lines / 3])])
endfunction

" 画像の下ごしらえ（非同期）。終わったら空きの行を付けて描き直す
function! s:prepare(paths) abort
  for l:p in a:paths
    if !has_key(s:meta, l:p) | let s:pending[l:p] = 1 | endif
  endfor
  if s:job isnot 0 && job_status(s:job) ==# 'run'
    return
  endif
  if empty(s:pending) | return | endif
  let l:ps = keys(s:pending)
  let s:pending = {}
  let s:out = ''
  let l:cmd = split(gnosis#python_cmd()) + [s:root . '/python/sixel_view.py', 'inline', s:cache_dir(), string(s:max_cols()), string(s:max_rows())] + l:ps
  let s:job = job_start(l:cmd, {'out_mode': 'raw', 'out_cb': {ch, msg -> s:job_out(msg)},
        \ 'exit_cb': {j, st -> s:job_done()}, 'err_io': 'null', 'in_io': 'null'})
endfunction

function! s:job_out(msg) abort
  let s:out .= a:msg
endfunction

function! s:job_done() abort
  try
    for [l:p, l:m] in items(json_decode(s:out))
      let s:meta[l:p] = l:m
    endfor
  catch
  endtry
  let s:job = 0
  call gnosis#imgview#refresh()
endfunction

" バッファに空きの行を付け直す。変わったら 1
function! s:apply_props(buf) abort
  let l:want = []
  for l:it in s:scan(a:buf)
    if has_key(s:meta, l:it.path)
      call add(l:want, [l:it.lnum, s:meta[l:it.path].rows])
    endif
  endfor
  if l:want ==# getbufvar(a:buf, 'gnosis_img_rows', [])
    return 0
  endif
  let l:mod = getbufvar(a:buf, '&modified')
  if empty(prop_type_get(s:ptype))
    call prop_type_add(s:ptype, {})
  endif
  call prop_remove({'type': s:ptype, 'bufnr': a:buf, 'all': 1})
  for [l:lnum, l:rows] in l:want
    for l:k in range(l:rows)
      call prop_add(l:lnum, 0, {'type': s:ptype, 'bufnr': a:buf, 'text': ' ', 'text_align': 'below'})
    endfor
  endfor
  call setbufvar(a:buf, 'gnosis_img_rows', l:want)
  call setbufvar(a:buf, '&modified', l:mod)
  let s:own_tick[a:buf] = getbufvar(a:buf, 'changedtick')
  return 1
endfunction

" 付けた空きの行を全部外す
function! s:remove_props(buf) abort
  if empty(prop_type_get(s:ptype)) || empty(getbufvar(a:buf, 'gnosis_img_rows', []))
    return
  endif
  let l:mod = getbufvar(a:buf, '&modified')
  call prop_remove({'type': s:ptype, 'bufnr': a:buf, 'all': 1})
  call setbufvar(a:buf, 'gnosis_img_rows', [])
  call setbufvar(a:buf, '&modified', l:mod)
  let s:own_tick[a:buf] = getbufvar(a:buf, 'changedtick')
endfunction

" 今の画面に出すべき画像 → [{row, col, six}] と署名
function! s:visible() abort
  let l:out = []
  for l:w in getwininfo()
    if l:w.tabnr != tabpagenr() || !s:eligible(l:w.bufnr) | continue | endif
    for l:it in s:scan(l:w.bufnr)
      let l:m = get(s:meta, l:it.path, {})
      if empty(l:m) | continue | endif
      let l:pos = screenpos(l:w.winid, l:it.lnum, 1)
      if l:pos.row == 0 | continue | endif
      if win_execute(l:w.winid, 'echo foldclosed(' . l:it.lnum . ')') =~# '\d' && str2nr(win_execute(l:w.winid, 'echo foldclosed(' . l:it.lnum . ')')) > 0
        continue
      endif
      let l:top = l:pos.row + 1
      if l:it.lnum < line('$', l:w.winid)
        let l:nx = screenpos(l:w.winid, l:it.lnum + 1, 1)
        if l:nx.row > 0 | let l:top = l:nx.row - l:m.rows | endif
      endif
      if l:top + l:m.rows - 1 > l:w.winrow + l:w.height - 1 || l:top <= l:pos.row
        continue
      endif
      if l:pos.col + l:m.cols - 1 > l:w.wincol + l:w.width - 1
        continue
      endif
      if !has_key(s:six, l:m.file)
        let l:r = readfile(l:m.file)
        let s:six[l:m.file] = empty(l:r) ? '' : l:r[0]
      endif
      if !empty(s:six[l:m.file])
        call add(l:out, {'row': l:top, 'col': l:pos.col, 'file': l:m.file})
      endif
    endfor
  endfor
  return l:out
endfunction

function! s:sig_of(vis) abort
  return join(map(copy(a:vis), 'v:val.row . "," . v:val.col . "," . v:val.file'), ';')
endfunction

function! s:popups() abort
  for l:id in popup_list()
    if get(popup_getpos(l:id), 'visible', 0) | return 1 | endif
  endfor
  return 0
endfunction

" 描き直す。force=1 は、同じ位置でも出し直す（ポップアップが閉じたあとなど）
function! s:draw(force) abort
  let s:timer = 0
  if !s:inline_on() || mode() =~# '^[cr]' || s:popups()
    return
  endif
  let l:vis = s:visible()
  let l:sig = s:sig_of(l:vis)
  if l:sig ==# s:sig && !a:force
    return
  endif
  if !empty(s:sig) && l:sig !=# s:sig
    " 古い位置の画像を消す（画面を描き直す）
    redraw!
  endif
  let s:sig = l:sig
  if empty(l:vis) | return | endif
  let l:s = "\<Esc>7"
  for l:v in l:vis
    let l:s .= "\<Esc>[" . l:v.row . ';' . l:v.col . 'H' . s:six[l:v.file]
  endfor
  call echoraw(l:s . "\<Esc>8")
endfunction

function! gnosis#imgview#schedule(...) abort
  let l:force = a:0 ? a:1 : 0
  if s:timer != 0 | call timer_stop(s:timer) | endif
  let s:timer = timer_start(60, {-> s:draw(l:force)})
endfunction

" ノート（今のタブの窓に出ているもの）の空きの行を付け直し、描き直す。編集・窓の変更・設定の変更のあとに呼ぶ
function! gnosis#imgview#refresh(...) abort
  if !s:inline_on()
    return
  endif
  let l:need = []
  let l:changed = 0
  for l:b in uniq(sort(map(filter(getwininfo(), 'v:val.tabnr == tabpagenr() && s:eligible(v:val.bufnr)'), 'v:val.bufnr'), 'n'))
    for l:it in s:scan(l:b)
      if !has_key(s:meta, l:it.path) | call add(l:need, l:it.path) | endif
    endfor
    let l:changed += s:apply_props(l:b)
  endfor
  if !empty(l:need)
    call s:prepare(l:need)
  endif
  call gnosis#imgview#schedule(l:changed)
  if l:changed && !get(s:, 'settling', 0)
    let s:settling = 1
    call timer_start(3500, {-> execute('let s:settling = 0')})
    call s:settle()
  endif
endfunction

" 編集のあと（こちらが付け替えた直後の変更は除く）
function! gnosis#imgview#on_text_changed() abort
  if get(s:own_tick, bufnr('%'), -1) == b:changedtick
    return
  endif
  call gnosis#imgview#refresh()
endfunction

" \zz で表示のオン・オフが変わったとき
function! gnosis#imgview#apply_setting() abort
  if s:hidden() || !s:term_sixel()
    for l:b in map(filter(getwininfo(), 's:eligible(v:val.bufnr)'), 'v:val.bufnr')
      call s:remove_props(l:b)
    endfor
    let s:sig = ''
    redraw!
  else
    call gnosis#imgview#refresh()
  endif
endfunction

" ポップアップが閉じたら出し直す（開いている間は描かない）
function! s:poll(t) abort
  let l:now = s:popups()
  if s:popup_open && !l:now
    call gnosis#imgview#schedule(1)
  endif
  let s:popup_open = l:now
endfunction

function! gnosis#imgview#start() abort
  if !has('timers') || !has('textprop') | return | endif
  call timer_start(300, function('s:poll'), {'repeat': -1})
  call gnosis#imgview#refresh()
  call s:settle()
endfunction

" 起動・ノートを開いた直後は、そのあとの画面の描き直し（曼荼羅や窓の組み立て）で画像が消えることがある。
" 少しあとに何度か、同じ位置のまま出し直す（\zz でオフ→オンにしないと出ない、を防ぐ）
function! s:settle() abort
  for l:ms in [400, 1200, 3000]
    call timer_start(l:ms, {-> gnosis#imgview#schedule(1)})
  endfor
endfunction
