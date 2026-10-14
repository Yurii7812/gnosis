" Gnosis work tabs: transient workspaces, independent from the persistent \h hub.
" Per-vault state is saved in .state; closing a tab never removes a Markdown note.
let s:root_cache = ''
let s:tabs = []
let s:active = -1
let s:armed = 0
let s:switching = 0
let s:popup = 0
let s:selection = 0
let s:query = ''

function! s:root() abort
  let l:root = get(g:, 'gnosis_root', '')
  if empty(l:root) || !isdirectory(l:root)
    return ''
  endif
  return substitute(fnamemodify(l:root, ':p'), '/\+$', '', '')
endfunction

function! s:eligible(path) abort
  let l:root = s:root()
  let l:path = fnamemodify(a:path, ':p')
  return !empty(l:root) && stridx(l:path, l:root . '/') == 0
        \ && l:path =~# '\.md$'
        \ && l:path !~# '/\.\%(state\|trash\|undo\|gnosis\)/'
        \ && filereadable(l:path)
endfunction

function! s:file() abort
  return s:root() . '/.state/work-tabs.json'
endfunction

function! s:load() abort
  let l:root = s:root()
  if empty(l:root) || s:root_cache ==# l:root
    return
  endif
  let s:root_cache = l:root
  let s:tabs = []
  let s:active = -1
  let s:armed = 0
  let l:path = s:file()
  if !filereadable(l:path)
    return
  endif
  try
    let l:data = json_decode(join(readfile(l:path), "\n"))
    let l:items = get(l:data, 'tabs', [])
    if type(l:items) == v:t_list
      for l:item in l:items
        if type(l:item) == v:t_dict && s:eligible(get(l:item, 'file', ''))
          call add(s:tabs, {
                \ 'file': fnamemodify(l:item.file, ':p'),
                \ 'back': get(l:item, 'back', []),
                \ 'forward': get(l:item, 'forward', [])})
        endif
      endfor
    endif
    if !empty(s:tabs)
      let s:active = min([len(s:tabs)-1, max([0, get(l:data, 'active', 0)])])
    endif
  catch
    " Invalid older state must not block the editor. Keep it on disk.
  endtry
endfunction

function! s:save() abort
  let l:root = s:root()
  if empty(l:root) || !isdirectory(l:root)
    return
  endif
  let l:dir = l:root . '/.state'
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  let l:path = s:file()
  let l:tmp = l:path . '.' . getpid() . '.tmp'
  try
    call writefile([json_encode({'version': 1, 'tabs': s:tabs, 'active': s:active})], l:tmp)
    if rename(l:tmp, l:path) != 0
      call delete(l:tmp)
    endif
  catch
    silent! call delete(l:tmp)
  endtry
endfunction

function! s:remember() abort
  if s:active >= 0 && s:active < len(s:tabs)
    let s:tabs[s:active].back = deepcopy(get(g:, 'gnosis_history', []))
    let s:tabs[s:active].forward = deepcopy(get(g:, 'gnosis_forward', []))
  endif
endfunction

function! s:ensure() abort
  call s:load()
  let l:first = !s:armed
  let s:armed = 1
  if l:first && s:active < 0 && s:eligible(expand('%:p'))
    call add(s:tabs, {'file': expand('%:p'), 'back': [], 'forward': []})
    let s:active = 0
    call s:save()
  endif
endfunction

" Any ordinary link navigation updates the current logical tab, not a new tab.
function! gnosis#tabs#on_enter() abort
  call s:load()
  if !s:armed || s:switching || s:active < 0 || !s:eligible(expand('%:p'))
    return
  endif
  let s:tabs[s:active].file = expand('%:p')
  call s:remember()
  call s:save()
endfunction

function! s:flush() abort
  if &buftype ==# '' && &modified
    try
      silent update
    catch
      echohl WarningMsg | echom 'Gnosis tabs: 保存できないため切り替えを中止しました' | echohl None
      return 0
    endtry
    if &modified
      echom 'Gnosis tabs: unsaved changes; tab switch cancelled'
      return 0
    endif
  endif
  return 1
endfunction

function! s:switch(idx) abort
  if a:idx < 0 || a:idx >= len(s:tabs) || !filereadable(s:tabs[a:idx].file)
    return 0
  endif
  if !s:flush() | return 0 | endif
  call s:remember()
  let s:switching = 1
  try
    let s:active = a:idx
    let g:gnosis_history = deepcopy(get(s:tabs[a:idx], 'back', []))
    let g:gnosis_forward = deepcopy(get(s:tabs[a:idx], 'forward', []))
    execute 'hide edit ' . fnameescape(s:tabs[a:idx].file)
    call s:save()
  finally
    let s:switching = 0
  endtry
  return 1
endfunction

" <Enter> switches within the current tab; \o deliberately creates another.
function! gnosis#tabs#open_link() abort
  call s:ensure()
  let l:link = gnosis#get_link_under_cursor()
  if empty(l:link) || empty(get(l:link, 'target', ''))
    echom 'Gnosis: cursor is not on a Markdown link'
    return
  endif
  let l:old = expand('%:p')
  let l:old_active = s:active
  if !s:flush() | return | endif
  call s:remember()
  " Reuse the existing navigation resolver, including anchors and validation.
  let s:switching = 1
  try
    call gnosis#open_link_under_cursor()
    let l:now = expand('%:p')
    if l:now ==# l:old || !s:eligible(l:now)
      return
    endif
    call add(s:tabs, {'file': l:now, 'back': [], 'forward': []})
    let s:active = len(s:tabs) - 1
    let g:gnosis_history = []
    let g:gnosis_forward = []
    call s:save()
  finally
    let s:switching = 0
  endtry
