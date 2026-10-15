" =============================================================================
" autoload/gnosis/context.vim — Context ブロック（`Context:` の行 + 直下のリンク群）
"
" ノートの Context は、本文の冒頭（H1 タイトルの直後）に置く。Markdown の見出しではなく、ふつうのテキスト行:
"
"     # ノート B
"
"     Context:
"     [ノート A](a.md)
"     [ノート C](c.md)
"
"     本文。
"
" 旧形式の `### Context` 節（旧 `### Parent`）も読める。Context を足すとき・移行するときは、リンクを
" 1 本も失わずに新形式へ寄せる（python/context_ops.py と同じ規則。同じ試験の入出力で揃えてある）。
" ここは行リスト → 行リストの純粋な関数だけ（バッファやファイルは触らない）。
" =============================================================================

let s:head = 'Context:'
let s:script = fnamemodify(expand('<sfile>:p:h:h:h') . '/python/context_ops.py', ':p')
let s:legacy_marks = ['### Context', '### Parent']
let s:section_marks = ['### ParentBranch', '### Context', '### Parent', '### Group', '### ChildBranch', '### Related', '### BackLink',
      \ 'ChildBranch:', 'Related:', 'BackLink:']
let s:link_line = '^\s*\[\%(\\.\|[^\]\\]\)*\]([^)]\+)\s*\%(—\s*\S\+\)\?\s*$'

function! gnosis#context#head() abort
  return s:head
endfunction

" コードブロック（``` / ~~~）の中の行か
function! s:fenced(lines) abort
  let l:out = []
  let l:mark = ''
  for l:ln in a:lines
    let l:m = matchlist(l:ln, '^\s\{0,3}\(`\{3,}\|\~\{3,}\)')
    if l:mark ==# ''
      if !empty(l:m)
        let l:mark = l:m[1][0]
        call add(l:out, 1)
      else
        call add(l:out, 0)
      endif
    else
      call add(l:out, 1)
      if !empty(l:m) && l:m[1][0] ==# l:mark && trim(l:ln) =~# '^' . (l:mark ==# '`' ? '`' : '\~') . '\+$'
        let l:mark = ''
      endif
    endif
  endfor
  return l:out
endfunction

" front matter の長さ（先頭の --- から閉じの --- まで）
function! s:fm_len(lines) abort
  if get(a:lines, 0, '') !~# '^---\s*$'
    return 0
  endif
  for l:i in range(1, len(a:lines) - 1)
    if a:lines[l:i] =~# '^---\s*$'
      return l:i + 1
    endif
  endfor
  return 0
endfunction

" Context: より上に来る、本文の上の先頭のブロック（並び: ParentBranch → BranchGroup → Group → Context）
let s:above_heads = ['ParentBranch:', 'BranchGroup:', 'ThisNoteGroup:', 'Group:']

" 新形式のブロックの [`Context:` の行, リンクの最後の行]（0 始まり）。無ければ []。
" H1 の直後にあるものだけ（間は空行と、上に来る先頭のブロックだけ。H1 が無ければ front matter の直後）。
function! gnosis#context#find_block(lines) abort
  let l:fl = s:fenced(a:lines)
  let l:seen_h1 = 0
  let l:i = s:fm_len(a:lines)
  while l:i < len(a:lines)
    if l:fl[l:i]
      return []
    endif
    let l:s = trim(a:lines[l:i])
    if l:s ==# s:head
      let l:j = l:i
      while l:j + 1 < len(a:lines) && !l:fl[l:j + 1] && a:lines[l:j + 1] =~# s:link_line
        let l:j += 1
      endwhile
      return [l:i, l:j]
    endif
    if l:s ==# ''
      let l:i += 1
      continue
    endif
    if a:lines[l:i] =~# '^#\s\+\S' && !l:seen_h1
      let l:seen_h1 = 1
      let l:i += 1
      continue
    endif
    if index(s:above_heads, l:s) >= 0
      let l:i += 1
      while l:i < len(a:lines) && !l:fl[l:i] && a:lines[l:i] =~# s:link_line
        let l:i += 1
      endwhile
      continue
    endif
    return []
  endwhile
  return []
endfunction

" H1 の直後に続く、Context: より上の先頭のブロックの終わりの次の行（0 始まり）。無ければ -1。
function! s:above_end(lines) abort
  let l:fl = s:fenced(a:lines)
  let l:seen_h1 = 0
  let l:end = -1
  let l:i = s:fm_len(a:lines)
  while l:i < len(a:lines)
    if l:fl[l:i] | break | endif
    let l:s = trim(a:lines[l:i])
    if l:s ==# ''
      let l:i += 1
      continue
    endif
    if a:lines[l:i] =~# '^#\s\+\S' && !l:seen_h1
      let l:seen_h1 = 1
      let l:i += 1
      continue
    endif
    if index(s:above_heads, l:s) >= 0
      let l:i += 1
      while l:i < len(a:lines) && !l:fl[l:i] && a:lines[l:i] =~# s:link_line
        let l:i += 1
      endwhile
      let l:end = l:i
      continue
    endif
    break
  endwhile
  return l:end
