" Navigation by YAML Folgezettel ID. Never renumber notes during navigation.
let s:script = fnamemodify(expand('<sfile>:p:h:h:h') . '/python/folgezettel.py', ':p')
let s:saved = {}

function! gnosis#folgezettel#toggle() abort
  let g:gnosis_folgezettel_move = !get(g:, 'gnosis_folgezettel_move', 0)
  for [l:key, l:dir] in items({'<C-Up>': 'up', '<C-Down>': 'down', '<C-Left>': 'left', '<C-Right>': 'right'})
    if g:gnosis_folgezettel_move
      let l:global = filter(maplist(), 'v:val.lhs ==# l:key && !v:val.buffer && v:val.mode =~# "[n ]"')
      let s:saved[l:key] = get(l:global, 0, {})
      execute 'nnoremap <silent> ' . l:key . ' <Cmd>call gnosis#folgezettel#move("' . l:dir . '")<CR>'
    else
      execute 'silent! nunmap ' . l:key
      if !empty(get(s:saved, l:key, {})) && !get(s:saved[l:key], 'buffer', 0)
        call mapset('n', 0, s:saved[l:key])
      endif
    endif
  endfor
  redrawstatus
  echo 'GnosisFolgezettelMove: ' . (g:gnosis_folgezettel_move ? 'ON' : 'OFF')
endfunction

function! gnosis#folgezettel#move(direction) abort
  if !get(g:, 'gnosis_folgezettel_move', 0) | return | endif
  let l:root = get(g:, 'gnosis_root', '')
  if empty(l:root) || !gnosis#is_vault_note(expand('%:p'))
    echo 'Gnosis: vaultのノートを開いてください'
    return
  endif
  call gnosis#save_current_note()
  if &modified | return | endif
  let l:out = system(gnosis#python_cmd() . ' ' . shellescape(s:script)
        \ . ' move ' . shellescape(l:root) . ' ' . shellescape(expand('%:p'))
        \ . ' ' . shellescape(a:direction))
  try
    let l:result = json_decode(trim(l:out))
    if !get(l:result, 'ok', 0)
      echo 'Gnosis: ' . get(l:result, 'error', '移動できませんでした')
      return
    endif
    call gnosis#push_history()
    execute 'edit ' . fnameescape(l:result.path)
    echo 'Folgezettel: ' . l:result.id
  catch
    echohl ErrorMsg | echo 'Gnosis: ' . v:exception | echohl NONE
  endtry
endfunction