endfunction

function! s:indices() abort
  let l:out = []
  for l:i in range(len(s:tabs))
    if empty(s:query) || stridx(tolower(fnamemodify(s:tabs[l:i].file, ':t:r')), tolower(s:query)) >= 0
      call add(l:out, l:i)
    endif
  endfor
  return l:out
endfunction

function! s:render() abort
  let l:idx = s:indices()
  let l:lines = [' Gnosis | Work Tabs      / search: ' . (empty(s:query) ? '(all)' : s:query), '']
  if empty(l:idx)
    call add(l:lines, '  (no matching tabs)  a: add current note')
  else
    let s:selection = min([s:selection, len(l:idx)-1])
    for l:j in range(len(l:idx))
      let l:i = l:idx[l:j]
      let l:cur = l:i == s:active ? '  *' : '   '
      let l:point = l:j == s:selection ? '>' : ' '
      call add(l:lines, printf('%s%s %2d  %s', l:point, l:cur, l:i + 1, fnamemodify(s:tabs[l:i].file, ':t:r')))
    endfor
  endif
  call extend(l:lines, ['', ' j/k move   Enter switch   a add   x close', ' X close others   C close all   / filter   q quit'])
  if s:popup > 0
    call popup_settext(s:popup, l:lines)
  endif
  return l:lines
endfunction

function! gnosis#tabs#popup() abort
  if !exists('*popup_create')
    echoerr 'Gnosis: this Vim requires +popupwin'
    return
  endif
  call s:ensure()
  let s:selection = max([0, s:active])
  let s:query = ''
  let l:lines = s:render()
  let s:popup = popup_create(l:lines, {
        \ 'title': ' Work Tabs ',
        \ 'pos': 'center', 'minwidth': 58, 'maxheight': 22,
        \ 'padding': [1, 2, 1, 2],
        \ 'border': [1, 1, 1, 1], 'borderchars': ['-', '|', '-', '|', '+', '+', '+', '+'],
        \ 'highlight': 'Pmenu', 'filter': function('gnosis#tabs#filter'),
        \ 'mapping': 0, 'zindex': 200})
endfunction

function! s:close_selection(which) abort
  let l:indices = s:indices()
  if empty(l:indices) | return | endif
  let l:target = l:indices[min([s:selection, len(l:indices) - 1])]
  if a:which ==# 'others'
    let l:keep = s:active >= 0 ? s:active : l:target
    let s:tabs = [s:tabs[l:keep]]
    let s:active = 0
  elseif a:which ==# 'all'
    if !s:flush() | return | endif
    let s:tabs = []
    let s:active = -1
  else
    if l:target == s:active && !s:flush() | return | endif
    call remove(s:tabs, l:target)
    if empty(s:tabs)
      let s:active = -1
    elseif l:target < s:active
      let s:active -= 1
    elseif l:target == s:active
      " Capture the remaining tab's own history, not the closed tab's history.
      let s:active = min([l:target, len(s:tabs)-1])
      let s:switching = 1
      try
        let g:gnosis_history = deepcopy(get(s:tabs[s:active], 'back', []))
        let g:gnosis_forward = deepcopy(get(s:tabs[s:active], 'forward', []))
        execute 'hide edit ' . fnameescape(s:tabs[s:active].file)
      finally
        let s:switching = 0
      endtry
    endif
  endif
  let s:selection = 0
  call s:save()
endfunction

function! gnosis#tabs#filter(winid, key) abort
  if a:key ==# 'q' || a:key ==# "\<Esc>"
    call popup_close(a:winid)
    let s:popup = 0
    return 1
  endif
  let l:idx = s:indices()
  if a:key ==# 'j' || a:key ==# "\<Down>"
    let s:selection = min([max([0, len(l:idx)-1]), s:selection+1])
  elseif a:key ==# 'k' || a:key ==# "\<Up>"
    let s:selection = max([0, s:selection-1])
  elseif a:key ==# "\<CR>" || a:key ==# "\<NL>"
    if !empty(l:idx)
      if s:switch(l:idx[s:selection])
        call popup_close(a:winid)
        let s:popup = 0
        return 1
      endif
    endif
  elseif a:key ==# 'a'
    if s:eligible(expand('%:p'))
      call s:remember()
      call add(s:tabs, {'file': expand('%:p'), 'back': [], 'forward': []})
      let s:active = len(s:tabs)-1
      call s:save()
      let s:selection = len(s:tabs)-1
    endif
  elseif a:key ==# 'x'
    call s:close_selection('one')
  elseif a:key ==# 'X'
    call s:close_selection('others')
  elseif a:key ==# 'C'
    call s:close_selection('all')
  elseif a:key ==# '/'
    let s:query = input('Tab name: ')
    let s:selection = 0
  else
    return 1
  endif
  if s:popup > 0
    call s:render()
  endif
  return 1
endfunction

function! gnosis#tabs#snapshot() abort
  call s:ensure()
  return {'tabs': deepcopy(s:tabs), 'active': s:active}
endfunction

" Tests and future API: programmatic navigation without triggering UI.
function! gnosis#tabs#select(idx) abort
  call s:ensure()
  return s:switch(a:idx)
endfunction
