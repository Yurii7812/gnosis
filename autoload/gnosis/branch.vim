" =============================================================================
" autoload/gnosis/branch.vim — Branch（直接のブランチ）の追加（リンク追加の `b`）
"
"   A から B を `b` で追加すると、
"     A:  ChildBranch:  → [B](b.md)
"     B:  ParentBranch: → [A](a.md)
"   を両方に書く。親は 1 ノートに最大 1 つ・子は複数。自分自身・循環・2 つ目の親は拒否する。
"   拒否したときはどちらのノートも変更しない。実体は python/branch_ops.py（検証して 2 ファイルを
"   まとめて書き、片方の保存に失敗したら元に戻す）。ここはそれを呼んで、Vim のバッファを読み直し、
"   結果を利用者に伝えるだけ。
" =============================================================================

let s:script_path = fnamemodify(expand('<sfile>:p:h:h:h') . '/python/branch_ops.py', ':p')

function! s:script() abort
  return s:script_path
endfunction

function! s:root() abort
  let l:r = get(g:, 'gnosis_root', '')
  return empty(l:r) ? '' : substitute(fnamemodify(l:r, ':p'), '[\\/]\+$', '', '')
endfunction

" 子のパスを集めるときの、リンク（[表示名](パス)）から実ファイルへの解決
function! s:targets(links, base) abort
  let l:out = []
  for l:lk in a:links
    let l:m = matchlist(l:lk, '\v\[%(\\.|[^\]\\])*\]\(([^)]*)\)')
    if empty(l:m) | continue | endif
    let l:p = gnosis#resolve_link(substitute(l:m[1], '#.*$', '', ''), a:base)
    if !empty(l:p) && filereadable(l:p) && index(l:out, l:p) < 0
      call add(l:out, l:p)
    endif
  endfor
  return l:out
endfunction

" python を呼ぶ。戻り値は結果の辞書（{ok, code, ...}）。起動できない・JSON でないときは code=error。
function! gnosis#branch#run(root, parent, children, ...) abort
  if !gnosis#has_python()
    return {'ok': 0, 'code': 'error', 'message': 'python not found'}
  endif
  let l:cmd = gnosis#python_cmd() . ' ' . shellescape(s:script()) . ' add ' . shellescape(a:root)
        \ . ' ' . shellescape(a:parent) . ' ' . join(map(copy(a:children), 'shellescape(v:val)'), ' ')
        \ . (a:0 && a:1 ? ' --dry-run' : '')
  let l:out = system(l:cmd)
  try
    let l:r = json_decode(trim(get(split(l:out, "\n"), -1, '')))
    if type(l:r) == v:t_dict
      return l:r
    endif
  catch
  endtry
  return {'ok': 0, 'code': 'error', 'message': trim(l:out)}
endfunction

" 結果を利用者に見せる文言
function! gnosis#branch#message(r) abort
  let l:c = get(a:r, 'code', 'error')
  if l:c ==# 'added'
    return gnosis#i18n#t('branch.added')
  elseif l:c ==# 'already'
    return gnosis#i18n#t('branch.already')
  elseif l:c ==# 'has_parent'
    return gnosis#i18n#t('branch.has_parent', a:r.title, a:r.parent_title)
  elseif l:c ==# 'multi_parent'
    return gnosis#i18n#t('branch.multi_parent', a:r.title, join(map(copy(a:r.parents), 'v:val.title'), ' / '))
  elseif l:c ==# 'self'
    return gnosis#i18n#t('branch.self')
  elseif l:c ==# 'cycle'
    return gnosis#i18n#t('branch.cycle')
  elseif l:c ==# 'index'
    return gnosis#i18n#t('branch.index')
  elseif l:c ==# 'missing'
    return gnosis#i18n#t('branch.missing', get(a:r, 'path', ''))
  elseif l:c ==# 'dirty'
    return gnosis#i18n#t('branch.dirty', fnamemodify(get(a:r, 'path', ''), ':t'))
  elseif l:c ==# 'conflict'
    return gnosis#i18n#t('branch.conflict', get(a:r, 'path', ''))
  elseif l:c ==# 'not_in_vault'
    return gnosis#i18n#t('branch.not_in_vault')
  elseif l:c ==# 'save_failed'
    return gnosis#i18n#t('branch.save_failed')
  endif
  return gnosis#i18n#t('branch.error', get(a:r, 'message', ''))
