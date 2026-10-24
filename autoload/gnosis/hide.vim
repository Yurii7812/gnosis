" =============================================================================
" autoload/gnosis/hide.vim — ノートで隠すもの（YAML・上の「名前:」系・下の「名前:」系）
"
" 表示だけの変更（折りたたみ）で、ファイルの中身は変わらない。1 行の目印（▸ YAML (6 行) など）を残し、zo で開ける。
" どれを隠すかは vault の設定（.gnosis/settings.json の hide）に保存し、再起動後も、オンにするまで保たれる。
" \c のアプリも同じ Vim なので、同じ設定が効く。
"
"   \zz  … 隠すものの窓（j k で動く・Space か Enter で切り替え・q で閉じる）
" =============================================================================

let s:cache = {}
" 上の「名前:」系: H1 の直後に続く先頭のブロック（find_context_block と同じ規則）
let s:top_heads = ['ParentBranch:', 'BranchGroup:', 'ThisNoteGroup:', 'Group:', 'Context:']
" 下の「名前:」系: 本文のあとに続く関係のブロック
let s:bottom_heads = ['ChildBranch:', 'Related:', 'BackLink:', '### Context', '### Related', '### BackLink', '### ParentBranch', '### ChildBranch']

function! gnosis#hide#get() abort
  try
    let l:h = get(gnosis#settings#current(), 'hide', {})
  catch
    let l:h = {}
  endtry
  return {'yaml': get(l:h, 'yaml', 0) ? 1 : 0, 'top': get(l:h, 'top', 0) ? 1 : 0, 'bottom': get(l:h, 'bottom', 0) ? 1 : 0, 'image': get(l:h, 'image', 0) ? 1 : 0}
endfunction

" ノートの隠す範囲を [{'kind': 'yaml'|'top'|'bottom', 'from': 行, 'to': 行}, …]（1 始まり）で返す
function! gnosis#hide#regions(lines) abort
  let l:n = len(a:lines)
  let l:out = []
  let l:i = 0
  if l:n > 0 && a:lines[0] ==# '---'
    for l:j in range(1, l:n - 1)
      if a:lines[l:j] ==# '---' || a:lines[l:j] ==# '...'
        call add(l:out, {'kind': 'yaml', 'from': 1, 'to': l:j + 1})
        let l:i = l:j + 1
        break
      endif
    endfor
  endif
  " 上のブロック: H1 の直後（間は空行と、上のブロックだけ）
  let l:seen_h1 = 0
  let l:from = 0
  let l:to = 0
  while l:i < l:n
    let l:s = trim(a:lines[l:i])
    if l:s ==# ''
      let l:i += 1
      continue
    endif
    if !l:seen_h1 && a:lines[l:i] =~# '^#\s\+\S'
      let l:seen_h1 = 1
      let l:i += 1
      continue
    endif
    if index(s:top_heads, l:s) >= 0
      if l:from == 0
        let l:from = l:i + 1
      endif
      let l:i += 1
      while l:i < l:n && a:lines[l:i] =~# '^\s*\[.*\](.*)\s*$'
        let l:i += 1
      endwhile
      let l:to = l:i
      continue
    endif
    break
  endwhile
  if l:from > 0
    call add(l:out, {'kind': 'top', 'from': l:from, 'to': l:to})
  endif
  " 下のブロック: 本文のあと、最初の関係の見出しから最後まで（コードブロックの中は見ない）
  let l:fence = 0
  for l:k in range(max([l:i, 0]), l:n - 1)
    if a:lines[l:k] =~# '^\s*\(```\|\~\~\~\)'
      let l:fence = !l:fence
      continue
    endif
    if !l:fence && index(s:bottom_heads, trim(a:lines[l:k])) >= 0
      call add(l:out, {'kind': 'bottom', 'from': l:k + 1, 'to': l:n})
      break
    endif
  endfor
  return l:out
endfunction

" 折りたたみの階層（foldexpr）。隠す範囲だけ階層 1、その先頭は '>1'
function! gnosis#hide#expr(lnum) abort
  let l:buf = bufnr('%')
  let l:h = gnosis#hide#get()
  let l:c = get(s:cache, l:buf, {})
  if get(l:c, 'tick', -1) != b:changedtick || get(l:c, 'h', {}) != l:h
    let l:lv = {}
    let l:lab = {}
    for l:r in gnosis#hide#regions(getbufline(l:buf, 1, '$'))
      if !l:h[l:r.kind]
        continue
      endif
      for l:x in range(l:r.from, l:r.to)
        let l:lv[l:x] = l:x == l:r.from ? '>1' : '1'
      endfor
      let l:lab[l:r.from] = l:r.kind
    endfor
    let l:c = {'tick': b:changedtick, 'h': l:h, 'lv': l:lv, 'lab': l:lab}
    let s:cache[l:buf] = l:c
  endif
  return get(l:c.lv, a:lnum, '0')
endfunction

function! gnosis#hide#text() abort
  let l:kind = get(get(get(s:cache, bufnr('%'), {}), 'lab', {}), v:foldstart, '')
  let l:name = l:kind ==# 'yaml' ? 'YAML' : (l:kind ==# 'top' ? '上の関係' : (l:kind ==# 'bottom' ? '下の関係' : '隠した部分'))
  return '▸ ' . gnosis#i18n#tr(l:name) . ' (' . (v:foldend - v:foldstart + 1) . ')'
endfunction

" 今の窓に反映する。隠すものが無ければ元の折りたたみ設定に戻す
function! gnosis#hide#apply() abort
  if &buftype !=# '' || &filetype ==# 'gnosis-mandala' || expand('%:e') !=# 'md'
    return
  endif
  let l:h = gnosis#hide#get()
  let l:any = l:h.yaml || l:h.top || l:h.bottom
  if l:any && !get(w:, 'gnosis_fold_on', 0)
    if !get(w:, 'gnosis_hide_on', 0)
      let w:gnosis_hide_saved = {'fdm': &l:foldmethod, 'fde': &l:foldexpr, 'fdt': &l:foldtext, 'fen': &l:foldenable, 'fdl': &l:foldlevel, 'fml': &l:foldminlines}
    endif
    setlocal foldmethod=expr foldexpr=gnosis#hide#expr(v:lnum) foldtext=gnosis#hide#text() foldenable foldlevel=0 foldminlines=0
    let w:gnosis_hide_on = 1
    " 式の結果を取り直させる
    silent! normal! zxzM
  elseif !l:any && get(w:, 'gnosis_hide_on', 0)
    let l:sv = w:gnosis_hide_saved
    let &l:foldmethod = l:sv.fdm
    let &l:foldexpr = l:sv.fde
    let &l:foldtext = l:sv.fdt
    let &l:foldenable = l:sv.fen
    let &l:foldlevel = l:sv.fdl
    let &l:foldminlines = l:sv.fml
    if l:sv.fdm ==# 'manual'
      silent! normal! zE
    endif
    let w:gnosis_hide_on = 0
  endif
endfunction

" 開いているすべての窓に反映する
function! gnosis#hide#apply_all() abort
  let l:back = win_getid()
  for l:w in range(1, winnr('$'))
    call win_execute(win_getid(l:w), 'call gnosis#hide#apply()')
  endfor
  call win_gotoid(l:back)
endfunction

" ---- \zz の窓 ------------------------------------------------------------------------------------

let s:items = [['yaml', 'YAML（先頭の --- で囲んだ部分）'], ['top', '上の「名前:」系（ParentBranch: など）'], ['bottom', '下の「名前:」系（BackLink: など）'], ['image', '画像（ノートの中の画像を表示しない）']]

function! s:lines() abort
  let l:h = gnosis#hide#get()
  let l:out = [' 隠すもの', '']
  for l:i in range(len(s:items))
    call add(l:out, (l:i == s:sel ? ' ▶ ' : '   ') . (l:h[s:items[l:i][0]] ? '[x] ' : '[ ] ') . gnosis#i18n#tr(s:items[l:i][1]))
  endfor
  call extend(l:out, ['', ' j k 動く   Space / Enter 切り替え   a 全部オン／全部オフ（画像の行は含めない）   q 閉じる'])
  return l:out
endfunction

function! s:filter(id, key) abort
  if a:key ==# 'q' || a:key ==# "\<Esc>"
    call popup_close(a:id)
    return 1
  elseif a:key ==# 'j' || a:key ==# "\<Down>"
    let s:sel = (s:sel + 1) % len(s:items)
  elseif a:key ==# 'k' || a:key ==# "\<Up>"
    let s:sel = (s:sel + len(s:items) - 1) % len(s:items)
  elseif a:key ==# ' ' || a:key ==# "\<CR>"
    let l:k = s:items[s:sel][0]
    call gnosis#settings#set('hide.' . l:k, !gnosis#hide#get()[l:k] ? v:true : v:false)
    if l:k ==# 'image'
      call gnosis#imgview#apply_setting()
    else
      call gnosis#hide#apply_all()
    endif
  elseif a:key ==# 'a'
    " 一括: ひとつでもオフならぜんぶオン、ぜんぶオンならぜんぶオフ
    let l:h = gnosis#hide#get()
    let l:to = (l:h.yaml && l:h.top && l:h.bottom) ? v:false : v:true
    for l:it in s:items[:2]
      call gnosis#settings#set('hide.' . l:it[0], l:to)
    endfor
    call gnosis#hide#apply_all()
  endif
  call popup_settext(a:id, s:lines())
  return 1
endfunction

function! gnosis#hide#window() abort
  let s:sel = 0
  call popup_create(s:lines(), {'title': ' ノートの表示 ', 'pos': 'center', 'border': [], 'padding': [1, 2, 1, 2],
        \ 'zindex': 300, 'mapping': 0, 'filter': function('s:filter'), 'wrap': 0})
endfunction
