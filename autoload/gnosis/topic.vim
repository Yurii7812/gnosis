" 作成端末に関係なく topic: を使う。\N では行・複数行のリンク先をまとめて移動できる。
function! gnosis#topic#assign(first, last, name) abort
  call gnosis#save_current_note()
  let l:paths = []
  if exists('b:gnosis_topic_list')
    for l:line in getline(a:first, a:last)
      let l:path = matchstr(l:line, ']\zs([^)]\+\.md)\ze\s*$')
      if !empty(l:path)
        call add(l:paths, l:path[1:-2])
      endif
    endfor
  else
    let l:paths = [expand('%:p')]
  endif
  if empty(l:paths) | return | endif
  try
    let l:topic = empty(a:name) ? input(gnosis#i18n#tr('トピック（空欄で未選択）: ')) : a:name
  catch /^Vim:Interrupt$/
    return
  endtry
  let l:topic = trim(l:topic)
  if l:topic ==# '未所属' || l:topic ==# 'トピック未選択' || l:topic ==# 'メモ' | let l:topic = '' | endif
  for l:path in uniq(sort(l:paths))
    if !filereadable(l:path) | continue | endif
    if getbufvar(bufnr(l:path), '&modified')
      echohl WarningMsg | echom 'Gnosis: 未保存の編集があります: ' . l:path | echohl NONE
      continue
    endif
    call gnosis#guard_vault_write(l:path)
    let l:lines = readfile(l:path)
    if get(l:lines, 0, '') !=# '---'
      let l:lines = ['---', 'topic: ' . json_encode(l:topic), '---', ''] + l:lines
    else
      let l:end = index(l:lines, '---', 1)
      if l:end < 0 | continue | endif
      for l:k in reverse(range(1, l:end - 1))
        if l:lines[l:k] =~# '^topic:' | call remove(l:lines, l:k) | endif
      endfor
      call insert(l:lines, 'topic: ' . json_encode(l:topic), 1)
    endif
    call writefile(l:lines, l:path)
    let l:nr = bufnr(l:path)
    if l:nr > 0 | execute 'checktime ' . l:nr | endif
  endfor
  if exists('b:gnosis_topic_list') | call gnosis#orphans_open() | endif
endfunction
