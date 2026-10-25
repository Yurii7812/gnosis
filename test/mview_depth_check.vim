" 曼荼羅: 外向き（v）の深さ（+ -）・何枚目か（1/1）・9×9 の [ ]（周りのブロックのページ）の回帰網。結果は $MD_WORK/result.txt
set nomore
let s:work = $MD_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1
let g:gnosis_mview_restore = 0
let g:gnosis_mview_border = 'line'

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
  call writefile(s:res, s:work . '/result.txt')
endfunction
function! s:keys(k) abort
  call feedkeys(a:k, 'xt')
endfunction
function! s:st() abort
  return gnosis#mview#state()
endfunction
function! s:names() abort
  let l:o = []
  for l:r in s:st().cells
    for l:c in l:r
      if get(l:c, 'role', '') ==# 'item' | call add(l:o, l:c.id) | endif
    endfor
  endfor
  return sort(l:o)
endfunction
function! s:mk(name, title, body) abort
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title, '---', '', '# ' . a:title, ''] + a:body, s:v . '/' . a:name)
endfunction
function! s:head() abort
  return getbufline(s:st().buf, 1, 1)[0]
endfunction

" index → a0 a1 a2 ／ a0 → b0 b1 ／ b0 → c0 ／ c0 → d0
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: Index', 'attribute: group', '---', '', '# Index', '', '[a0](a0.md)', '[a1](a1.md)', '[a2](a2.md)'] + map(range(10), '"[m" . v:val . "](m" . v:val . ".md)"'), s:v . '/index.md')
call s:mk('a0.md', 'a0', ['[b0](b0.md)', '[b1](b1.md)'])
call s:mk('a1.md', 'a1', [])
call s:mk('a2.md', 'a2', [])
call s:mk('b0.md', 'b0', ['[c0](c0.md)'])
call s:mk('b1.md', 'b1', [])
call s:mk('c0.md', 'c0', ['[d0](d0.md)'])
call s:mk('d0.md', 'd0', [])
for s:i in range(10)
  call s:mk('m' . s:i . '.md', 'm' . s:i, [])
endfor

execute 'edit ' . s:v . '/index.md'
call s:keys(' ')
" 何枚目か: # に関わらず、左上の [モード] のすぐ後ろに出る
call s:ok('1/1 でなく、何枚目かが [a] のすぐ後ろに出る（13 件 = 2 枚）', s:head() =~# '\[a\] 1/2', s:head())
call s:keys('#')
call s:ok('# で数字を消しても、何枚目かは出たまま', s:head() =~# '\[a\] 1/2', s:head())
call s:keys('#')
call s:keys(']')
call s:ok('] で 2/2', s:head() =~# '\[a\] 2/2', s:head())
call s:keys('[')
" 1 枚だけのときも 1/1
execute 'edit ' . s:v . '/b1.md'
call s:keys(' ')
call s:ok('1 枚だけなら 1/1', s:head() =~# '\[a\] 1/1', s:head())
call s:keys('Q')

" 外向きの深さ
execute 'edit ' . s:v . '/a0.md'
call s:keys(' ')
call s:keys('f')
call s:keys('v')
call s:ok('外向き 深さ 1: 直接のつながりだけ', s:names() ==# ['b0.md', 'b1.md'] || index(s:names(), 'c0.md') < 0, string(s:names()))
call gnosis#mview#set_depth(2)
call s:ok('深さ 2: その先（c0）も出る', index(s:names(), 'c0.md') >= 0 && index(s:names(), 'd0.md') < 0, string(s:names()))
call s:ok('ヘッダーに深さが出る', s:head() =~# 'out dep2', s:head())
call gnosis#mview#set_depth(3)
call s:ok('深さ 3 で d0 も', index(s:names(), 'd0.md') >= 0, string(s:names()))
call gnosis#mview#set_depth(99)
call s:ok('深さは 10 まで', s:st().depth == 10, string(s:st().depth))
call gnosis#mview#set_depth(1)
call s:ok('深さ 1 に戻り、直接のつながりだけ', s:st().depth == 1 && index(s:names(), 'c0.md') < 0, string([s:st().depth, s:names()]))
call gnosis#mview#set_depth(0)
call s:ok('深さ 1 より下には行かない', s:st().depth == 1)

" 設定の画面の行にも出る
call s:ok('設定の画面に外向きの深さの行がある', gnosis#mview#panel_text() =~# '外向きの深さ')

" 9×9 の [ ]: カーソルが周りのブロックにあるときは、そのブロックのページを送る
call s:keys('v')
execute 'edit ' . s:v . '/index.md'
call s:keys('Q')
call s:keys(' ')
call s:keys('f')
let s:st = s:st()
let s:st.cur = [1, 1]
call s:keys(']')
call s:ok('周りのブロックにカーソルがあるとき ] は周りのページ（opage）を送る（中心のページは動かない）', get(s:st(), 'opage', 0) >= 0 && s:st().page == 0, string([get(s:st(), 'opage', 0), s:st().page]))

call s:keys('Q')
call writefile(s:res, s:work . '/result.txt')
qa!
