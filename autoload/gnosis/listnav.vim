" リストビュー。データは曼荼羅と gs を共用し、探索の基準・プレビュー・戻る位置を分けて持つ。
let s:here = expand('<sfile>:p:h:h:h')
let s:L = {}
let s:timer = -1
let s:kinds = {'index': '索引', 'group': 'グループ', 'parent': '親', 'child': '子',
      \ 'context': '文脈', 'related': '関連', 'cite': '引用', 'back': 'BackLink', 'pred': '予測関連', 'note': 'ノート'}

function! gnosis#listnav#search_rows(root, query, scope) abort
  let l:cmd = join(map([gnosis#python_cmd(), s:here . '/python/listnav.py', a:root,
        \ '--query', a:query, '--scope', a:scope], 'shellescape(v:val)'), ' ')
  let l:out = system(l:cmd)
  if v:shell_error | return [] | endif
  try
    let l:data = json_decode(l:out)
    return type(l:data) == v:t_list ? l:data : []
  catch
    return []
  endtry
endfunction

function! s:paths(query) abort
  if has_key(get(s:L, 'pathcache', {}), a:query) | return s:L.pathcache[a:query] | endif
  let l:out = {}
  for l:r in gnosis#listnav#search_rows(s:L.root, a:query, 'all')
    let l:out[l:r.path] = 1
  endfor
  if len(s:L.pathcache) > 16 | let s:L.pathcache = {} | endif
  let s:L.pathcache[a:query] = l:out
  return l:out
endfunction

function! s:save_origin() abort
  let l:st = gnosis#mview#state()
  let l:nw = gnosis#mview#note_win()
  let l:origin = {'path': s:L.anchor, 'view': {}}
  if l:nw > 0
    let l:path = fnamemodify(bufname(winbufnr(l:nw)), ':p')
    if stridx(l:path, s:L.root . '/') == 0
      let l:origin.path = strpart(l:path, strlen(s:L.root) + 1)
    endif
    call win_execute(l:nw, 'let w:gnosis_list_origin_view = winsaveview()')
    let l:origin.view = getwinvar(l:nw, 'gnosis_list_origin_view', {})
  endif
  return l:origin
endfunction

