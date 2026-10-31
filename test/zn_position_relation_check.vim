" zn: 位置 → 関係性の独立性を検証。結果は $ZN_WORK/result.txt。
set nomore
let s:work = $ZN_WORK
let s:root = s:work . '/vault'
let s:results = []
let g:gnosis_root = s:root . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1
function! s:ok(name, yes) abort
  call add(s:results, (a:yes ? 'OK ' : 'NG ') . a:name)
  call writefile(s:results, s:work . '/result.txt')
endfunction
function! s:mk(name, title, body) abort
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title, '---', '', '# ' . a:title, ''] + a:body, s:root . '/' . a:name)
endfunction
function! s:lines(path) abort
  return readfile(s:root . '/' . a:path)
endfunction
function! s:new(before) abort
  let l:all = map(glob(s:root . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")')
  return get(filter(l:all, 'index(a:before, v:val) < 0'), 0, '')
endfunction
function! s:make(base, keys, ...) abort
  execute 'edit ' . fnameescape(s:root . '/' . a:base)
  if a:base ==# 'inline.md'
    call cursor(search('^ABCDE
  let g:gnosis_test_keys = a:keys
  if a:0 > 0
    let g:gnosis_test_heading = a:1
  endif
  sleep 1100m
  call gnosis#v2_new_plain()
  silent! stopinsert
  unlet! g:gnosis_test_heading
  return s:new(l:old)
endfunction

call s:mk('none.md', '関係なし', ['元の文章'])
let s:n = s:make('none.md', ["\r", "\r"])
call s:ok('Enter Enter は本文リンクのみ、Branchは無し',
      \ !empty(s:n) && index(s:lines(s:n), 'ParentBranch:') < 0
      \ && index(s:lines('none.md'), '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')') >= 0)

call s:mk('inline.md', '文中', ['ABCDE'])
execute 'edit ' . fnameescape(s:root . '/inline.md')
call cursor(search('^ABCDE$', 'nw'), 3)
" s:make が同じバッファを edit し直すが、cursor位置は維持される。
let s:n = s:make('inline.md', ['i', "\r"])
call s:ok('i Enter は文字Cの直後だけにリンクを作る',
      \ !empty(s:n) && index(s:lines('inline.md'), 'ABC[' . fnamemodify(s:n, ':r') . '](' . s:n . ')DE') >= 0
      \ && index(s:lines(s:n), 'ParentBranch:') < 0)

call s:mk('child.md', '子の位置', ['子の直下'])
execute 'edit ' . fnameescape(s:root . '/child.md')
call cursor(search('^子の直下$', 'nw'), 1)
let s:n = s:make('child.md', ['h', 'b'])
let s:cl = s:lines('child.md')
call s:ok('h b は行直下にリンク、ChildBranchも登録',
      \ !empty(s:n) && get(s:cl, index(s:cl, '子の直下') + 1, '') ==# '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')'
      \ && index(s:cl, 'ChildBranch:') >= 0 && index(s:lines(s:n), 'ParentBranch:') >= 0)

call s:mk('context.md', '文脈', ['変更しない'])
let s:before = s:lines('context.md')
let s:n = s:make('context.md', ['o', 'c'])
call s:ok('o c は新ノートのContextのみ、本文配置なし',
      \ !empty(s:n) && index(s:lines(s:n), 'Context:') >= 0
      \ && index(s:lines(s:n), '[文脈](context.md)') >= 0
      \ && index(s:lines(s:n), 'ParentBranch:') < 0
      \ && s:lines('context.md') ==# s:before)

call s:mk('parent.md', '親の位置', ['本文'])
let s:n = s:make('parent.md', ['o', 'p'])
call s:ok('o p は本文に置かず親子関係のみ',
      \ !empty(s:n) && index(s:lines('parent.md'), 'ParentBranch:') >= 0
      \ && index(s:lines(s:n), 'ChildBranch:') >= 0)

call s:mk('related.md', '関連', ['本文'])
let s:n = s:make('related.md', ['o', 'r'])
call s:ok('o r はRelatedのみ、ChildBranchなし',
      \ !empty(s:n) && index(s:lines('related.md'), 'Related:') >= 0
      \ && index(s:lines(s:n), 'Related:') >= 0
      \ && index(s:lines('related.md'), 'ChildBranch:') < 0)

call s:mk('heading.md', '見出し元', ['## 見出しA', '文章A', '', '## 見出しB', '文章B'])
let s:n = s:make('heading.md', ['t', "\r"], '見出しA')
let s:hl = s:lines('heading.md')
call s:ok('t Enter は指定見出し節に配置するだけでBranchなし',
      \ !empty(s:n) && index(s:hl, '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')') > index(s:hl, '文章A')
      \ && index(s:hl, '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')') < index(s:hl, '## 見出しB')
      \ && index(s:lines(s:n), 'ParentBranch:') < 0)

execute 'edit ' . fnameescape(s:root . '/none.md')
let s:all = map(glob(s:root . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")')
let g:gnosis_test_keys = ['h', "\<Esc>"]
call gnosis#v2_new_plain()
silent! stopinsert
call s:ok('2段階目をEscで取消したらファイルは増えない',
      \ s:all ==# map(glob(s:root . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")'))

call add(s:results, 'FINISHED')
call writefile(s:results, s:work . '/result.txt')
qa!
, 'nw'), 3)
  elseif a:base ==# 'child.md'
    call cursor(search('^子の直下
  let g:gnosis_test_keys = a:keys
  if a:0 > 0
    let g:gnosis_test_heading = a:1
  endif
  sleep 1100m
  call gnosis#v2_new_plain()
  silent! stopinsert
  unlet! g:gnosis_test_heading
  return s:new(l:old)
endfunction

call s:mk('none.md', '関係なし', ['元の文章'])
let s:n = s:make('none.md', ["\r", "\r"])
call s:ok('Enter Enter は本文リンクのみ、Branchは無し',
      \ !empty(s:n) && index(s:lines(s:n), 'ParentBranch:') < 0
      \ && index(s:lines('none.md'), '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')') >= 0)

call s:mk('inline.md', '文中', ['ABCDE'])
execute 'edit ' . fnameescape(s:root . '/inline.md')
call cursor(search('^ABCDE$', 'nw'), 3)
" s:make が同じバッファを edit し直すが、cursor位置は維持される。
let s:n = s:make('inline.md', ['i', "\r"])
call s:ok('i Enter は文字Cの直後だけにリンクを作る',
      \ !empty(s:n) && index(s:lines('inline.md'), 'ABC[' . fnamemodify(s:n, ':r') . '](' . s:n . ')DE') >= 0
      \ && index(s:lines(s:n), 'ParentBranch:') < 0)

call s:mk('child.md', '子の位置', ['子の直下'])
execute 'edit ' . fnameescape(s:root . '/child.md')
call cursor(search('^子の直下$', 'nw'), 1)
let s:n = s:make('child.md', ['h', 'b'])
let s:cl = s:lines('child.md')
call s:ok('h b は行直下にリンク、ChildBranchも登録',
      \ !empty(s:n) && get(s:cl, index(s:cl, '子の直下') + 1, '') ==# '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')'
      \ && index(s:cl, 'ChildBranch:') >= 0 && index(s:lines(s:n), 'ParentBranch:') >= 0)

call s:mk('context.md', '文脈', ['変更しない'])
let s:before = s:lines('context.md')
let s:n = s:make('context.md', ['o', 'c'])
call s:ok('o c は新ノートのContextのみ、本文配置なし',
      \ !empty(s:n) && index(s:lines(s:n), 'Context:') >= 0
      \ && index(s:lines(s:n), '[文脈](context.md)') >= 0
      \ && index(s:lines(s:n), 'ParentBranch:') < 0
      \ && s:lines('context.md') ==# s:before)

call s:mk('parent.md', '親の位置', ['本文'])
let s:n = s:make('parent.md', ['o', 'p'])
call s:ok('o p は本文に置かず親子関係のみ',
      \ !empty(s:n) && index(s:lines('parent.md'), 'ParentBranch:') >= 0
      \ && index(s:lines(s:n), 'ChildBranch:') >= 0)

call s:mk('related.md', '関連', ['本文'])
let s:n = s:make('related.md', ['o', 'r'])
call s:ok('o r はRelatedのみ、ChildBranchなし',
      \ !empty(s:n) && index(s:lines('related.md'), 'Related:') >= 0
      \ && index(s:lines(s:n), 'Related:') >= 0
      \ && index(s:lines('related.md'), 'ChildBranch:') < 0)

call s:mk('heading.md', '見出し元', ['## 見出しA', '文章A', '', '## 見出しB', '文章B'])
let s:n = s:make('heading.md', ['t', "\r"], '見出しA')
let s:hl = s:lines('heading.md')
call s:ok('t Enter は指定見出し節に配置するだけでBranchなし',
      \ !empty(s:n) && index(s:hl, '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')') > index(s:hl, '文章A')
      \ && index(s:hl, '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')') < index(s:hl, '## 見出しB')
      \ && index(s:lines(s:n), 'ParentBranch:') < 0)

execute 'edit ' . fnameescape(s:root . '/none.md')
let s:all = map(glob(s:root . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")')
let g:gnosis_test_keys = ['h', "\<Esc>"]
call gnosis#v2_new_plain()
silent! stopinsert
call s:ok('2段階目をEscで取消したらファイルは増えない',
      \ s:all ==# map(glob(s:root . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")'))

call add(s:results, 'FINISHED')
call writefile(s:results, s:work . '/result.txt')
qa!
, 'nw'), 1)
  endif
  let l:old = map(glob(s:root . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")')
  let g:gnosis_test_keys = a:keys
  if a:0 > 0
    let g:gnosis_test_heading = a:1
  endif
  sleep 1100m
  call gnosis#v2_new_plain()
  silent! stopinsert
  unlet! g:gnosis_test_heading
  return s:new(l:old)
endfunction

call s:mk('none.md', '関係なし', ['元の文章'])
let s:n = s:make('none.md', ["\r", "\r"])
call s:ok('Enter Enter は本文リンクのみ、Branchは無し',
      \ !empty(s:n) && index(s:lines(s:n), 'ParentBranch:') < 0
      \ && index(s:lines('none.md'), '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')') >= 0)

call s:mk('inline.md', '文中', ['ABCDE'])
execute 'edit ' . fnameescape(s:root . '/inline.md')
call cursor(search('^ABCDE$', 'nw'), 3)
" s:make が同じバッファを edit し直すが、cursor位置は維持される。
let s:n = s:make('inline.md', ['i', "\r"])
call s:ok('i Enter は文字Cの直後だけにリンクを作る',
      \ !empty(s:n) && index(s:lines('inline.md'), 'ABC[' . fnamemodify(s:n, ':r') . '](' . s:n . ')DE') >= 0
      \ && index(s:lines(s:n), 'ParentBranch:') < 0)

call s:mk('child.md', '子の位置', ['子の直下'])
execute 'edit ' . fnameescape(s:root . '/child.md')
call cursor(search('^子の直下$', 'nw'), 1)
let s:n = s:make('child.md', ['h', 'b'])
let s:cl = s:lines('child.md')
call s:ok('h b は行直下にリンク、ChildBranchも登録',
      \ !empty(s:n) && get(s:cl, index(s:cl, '子の直下') + 1, '') ==# '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')'
      \ && index(s:cl, 'ChildBranch:') >= 0 && index(s:lines(s:n), 'ParentBranch:') >= 0)

call s:mk('context.md', '文脈', ['変更しない'])
let s:before = s:lines('context.md')
let s:n = s:make('context.md', ['o', 'c'])
call s:ok('o c は新ノートのContextのみ、本文配置なし',
      \ !empty(s:n) && index(s:lines(s:n), 'Context:') >= 0
      \ && index(s:lines(s:n), '[文脈](context.md)') >= 0
      \ && index(s:lines(s:n), 'ParentBranch:') < 0
      \ && s:lines('context.md') ==# s:before)

call s:mk('parent.md', '親の位置', ['本文'])
let s:n = s:make('parent.md', ['o', 'p'])
call s:ok('o p は本文に置かず親子関係のみ',
      \ !empty(s:n) && index(s:lines('parent.md'), 'ParentBranch:') >= 0
      \ && index(s:lines(s:n), 'ChildBranch:') >= 0)

call s:mk('related.md', '関連', ['本文'])
let s:n = s:make('related.md', ['o', 'r'])
call s:ok('o r はRelatedのみ、ChildBranchなし',
      \ !empty(s:n) && index(s:lines('related.md'), 'Related:') >= 0
      \ && index(s:lines(s:n), 'Related:') >= 0
      \ && index(s:lines('related.md'), 'ChildBranch:') < 0)

call s:mk('heading.md', '見出し元', ['## 見出しA', '文章A', '', '## 見出しB', '文章B'])
let s:n = s:make('heading.md', ['t', "\r"], '見出しA')
let s:hl = s:lines('heading.md')
call s:ok('t Enter は指定見出し節に配置するだけでBranchなし',
      \ !empty(s:n) && index(s:hl, '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')') > index(s:hl, '文章A')
      \ && index(s:hl, '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')') < index(s:hl, '## 見出しB')
      \ && index(s:lines(s:n), 'ParentBranch:') < 0)

execute 'edit ' . fnameescape(s:root . '/none.md')
let s:all = map(glob(s:root . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")')
let g:gnosis_test_keys = ['h', "\<Esc>"]
call gnosis#v2_new_plain()
silent! stopinsert
call s:ok('2段階目をEscで取消したらファイルは増えない',
      \ s:all ==# map(glob(s:root . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")'))

call add(s:results, 'FINISHED')
call writefile(s:results, s:work . '/result.txt')
qa!
