" test/requests_1020b_net.sh から使う。$D に vault（v/）を用意して呼ぶ。
set nocp
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
let g:R = []
function! F(name) abort
  return readfile($D . '/v/' . a:name)
endfunction
function! Has(name, pat) abort
  return len(filter(F(a:name), 'v:val =~# a:pat'))
endfunction
function! Ctx(name, target) abort
  " a:name の Context: のブロックに a:target へのリンクがあるか
  let l:in = 0
  for l:ln in F(a:name)
    if l:ln =~# '^Context:$'
      let l:in = 1
    elseif l:in && l:ln =~# '^\['
      if l:ln =~# '(' . a:target . ')'
        return 1
      endif
    else
      let l:in = 0
    endif
  endfor
  return 0
endfunction

" 1) c → i: C の Context: に A。A には、カーソルの文字のすぐ後ろに C へのリンク
execute 'edit ' . fnameescape($D . '/v/a.md')
call cursor(search('^あいう$'), 1)
let g:gnosis_test_keys = ['c', 'i']
call gnosis#insert_links_pick(['[シー](c.md)'], getpos('.'))
call add(g:R, 'c-i ' . get(filter(F('a.md'), 'v:val =~# "^あ"'), 0, ''))
call add(g:R, 'c-i-ctx ' . Ctx('c.md', 'a.md'))

" 2) c → o: D の Context: に A。A にはリンクを置かない
let g:gnosis_test_keys = ['c', 'o']
call gnosis#insert_links_pick(['[D](d.md)'], getpos('.'))
let s:a = F('a.md')
let s:cb = index(s:a, 'ChildBranch:')
call add(g:R, 'c-o-body ' . len(filter(s:a[: (s:cb < 0 ? -1 : s:cb - 1)], 'v:val =~# "(d.md)"')))
call add(g:R, 'c-o-ctx ' . Ctx('d.md', 'a.md'))

" 3) a → Enter: B（の Context ではなく）今のノート E の Context: に B。B の本文の最後に E へのリンク
execute 'edit ' . fnameescape($D . '/v/e.md')
let g:gnosis_test_keys = ['a', "\<CR>"]
call gnosis#insert_links_pick(['[B](b.md)'], getpos('.'))
call add(g:R, 'a-end-ctx ' . Ctx('e.md', 'b.md'))
call add(g:R, 'a-end-back ' . Has('b.md', '^\[E\](e.md)$'))

" 4) a → o: E の Context: に C。C には何も書かない
let g:gnosis_test_keys = ['a', 'o']
call gnosis#insert_links_pick(['[シー](c.md)'], getpos('.'))
call add(g:R, 'a-o-ctx ' . Ctx('e.md', 'c.md'))
call add(g:R, 'a-o-back ' . Has('c.md', '(e.md)'))

" 5) a → w: E の Context: に D。E へのリンクをヤンクして D を開く（D には自動で書かない）
let g:gnosis_test_keys = ['a', 'w']
call gnosis#insert_links_pick(['[D](d.md)'], getpos('.'))
call add(g:R, 'a-w-ctx ' . Ctx('e.md', 'd.md'))
call add(g:R, 'a-w-open ' . expand('%:t') . ' ' . @")

" 6) ParentBranch: のリンクで親へ移ると、- [x] の行でもリンクの上（チェックボックスの左ではない）
execute 'edit ' . fnameescape($D . '/v/q.md')
call cursor(search('^\[P\]'), 1)
call gnosis#open_link_under_cursor()
call add(g:R, 'nav ' . (line('.') - search('^- \[x\]', 'nw') + 3) . ' ' . col('.'))

" 7) \y: 題と本文だけ（ノートへのリンクは表示名だけ。URL のリンクはそのまま）
execute 'edit ' . fnameescape($D . '/v/q.md')
call gnosis#yank_title_body()
call add(g:R, 'yank ' . string(getreg('"', 1, 1)))

call writefile(g:R, $D . '/out.txt')
qa!
