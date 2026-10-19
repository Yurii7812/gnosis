" High contrast dedicated statusline with a visible mode badge.
function! gnosis#ui#statusline() abort
  let l:m = mode(1)
  if l:m =~# '^[i]'
    let l:kind = 'Insert'
    let l:label = ' INSERT '
  elseif l:m =~# '^[Rr]'
    let l:kind = 'Replace'
    let l:label = ' REPLACE '
  elseif l:m =~# '^[vV]' || l:m ==# "\<C-v>"
    let l:kind = 'Visual'
    let l:label = ' VISUAL '
  else
    let l:kind = 'Normal'
    let l:label = ' NORMAL '
  endif
  " 時刻モード（\T）のときは、Enter で時刻が入ることが分かるように表示する
  let l:time = get(b:, 'gnosis_time_mode', 0) ? '%#GnosisModeInsert# 時刻 ' : ''
  return '%#GnosisMode' . l:kind . '#' . l:label . l:time
        \ . '%#StatusLine#  %f %m%r%=%l:%c  %p%% '
endfunction

" ---------------------------------------------------------------------------
" 矢印キーで選べる一覧（inputlist の代わり）
"
" Vim 標準の inputlist() は番号を打つだけで、↑ ↓ で選べない。同じ呼び方（先頭は見出し、
" 戻り値は選んだ項目の番号（1 始まり）・取り消しは 0）で、↑ ↓（j k・Ctrl-N / Ctrl-P）で動かし、
" Enter（Space）で決め、Esc（q）で取り消し、番号キーでも選べるようにしたもの。
" ポップアップが使えない Vim では inputlist をそのまま使う。
" g:gnosis_ui_keys（キーのリスト）があれば、そこから読む（試験用）。
" ---------------------------------------------------------------------------
function! gnosis#ui#getkey() abort
  if exists('g:gnosis_ui_keys') && !empty(g:gnosis_ui_keys)
    return remove(g:gnosis_ui_keys, 0)
  endif
  try
    return getcharstr()
  catch /^Vim:Interrupt$/
    return "\<Esc>"
  endtry
endfunction

function! gnosis#ui#inputlist(lines) abort
  if empty(a:lines)
    return 0
  endif
  let l:items = a:lines[1:]
  if empty(l:items)
    return 0
  endif
  if !exists('*popup_create') || !has('timers')
    return inputlist(a:lines)
  endif
  let l:n = len(l:items)
  let l:sel = 0
  let l:num = ''
  let l:id = popup_create(l:items, {
        \ 'title': ' ' . substitute(a:lines[0], '\s\+$', '', '') . ' ',
        \ 'pos': 'center', 'minwidth': 40, 'maxheight': max([5, &lines - 10]),
        \ 'padding': [0, 1, 0, 1], 'border': [1, 1, 1, 1],
        \ 'highlight': 'Pmenu', 'cursorline': 1, 'wrap': 0, 'zindex': 300,
        \ 'mapping': 0})
  let l:result = 0
  try
    while 1
      call win_execute(l:id, 'call cursor(' . (l:sel + 1) . ', 1)')
      redraw
      let l:k = gnosis#ui#getkey()
      if l:k ==# "\<Down>" || l:k ==# 'j' || l:k ==# "\<C-n>"
        let l:sel = min([l:sel + 1, l:n - 1])
        let l:num = ''
      elseif l:k ==# "\<Up>" || l:k ==# 'k' || l:k ==# "\<C-p>"
        let l:sel = max([l:sel - 1, 0])
        let l:num = ''
      elseif l:k ==# "\<Home>" || l:k ==# 'g'
        let l:sel = 0
      elseif l:k ==# "\<End>" || l:k ==# 'G'
        let l:sel = l:n - 1
      elseif l:k ==# "\<PageDown>"
        let l:sel = min([l:sel + 8, l:n - 1])
      elseif l:k ==# "\<PageUp>"
        let l:sel = max([l:sel - 8, 0])
      elseif l:k ==# "\<CR>" || l:k ==# "\<NL>" || l:k ==# ' '
        let l:result = empty(l:num) ? l:sel + 1 : (str2nr(l:num) >= 1 && str2nr(l:num) <= l:n ? str2nr(l:num) : 0)
        break
      elseif l:k ==# "\<Esc>" || l:k ==# 'q' || l:k ==# "\<C-c>"
        let l:result = 0
        break
      elseif l:k =~# '^\d$'
        let l:num .= l:k
        if l:n < 10 && str2nr(l:num) >= 1 && str2nr(l:num) <= l:n
          let l:result = str2nr(l:num)
          break
        elseif str2nr(l:num) >= 1 && str2nr(l:num) <= l:n
          let l:sel = str2nr(l:num) - 1
        endif
      endif
    endwhile
  finally
    call popup_close(l:id)
    redraw
  endtry
  return l:result
endfunction