endfunction

" 他のバッファで開いているノートが変わったときに読み直す（未保存の変更があるバッファは触らない）
function! s:reload(paths) abort
  for l:p in a:paths
    let l:nr = bufnr(l:p)
    if l:nr < 0 || !bufloaded(l:nr) || getbufvar(l:nr, '&modified')
      continue
    endif
    if l:nr == bufnr('%')
      let l:view = winsaveview()
      silent! edit
      call winrestview(l:view)
    else
      silent! execute 'checktime ' . l:nr
    endif
  endfor
endfunction

" 今のノートを親にして、a:paths（実在するノートのパス）を ChildBranch に追加する（python 側で検証・書き込み）。
" a:1 が真なら案内を出さない（呼び出し側が出す）。戻り値は python の結果の辞書。
" ok のときは、読み込み済みのバッファを読み直してある。拒否・失敗のときはどのノートも変更していない。
function! gnosis#branch#add_paths(parent, paths, ...) abort
  let l:root = s:root()
  if empty(a:parent) || empty(l:root) || stridx(a:parent, l:root . '/') != 0
    return {'ok': 0, 'code': 'not_in_vault'}
  endif
  " ディスク上の内容で検証・追記するので、今のノートの未保存の変更を先に保存する（保存できなければ中止）
  " 関わるノートのうち、開いていて未保存のものを先に保存する（今のノートは保存する。別のバッファは保存できないので中止）
  for l:f in [a:parent] + a:paths
    let l:nr = bufnr(l:f)
    if l:nr > 0 && getbufvar(l:nr, '&modified')
      if l:nr == bufnr('%')
        try
          silent update
        catch
        endtry
      endif
      if getbufvar(l:nr, '&modified')
        return {'ok': 0, 'code': 'save_failed'}
      endif
    endif
  endfor
  let l:r = gnosis#branch#run(l:root, a:parent, a:paths)
  if get(l:r, 'ok', 0)
    call s:reload([a:parent] + a:paths)
  endif
  return l:r
endfunction

