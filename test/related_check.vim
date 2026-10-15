set nomore
let g:gnosis_history = []
let g:gnosis_history_max = 100
let g:gnosis_forward = []
let s:v = $RELATED_WORK . '/vault'
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
function! s:mk(n, extra) abort
  call writefile(['---', 'title: ' . a:n, '---', '', '# ' . a:n, '', '本文 ' . a:n] + a:extra, s:v . '/' . a:n . '.md')
endfunction
function! s:read(n) abort
  return readfile(s:v . '/' . a:n . '.md')
endfunction
function! s:pick(links) abort
  let g:gnosis_test_keys = ['r']
  call gnosis#insert_links_pick(a:links, getpos('.'))
endfunction
function! s:za(links) abort
  let @" = join(a:links, "\n")
  let @0 = @"
  let g:gnosis_test_keys = ['r']
  call gnosis#add_clipboard_before_up_note()
endfunction
call s:mk('a', [])
call s:mk('b', [])
call s:mk('c', [])
execute 'edit ' . s:v . '/a.md'
let g:gnosis_test_keys = ['r']
call gnosis#v2_new_plain()
stopinsert
let s:new = expand('%:t:r')
call assert_notequal('a', s:new, 'zn r opens new note')
call assert_equal(1, count(s:read(s:new), '[a](a.md)'))
call assert_equal(1, count(s:read('a'), '[' . s:new . '](' . s:new . '.md)'))
for s:n in ['a', s:new]
  call assert_true(index(s:read(s:n), 'Related:') >= 0)
  for s:mark in ['ParentBranch:', 'ChildBranch:', 'Context:', 'Group:', 'BranchGroup:']
    call assert_equal(-1, index(s:read(s:n), s:mark), 'zn r: ' . s:mark)
  endfor