endfunction

" 旧 `### Context`（`### Parent`）節の [見出しの行, 終わりの次の行)（0 始まり）のリスト
function! gnosis#context#legacy(lines) abort
  let l:fl = s:fenced(a:lines)
  let l:marks = []
  for l:i in range(s:fm_len(a:lines), len(a:lines) - 1)
    if !l:fl[l:i] && index(s:section_marks, trim(a:lines[l:i])) >= 0
      call add(l:marks, l:i)
    endif
  endfor
  let l:out = []
  for l:k in range(len(l:marks))
    if index(s:legacy_marks, trim(a:lines[l:marks[l:k]])) >= 0
      call add(l:out, [l:marks[l:k], l:k + 1 < len(l:marks) ? l:marks[l:k + 1] : len(a:lines)])
    endif
  endfor
  return l:out
endfunction

" Context のリンク行（新形式 + 旧形式）
function! gnosis#context#links(lines) abort
  let l:out = []
  let l:b = gnosis#context#find_block(a:lines)
  if !empty(l:b)
    call extend(l:out, a:lines[l:b[0] + 1 : l:b[1]])
  endif
  for [l:s, l:e] in gnosis#context#legacy(a:lines)
    for l:k in range(l:s + 1, l:e - 1)
      if a:lines[l:k] =~# s:link_line
        call add(l:out, a:lines[l:k])
      endif
    endfor
  endfor
  return l:out
endfunction