" 今のノートを親にして、a:links（Markdown リンクの文字列のリスト）を ChildBranch に追加する。
" 戻り値: 追加できた（既にある場合も含む）なら 1。拒否・失敗は 0（どのノートも変更しない）。
function! gnosis#branch#add_links(links) abort
  let l:cur = expand('%:p')
  let l:kids = s:targets(a:links, expand('%:p:h'))
  if empty(l:kids)
    call s:warn(gnosis#i18n#t('branch.no_target'))
    return 0
  endif
  let l:r = gnosis#branch#add_paths(l:cur, l:kids)
  if !get(l:r, 'ok', 0)
    call s:warn(gnosis#branch#message(l:r))
    return 0
  endif
  echo gnosis#branch#message(l:r)
  return 1
endfunction

" p モード: 今のノートの親（ParentBranch）として a:links のノートを追加する。親は 1 つだけなので、
" リンクが 2 つ以上なら何も変えずに断る。b と同じ add_paths（parent と child を決めて同じ検証・更新）を使う。
function! gnosis#branch#add_parent_links(links) abort
  let l:cur = expand('%:p')
  let l:ps = s:targets(a:links, expand('%:p:h'))
  if empty(l:ps)
    call s:warn(gnosis#i18n#t('branch.no_target'))
    return 0
  endif
  if len(l:ps) > 1
    call s:warn(gnosis#i18n#t('branch.one_parent_only'))
    return 0
  endif
  let l:r = gnosis#branch#add_paths(l:ps[0], [l:cur])
  if !get(l:r, 'ok', 0)
    call s:warn(gnosis#branch#message(l:r))
    return 0
  endif
  echo gnosis#branch#message(l:r)
  return 1
endfunction

" zn / zk の p: 作る前に、今のノートが子になれるか（index.md は不可・保存できる）を確かめる。
" 既に親があるかは、作ったあとの検証で分かる（その場合は作ったノートを消して何も残さない）。
function! gnosis#branch#can_child_here() abort
  return gnosis#branch#can_parent_here()
endfunction

" 新しいノートを今のノートの ChildBranch として作るとき（zn / zk の b）に、作る前に確かめる。
" 今のノートが Branch を持てるか（index.md は節を持たない）・未保存の変更を保存できるか。
" 戻り値: 続けてよければ 1。だめなら理由を出して 0（何も作らない）。
function! gnosis#branch#can_parent_here() abort
  let l:cur = expand('%:p')
  let l:root = s:root()
  if empty(l:cur) || empty(l:root) || stridx(l:cur, l:root . '/') != 0
    call s:warn(gnosis#i18n#t('branch.not_in_vault'))
    return 0
  endif
  if fnamemodify(l:cur, ':t') ==# 'index.md'
    call s:warn(gnosis#i18n#t('branch.index'))
    return 0
  endif
  if &buftype ==# '' && &modified
    try
      silent update
    catch
    endtry
    if &modified
      call s:warn(gnosis#i18n#t('branch.save_failed'))
      return 0
    endif
  endif
  return 1
endfunction

" 整合性の検査（:GnosisBranchCheck）。何も書き換えず、問題を一覧する。
function! gnosis#branch#check() abort
  let l:root = s:root()
  if empty(l:root) || !gnosis#has_python()
    return {}
  endif
  let l:out = system(gnosis#python_cmd() . ' ' . shellescape(s:script()) . ' check ' . shellescape(l:root))
  try
    let l:r = json_decode(trim(get(split(l:out, "\n"), -1, '')))
    return type(l:r) == v:t_dict ? l:r : {}
  catch
    return {}
  endtry
endfunction

function! gnosis#branch#check_command() abort
  let l:r = gnosis#branch#check()
  if empty(l:r)
    call s:warn(gnosis#i18n#t('branch.check_failed'))
    return
  endif
  if get(l:r, 'ok', 0)
    echo gnosis#i18n#t('branch.check_ok')
    return
  endif
  let l:lines = []
  for l:m in get(l:r, 'multi_parent', [])
    call add(l:lines, gnosis#i18n#t('branch.check_multi', l:m.note, join(l:m.parents, ', ')))
  endfor
  for l:m in get(l:r, 'one_sided', [])
    call add(l:lines, gnosis#i18n#t('branch.check_one_sided', l:m.parent, l:m.child, l:m.missing))
  endfor
  for l:n in get(l:r, 'cycle', [])
    call add(l:lines, gnosis#i18n#t('branch.check_cycle', l:n))
  endfor
  for l:n in get(l:r, 'self', [])
    call add(l:lines, gnosis#i18n#t('branch.check_self', l:n))
  endfor
  echohl WarningMsg
  echo join([gnosis#i18n#t('branch.check_ng')] + l:lines, "\n")
  echohl NONE
endfunction

function! gnosis#branch#warn(msg) abort
  call s:warn(a:msg)
endfunction

function! s:warn(msg) abort
  echohl WarningMsg
  echom 'Gnosis: ' . a:msg
  echohl NONE
endfunction

" ---------------------------------------------------------------------------
" BranchGroup: の中の並び（階層）を変える（:GnosisBranchNest / :GnosisBranchUnnest）
"   BranchGroup: の中の上下関係は、並びとインデント（2 スペース）だけで表す。
"     BranchGroup:
"     [A](a.md)
"       [B](b.md)    ← B は A の下に並ぶ（上位が A）。ただそれだけ（リンクや関係は増えない）
"   ビジュアル選択（:'<,'>）か、今の行（範囲なし）の BranchGroup のリンク行を 1 段下げる（Nest）／上げる（Unnest）。
"   子（その行より深くインデントされた続きの行）は、選んでいなければいっしょに動く。
"   Nest は直前の行の 1 段下までしか下げられない（先頭の行や、すでに親の直下の行は下げられない）。
" ---------------------------------------------------------------------------
function! s:branch_block_range() abort
  let l:lines = getline(1, '$')
  let l:in_fence = 0
  for l:i in range(0, len(l:lines) - 1)
    if l:lines[l:i] =~# '^\s*\(```\|\~\~\~\)'
      let l:in_fence = !l:in_fence
      continue
    endif
    if !l:in_fence && trim(l:lines[l:i]) =~# '^\%(BranchGroup\|ThisNoteGroup\):$'
      let l:j = l:i + 1
      while l:j < len(l:lines) && l:lines[l:j] =~# '^\s*\[[^]]*\]([^)]\+)\s*$'
        let l:j += 1
      endwhile
      return [l:i + 1, l:j - 1]   " 見出しの次の行から最後のリンク行まで（0 始まり）
    endif
  endfor
  return [-1, -2]
endfunction

function! s:indent_of(line) abort
  return len(a:line) - len(substitute(a:line, '^ \+', '', ''))
endfunction

function! gnosis#branch#nest(line1, line2, dir) abort
  let [l:b0, l:b1] = s:branch_block_range()
  if l:b0 < 0 || l:b1 < l:b0
    call s:warn(gnosis#i18n#t('branch.nest_no_block'))
    return 0
  endif
  let l:first = max([a:line1 - 1, l:b0])
  let l:last = min([a:line2 - 1, l:b1])
  if l:first > l:last
    call s:warn(gnosis#i18n#t('branch.nest_not_in_block'))
    return 0
  endif
  let l:lines = getline(l:b0 + 1, l:b1 + 1)
  let l:n = len(l:lines)
  let l:orig = map(copy(l:lines), {_, v -> s:indent_of(v)})
  let l:new = copy(l:orig)
  let l:sel = {}
  for l:i in range(l:first - l:b0, l:last - l:b0)
    let l:sel[l:i] = 1
  endfor
  let l:changed = 0
  for l:i in range(0, l:n - 1)
    if !has_key(l:sel, l:i)
      continue
    endif
    if a:dir > 0
      if l:i == 0
        continue
      endif
      let l:target = min([l:orig[l:i] + 2, l:new[l:i - 1] + 2])
    else
      let l:target = max([l:orig[l:i] - 2, 0])
    endif
    let l:delta = l:target - l:new[l:i]
    if l:delta == 0
      continue
    endif
    let l:new[l:i] = l:target
    let l:changed += 1
    " 選んでいない子（深くインデントされた続きの行）もいっしょに動かす
    let l:j = l:i + 1
    while l:j < l:n && l:orig[l:j] > l:orig[l:i] && !has_key(l:sel, l:j)
      let l:new[l:j] = max([l:orig[l:j] + l:delta, 0])
      let l:j += 1
    endwhile
  endfor
  if l:changed == 0
    call s:warn(gnosis#i18n#t(a:dir > 0 ? 'branch.nest_cannot' : 'branch.unnest_cannot'))
    return 0
  endif
  for l:i in range(0, l:n - 1)
    if l:new[l:i] != l:orig[l:i]
      call setline(l:b0 + l:i + 1, repeat(' ', l:new[l:i]) . substitute(l:lines[l:i], '^ \+', '', ''))
    endif
  endfor
  return l:changed
endfunction