function! gnosis#listnav#setup() abort
  let l:st = gnosis#mview#state()
  if empty(s:L) || get(s:L, 'root', '') !=# l:st.root || get(s:L, 'anchor', '') !=# l:st.center
    let s:L = {'root': l:st.root, 'anchor': l:st.center, 'mode': 'links', 'scope': 'all',
          \ 'search': '', 'filter': '', 'highlight': '', 'relation': '', 'depth': get(l:st, 'depth', 1),
          \ 'rank': get(l:st, 'rank_on', 0), 'history': [], 'rows': [], 'cache': {}, 'pathcache': {}, 'lines': [], 'hits': {}}
    call s:load_preferences()
    let s:L.origin = s:save_origin()
    let s:L.seen = l:st.center
  endif
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted nowrap nolist nonumber norelativenumber
  setlocal nocursorline nospell nofoldenable colorcolumn= signcolumn=no filetype=gnosis-mandala scrolloff=3
  for [l:key, l:cmd] in items({'j': "call gnosis#listnav#move(1)", 'k': "call gnosis#listnav#move(-1)",
        \ '<Down>': "call gnosis#listnav#move(1)", '<Up>': "call gnosis#listnav#move(-1)",
        \ 'gg': "call gnosis#listnav#edge(0)", 'G': "call gnosis#listnav#edge(1)",
        \ '<CR>': "call gnosis#listnav#enter()", '<2-LeftMouse>': "call gnosis#listnav#enter()",
        \ 's': "call gnosis#listnav#prompt('search')", 'x': "call gnosis#listnav#prompt('filter')",
        \ 'm': "call gnosis#listnav#prompt('highlight')", 'n': "call gnosis#listnav#next_hit(1)", 'N': "call gnosis#listnav#next_hit(-1)",
        \ '1': "call gnosis#listnav#option('mode', 'search')", '2': "call gnosis#listnav#option('mode', 'similar')",
        \ '3': "call gnosis#listnav#option('mode', 'links')", 'S': "call gnosis#listnav#scope()",
        \ 'w': "call gnosis#listnav#option('rank', !gnosis#listnav#state().rank)",
        \ '+': "call gnosis#listnav#depth()", 'o': "call gnosis#listnav#origin()", '<BS>': "call gnosis#listnav#back()",
        \ 'q': "call gnosis#listnav#quit()", 'Q': "call gnosis#mview#win_op('quit')",
        \ '<Space>': "call gnosis#mview#toggle()", 'f': "call gnosis#mview#win_op('full')",
        \ '<lt>': "call gnosis#mview#win_op('resize-')", '>': "call gnosis#mview#win_op('resize+')",
        \ '=': "call gnosis#mview#win_op('equalize')", '.': "call gnosis#mview#win_op('reload')",
        \ '<C-Right>': "call gnosis#mview#switch_view()", '<C-Left>': "call gnosis#mview#switch_view('previous')",
        \ 'gv': "call gnosis#mview#switch_view()", '?': "call gnosis#listnav#help()",
        \ 'e': "call gnosis#listnav#decide(0)", 'I': "call gnosis#listnav#decide(1)"})
    execute 'nnoremap <buffer><nowait><silent> ' . l:key . ' <Cmd>' . l:cmd . '<CR>'
  endfor
  for [l:key, l:kind] in items({'a': '', 'b': 'child', 'p': 'parent', 'g': 'group', 'c': 'context', 'r': 'related', 'v': 'cite', 'B': 'back', 'i': 'index'})
    execute 'nnoremap <buffer><nowait><silent> ' . l:key . ' <Cmd>call gnosis#listnav#option("relation", "' . l:kind . '")<CR>'
  endfor
  nnoremap <buffer><silent> \l <Cmd>call gnosis#mview#link_pick()<CR>
  nnoremap <buffer><silent> \o <Cmd>call gnosis#panel#key('outline')<CR>
  nnoremap <buffer><silent> \W <Cmd>call gnosis#mview#only_note()<CR>
  nnoremap <buffer><silent> \c <Cmd>call gnosis#open_web()<CR>
  nnoremap <buffer><silent> \C <Cmd>call gnosis#run#switch('cui')<CR>
  nnoremap <buffer><silent> \x <Cmd>call gnosis#run#close_here()<CR>
  nnoremap <buffer><silent> \X <Cmd>call gnosis#run#close_all()<CR>
  augroup gnosis_list_buf
    autocmd! * <buffer>
    autocmd CursorMoved <buffer> call gnosis#listnav#moved()
  augroup END
  let s:L.lines = []
endfunction

function! s:rows() abort
  let l:key = string([s:L.mode, s:L.scope, s:L.search, s:L.depth, s:L.rank])
  if len(s:L.cache) > 16 | let s:L.cache = {} | endif
  if !has_key(s:L.cache, l:key)
    let s:L.cache[l:key] = s:L.mode ==# 'search'
          \ ? gnosis#listnav#search_rows(s:L.root, s:L.search, s:L.scope)
          \ : gnosis#mview#list_data(s:L.anchor, s:L.depth, s:L.rank, s:L.mode ==# 'similar')
  endif
  let l:rows = copy(s:L.cache[l:key])
  if !empty(s:L.relation) && s:L.mode ==# 'links'
    call filter(l:rows, 'index(get(v:val, "relations", [v:val.kind]), s:L.relation) >= 0')
  endif
  if !empty(s:L.filter)
    let l:paths = s:paths(s:L.filter)
    call filter(l:rows, 'has_key(l:paths, v:val.path) || gnosis#query#match(s:L.filter, v:val.title)')
  endif
  return l:rows
endfunction