function! s:target_path(link, base) abort
  let l:m = matchlist(a:link, '\v\[%(\\.|[^\]\\])*\]\(([^)]*)\)')
  if empty(l:m)
    return ''
  endif
  return fnamemodify(gnosis#resolve_link(substitute(l:m[1], '#.*$', '', ''), a:base), ':p')
endfunction

" H1 の直後（無ければ front matter の直後）に Context ブロックを作る。前後に空行を確保する。
function! s:insert_new_block(lines, links) abort
  let l:out = copy(a:lines)
  let l:start = s:fm_len(l:out)
  let l:fl = s:fenced(l:out)
  let l:h1 = -1
  for l:i in range(l:start, len(l:out) - 1)
    if !l:fl[l:i] && l:out[l:i] =~# '^#\s\+\S'
      let l:h1 = l:i
      break
    endif
  endfor
  let l:at = l:h1 >= 0 ? l:h1 + 1 : l:start
  let l:block = [s:head] + a:links
  " 上に来るブロック（ParentBranch: / BranchGroup: / Group:）があれば、そのすぐ下に並べる
  let l:above = s:above_end(l:out)
  if l:above >= 0
    call extend(l:out, l:block + (l:above < len(l:out) && trim(l:out[l:above]) !=# '' ? [''] : []), l:above)
    return l:out
  endif
  if l:at < len(l:out) && trim(l:out[l:at]) ==# ''
    " H1 の次の空行を、Context の前の空行として使う
    call extend(l:out, l:block + [''], l:at + 1)
  else
    call extend(l:out, [''] + l:block + [''], l:at)
  endif
  return l:out
endfunction

" 旧 `### Context` 節のリンクを新形式のブロックへ移す。リンクは 1 本も失わない（重複は 1 本）。
" リンクでない行（メモなど）が旧節にあれば、その節は残す。旧節が無ければそのまま返す。
function! gnosis#context#migrate(lines) abort
  let l:secs = gnosis#context#legacy(a:lines)
  if empty(l:secs)
    return copy(a:lines)
  endif
  let l:out = copy(a:lines)
  let l:legacy_links = []
  for [l:s, l:e] in reverse(copy(l:secs))
    let l:keep = []
    let l:links = []
    for l:k in range(l:s + 1, l:e - 1)
      if l:out[l:k] =~# s:link_line
        call add(l:links, l:out[l:k])
      elseif trim(l:out[l:k]) !=# ''
        call add(l:keep, l:out[l:k])
      endif
    endfor
    let l:legacy_links = l:links + l:legacy_links
    let l:at_end = l:e >= len(l:out)
    call remove(l:out, l:s, l:e - 1)
    if !empty(l:keep)
      call extend(l:out, [a:lines[l:s]] + l:keep, l:s)
    elseif l:at_end
      while !empty(l:out) && trim(l:out[-1]) ==# ''
        call remove(l:out, -1)
      endwhile
    endif
  endfor
  let l:b = gnosis#context#find_block(l:out)
  let l:merged = empty(l:b) ? [] : copy(l:out[l:b[0] + 1 : l:b[1]])
  let l:keys = {}
  for l:l in l:merged
    let l:keys[trim(l:l)] = 1
  endfor
  for l:l in l:legacy_links
    if !has_key(l:keys, trim(l:l))
      let l:keys[trim(l:l)] = 1
      call add(l:merged, l:l)
    endif
  endfor
  if !empty(l:b)
    call remove(l:out, l:b[0] + 1, l:b[1])
    call extend(l:out, l:merged, l:b[0] + 1)
  elseif !empty(l:merged)
    let l:out = s:insert_new_block(l:out, l:merged)
  endif
  return l:out
endfunction

" Context に a:link を足す。戻り値 {'lines': 新しい行, 'added': 足したか, 'lnum': 足したリンクの行（0 始まり）}。
" 既に同じノート（相対パスを解決して比べる）があれば足さない。新しいリンクは既存リンク群の最後へ。
" Context が無ければ H1 の直後に作る。旧形式があれば、その場でリンクを失わず新形式へ寄せてから足す。
function! gnosis#context#add(lines, link, base_dir) abort
  let l:want = s:target_path(a:link, a:base_dir)
  for l:l in gnosis#context#links(a:lines)
    if l:l ==# a:link || (!empty(l:want) && s:target_path(l:l, a:base_dir) ==# l:want)
      return {'lines': copy(a:lines), 'added': 0, 'lnum': -1}
    endif
  endfor
  let l:out = gnosis#context#migrate(a:lines)
  let l:b = gnosis#context#find_block(l:out)
  if !empty(l:b)
    call insert(l:out, a:link, l:b[1] + 1)
    return {'lines': l:out, 'added': 1, 'lnum': l:b[1] + 1}
  endif
  let l:out = s:insert_new_block(l:out, [a:link])
  let l:nb = gnosis#context#find_block(l:out)
  return {'lines': l:out, 'added': 1, 'lnum': empty(l:nb) ? -1 : l:nb[1]}
endfunction

" 新しいノートの冒頭（H1 の直後）に入れる Context ブロックの行（グループ作成などの組み立て用）
function! gnosis#context#block_lines(links) abort
  return [s:head] + a:links
endfunction

" 旧形式 `### Context` の明示的な移行（:GnosisContextMigrate）。
"   :GnosisContextMigrate        … 今のノートだけ移行する
"   :GnosisContextMigrate all    … vault 全体を試走（書き換えず、移行するノートの数だけ知らせる）
"   :GnosisContextMigrate! all   … vault 全体を実際に移行する（確認あり。python が移行前後のリンクと他の行を検証してから書く）
" 開いただけ・同期しただけでは移行しない（勝手な一括書き換えをしない）。
function! gnosis#context#migrate_command(arg, bang) abort
  if trim(a:arg) ==# 'all'
    return s:migrate_all(a:bang)
  endif
  let l:lines = getline(1, '$')
  if empty(gnosis#context#legacy(l:lines))
    echo 'Gnosis: ' . gnosis#i18n#t('context.nothing')
    return
  endif
  let l:new = gnosis#context#migrate(l:lines)
  call s:replace(l:new)
  echo 'Gnosis: ' . gnosis#i18n#t('context.migrated', len(gnosis#context#links(l:new)))
endfunction

function! s:replace(new) abort
  let l:view = winsaveview()
  call setline(1, a:new)
  if line('$') > len(a:new)
    silent! execute (len(a:new) + 1) . ',$delete _'
  endif
  call winrestview(l:view)
endfunction

function! s:migrate_all(apply) abort
  let l:root = get(g:, 'gnosis_root', '')
  if empty(l:root) || !gnosis#has_python()
    return
  endif
  let l:cmd = gnosis#python_cmd() . ' ' . shellescape(s:script) . ' migrate ' . shellescape(l:root) . (a:apply ? ' --apply' : '')
  if a:apply
    let l:dry = json_decode(trim(get(split(system(substitute(l:cmd, ' --apply$', '', '')), "\n"), -1, '')))
    if confirm(gnosis#i18n#t('context.confirm', len(l:dry.migrated)), "&Yes\n&No", 2) != 1
      return
    endif
    silent! wall
  endif
  let l:r = json_decode(trim(get(split(system(l:cmd), "\n"), -1, '')))
  if a:apply
    echo 'Gnosis: ' . gnosis#i18n#t('context.done', len(l:r.migrated), len(l:r.failed))
    silent! checktime
  else
    echo 'Gnosis: ' . gnosis#i18n#t('context.dry', len(l:r.migrated))
  endif
endfunction
