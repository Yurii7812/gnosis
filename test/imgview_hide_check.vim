" \zz の「画像の行」: ![](…) だけの行が畳まれる（test/imgview_hide_net.sh から呼ぶ）。結果は $IMGH_WORK/result.txt
set nomore
let s:work = $IMGH_WORK
let s:res = []
let g:gnosis_open_index_on_startup = 0
function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
call writefile(['# n', '', '![](a.jpg)', '', '![](b.png)', '![](c.png)', '', '文 ![](d.png) 文', '```', '![](e.png)', '```', 'last'], s:work . '/n.md')
execute 'edit ' . s:work . '/n.md'
let s:r = gnosis#hide#regions(getline(1, '$'))
call s:ok('画像だけの行の範囲（続く行は 1 つ・文中・コードの中は除く）', s:r ==# [{'kind': 'image', 'from': 3, 'to': 3}, {'kind': 'image', 'from': 5, 'to': 6}], string(s:r))
call s:ok('既定はオフ', gnosis#hide#get().image == 0)
call gnosis#settings#set('hide.image', v:true)
call gnosis#hide#apply_all()
call s:ok('オンで 3 行目が畳まれる', foldclosed(3) == 3)
call s:ok('5〜6 行目は 1 つに畳まれる', foldclosed(6) == 5 && foldclosed(8) == -1)
call s:ok('文中の画像は畳まれない', foldclosed(8) == -1)
call s:ok('畳んだ表示', foldtextresult(3) =~# '画像' && foldtextresult(5) =~# '(2)', foldtextresult(5))
call gnosis#settings#set('hide.image', v:false)
call gnosis#hide#apply_all()
call s:ok('オフで戻る', foldclosed(3) == -1)
call writefile(s:res, s:work . '/result.txt')
qa!
