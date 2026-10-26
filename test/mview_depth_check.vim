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

" B は設定画面の外でも動き、表示条件を勝手に切り替えない
execute 'edit ' . s:v . '/a0.md'
call s:keys(' ')
let s:before = deepcopy(s:st())
let s:basis = get(s:before, 'dbasis', 'center')
call s:keys('B')
call s:ok('3x3 の B も基準を変更・近さ順と大きさは維持', get(s:st(), 'dbasis', 'center') !=# s:basis && s:st().size == s:before.size && get(s:st(), 'rank_on', 0) == get(s:before, 'rank_on', 0))
call s:keys('f')
if !get(s:st(), 'rank_on', 0) | call s:keys('w') | endif
call s:keys('B')
call s:ok('通常9x9 の B は現在の基準も表示', s:head() =~# (get(s:st(), 'dbasis', 'center') ==# 'self' ? 'rank(block)' : 'rank(center)'))
call s:keys('v')
let s:before = deepcopy(s:st())
call s:keys('B')
call s:ok('外向きの B は基準を保存して方向と深さを維持', s:st().dbasis !=# s:before.dbasis && s:st().out_on && s:st().depth == s:before.depth && get(s:st(), 'out_dir', 'all') ==# get(s:before, 'out_dir', 'all') && s:head() !~# 'rank(')
call s:keys('vwfQ')

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
" 配下だけ: 親・所属索引・引用・BackLink・関連へは一段目から広げない。
call s:mk('root.md', 'Root', ['[引用](quote.md)', '', 'ParentBranch:', '[Parent](parent.md)', '', 'Group:', '[Index](index.md)', '', 'ChildBranch:', '[Child](child.md)', '', 'Related:', '[Side](side.md)', '', 'BackLink:', '[Back](back.md)'])
call s:mk('parent.md', 'Parent', ['ChildBranch:', '[Root](root.md)', '[Sibling](sibling.md)'])
call s:mk('child.md', 'Child', ['ParentBranch:', '[Root](root.md)', '', 'ChildBranch:', '[Leaf](leaf.md)', '', 'Related:', '[Leak](leak.md)'])
call s:mk('inverse.md', 'Inverse', ['ParentBranch:', '[Root](root.md)'])
call s:mk('leaf.md', 'Leaf', ['ChildBranch:', '[Root](root.md)'])
for s:f in ['quote', 'side', 'back', 'sibling', 'leak']
  call s:mk(s:f . '.md', s:f, [])
endfor
execute 'edit ' . s:v . '/root.md'
call s:keys(' ')
call gnosis#mview#set_depth(3)
call gnosis#mview#preset_save('通常')
call s:keys('D')
call s:ok('D で配下だけ・深さは維持', get(s:st(), 'out_dir', '') ==# 'down' && s:st().depth == 3)
call s:ok('子・逆向きの親指定・孫だけ。循環や横の枝を除く', s:names() ==# ['child.md', 'inverse.md', 'leaf.md'], string(s:names()))
call s:ok('CUI と GUI に方向と深さを表示', s:head() =~# 'down-dep3' && gnosis#mview#gui_state().status =~# 'down-dep3' && gnosis#mview#gui_state().flags.outDir ==# 'down')
call gnosis#mview#set_depth(1)
call s:ok('配下の深さ 1 は直下だけ', s:names() ==# ['child.md', 'inverse.md'], string(s:names()))
call gnosis#mview#set_depth(2)
call s:ok('配下の深さ 2 で孫を含む', s:names() ==# ['child.md', 'inverse.md', 'leaf.md'], string(s:names()))
call s:keys('D')
call s:ok('D でもう一度通常へ・深さは維持', get(s:st(), 'out_dir', '') ==# 'all' && s:st().depth == 2 && index(s:names(), 'parent.md') >= 0 && index(s:names(), 'quote.md') >= 0)
call s:keys('DCR')
call s:ok('重ねる設定があっても配下だけ', s:names() ==# ['child.md', 'inverse.md', 'leaf.md'], string(s:names()))
call s:keys('D')
call s:ok('通常へ戻すと重ねる設定もそのまま', get(s:st(), 'near_on', 0) && get(s:st(), 'rel_on', 0))
call s:keys('CRfD')
call s:ok('3x3 から D でも外向き・配下だけになる', s:st().size == 9 && s:st().out_on && s:st().out_dir ==# 'down' && s:st().depth == 2)
let s:basis = get(s:st(), 'dbasis', 'center')
let s:direction_row = match(split(gnosis#mview#panel_text(), "\n"), '外向きに辿る方向 D') - 2
call gnosis#mview#panel_act(s:direction_row)
call s:ok('Z の D も同じ切り替え', s:st().out_dir ==# 'all' && get(s:st(), 'dbasis', 'center') ==# s:basis)
call s:ok('設定に D の方向・B の近さ基準がある', gnosis#mview#panel_text() =~# '外向きに辿る方向 D' && gnosis#mview#panel_text() =~# '近さ順の基準 rank（center ⇔ block。通常9×9の外側） B')
call s:keys('D')
call gnosis#mview#preset_save('配下')
call s:keys('D')
call gnosis#mview#set_depth(1)
call gnosis#mview#preset_apply('配下')
call s:ok('プリセットは方向と深さを復元', s:st().out_dir ==# 'down' && s:st().depth == 2)
call gnosis#mview#preset_apply('通常')
call s:ok('古い形式のプリセットも通常方向へ戻る', s:st().out_dir ==# 'all' && s:st().depth == 3)
" グループは収録先と下位グループ。別名による重複も一度だけ。
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: Tree', 'attribute: group', '---', '', '# Tree', '', '[Root](root.md)', '[別名](root.md)', '[Sub](sub.md)', '', 'Group:', '[Index](index.md)'], s:v . '/tree.md')
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: Sub', 'attribute: group', '---', '', '# Sub', '', '[Leaf](leaf.md)', '', 'Group:', '[Tree](tree.md)'], s:v . '/sub.md')
call s:keys('Q')
execute 'edit ' . s:v . '/tree.md'
call s:keys(' ')
call gnosis#mview#set_depth(1)
call s:keys('D')
call s:ok('索引の収録先だけで所属先へ戻らない', s:names() ==# ['root.md', 'sub.md'], string(s:names()))
call gnosis#mview#set_depth(2)
call s:ok('下位グループの収録先・子も深さ順に出る', s:names() ==# ['child.md', 'inverse.md', 'leaf.md', 'root.md', 'sub.md'], string(s:names()))
" 見出しは下位だけ。本文の引用や親・兄弟の節を辿らない。
call s:mk('outline-down.md', 'Outline', ['## Chapter', '[引用](quote.md)', '#### Skipped', '##### Deep', '### Section', '#### Leaf', '## Sibling'])
call s:keys('Q')
execute 'edit ' . s:v . '/outline-down.md'
call s:keys(' ')
call gnosis#mview#set_depth(3)
let s:heading = gnosis#mview#handoff()
let s:heading.center = 'outline-down.md#chapter'
let s:heading.out_dir = 'down'
let s:heading.ol_on = 1
call gnosis#mview#restore_handoff(s:heading)
call s:ok('下位見出しだけ。飛び級の見出しも含む', s:names() ==# ['outline-down.md#deep', 'outline-down.md#leaf', 'outline-down.md#section', 'outline-down.md#skipped'], string(s:names()))
call s:ok('各見出しの深さは階層の辺で数える', get(s:st().dmap, 'outline-down.md#skipped', 0) == 1 && get(s:st().dmap, 'outline-down.md#deep', 0) == 2)
" Vim を起動し直しても方向・深さを維持する。
call s:keys('Q')
call gnosis#mview#reset_for_test()
let g:gnosis_mview_restore = 1
execute 'edit ' . s:v . '/root.md'
call s:keys(' ')
call s:ok('再起動相当でも方向と深さを復元', get(s:st(), 'out_dir', '') ==# 'down' && get(s:st(), 'depth', 0) == 3 && get(s:st(), 'out_on', 0))
call s:keys('Q')
call writefile(s:res + ['DONE'], s:work . '/result.txt')
qa!