endfor
execute 'edit ' . s:v . '/a.md'
call s:pick(['[b](b.md)'])
call assert_equal(1, count(s:read('b'), '[a](a.md)'), 'picker reverse')
call s:za(['[b](b.md)', '[c](c.md)'])
call s:za(['[alias](b.md)', '[c](c.md)'])
call assert_equal(1, count(s:read('a'), '[b](b.md)'), 'repeat dedup')
call assert_equal(1, count(s:read('c'), '[a](a.md)'), 'za multiple reverse')
call assert_equal(-1, index(s:read('a'), 'Context:'))
" Existing body / Branch / Context are preserved exactly before Related.
call s:mk('d', [])
call s:mk('e', [])
call writefile(['---', 'title: d', '---', '', '# d', '', 'ParentBranch:', '[b](b.md)', '', 'Context:', '[c](c.md)', '', '本文 d', '', 'ChildBranch:', '[e](e.md)'], s:v . '/d.md')
execute 'edit ' . s:v . '/d.md'
let s:before = getline(1, '$')
call s:pick(['[b](b.md)'])
call assert_equal(s:before, s:read('d')[:len(s:before)-1], 'preserve existing relations and body')
" Repair either direction without duplicating the existing side.
call s:mk('f', ['Related:', '[e](e.md)'])
execute 'edit ' . s:v . '/f.md'
call s:pick(['[e](e.md)'])
call assert_equal(1, count(s:read('f'), '[e](e.md)'))
call assert_equal(1, count(s:read('e'), '[f](f.md)'))
call s:mk('g', ['Related:', '[f](f.md)'])
call s:pick(['[g](g.md)'])
call assert_equal(1, count(s:read('f'), '[g](g.md)'))
" Invalid targets and self-links leave the source unchanged.
let s:before = s:read('f')
call s:pick(['[f](f.md)', '[missing](missing.md)'])
call assert_equal(s:before, s:read('f'))
" An unsaved target cancels the whole multiple-link operation.
execute 'edit ' . s:v . '/c.md'
call append('$', '未保存')
set hidden
execute 'edit ' . s:v . '/f.md'
let s:ebefore = s:read('e')
call s:pick(['[e](e.md)', '[c](c.md)'])
call assert_equal(s:before, s:read('f'))
call assert_equal(s:ebefore, s:read('e'))
call assert_equal(1, getbufvar(bufnr(s:v . '/c.md'), '&modified'))
execute 'bwipeout! ' . bufnr(s:v . '/c.md')
" A nonwritable target cancels before any relation is written.
call setfperm(s:v . '/c.md', 'r--r--r--')
call s:pick(['[c](c.md)', '[e](e.md)'])
call assert_equal(s:before, s:read('f'))
call setfperm(s:v . '/c.md', 'rw-r--r--')
" Group zn, zk and c submenu still reject r.
call writefile(['---', 'title: group', 'attribute: group', '---', '', '# group'], s:v . '/group.md')
execute 'edit ' . s:v . '/group.md'
let s:files = glob(s:v . '/*.md')
let g:gnosis_test_keys = ['r']
call gnosis#v2_new_plain()
call assert_equal(s:files, glob(s:v . '/*.md'))
execute 'edit ' . s:v . '/f.md'
let g:gnosis_test_keys = ['c', 'r']
call gnosis#insert_links_pick(['[e](e.md)'], getpos('.'))
call assert_equal(s:before, s:read('f'))
call assert_equal(s:ebefore, s:read('e'))
let g:gnosis_test_keys = ['r']
call gnosis#v2_new_group()
call assert_equal(s:files, glob(s:v . '/*.md'))
call assert_match('r=Related', gnosis#insert_prompt_text(1, 0))
call assert_notmatch('g=', gnosis#insert_prompt_text(1, 0))
call assert_match('g=', gnosis#insert_prompt_text(1, 1))
" Every first-stage key remains visible at 80 columns in both languages.
let s:cols = &columns
set columns=80
for s:lang in ['ja', 'en']
  call gnosis#i18n#set_lang(s:lang)
  let s:prompt = gnosis#insert_prompt_text(1, 1)
  for s:key in ['t=', 'g=', 'Enter=', 'p=', 'b=', 'h=', 'c=', 'r=Related']
    call assert_match(s:key, s:prompt)
  endfor
endfor
let &columns = s:cols
" A's unsaved body is saved together with Related, without losing edits.
call append(7, '未保存の本文')
call s:pick(['[b](b.md)'])
call assert_equal(1, count(s:read('f'), '未保存の本文'))
" zn cancellation and failure must not leave a new file.
let s:files = glob(s:v . '/*.md')
let g:gnosis_test_keys = ["\<Esc>"]
call gnosis#v2_new_plain()
call assert_equal(s:files, glob(s:v . '/*.md'))
sleep 1100m
setlocal readonly
let g:gnosis_test_keys = ['r']
call gnosis#v2_new_plain()
call assert_equal(s:files, glob(s:v . '/*.md'))
setlocal noreadonly
" Inject a one-time write failure into the private writer, after planning.
" This is test-only: subsequent calls can restore the original bytes.
let s:sid = filter(getscriptinfo(), 'v:val.name =~# "/autoload/gnosis.vim$"')[0].sid
let g:related_writes = 0
let g:related_fail_at = 2
execute "function! <SNR>" . s:sid . "_syn_writefile(lines, path, ...) abort\n"
      \ . "call gnosis#guard_vault_write(a:path)\n"
      \ . "let g:related_writes += 1\n"
      \ . "if g:related_writes == g:related_fail_at | throw 'injected write failure' | endif\n"
      \ . "return call('writefile', [a:lines, a:path] + a:000)\nendfunction"
let s:fsnap = readfile(s:v . '/f.md', 'b')
let s:csnap = readfile(s:v . '/c.md', 'b')
call s:pick(['[c](c.md)'])
call assert_equal(s:fsnap, readfile(s:v . '/f.md', 'b'), 'rollback A')
call assert_equal(s:csnap, readfile(s:v . '/c.md', 'b'), 'rollback B')
let g:related_writes = 0
let g:related_fail_at = 3
sleep 1100m
let g:gnosis_test_keys = ['r']
call gnosis#v2_new_plain()
call assert_equal(s:files, glob(s:v . '/*.md'), 'failed zn r leaves no new note')
call assert_equal(s:fsnap, readfile(s:v . '/f.md', 'b'), 'failed zn r leaves no one-sided link')
call writefile(v:errors, $RELATED_WORK . '/errors')
if !empty(v:errors) | cquit | endif
qa!
