" ノートの画像をポップアップで見る（gz）。
"   ノートにある画像の一覧（popup_menu）→ Enter で端末に sixel で重ねて表示 → q で一覧に戻る → もう一度 q で閉じる。
"   キーボードだけで動く。閉じたあとは redraw! で画像を消し、カーソルは元のまま Vim にある。
"   sixel に対応しない端末では、外部のビューア（xdg-open など）で開く。
"   g:gnosis_image_viewer = 'auto' | 'sixel' | 'external'。
"   Python 側: python/sixel_view.py

let s:root = expand('<sfile>:p:h:h:h')
let s:esc = "\<Esc>"

function! s:py(args) abort
  let l:cmd = gnosis#python_cmd() . ' ' . shellescape(s:root . '/python/sixel_view.py')
        \ . ' ' . join(map(copy(a:args), 'shellescape(v:val)'), ' ') . ' 2>/dev/null'
  return system(l:cmd)
endfunction

" 今の端末に sixel で出せるか
function! s:sixel_ok() abort
  let l:mode = get(g:, 'gnosis_image_viewer', 'auto')
  if l:mode ==# 'sixel' | return 1 | endif
  if l:mode ==# 'external' | return 0 | endif
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
    let l:k = getcharstr()
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
  return popup_filter_menu(a:id, a:key)
endfunction

function! s:menu_done(id, result) abort
  if a:result < 1 || a:result > len(s:menu_items)
    return
  endif
  let l:items = s:menu_items
  let l:i = s:view(l:items, a:result - 1)
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
  if !s:sixel_ok()
    for l:it in filter(copy(l:items), 'v:val.exists')
      call job_start(['xdg-open', l:it.path], {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
      break
    endfor
    echo 'この端末は sixel 非対応のため、外部のビューアで開きました'
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
    call s:view(l:items, 0)
    return
  endif
  call s:menu(l:items, l:sel)
endfunction