" Enter などで開いているノート（曼荼羅の中心）が変わったら、リストの基準も今のノートに合わせる。
" カーソルを動かしただけのプレビューでは中心は変わらないので、基準は固定のまま。
function! s:follow_center() abort
  let l:center = get(gnosis#mview#state(), 'center', '')
  if empty(l:center) || get(s:L, 'seen', '') ==# l:center | return | endif
  let s:L.seen = l:center
  if s:L.anchor ==# l:center | return | endif
  let s:L.anchor = l:center
  let s:L.history = []
  let s:L.cache = {}
  let s:L.pathcache = {}
  let s:L.rows = []
  let s:L.origin = s:save_origin()
endfunction

function! gnosis#listnav#render() abort
  if empty(s:L) | return | endif
  call s:follow_center()
  let l:oldrow = get(s:L.rows, line('.') - 3, {})
  let s:L.rows = s:rows()
  let l:title = gnosis#i18n#tr({'search': '検索', 'similar': '類似', 'links': 'リンク'}[s:L.mode])
  let s:L.title = 'LIST / ' . l:title
  let l:pick = gnosis#mview#pick_label()
  if !empty(l:pick) | let s:L.title .= '  ' . l:pick | endif
  let l:flags = s:L.mode ==# 'search' ? gnosis#i18n#tr({'all': '全部', 'index': '索引とグループ', 'no-index': '索引以外'}[s:L.scope])
        \ : s:L.mode ==# 'similar' ? gnosis#i18n#tr('類似')
        \ : gnosis#i18n#tr('深さ') . ' ' . s:L.depth . (s:L.rank ? ' / w' : '')
  if !empty(s:L.relation) && s:L.mode ==# 'links' | let l:flags .= ' / ' . gnosis#i18n#tr(s:kinds[s:L.relation]) | endif
  if !empty(s:L.search) && s:L.mode ==# 'search' | let l:flags .= ' / s: ' . s:L.search | endif
  if !empty(s:L.filter) | let l:flags .= ' / x: ' . s:L.filter | endif
  if !empty(s:L.highlight) | let l:flags .= ' / m: ' . s:L.highlight | endif
  let s:L.status = l:flags . ' / ' . len(s:L.rows) . (len(s:L.rows) >= 300 && s:L.mode ==# 'links' ? ' (max 300)' : '')
  let l:lines = [s:L.title, s:L.status]
  let l:want = 3
  let l:i = 0
  for l:row in s:L.rows
    let l:tag = gnosis#i18n#tr(get(s:kinds, !empty(s:L.relation) && s:L.mode ==# 'links' ? s:L.relation : l:row.kind, 'ノート'))
    let l:tail = get(l:row, 'depth', 0) > 1 ? '  ← ' . get(l:row, 'viaTitle', l:row.via) : ''
    if !empty(get(l:row, 'why', '')) | let l:tail .= '  ' . l:row.why | endif
    call add(l:lines, '  ' . (l:row.depth > 0 ? l:row.depth . ' ' : '') . '[' . l:tag . '] ' . l:row.title . l:tail)
    if get(l:oldrow, 'path', '') ==# l:row.path && get(l:oldrow, 'title', '') ==# l:row.title | let l:want = l:i + 3 | endif
    let l:i += 1
  endfor
  if empty(s:L.rows) | call add(l:lines, '  ' . gnosis#i18n#tr('該当なし')) | endif
  let s:L.hits = empty(s:L.highlight) ? {} : s:paths(s:L.highlight)
  let l:save = winsaveview()
  let l:old = getline(1, '$')
  setlocal modifiable
  for l:i in range(len(l:lines))
    if get(l:old, l:i, '') !=# l:lines[l:i] | call setline(l:i + 1, l:lines[l:i]) | endif
  endfor
  if line('$') > len(l:lines) | execute (len(l:lines) + 1) . ',$delete _' | endif
  setlocal nomodifiable nomodified
  let s:L.lines = l:lines
  call winrestview(l:save)
  call cursor(min([len(l:lines), l:want]), 1)
  let s:L.lastpos = getpos('.')[1:2]
  call gnosis#listnav#paint(s:L.highlight, ['', ''] + map(copy(s:L.rows), 'v:val.path'), s:L.hits)
  call gnosis#listnav#mark()
  call gnosis#mview#sync_leader()
endfunction

function! gnosis#listnav#paint(query, ...) abort
  highlight default GnosisNavMatch term=reverse cterm=reverse gui=reverse
  if empty(prop_type_get('gnosis_nav_match'))
    call prop_type_add('gnosis_nav_match', {'highlight': 'GnosisNavMatch', 'combine': v:true})
  endif
  silent! call prop_remove({'type': 'gnosis_nav_match', 'all': 1}, 1, line('$'))
  for l:ln in range(3, line('$'))
    let l:text = getline(l:ln)
    let l:hay = gnosis#query#normalize(l:text)
    let l:spans = 0
    for l:term in gnosis#query#terms(a:query)
      let l:start = 0
      while l:start < strlen(l:hay)
        let l:m = matchstrpos(l:hay, '\V' . escape(gnosis#query#normalize(l:term), '\'), l:start)
        if l:m[1] < 0 | break | endif
        let l:first = byteidx(l:text, charidx(l:hay, l:m[1]))
        let l:last = l:m[2] >= strlen(l:hay) ? strlen(l:text) : byteidx(l:text, charidx(l:hay, l:m[2]))
        call prop_add(l:ln, l:first + 1, {'type': 'gnosis_nav_match', 'length': l:last - l:first})
        let l:spans += 1
        let l:start = l:m[2]
      endwhile
    endfor
    if l:spans == 0 && a:0 >= 2 && has_key(a:2, get(a:1, l:ln - 1, '')) && !empty(l:text)
      call prop_add(l:ln, 1, {'type': 'gnosis_nav_match', 'length': strlen(l:text)})
    endif
  endfor
endfunction

function! gnosis#listnav#mark() abort
  if exists('w:mview_match')
    for l:m in w:mview_match | silent! call matchdelete(l:m) | endfor
  endif
  let w:mview_match = []
  if line('.') >= 3 && !empty(get(s:L, 'rows', [])) && get(gnosis#mview#state(), 'focus', 1)
    call add(w:mview_match, matchaddpos('Visual', [line('.')], 10))
  endif
  if exists('*GnosisGuiChanged') | call GnosisGuiChanged() | endif
endfunction

function! gnosis#listnav#moved() abort
  if gnosis#mview#view() !=# 'list' || empty(s:L) | return | endif
  if !empty(s:L.rows) && line('.') < 3 | call cursor(3, 1) | endif
  if get(s:L, 'lastpos', []) ==# getpos('.')[1:2] | return | endif
  let s:L.lastpos = getpos('.')[1:2]
  call gnosis#listnav#mark()
  if s:timer >= 0 | call timer_stop(s:timer) | endif
  let s:timer = timer_start(60, function('s:preview'))
endfunction

" 行 L を窓の一番上に出す。`normal! zt` は、feedkeys で積まれて残ったキー（起動時の nohlsearch など）まで
" 実行してしまい、n が前回の検索（E486）になることがあるので使わない。
function! s:top_line(win, lnum) abort
  call win_execute(a:win, 'keepjumps call winrestview({"lnum": ' . a:lnum . ', "col": 0, "topline": ' . a:lnum . '})')
endfunction

function! s:preview(timer) abort
  let s:timer = -1
  let l:st = gnosis#mview#state()
  if gnosis#mview#view() !=# 'list' || win_getid() != get(l:st, 'win', -1) | return | endif
  let l:row = get(s:L.rows, line('.') - 3, {})
  if empty(l:row) | return | endif
  call gnosis#mview#preview_rel(l:row.path)
  let l:nw = gnosis#mview#note_win()
  if l:nw > 0 && get(l:row, 'line', 0) > 0
    call s:top_line(l:nw, l:row.line)
  endif
endfunction

function! gnosis#listnav#move(d) abort
  if empty(s:L.rows) | return | endif
  call cursor(max([3, min([len(s:L.rows) + 2, line('.') + a:d * v:count1])]), 1)
  call gnosis#listnav#moved()
endfunction

function! gnosis#listnav#edge(last) abort
  call cursor(a:last ? len(s:L.rows) + 2 : 3, 1)
  call gnosis#listnav#moved()
endfunction

function! gnosis#listnav#enter() abort
  let l:row = get(s:L.rows, line('.') - 3, {})
  if empty(l:row) | return | endif
  if s:timer >= 0 | call timer_stop(s:timer) | let s:timer = -1 | endif
  call gnosis#mview#open_rel(l:row.path)
  if !gnosis#mview#picking()
    call gnosis#mview#toggle()
    if get(l:row, 'line', 0) > 0 | call s:top_line(win_getid(), l:row.line) | endif
    let s:L.origin = s:save_origin()
  endif
endfunction

function! s:snapshot() abort
  let l:snap = {}
  for l:key in ['mode', 'scope', 'search', 'filter', 'highlight', 'relation', 'depth', 'rank'] | let l:snap[l:key] = s:L[l:key] | endfor
  let l:snap.view = winsaveview()
  return l:snap
endfunction

function! gnosis#listnav#option(key, value) abort
  if s:L[a:key] ==# a:value | return | endif
  call add(s:L.history, s:snapshot())
  let s:L[a:key] = a:value
  call s:save_preferences()
  call gnosis#listnav#render()
endfunction

function! gnosis#listnav#back() abort
  if empty(s:L.history) | call gnosis#listnav#origin() | return | endif
  let l:old = remove(s:L.history, -1)
  let l:view = remove(l:old, 'view')
  call extend(s:L, l:old)
  call s:save_preferences()
  call gnosis#listnav#render()
  call winrestview(l:view)
endfunction

function! gnosis#listnav#origin() abort
  if s:timer >= 0 | call timer_stop(s:timer) | let s:timer = -1 | endif
  call gnosis#mview#preview_rel(s:L.origin.path)
  let l:nw = gnosis#mview#note_win()
  if l:nw > 0 && !empty(s:L.origin.view)
    call win_execute(l:nw, 'call winrestview(' . string(s:L.origin.view) . ')')
  endif
endfunction

" 下の入力欄で検索する。結果は同じビューへ描く（ポップアップは作らない）。Esc は元の条件へ戻す。
function! gnosis#listnav#input(label, initial, Callback) abort
  let l:text = a:initial
  let l:was_input = get(b:, 'gnosis_nav_input', 0)
  let b:gnosis_nav_input = 1
  try
  while 1
    redraw!
    echo a:label . l:text . '▏'
    if exists('g:gnosis_test_keys') && type(g:gnosis_test_keys) == v:t_list && !empty(g:gnosis_test_keys)
      let l:key = remove(g:gnosis_test_keys, 0)
    else
      let l:key = gnosis#ui#getcharstr()
    endif
    if l:key ==# "\<CR>" | redraw! | echo '' | return 1 | endif
    if index(["\<Esc>", "\<C-c>"], l:key) >= 0
      silent call a:Callback(a:initial)
      echo ''
      return 0
    endif
    if l:key ==# "\<BS>" || l:key ==# "\<C-h>" || l:key ==# "\<Del>"
      let l:text = strcharpart(l:text, 0, max([0, strchars(l:text) - 1]))
    elseif l:key ==# "\<C-u>"
      let l:text = ''
    elseif strchars(l:key) == 1 && char2nr(l:key) >= 32
      let l:text .= l:key
    else
      continue
    endif
    silent call a:Callback(l:text)
    redraw
  endwhile
  finally
    let b:gnosis_nav_input = l:was_input
  endtry
endfunction

function! gnosis#listnav#query(op, text) abort
  let s:L[a:op] = a:text
  call gnosis#listnav#render()
endfunction

function! gnosis#listnav#prompt(op) abort
  let l:old = s:snapshot()
  if a:op ==# 'search' | let s:L.mode = 'search' | endif
  call gnosis#listnav#render()
  let l:label = gnosis#i18n#tr({'search': '検索', 'filter': '絞り込み', 'highlight': 'ハイライト'}[a:op]) . ': '
  if gnosis#listnav#input(l:label, s:L[a:op], function('gnosis#listnav#query', [a:op]))
    call add(s:L.history, l:old)
    call s:save_preferences()
  else
    call extend(s:L, l:old)
    call remove(s:L, 'view')
    call gnosis#listnav#render()
    call winrestview(l:old.view)
  endif
endfunction

function! gnosis#listnav#scope() abort
  let l:scopes = ['all', 'index', 'no-index']
  call gnosis#listnav#option('scope', l:scopes[(index(l:scopes, s:L.scope) + 1) % 3])
endfunction

function! s:depth_changed(text) abort
  if a:text =~# '^\d\+$'
    let s:L.depth = max([1, min([10, str2nr(a:text)])])
    call gnosis#listnav#render()
  endif
endfunction

function! gnosis#listnav#depth() abort
  let l:old = s:snapshot()
  if gnosis#listnav#input(gnosis#i18n#tr('深さ') . ': ', string(s:L.depth), function('s:depth_changed'))
    call add(s:L.history, l:old)
    call s:save_preferences()
  else
    let s:L.depth = l:old.depth
    call gnosis#listnav#render()
  endif
endfunction

function! gnosis#listnav#next_hit(dir) abort
  if empty(s:L.rows) || empty(s:L.highlight) | return | endif
  let l:cur = line('.') - 3
  for l:n in range(1, len(s:L.rows))
    let l:i = (l:cur + a:dir * l:n + len(s:L.rows)) % len(s:L.rows)
    if has_key(s:L.hits, s:L.rows[l:i].path) || gnosis#query#match(s:L.highlight, s:L.rows[l:i].title)
      call cursor(l:i + 3, 1)
      call gnosis#listnav#moved()
      return
    endif
  endfor
endfunction

function! gnosis#listnav#quit() abort
  call gnosis#listnav#origin()
  call gnosis#mview#quit_layers()
endfunction

function! gnosis#listnav#decide(index) abort
  let l:row = get(s:L.rows, line('.') - 3, {})
  if !empty(l:row) && gnosis#mview#picking() | call gnosis#mview#fz_decide(l:row.path, a:index) | endif
endfunction

function! gnosis#listnav#help() abort
  echo 'LIST: 1 ' . gnosis#i18n#tr('検索') . '  2 ' . gnosis#i18n#tr('類似') . '  3 ' . gnosis#i18n#tr('リンク')
        \ . ' | s/x/m  n/N  S  +  w  b/p/g/c/r/a  o  Backspace  Enter  Ctrl+←/→'
endfunction

function! gnosis#listnav#gui_state() abort
  let l:st = gnosis#mview#state()
  let l:wi = getwininfo(get(l:st, 'win', -1))
  if empty(l:wi) || empty(s:L) | return {} | endif
  let l:cur = getcurpos(l:st.win)[1]
  let l:cells = []
  for l:n in range(l:wi[0].topline, min([len(s:L.lines), l:wi[0].topline + l:wi[0].height - 1]))
    let l:r = get(s:L.rows, l:n - 3, {})
    if l:n < 3
      call add(l:cells, {'k': 'h', 't': s:L.lines[l:n - 1], 'ln': l:n})
    elseif empty(l:r)
      call add(l:cells, {'k': 'h', 't': gnosis#i18n#tr('該当なし'), 'ln': l:n})
    else
      call add(l:cells, {'k': l:r.kind ==# 'group' ? 'g' : 'n', 't': l:r.title,
            \ 'n': l:r.depth > 0 ? string(l:r.depth) : '', 'id': l:r.path, 'ln': l:n,
            \ 'c': '  [' . gnosis#i18n#tr(get(s:kinds, l:r.kind, 'ノート')) . ']' . (l:r.depth > 1 ? ' ← ' . get(l:r, 'viaTitle', l:r.via) : ''),
            \ 'sel': l:n == l:cur, 'hit': has_key(s:L.hits, l:r.path)})
    endif
  endfor
  return {'view': 'list', 'title': s:L.title, 'status': s:L.status, 'mode': s:L.mode, 'lines': l:cells,
        \ 'top': l:wi[0].topline, 'height': l:wi[0].height, 'total': len(s:L.lines), 'cursor': l:cur, 'numw': 2,
        \ 'detail': get(get(s:L.rows, l:cur - 3, {}), 'path', ''), 'win': l:st.win,
        \ 'noteWin': gnosis#mview#note_win(), 'wcols': winwidth(l:st.win), 'legend': 0}
endfunction

function! gnosis#listnav#gui_click(lnum, enter) abort
  if gnosis#mview#view() !=# 'list' || a:lnum < 3 || a:lnum > len(s:L.rows) + 2 | return | endif
  call win_gotoid(gnosis#mview#state().win)
  call cursor(a:lnum, 1)
  let s:L.lastpos = []
  call gnosis#listnav#moved()
  if a:enter | call gnosis#listnav#enter() | endif
endfunction

function! gnosis#listnav#gui_scroll(n) abort
  let l:st = gnosis#mview#state()
  if gnosis#mview#view() !=# 'list' || empty(getwininfo(get(l:st, 'win', -1))) | return | endif
  call win_execute(l:st.win, 'normal! ' . repeat(a:n > 0 ? "\<C-e>" : "\<C-y>", abs(a:n)))
  if exists('*GnosisGuiChanged') | call GnosisGuiChanged() | endif
endfunction

function! gnosis#listnav#invalidate() abort
  if !empty(s:L) | let s:L.cache = {} | let s:L.pathcache = {} | endif
endfunction

function! gnosis#listnav#teardown() abort
  if s:timer >= 0 | call timer_stop(s:timer) | let s:timer = -1 | endif
  augroup gnosis_list_buf
    autocmd! * <buffer>
  augroup END
  silent! call prop_clear(1, line('$'))
endfunction

function! gnosis#listnav#reset() abort
  if s:timer >= 0 | call timer_stop(s:timer) | let s:timer = -1 | endif
  let s:L = {}
endfunction

function! gnosis#listnav#state() abort
  return s:L
endfunction


function! s:save_preferences() abort
  let l:prefs = {}
  for l:k in ['mode', 'scope', 'depth', 'rank', 'relation'] | let l:prefs[l:k] = s:L[l:k] | endfor
  call gnosis#home#write_json(gnosis#home#path('listnav.json'), l:prefs)
endfunction

function! s:load_preferences() abort
  if !get(g:, 'gnosis_mview_restore', 1) | return | endif
  let l:d = gnosis#home#read_json(gnosis#home#path('listnav.json'), {})
  for [l:k, l:allowed] in items({'mode': ['links', 'search', 'similar'], 'scope': ['all', 'index', 'no-index'],
        \ 'relation': [''] + keys(s:kinds)})
    if index(l:allowed, get(l:d, l:k, v:null)) >= 0 | let s:L[l:k] = l:d[l:k] | endif
  endfor
  if type(get(l:d, 'depth', '')) == v:t_number | let s:L.depth = max([1, min([10, l:d.depth])]) | endif
  if type(get(l:d, 'rank', '')) == v:t_number | let s:L.rank = !!l:d.rank | endif
endfunction

function! gnosis#listnav#handoff() abort
  if empty(s:L) | return {} | endif
  let l:d = s:snapshot()
  for l:k in ['root', 'anchor', 'origin', 'history'] | let l:d[l:k] = deepcopy(s:L[l:k]) | endfor
  return l:d
endfunction

function! gnosis#listnav#restore(d) abort
  if empty(a:d) || get(a:d, 'root', '') !=# get(s:L, 'root', '') | return | endif
  for l:k in ['mode', 'scope', 'search', 'filter', 'highlight', 'relation', 'depth', 'rank', 'anchor', 'origin', 'history']
    if has_key(a:d, l:k) | let s:L[l:k] = deepcopy(a:d[l:k]) | endif
  endfor
  let s:L.cache = {}
  let s:L.pathcache = {}
  call gnosis#listnav#render()
  if has_key(a:d, 'view') | call winrestview(a:d.view) | let s:L.lastpos = getpos('.')[1:2] | endif
endfunction
