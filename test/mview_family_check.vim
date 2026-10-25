" 曼荼羅の「親子だけ」モード（,）と、右に出る設定の画面（'）の回帰網。結果は $MF_WORK/result.txt（test/mview_family_net.sh から呼ぶ）
set nomore
let s:work = $MF_WORK
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

call s:mk('top.md', '上位', ['ParentBranch:', '[親](par.md)', '', '本文 [リンク先](linkonly.md)', '', 'ChildBranch:', '[子1](kid1.md)'])
call s:mk('par.md', '親', ['ChildBranch:', '[上位](top.md)'])
call s:mk('kid1.md', '子1', [])
" top の ChildBranch: に書かれていないが、自分の ParentBranch: で top を指している子
call s:mk('kid2.md', '子2', [])
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 子2', '---', '', '# 子2', '', 'ParentBranch:', '[上位](top.md)', ''], s:v . '/kid2.md')
call s:mk('linkonly.md', 'リンク先', [])
call s:mk('index.md', 'Index', [])

execute 'edit ' . s:v . '/top.md'
call s:keys(' ')
call s:ok('全体では普通のリンクも出る', index(s:names(), 'linkonly.md') >= 0 && index(s:names(), 'kid1.md') >= 0, string(s:names()))
call s:keys('d')
call s:ok(', で親子モードになる', s:st().mode ==# 'family', s:st().mode)
call s:ok('親子: 親・子が出る', index(s:names(), 'par.md') >= 0 && index(s:names(), 'kid1.md') >= 0, string(s:names()))
call s:ok('親子: 相手の ParentBranch: に書かれているだけの子も出る', index(s:names(), 'kid2.md') >= 0, string(s:names()))
call s:ok('親子: 普通のリンクは出ない', index(s:names(), 'linkonly.md') < 0, string(s:names()))
call s:ok('親子: ヘッダーのモードの印が d になる', getbufline(s:st().buf, 1, 3)->join("\n") =~# '\[d\]', join(getbufline(s:st().buf, 1, 3), "\n"))
call s:keys('a')
call s:ok('a で全体に戻る', s:st().mode ==# 'all' && index(s:names(), 'linkonly.md') >= 0)
call s:keys('i')
call s:ok('i は今までどおり索引だけ', s:st().mode ==# 'groups' && index(s:names(), 'kid1.md') < 0, string(s:names()))
call s:keys('a')
call s:keys('b')

" 設定の画面（'）の行と操作
let s:t = gnosis#mview#panel_text()
call s:ok('設定の画面に モード と プリセット の段がある', s:t =~# 'モード' && s:t =~# 'プリセット' && s:t =~# '近いグループ', s:t)
call s:ok('設定の画面にモードの 3 つが出る', s:t =~# '全体' && s:t =~# '索引' && s:t =~# '親子', s:t)
call gnosis#mview#panel_act(0)
call s:ok('モードの行の操作で 全体 → 索引', s:st().mode ==# 'groups', s:st().mode)
call gnosis#mview#panel_act(0)
call s:ok('次は 親子', s:st().mode ==# 'family', s:st().mode)
call gnosis#mview#panel_act(0)
call s:ok('次は 全体に戻る', s:st().mode ==# 'all', s:st().mode)
call gnosis#mview#panel_act(2)
call s:ok('近いグループの行の操作でオンになる', get(s:st(), "near_on", 0), string(s:st().near_on))
call gnosis#mview#panel_act(2)
call s:ok('もう一度でオフ', !get(s:st(), "near_on", 0))
call gnosis#mview#panel_act(5)
call s:ok('数字キーの動きの行の操作で切り替わる', s:st().digit !=# 'jump', s:st().digit)
call gnosis#mview#panel_act(5)

" プリセットに親子モードも入る
call s:keys('d')
call gnosis#mview#preset_save('親子用')
call s:keys('a')
call gnosis#mview#preset_apply('親子用')
call s:ok('プリセットを呼び出すと親子モードに戻る', s:st().mode ==# 'family', s:st().mode)
call s:ok('設定の画面にプリセットの名前が出る', gnosis#mview#panel_text() =~# '親子用')
call gnosis#mview#preset_delete('親子用')

call s:keys('Q')
call writefile(s:res, s:work . '/result.txt')
qa!
