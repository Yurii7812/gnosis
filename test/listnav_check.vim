set nomore
let s:v = $LIST_WORK . '/v'
let g:gnosis_root = s:v . '/'
let g:gnosis_start_screen = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_autosync = 0
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1
let g:gnosis_mview_restore = 0
let s:res = []
function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:0 ? ' ' . string(a:1) : ''))
  call writefile(s:res, $LIST_WORK . '/result')
endfunction
function! s:mk(name, title, fz, attr, body) abort
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'folgezettel: "' . a:fz . '"']
        \ + (a:attr ? ['attribute: group'] : []) + ['---', '', '# ' . a:title, ''] + a:body, s:v . '/' . a:name)
endfunction
function! s:paths() abort
  return map(copy(gnosis#listnav#state().rows), 'v:val.path')
endfunction
call s:mk('index.md', 'Index', '', 1, ['[Alpha](a.md)'])
call s:mk('a.md', 'Alpha garden', '1', 0, ['Group:', '[Garden](g.md)', '', 'ChildBranch:', '[Beta](b.md)', '', 'Context:', '[Context](c.md)', '', 'Related:', '[Related](r.md)', '', 'Original body', 'Original end'])
call s:mk('b.md', 'Beta garden', '1a', 0, ['ParentBranch:', '[Alpha](a.md)', '', 'ChildBranch:', '[Delta](d.md)', '', 'Body beta'])
call s:mk('d.md', 'Delta garden', '1a1', 0, ['ParentBranch:', '[Beta](b.md)', '', 'Needle body'])
call s:mk('c.md', 'Context garden', '2', 0, ['ParentBranch:', '[Related](r.md)', '', 'Context:', '[Alpha](a.md)'])
call s:mk('r.md', 'Related garden', '3', 0, ['Related:', '[Alpha](a.md)'])
call s:mk('e.md', 'Alpha garden research', '5', 0, ['Garden plants and soil'])
call s:mk('g.md', 'Garden group', '4', 1, ['[Unique alias](a.md)'])
execute 'edit ' . s:v . '/a.md'
call cursor(line('$') - 1, 3)
normal! zt
let s:origin = winsaveview()
call gnosis#mview#start()
call gnosis#mview#switch_view()
call s:ok('次のビューはFolgezettel', gnosis#mview#view() ==# 'fz')
call s:ok('Folgezettelにはリストのキーがある', maparg('s','n') =~# 'enter_mode' && maparg('l','n') =~# 'enter_mode' && maparg('r','n') =~# 'enter_mode' && maparg('m','n') =~# 'menu')
call gnosis#listnav#enter_mode('links')
call s:ok('lでリンクのリストへ', gnosis#mview#view() ==# 'list' && gnosis#listnav#state().mode ==# 'links')
call s:ok('リストは同じバッファで表示', &filetype ==# 'gnosis-mandala' && getline(1) =~# '^FOLGEZETTEL / ')
call s:ok('グループと子が並ぶ', index(s:paths(), 'g.md') >= 0 && index(s:paths(), 'b.md') >= 0, s:paths())
let s:before = fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t')
call gnosis#listnav#option('relation', 'child')
call s:ok('b相当は子だけに絞る', index(s:paths(), 'b.md') >= 0 && empty(filter(copy(gnosis#listnav#state().rows), 'v:val.kind !=# "child"')), s:paths())
call s:ok('絞るだけでは右を変えない', fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t') ==# s:before)
call gnosis#listnav#back()
call s:ok('Backspaceで絞り込み前へ', index(s:paths(), 'g.md') >= 0)
call gnosis#listnav#option('depth', 2)
call s:ok('深さ2で孫も表示', index(s:paths(), 'd.md') >= 0, s:paths())
let s:deep = filter(copy(gnosis#listnav#state().rows), 'v:val.path ==# "d.md"')
call s:ok('経由と深さを表示', len(s:deep) == 1 && s:deep[0].depth == 2 && s:deep[0].via ==# 'b.md', s:deep)
call gnosis#listnav#option('rank', 1)
call s:ok('近さ順でも候補は同じ', index(s:paths(), 'd.md') >= 0)
call gnosis#listnav#query('filter', 'Needle -absent')
call s:ok('xは本文と検索式で絞る', s:paths() ==# ['d.md'], s:paths())
call gnosis#listnav#query('filter', '')
call gnosis#listnav#option('mode', 'search')
call s:ok('検索語なしでは一覧を出さない', empty(gnosis#listnav#state().rows))
call gnosis#listnav#query('search', 'Unique alias')
call s:ok('gsと同じ索引名から検索', index(s:paths(), 'a.md') >= 0, s:paths())
call gnosis#listnav#option('scope', 'no-index')
call s:ok('索引以外には索引の表示名候補がない', empty(filter(copy(gnosis#listnav#state().rows), 'v:val.kind ==# "index"')))
call gnosis#listnav#query('search', 'garden | Needle -absent')
call s:ok('ORと除外も共用', index(s:paths(), 'd.md') >= 0)
call gnosis#listnav#query('highlight', 'garden')
call s:ok('mはハイライトを付ける', !empty(filter(prop_list(3), 'v:val.type ==# "gnosis_nav_match"')))
call s:ok('GUIもリストの同じ行を受け取る', get(gnosis#mview#gui_state(), 'view', '') ==# 'list')
let s:anchor = gnosis#listnav#state().anchor
call gnosis#listnav#move(1)
sleep 100m
call s:ok('カーソル移動で右にプレビュー', fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t') ==# gnosis#listnav#state().rows[line('.') - 3].path)
call s:ok('プレビューで基準は動かない', gnosis#listnav#state().anchor ==# s:anchor && gnosis#mview#state().center ==# s:anchor)
call gnosis#listnav#origin()
call s:ok('oで元のノートへ戻る', fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t') ==# 'a.md')
call s:ok('o は左の基準を動かさない', gnosis#listnav#state().anchor ==# s:anchor)
call gnosis#mview#center_rel('d.md')
call s:ok('（準備）左の基準を a.md 以外にした', gnosis#mview#state().center ==# 'd.md')
call gnosis#listnav#goto_origin()
call s:ok('O: 右に元のノート、左の中心も元のノート', fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t') ==# 'a.md' && gnosis#mview#state().center ==# gnosis#listnav#state().origin.path, string([gnosis#mview#state().center, gnosis#listnav#state().origin]))
let s:ov = gnosis#listnav#state().origin.view
let s:cur = getcurpos(gnosis#mview#note_win())
call s:ok('元のカーソル位置も復元する', s:cur[1] == s:ov.lnum && s:cur[2] == s:ov.col + 1, [s:cur, s:ov])
call gnosis#listnav#query('search', '')
call gnosis#listnav#query('highlight', '')
call gnosis#listnav#option('mode', 'similar')
call s:ok('類似は予測関連の候補を表示', !empty(gnosis#listnav#state().rows) && empty(filter(copy(gnosis#listnav#state().rows), 'v:val.kind !=# "pred"')), s:paths())
let s:handoff = gnosis#mview#handoff()
call gnosis#mview#switch_view('mandala')
call gnosis#mview#restore_handoff(s:handoff)
call s:ok('GUI/CUI引継ぎでリストのモードとキーを保つ', gnosis#mview#view() ==# 'list' && gnosis#listnav#state().mode ==# 'similar' && maparg('x','n') =~# 'listnav')
call gnosis#mview#switch_view()
call s:ok('リストの次は曼荼羅', gnosis#mview#view() ==# 'mandala')
call gnosis#mview#switch_view('previous')
call s:ok('逆方向でFolgezettelへ', gnosis#mview#view() ==# 'fz')
call gnosis#listnav#enter_mode('similar')
call s:ok('rで類似のリストへ', gnosis#mview#view() ==# 'list' && gnosis#listnav#state().mode ==# 'similar')
call gnosis#mview#switch_view('fz')
call s:ok('fでFolgezettelへ戻る', gnosis#mview#view() ==# 'fz')
call gnosis#listnav#enter_mode('links')
let s:cur_before = gnosis#mview#state().center
call gnosis#listnav#move(1)
call gnosis#listnav#enter()
call s:ok('Enterでは右のノートへカーソルを移さない', &filetype ==# 'gnosis-mandala')
" \l はリストのどのモードでも使え、選ぶモードの最中も Enter でビューに留まる
for s:m in ['links', 'similar', 'search']
  call gnosis#listnav#option('mode', s:m)
  call gnosis#mview#link_pick()
  call s:ok('リスト(' . s:m . ')で \\l: 選ぶモードになる', gnosis#mview#state().pick ==# 'link' && gnosis#mview#view() ==# 'list', gnosis#mview#state())
  call gnosis#listnav#enter()
  call s:ok('選ぶモードでは Enter でも窓に留まる(' . s:m . ')', &filetype ==# 'gnosis-mandala')
  call gnosis#mview#quit_layers()
endfor
" , （画像）は曼荼羅系の窓でも効く: 窓の中に , の専用割り当てが無く、全体の割り当てが生きている。右のノートに画像が無ければその旨を出す
call s:ok(', はビューの窓でも全体の割り当て', maparg(',', 'n', 0, 1).buffer == 0 && maparg(',', 'n') =~# 'imgview#open')
redir => s:imsg
silent call gnosis#imgview#open()
redir END
call s:ok('ビューの窓から , を押すと右のノートの画像を調べる', s:imsg =~# '画像はありません' || s:imsg =~# 'Markdown', s:imsg)
" \e は左窓に出ているノート全部を、出ている順に 1 つの md にまとめる（リストビュー・Folgezettel・曼荼羅）
call gnosis#listnav#enter_mode('links')
let s:shown = gnosis#mview#shown_paths()
call s:ok('リストの \e の入力は一覧そのまま', s:shown ==# s:paths() && len(s:shown) > 1, s:shown)
call gnosis#mview#switch_view('mandala')
let s:mp = gnosis#mview#shown_paths()
call s:ok('曼荼羅の入力は中心と周り全部', s:mp[0] ==# gnosis#mview#state().center && len(s:mp) > 2, s:mp)
call gnosis#mview#switch_view('fz')
let s:fzp = gnosis#mview#shown_paths()
call s:ok('Folgezettel の入力は番号順の全部', len(s:fzp) > 2 && s:fzp[0] ==# 'a.md' && index(s:fzp, 'd.md') > index(s:fzp, 'b.md'), s:fzp)
call gnosis#mview#switch_view('list')
let s:want = gnosis#mview#shown_paths()
call gnosis#v2_expand()
let s:outf = expand('%:p')
call s:ok('\e の出力は .trash の md', s:outf =~# '/\.trash/T_.*\.md$', s:outf)
let s:txt = join(getline(1, '$'), "\n")
let s:heads = map(filter(split(s:txt, "\n"), 'v:val =~# "^## " && v:val !=# "## 目次"'), 'strpart(v:val, 3)')
call s:ok('\e の出力は一覧の順', s:heads ==# ['Alpha garden', 'Delta garden', 'Context garden', 'Related garden', 'Garden group'], s:heads)
call gnosis#mview#close()
qa!
