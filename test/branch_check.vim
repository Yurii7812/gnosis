" Branch（b モード）の回帰網（test/branch_net.sh から呼ぶ）。
"   zn / zk / za / \l の位置キー b: 親の ChildBranch ＋ 子の ParentBranch を両方に書く。
"   2 つ目の親・自己参照・循環・index.md は拒否し、どのノートも（バッファも）変更しない。
" 結果は $BRANCH_WORK/result.txt に「OK 名前」「NG 名前: 詳細」で書く。
set nomore
let s:work = $BRANCH_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
function! s:mk(name, title, body, ...) abort
  let l:attr = a:0 && a:1 ? ['attribute: group'] : []
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title] + l:attr + ['---', '', '# ' . a:title, ''] + a:body, s:v . '/' . a:name)
endfunction
function! s:file(name) abort
  return readfile(s:v . '/' . a:name)
endfunction
function! s:count(name, pat) abort
  return len(filter(s:file(a:name), 'v:val =~# a:pat'))
endfunction
function! s:msgs() abort
  redir => l:m
  silent messages
  redir END
  return l:m
endfunction
function! s:files() abort
  return map(glob(s:v . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")')
endfunction
function! s:newest_except(before) abort
  let l:now = filter(s:files(), 'index(a:before, v:val) < 0')
  return get(l:now, 0, '')
endfunction

call s:mk('index.md', 'Index', ['[A](a.md)'], 1)
call s:mk('a.md', 'ノートA', ['本文の文。', ''])
call s:mk('b.md', 'ノートB', ['B の本文。'])
call s:mk('c.md', 'ノートC', ['C の本文。'])
call s:mk('d.md', 'ノートD', ['D の本文。'])
call s:mk('e.md', 'ノートE', ['E の本文。'])

" ---------------------------------------------------------------- zn → b（新ノートを子として作る）
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:before = s:files()
let g:gnosis_test_keys = ['b']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:n1 = s:newest_except(s:before)
call s:ok('zn b: 新ノートができる', !empty(s:n1))
call s:ok('zn b: A に ChildBranch と新ノートへのリンク', index(s:file('a.md'), 'ChildBranch:') >= 0 && s:count('a.md', '(' . s:n1 . ')') == 1)
call s:ok('zn b: 新ノートに ParentBranch と A へのリンク', index(s:file(s:n1), 'ParentBranch:') >= 0 && s:count(s:n1, '^\[ノートA\](a\.md)$') == 1)
call s:ok('zn b: Context には入れない', empty(gnosis#context#find_block(s:file('a.md'))) && empty(gnosis#context#find_block(s:file(s:n1))) && index(s:file('a.md'), '### Context') < 0)
call s:ok('zn b: 新ノートが開いている', expand('%:t') ==# s:n1)

" ---------------------------------------------------------------- 2 本目の子（1 つの親から複数の子）
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:before = s:files()
let g:gnosis_test_keys = ['b']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:n2 = s:newest_except(s:before)
call s:ok('zn b 2 本目: A の ChildBranch に 2 本', s:count('a.md', '^ChildBranch:$') == 1 && s:count('a.md', '(' . s:n1 . ')') == 1 && s:count('a.md', '(' . s:n2 . ')') == 1)
call s:ok('zn b 2 本目: 2 本目の子の親も A', s:count(s:n2, '^\[ノートA\](a\.md)$') == 1)

" ---------------------------------------------------------------- za → b（既存ノート B を子に）
execute 'edit ' . fnameescape(s:v . '/a.md')
let @" = '[ノートB](b.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('za b: A の ChildBranch に B', s:count('a.md', '^\[ノートB\](b\.md)$') == 1)
call s:ok('za b: B の ParentBranch に A', index(s:file('b.md'), 'ParentBranch:') >= 0 && s:count('b.md', '^\[ノートA\](a\.md)$') == 1)
call s:ok('za b: バッファが読み直されている（未保存でない）', !&modified && join(getline(1, '$'), "\n") ==# join(s:file('a.md'), "\n"))

" ---------------------------------------------------------------- 同じ組をもう一度（重複を作らない）
let s:a_snap = s:file('a.md')
let s:b_snap = s:file('b.md')
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('za b 再実行: 重複を作らない', s:file('a.md') ==# s:a_snap && s:file('b.md') ==# s:b_snap)

" ---------------------------------------------------------------- 2 つ目の親は拒否（C から B）
execute 'edit ' . fnameescape(s:v . '/c.md')
let s:c_snap = s:file('c.md')
let @" = '[ノートB](b.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('C→B 拒否: C は変わらない', s:file('c.md') ==# s:c_snap && getline(1, '$') ==# s:c_snap)
call s:ok('C→B 拒否: B の親は A のまま（C を足さない・A を消さない）', s:file('b.md') ==# s:b_snap)
call s:ok('C→B 拒否: A も変わらない', s:file('a.md') ==# s:a_snap)

" ---------------------------------------------------------------- 自己参照は拒否
execute 'edit ' . fnameescape(s:v . '/c.md')
let @" = '[ノートC](c.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('自己参照 拒否: C は変わらない', s:file('c.md') ==# s:c_snap)

" ---------------------------------------------------------------- 循環は拒否（A → B、B → D、D → A）
execute 'edit ' . fnameescape(s:v . '/b.md')
let @" = '[ノートD](d.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('B→D: 追加できる', s:count('b.md', '^\[ノートD\](d\.md)$') == 1 && s:count('d.md', '^\[ノートB\](b\.md)$') == 1)
let s:d_snap = s:file('d.md')
let s:a2 = s:file('a.md')
execute 'edit ' . fnameescape(s:v . '/d.md')
let @" = '[ノートA](a.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('D→A 循環 拒否: D も A も変わらない', s:file('d.md') ==# s:d_snap && s:file('a.md') ==# s:a2)

" ---------------------------------------------------------------- index.md からの zn → b は何も作らない
execute 'edit ' . fnameescape(s:v . '/index.md')
let s:before = s:files()
let s:i_snap = s:file('index.md')
let g:gnosis_test_keys = ['b']
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('index.md の zn b: 新ノートを作らない・index.md も変わらない', s:files() ==# s:before && s:file('index.md') ==# s:i_snap)

" ---------------------------------------------------------------- 未保存の編集は失われない（保存してから足す）
execute 'edit ' . fnameescape(s:v . '/e.md')
call append(line('$'), '未保存で書いた行')
let @" = '[ノートC](c.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('未保存の編集: ファイルに残り、ChildBranch も入る', s:count('e.md', '^未保存で書いた行$') == 1 && s:count('e.md', '^\[ノートC\](c\.md)$') == 1 && !&modified)
call s:ok('未保存の編集: C の ParentBranch は E', s:count('c.md', '^\[ノートE\](e\.md)$') == 1)

" ---------------------------------------------------------------- \l（gnosis#insert_links_pick）からの b
call s:mk('f.md', 'ノートF', ['F の本文。'])
execute 'edit ' . fnameescape(s:v . '/e.md')
let g:gnosis_test_keys = ['b']
call gnosis#insert_links_pick(['[ノートF](f.md)'], getpos('.'))
call s:ok('\l b: E の ChildBranch に F・F の ParentBranch に E', s:count('e.md', '^\[ノートF\](f\.md)$') == 1 && s:count('f.md', '^\[ノートE\](e\.md)$') == 1)

" ---------------------------------------------------------------- zk → b（グループノートを子に）
execute 'edit ' . fnameescape(s:v . '/f.md')
let s:before = s:files()
let g:gnosis_test_keys = ['b']
sleep 1100m
call gnosis#v2_new_group()
stopinsert
let s:g = s:newest_except(s:before)
call s:ok('zk b: グループノートが F の ChildBranch に入る', !empty(s:g) && s:count('f.md', '(' . s:g . ')') == 1 && s:count(s:g, '^attribute: group$') == 1 && s:count(s:g, '^\[ノートF\](f\.md)$') == 1)

" ---------------------------------------------------------------- 既存の c / Enter は意味が変わらない
execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ['c', "\r"]
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:nc = s:newest_except(s:before)
call s:ok('zn c Enter: Context と自動 Branch が共存', !empty(s:nc)
      \ && !empty(gnosis#context#find_block(s:file('d.md')))
      \ && s:count('d.md', '^ChildBranch:$') == 1
      \ && s:count(s:nc, '^ParentBranch:$') == 1
      \ && empty(gnosis#context#find_block(s:file(s:nc)))
      \ && s:count(s:nc, '^\[ノートD\](d\.md)$') >= 1)
execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:ne = s:newest_except(s:before)
call s:ok('zn Enter: 本文リンク・Branch・Context が共存', !empty(s:ne)
      \ && s:count('d.md', '(' . s:ne . ')') >= 2
      \ && s:count(s:ne, '^ParentBranch:$') == 1 && !empty(gnosis#context#find_block(s:file(s:ne)))
      \ && gnosis#context#find_block(s:file(s:ne))[1] < index(s:file(s:ne), 'ParentBranch:')
      \ && s:count(s:ne, '^\[ノートD\](d\.md)


" ---------------------------------------------------------------- zn h / t は派生関係を付けるが Context は増やさない
execute 'edit ' . fnameescape(s:v . '/d.md')
call cursor(8, 1)
let s:before = s:files()
let g:gnosis_test_keys = ['h']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:nh = s:newest_except(s:before)
call s:ok('zn h: 自動 Branch / 新ノートの Context は無し', !empty(s:nh)
      \ && s:count(s:nh, '^ParentBranch:$') == 1
      \ && empty(gnosis#context#find_block(s:file(s:nh))) && s:count('d.md', '(' . s:nh . ')') >= 2)

execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_heading = 'ノートD'
let g:gnosis_test_keys = ['t']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
unlet g:gnosis_test_heading
let s:nt = s:newest_except(s:before)
call s:ok('zn t: 見出し下に置いても自動 Branch / Context は無し', !empty(s:nt)
      \ && s:count(s:nt, '^ParentBranch:$') == 1
      \ && s:count(s:nt, '^### Context

" ---------------------------------------------------------------- o は孤立、zk は明示的な b/p だけ Branch を付ける
execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ['o']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:no = s:newest_except(s:before)
call s:ok('zn o: Branch と本文リンクを作らない', !empty(s:no)
      \ && s:count(s:no, 'Branch') == 0 && s:count('d.md', '(' . s:no . ')') == 0)

execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_group()
stopinsert
let s:ng = s:newest_except(s:before)
call s:ok('zk Enter: Group は自動 Branch の対象外', !empty(s:ng)
      \ && s:count(s:ng, 'Branch') == 0 && s:count(s:ng, '^attribute: group$') == 1)

" ---------------------------------------------------------------- index.md からの通常作成は Branch の親にしない
execute 'edit ' . fnameescape(s:v . '/index.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:ni = s:newest_except(s:before)
call s:ok('zn Enter: index.md は Branch を作らず通常のリンクだけ', !empty(s:ni)
      \ && s:count(s:ni, 'Branch') == 0 && s:count('index.md', '(' . s:ni . ')') == 1)

" ================================================================ p モード（現在のノートの親を追加）
call s:mk('p1.md', 'ノートP1', ['P1 の本文。'])
call s:mk('q1.md', 'ノートQ1', ['Q1 の本文。'])
call s:mk('r1.md', 'ノートR1', ['R1 の本文。'])
call s:mk('s1.md', 'ノートS1', ['S1 の本文。'])
call s:mk('t1.md', 'ノートT1', ['T1 の本文。'])
" b: P1 → Q1 / p: S1 の親に R1（どちらも「親 ChildBranch・子 ParentBranch」の同じ形になる）
execute 'edit ' . fnameescape(s:v . '/p1.md')
let @" = '[ノートQ1](q1.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
execute 'edit ' . fnameescape(s:v . '/s1.md')
let @" = '[ノートR1](r1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 現在のノート S1 の ParentBranch に R1', index(s:file('s1.md'), 'ParentBranch:') >= 0 && s:count('s1.md', '^\[ノートR1\](r1\.md)$') == 1)
call s:ok('p: 相手 R1 の ChildBranch に S1', index(s:file('r1.md'), 'ChildBranch:') >= 0 && s:count('r1.md', '^\[ノートS1\](s1\.md)$') == 1)
call s:ok('p: バッファが読み直されている', !&modified && join(getline(1, '$'), "\n") ==# join(s:file('s1.md'), "\n"))
call s:ok('b と p は同じ形の関係を作る（親に ChildBranch・子に ParentBranch）',
      \ s:file('p1.md')[-2 :] ==# ['ChildBranch:', '[ノートQ1](q1.md)'] && s:file('q1.md')[-2 :] ==# ['ParentBranch:', '[ノートP1](p1.md)']
      \ && s:file('r1.md')[-2 :] ==# ['ChildBranch:', '[ノートS1](s1.md)'] && s:file('s1.md')[-2 :] ==# ['ParentBranch:', '[ノートR1](r1.md)'])
" 同じ関係をもう一度（重複しない）
let s:s1 = s:file('s1.md')
let s:r1 = s:file('r1.md')
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p 再実行: 重複を作らない', s:file('s1.md') ==# s:s1 && s:file('r1.md') ==# s:r1)
" 既に親がある S1 に、別の親 T1 を p で足せない（どちらも変更しない）
let s:t1 = s:file('t1.md')
let @" = '[ノートT1](t1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 既に親がある S1 に別の親は付けられない（S1・T1・R1 は変わらない）', s:file('s1.md') ==# s:s1 && s:file('t1.md') ==# s:t1 && s:file('r1.md') ==# s:r1 && getline(1, '$') ==# s:s1)
call s:ok('p: 拒否の理由に現在の親のタイトルを出す', s:msgs() =~# 'ノートR1' || s:msgs() =~# 'R1')
" b でも、既に親がある S1 を別のノート T1 の子にはできない
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートS1](s1.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('b: 既に親がある S1 を別のノートの子にはできない', s:file('s1.md') ==# s:s1 && s:file('t1.md') ==# s:t1 && s:file('r1.md') ==# s:r1)
" p で自己参照・循環は拒否（R1 の親に、子孫の S1 は選べない）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートT1](t1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 自己参照は拒否', s:file('t1.md') ==# s:t1)
execute 'edit ' . fnameescape(s:v . '/r1.md')
let s:r1 = s:file('r1.md')
let @" = '[ノートS1](s1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 循環（R1 の親に子の S1）は拒否', s:file('r1.md') ==# s:r1 && s:file('s1.md') ==# s:s1)
" p は親を 1 つだけ（2 つ選ぶと何も変えない）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = "[ノートP1](p1.md)\n[ノートR1](r1.md)"
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 親を 2 つ同時には選べない（何も変えない）', s:file('t1.md') ==# s:t1 && s:file('p1.md')[-1] ==# '[ノートQ1](q1.md)')
" p を使える \l（insert_links_pick）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let g:gnosis_test_keys = ['p']
call gnosis#insert_links_pick(['[ノートP1](p1.md)'], getpos('.'))
call s:ok('\l p: T1 の親が P1', s:count('t1.md', '^\[ノートP1\](p1\.md)$') == 1 && s:count('p1.md', '^\[ノートT1\](t1\.md)$') == 1)
" zn → p（新ノートが今のノートの親になる）
call s:mk('u1.md', 'ノートU1', ['U1 の本文。'])
execute 'edit ' . fnameescape(s:v . '/u1.md')
let s:before = s:files()
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:np = s:newest_except(s:before)
call s:ok('zn p: 新ノートが U1 の親になる（U1 に ParentBranch・新ノートに ChildBranch）', !empty(s:np) && s:count('u1.md', '](' . s:np . ')$') == 1 && index(s:file(s:np), 'ChildBranch:') >= 0 && s:count(s:np, '^\[ノートU1\](u1\.md)$') == 1)
" 既に親がある U1 で zn → p: 新ノートを作らず、何も変えない
execute 'edit ' . fnameescape(s:v . '/u1.md')
let s:before = s:files()
let s:u1 = s:file('u1.md')
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('zn p: 既に親がある U1 では新ノートを作らず何も変えない', s:files() ==# s:before && s:file('u1.md') ==# s:u1)
" index.md の zn → p も何も作らない
execute 'edit ' . fnameescape(s:v . '/index.md')
let s:before = s:files()
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('index.md の zn p: 何も作らない', s:files() ==# s:before)
" 既存の c / t / Enter は p を足しても変わらない（za の Enter・c）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートQ1](q1.md)'
let @0 = @"
let g:gnosis_test_keys = ["\r"]
call gnosis#add_clipboard_before_up_note()
call s:ok('za Enter は従来どおり（本文の最後に本文リンク・Branch は作らない）', s:count('t1.md', '^\[ノートQ1\](q1\.md)$') == 1 && s:count('q1.md', 'ChildBranch') == 0, string(s:file('t1.md')))

" ------------------------------------------------------------------ BranchGroup: の並び（階層）: Nest / Unnest
call s:mk('bg.md', 'BG', ['BranchGroup:', '[A](a.md)', '[B](b.md)', '[C](c.md)', '[D](d.md)', '', '本文。'])
execute 'edit ' . fnameescape(s:v . '/bg.md')
let s:h = search('^BranchGroup:$', 'nw')
function! s:bg() abort
  let l:h = search('^BranchGroup:$', 'nw')
  return getline(l:h + 1, l:h + 4)
endfunction
call s:ok('Nest: 先頭の行は下げられない（変更なし）', gnosis#branch#nest(s:h + 1, s:h + 1, 1) == 0 && s:bg() ==# ['[A](a.md)', '[B](b.md)', '[C](c.md)', '[D](d.md)'])
call gnosis#branch#nest(s:h + 2, s:h + 2, 1)
call s:ok('Nest: 今の行（範囲 1 行）を 1 段下げる → B は A の下', s:bg() ==# ['[A](a.md)', '  [B](b.md)', '[C](c.md)', '[D](d.md)'], string(s:bg()))
call gnosis#branch#nest(s:h + 3, s:h + 4, 1)
call s:ok('Nest: ビジュアルで 2 行まとめて下げる → C と D は A の下（B と同じ段）', s:bg() ==# ['[A](a.md)', '  [B](b.md)', '  [C](c.md)', '  [D](d.md)'], string(s:bg()))
call s:ok('Nest: 直前の行の 1 段下までしか下げられない', gnosis#branch#nest(s:h + 2, s:h + 2, 1) == 0 && s:bg()[1] ==# '  [B](b.md)')
call gnosis#branch#nest(s:h + 3, s:h + 3, 1)
call s:ok('Nest: C を B の下へ（2 段目）', s:bg() ==# ['[A](a.md)', '  [B](b.md)', '    [C](c.md)', '  [D](d.md)'], string(s:bg()))
call gnosis#branch#nest(s:h + 2, s:h + 2, -1)
call s:ok('Unnest: B を上げると、選んでいない子（C）もいっしょに動く', s:bg() ==# ['[A](a.md)', '[B](b.md)', '  [C](c.md)', '  [D](d.md)'], string(s:bg()))
call s:ok('Unnest: 一番上の階層の行は上げられない（変更なし）', gnosis#branch#nest(s:h + 1, s:h + 1, -1) == 0)
call s:ok('Nest: BranchGroup の外の行は何もしない', gnosis#branch#nest(line('$'), line('$'), 1) == 0 && getline('$') ==# '本文。')
call s:ok('Nest: 本文・見出しは変えない', getline(s:h) ==# 'BranchGroup:' && getline(s:h + 6) ==# '本文。')
call s:mk('nobg.md', 'NOBG', ['[A](a.md)'])
execute 'edit ' . fnameescape(s:v . '/nobg.md')
call s:ok('Nest: BranchGroup: が無いノートでは何もしない', gnosis#branch#nest(1, line('$'), 1) == 0)

call writefile(s:res, s:work . '/result.txt')
qa!
) == 0 && s:count('d.md', '(' . s:nt . ')') >= 2,
      \ string({'new': s:nt, 'd': s:file('d.md'), 'note': empty(s:nt) ? [] : s:file(s:nt)}))

" ---------------------------------------------------------------- o は孤立、zk は明示的な b/p だけ Branch を付ける
execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ['o']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:no = s:newest_except(s:before)
call s:ok('zn o: Branch と本文リンクを作らない', !empty(s:no)
      \ && s:count(s:no, 'Branch') == 0 && s:count('d.md', '(' . s:no . ')') == 0)

execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_group()
stopinsert
let s:ng = s:newest_except(s:before)
call s:ok('zk Enter: Group は自動 Branch の対象外', !empty(s:ng)
      \ && s:count(s:ng, 'Branch') == 0 && s:count(s:ng, '^attribute: group$') == 1)

" ---------------------------------------------------------------- index.md からの通常作成は Branch の親にしない
execute 'edit ' . fnameescape(s:v . '/index.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:ni = s:newest_except(s:before)
call s:ok('zn Enter: index.md は Branch を作らず通常のリンクだけ', !empty(s:ni)
      \ && s:count(s:ni, 'Branch') == 0 && s:count('index.md', '(' . s:ni . ')') == 1)

" ================================================================ p モード（現在のノートの親を追加）
call s:mk('p1.md', 'ノートP1', ['P1 の本文。'])
call s:mk('q1.md', 'ノートQ1', ['Q1 の本文。'])
call s:mk('r1.md', 'ノートR1', ['R1 の本文。'])
call s:mk('s1.md', 'ノートS1', ['S1 の本文。'])
call s:mk('t1.md', 'ノートT1', ['T1 の本文。'])
" b: P1 → Q1 / p: S1 の親に R1（どちらも「親 ChildBranch・子 ParentBranch」の同じ形になる）
execute 'edit ' . fnameescape(s:v . '/p1.md')
let @" = '[ノートQ1](q1.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
execute 'edit ' . fnameescape(s:v . '/s1.md')
let @" = '[ノートR1](r1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 現在のノート S1 の ParentBranch に R1', index(s:file('s1.md'), 'ParentBranch:') >= 0 && s:count('s1.md', '^\[ノートR1\](r1\.md)$') == 1)
call s:ok('p: 相手 R1 の ChildBranch に S1', index(s:file('r1.md'), 'ChildBranch:') >= 0 && s:count('r1.md', '^\[ノートS1\](s1\.md)$') == 1)
call s:ok('p: バッファが読み直されている', !&modified && join(getline(1, '$'), "\n") ==# join(s:file('s1.md'), "\n"))
call s:ok('b と p は同じ形の関係を作る（親に ChildBranch・子に ParentBranch）',
      \ s:file('p1.md')[-2 :] ==# ['ChildBranch:', '[ノートQ1](q1.md)'] && s:file('q1.md')[-2 :] ==# ['ParentBranch:', '[ノートP1](p1.md)']
      \ && s:file('r1.md')[-2 :] ==# ['ChildBranch:', '[ノートS1](s1.md)'] && s:file('s1.md')[-2 :] ==# ['ParentBranch:', '[ノートR1](r1.md)'])
" 同じ関係をもう一度（重複しない）
let s:s1 = s:file('s1.md')
let s:r1 = s:file('r1.md')
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p 再実行: 重複を作らない', s:file('s1.md') ==# s:s1 && s:file('r1.md') ==# s:r1)
" 既に親がある S1 に、別の親 T1 を p で足せない（どちらも変更しない）
let s:t1 = s:file('t1.md')
let @" = '[ノートT1](t1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 既に親がある S1 に別の親は付けられない（S1・T1・R1 は変わらない）', s:file('s1.md') ==# s:s1 && s:file('t1.md') ==# s:t1 && s:file('r1.md') ==# s:r1 && getline(1, '$') ==# s:s1)
call s:ok('p: 拒否の理由に現在の親のタイトルを出す', s:msgs() =~# 'ノートR1' || s:msgs() =~# 'R1')
" b でも、既に親がある S1 を別のノート T1 の子にはできない
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートS1](s1.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('b: 既に親がある S1 を別のノートの子にはできない', s:file('s1.md') ==# s:s1 && s:file('t1.md') ==# s:t1 && s:file('r1.md') ==# s:r1)
" p で自己参照・循環は拒否（R1 の親に、子孫の S1 は選べない）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートT1](t1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 自己参照は拒否', s:file('t1.md') ==# s:t1)
execute 'edit ' . fnameescape(s:v . '/r1.md')
let s:r1 = s:file('r1.md')
let @" = '[ノートS1](s1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 循環（R1 の親に子の S1）は拒否', s:file('r1.md') ==# s:r1 && s:file('s1.md') ==# s:s1)
" p は親を 1 つだけ（2 つ選ぶと何も変えない）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = "[ノートP1](p1.md)\n[ノートR1](r1.md)"
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 親を 2 つ同時には選べない（何も変えない）', s:file('t1.md') ==# s:t1 && s:file('p1.md')[-1] ==# '[ノートQ1](q1.md)')
" p を使える \l（insert_links_pick）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let g:gnosis_test_keys = ['p']
call gnosis#insert_links_pick(['[ノートP1](p1.md)'], getpos('.'))
call s:ok('\l p: T1 の親が P1', s:count('t1.md', '^\[ノートP1\](p1\.md)$') == 1 && s:count('p1.md', '^\[ノートT1\](t1\.md)$') == 1)
" zn → p（新ノートが今のノートの親になる）
call s:mk('u1.md', 'ノートU1', ['U1 の本文。'])
execute 'edit ' . fnameescape(s:v . '/u1.md')
let s:before = s:files()
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:np = s:newest_except(s:before)
call s:ok('zn p: 新ノートが U1 の親になる（U1 に ParentBranch・新ノートに ChildBranch）', !empty(s:np) && s:count('u1.md', '](' . s:np . ')$') == 1 && index(s:file(s:np), 'ChildBranch:') >= 0 && s:count(s:np, '^\[ノートU1\](u1\.md)$') == 1)
" 既に親がある U1 で zn → p: 新ノートを作らず、何も変えない
execute 'edit ' . fnameescape(s:v . '/u1.md')
let s:before = s:files()
let s:u1 = s:file('u1.md')
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('zn p: 既に親がある U1 では新ノートを作らず何も変えない', s:files() ==# s:before && s:file('u1.md') ==# s:u1)
" index.md の zn → p も何も作らない
execute 'edit ' . fnameescape(s:v . '/index.md')
let s:before = s:files()
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('index.md の zn p: 何も作らない', s:files() ==# s:before)
" 既存の c / t / Enter は p を足しても変わらない（za の Enter・c）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートQ1](q1.md)'
let @0 = @"
let g:gnosis_test_keys = ["\r"]
call gnosis#add_clipboard_before_up_note()
call s:ok('za Enter は従来どおり（本文の最後に本文リンク・Branch は作らない）', s:count('t1.md', '^\[ノートQ1\](q1\.md)$') == 1 && s:count('q1.md', 'ChildBranch') == 0, string(s:file('t1.md')))

call writefile(s:res, s:work . '/result.txt')
qa!
) == 2,
      \ string({'new': s:ne, 'd': s:file('d.md'), 'note': empty(s:ne) ? [] : s:file(s:ne)}))


" ---------------------------------------------------------------- zn h / t は派生関係を付けるが Context は増やさない
execute 'edit ' . fnameescape(s:v . '/d.md')
call cursor(8, 1)
let s:before = s:files()
let g:gnosis_test_keys = ['h']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:nh = s:newest_except(s:before)
call s:ok('zn h: 自動 Branch / 新ノートの Context は無し', !empty(s:nh)
      \ && s:count(s:nh, '^ParentBranch:$') == 1
      \ && empty(gnosis#context#find_block(s:file(s:nh))) && s:count('d.md', '(' . s:nh . ')') >= 2)

execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_heading = 'ノートD'
let g:gnosis_test_keys = ['t']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
unlet g:gnosis_test_heading
let s:nt = s:newest_except(s:before)
call s:ok('zn t: 見出し下に置いても自動 Branch / Context は無し', !empty(s:nt)
      \ && s:count(s:nt, '^ParentBranch:$') == 1
      \ && s:count(s:nt, '^### Context

" ---------------------------------------------------------------- o は孤立、zk は明示的な b/p だけ Branch を付ける
execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ['o']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:no = s:newest_except(s:before)
call s:ok('zn o: Branch と本文リンクを作らない', !empty(s:no)
      \ && s:count(s:no, 'Branch') == 0 && s:count('d.md', '(' . s:no . ')') == 0)

execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_group()
stopinsert
let s:ng = s:newest_except(s:before)
call s:ok('zk Enter: Group は自動 Branch の対象外', !empty(s:ng)
      \ && s:count(s:ng, 'Branch') == 0 && s:count(s:ng, '^attribute: group$') == 1)

" ---------------------------------------------------------------- index.md からの通常作成は Branch の親にしない
execute 'edit ' . fnameescape(s:v . '/index.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:ni = s:newest_except(s:before)
call s:ok('zn Enter: index.md は Branch を作らず通常のリンクだけ', !empty(s:ni)
      \ && s:count(s:ni, 'Branch') == 0 && s:count('index.md', '(' . s:ni . ')') == 1)

" ================================================================ p モード（現在のノートの親を追加）
call s:mk('p1.md', 'ノートP1', ['P1 の本文。'])
call s:mk('q1.md', 'ノートQ1', ['Q1 の本文。'])
call s:mk('r1.md', 'ノートR1', ['R1 の本文。'])
call s:mk('s1.md', 'ノートS1', ['S1 の本文。'])
call s:mk('t1.md', 'ノートT1', ['T1 の本文。'])
" b: P1 → Q1 / p: S1 の親に R1（どちらも「親 ChildBranch・子 ParentBranch」の同じ形になる）
execute 'edit ' . fnameescape(s:v . '/p1.md')
let @" = '[ノートQ1](q1.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
execute 'edit ' . fnameescape(s:v . '/s1.md')
let @" = '[ノートR1](r1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 現在のノート S1 の ParentBranch に R1', index(s:file('s1.md'), 'ParentBranch:') >= 0 && s:count('s1.md', '^\[ノートR1\](r1\.md)$') == 1)
call s:ok('p: 相手 R1 の ChildBranch に S1', index(s:file('r1.md'), 'ChildBranch:') >= 0 && s:count('r1.md', '^\[ノートS1\](s1\.md)$') == 1)
call s:ok('p: バッファが読み直されている', !&modified && join(getline(1, '$'), "\n") ==# join(s:file('s1.md'), "\n"))
call s:ok('b と p は同じ形の関係を作る（親に ChildBranch・子に ParentBranch）',
      \ s:file('p1.md')[-2 :] ==# ['ChildBranch:', '[ノートQ1](q1.md)'] && s:file('q1.md')[-2 :] ==# ['ParentBranch:', '[ノートP1](p1.md)']
      \ && s:file('r1.md')[-2 :] ==# ['ChildBranch:', '[ノートS1](s1.md)'] && s:file('s1.md')[-2 :] ==# ['ParentBranch:', '[ノートR1](r1.md)'])
" 同じ関係をもう一度（重複しない）
let s:s1 = s:file('s1.md')
let s:r1 = s:file('r1.md')
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p 再実行: 重複を作らない', s:file('s1.md') ==# s:s1 && s:file('r1.md') ==# s:r1)
" 既に親がある S1 に、別の親 T1 を p で足せない（どちらも変更しない）
let s:t1 = s:file('t1.md')
let @" = '[ノートT1](t1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 既に親がある S1 に別の親は付けられない（S1・T1・R1 は変わらない）', s:file('s1.md') ==# s:s1 && s:file('t1.md') ==# s:t1 && s:file('r1.md') ==# s:r1 && getline(1, '$') ==# s:s1)
call s:ok('p: 拒否の理由に現在の親のタイトルを出す', s:msgs() =~# 'ノートR1' || s:msgs() =~# 'R1')
" b でも、既に親がある S1 を別のノート T1 の子にはできない
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートS1](s1.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('b: 既に親がある S1 を別のノートの子にはできない', s:file('s1.md') ==# s:s1 && s:file('t1.md') ==# s:t1 && s:file('r1.md') ==# s:r1)
" p で自己参照・循環は拒否（R1 の親に、子孫の S1 は選べない）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートT1](t1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 自己参照は拒否', s:file('t1.md') ==# s:t1)
execute 'edit ' . fnameescape(s:v . '/r1.md')
let s:r1 = s:file('r1.md')
let @" = '[ノートS1](s1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 循環（R1 の親に子の S1）は拒否', s:file('r1.md') ==# s:r1 && s:file('s1.md') ==# s:s1)
" p は親を 1 つだけ（2 つ選ぶと何も変えない）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = "[ノートP1](p1.md)\n[ノートR1](r1.md)"
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 親を 2 つ同時には選べない（何も変えない）', s:file('t1.md') ==# s:t1 && s:file('p1.md')[-1] ==# '[ノートQ1](q1.md)')
" p を使える \l（insert_links_pick）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let g:gnosis_test_keys = ['p']
call gnosis#insert_links_pick(['[ノートP1](p1.md)'], getpos('.'))
call s:ok('\l p: T1 の親が P1', s:count('t1.md', '^\[ノートP1\](p1\.md)$') == 1 && s:count('p1.md', '^\[ノートT1\](t1\.md)$') == 1)
" zn → p（新ノートが今のノートの親になる）
call s:mk('u1.md', 'ノートU1', ['U1 の本文。'])
execute 'edit ' . fnameescape(s:v . '/u1.md')
let s:before = s:files()
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:np = s:newest_except(s:before)
call s:ok('zn p: 新ノートが U1 の親になる（U1 に ParentBranch・新ノートに ChildBranch）', !empty(s:np) && s:count('u1.md', '](' . s:np . ')$') == 1 && index(s:file(s:np), 'ChildBranch:') >= 0 && s:count(s:np, '^\[ノートU1\](u1\.md)$') == 1)
" 既に親がある U1 で zn → p: 新ノートを作らず、何も変えない
execute 'edit ' . fnameescape(s:v . '/u1.md')
let s:before = s:files()
let s:u1 = s:file('u1.md')
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('zn p: 既に親がある U1 では新ノートを作らず何も変えない', s:files() ==# s:before && s:file('u1.md') ==# s:u1)
" index.md の zn → p も何も作らない
execute 'edit ' . fnameescape(s:v . '/index.md')
let s:before = s:files()
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('index.md の zn p: 何も作らない', s:files() ==# s:before)
" 既存の c / t / Enter は p を足しても変わらない（za の Enter・c）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートQ1](q1.md)'
let @0 = @"
let g:gnosis_test_keys = ["\r"]
call gnosis#add_clipboard_before_up_note()
call s:ok('za Enter は従来どおり（本文の最後に本文リンク・Branch は作らない）', s:count('t1.md', '^\[ノートQ1\](q1\.md)$') == 1 && s:count('q1.md', 'ChildBranch') == 0, string(s:file('t1.md')))

call writefile(s:res, s:work . '/result.txt')
qa!
) == 0 && s:count('d.md', '(' . s:nt . ')') >= 2,
      \ string({'new': s:nt, 'd': s:file('d.md'), 'note': empty(s:nt) ? [] : s:file(s:nt)}))

" ---------------------------------------------------------------- o は孤立、zk は明示的な b/p だけ Branch を付ける
execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ['o']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:no = s:newest_except(s:before)
call s:ok('zn o: Branch と本文リンクを作らない', !empty(s:no)
      \ && s:count(s:no, 'Branch') == 0 && s:count('d.md', '(' . s:no . ')') == 0)

execute 'edit ' . fnameescape(s:v . '/d.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_group()
stopinsert
let s:ng = s:newest_except(s:before)
call s:ok('zk Enter: Group は自動 Branch の対象外', !empty(s:ng)
      \ && s:count(s:ng, 'Branch') == 0 && s:count(s:ng, '^attribute: group$') == 1)

" ---------------------------------------------------------------- index.md からの通常作成は Branch の親にしない
execute 'edit ' . fnameescape(s:v . '/index.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:ni = s:newest_except(s:before)
call s:ok('zn Enter: index.md は Branch を作らず通常のリンクだけ', !empty(s:ni)
      \ && s:count(s:ni, 'Branch') == 0 && s:count('index.md', '(' . s:ni . ')') == 1)

" ================================================================ p モード（現在のノートの親を追加）
call s:mk('p1.md', 'ノートP1', ['P1 の本文。'])
call s:mk('q1.md', 'ノートQ1', ['Q1 の本文。'])
call s:mk('r1.md', 'ノートR1', ['R1 の本文。'])
call s:mk('s1.md', 'ノートS1', ['S1 の本文。'])
call s:mk('t1.md', 'ノートT1', ['T1 の本文。'])
" b: P1 → Q1 / p: S1 の親に R1（どちらも「親 ChildBranch・子 ParentBranch」の同じ形になる）
execute 'edit ' . fnameescape(s:v . '/p1.md')
let @" = '[ノートQ1](q1.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
execute 'edit ' . fnameescape(s:v . '/s1.md')
let @" = '[ノートR1](r1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 現在のノート S1 の ParentBranch に R1', index(s:file('s1.md'), 'ParentBranch:') >= 0 && s:count('s1.md', '^\[ノートR1\](r1\.md)$') == 1)
call s:ok('p: 相手 R1 の ChildBranch に S1', index(s:file('r1.md'), 'ChildBranch:') >= 0 && s:count('r1.md', '^\[ノートS1\](s1\.md)$') == 1)
call s:ok('p: バッファが読み直されている', !&modified && join(getline(1, '$'), "\n") ==# join(s:file('s1.md'), "\n"))
call s:ok('b と p は同じ形の関係を作る（親に ChildBranch・子に ParentBranch）',
      \ s:file('p1.md')[-2 :] ==# ['ChildBranch:', '[ノートQ1](q1.md)'] && s:file('q1.md')[-2 :] ==# ['ParentBranch:', '[ノートP1](p1.md)']
      \ && s:file('r1.md')[-2 :] ==# ['ChildBranch:', '[ノートS1](s1.md)'] && s:file('s1.md')[-2 :] ==# ['ParentBranch:', '[ノートR1](r1.md)'])
" 同じ関係をもう一度（重複しない）
let s:s1 = s:file('s1.md')
let s:r1 = s:file('r1.md')
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p 再実行: 重複を作らない', s:file('s1.md') ==# s:s1 && s:file('r1.md') ==# s:r1)
" 既に親がある S1 に、別の親 T1 を p で足せない（どちらも変更しない）
let s:t1 = s:file('t1.md')
let @" = '[ノートT1](t1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 既に親がある S1 に別の親は付けられない（S1・T1・R1 は変わらない）', s:file('s1.md') ==# s:s1 && s:file('t1.md') ==# s:t1 && s:file('r1.md') ==# s:r1 && getline(1, '$') ==# s:s1)
call s:ok('p: 拒否の理由に現在の親のタイトルを出す', s:msgs() =~# 'ノートR1' || s:msgs() =~# 'R1')
" b でも、既に親がある S1 を別のノート T1 の子にはできない
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートS1](s1.md)'
let @0 = @"
let g:gnosis_test_keys = ['b']
call gnosis#add_clipboard_before_up_note()
call s:ok('b: 既に親がある S1 を別のノートの子にはできない', s:file('s1.md') ==# s:s1 && s:file('t1.md') ==# s:t1 && s:file('r1.md') ==# s:r1)
" p で自己参照・循環は拒否（R1 の親に、子孫の S1 は選べない）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートT1](t1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 自己参照は拒否', s:file('t1.md') ==# s:t1)
execute 'edit ' . fnameescape(s:v . '/r1.md')
let s:r1 = s:file('r1.md')
let @" = '[ノートS1](s1.md)'
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 循環（R1 の親に子の S1）は拒否', s:file('r1.md') ==# s:r1 && s:file('s1.md') ==# s:s1)
" p は親を 1 つだけ（2 つ選ぶと何も変えない）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = "[ノートP1](p1.md)\n[ノートR1](r1.md)"
let @0 = @"
let g:gnosis_test_keys = ['p']
call gnosis#add_clipboard_before_up_note()
call s:ok('p: 親を 2 つ同時には選べない（何も変えない）', s:file('t1.md') ==# s:t1 && s:file('p1.md')[-1] ==# '[ノートQ1](q1.md)')
" p を使える \l（insert_links_pick）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let g:gnosis_test_keys = ['p']
call gnosis#insert_links_pick(['[ノートP1](p1.md)'], getpos('.'))
call s:ok('\l p: T1 の親が P1', s:count('t1.md', '^\[ノートP1\](p1\.md)$') == 1 && s:count('p1.md', '^\[ノートT1\](t1\.md)$') == 1)
" zn → p（新ノートが今のノートの親になる）
call s:mk('u1.md', 'ノートU1', ['U1 の本文。'])
execute 'edit ' . fnameescape(s:v . '/u1.md')
let s:before = s:files()
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:np = s:newest_except(s:before)
call s:ok('zn p: 新ノートが U1 の親になる（U1 に ParentBranch・新ノートに ChildBranch）', !empty(s:np) && s:count('u1.md', '](' . s:np . ')$') == 1 && index(s:file(s:np), 'ChildBranch:') >= 0 && s:count(s:np, '^\[ノートU1\](u1\.md)$') == 1)
" 既に親がある U1 で zn → p: 新ノートを作らず、何も変えない
execute 'edit ' . fnameescape(s:v . '/u1.md')
let s:before = s:files()
let s:u1 = s:file('u1.md')
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('zn p: 既に親がある U1 では新ノートを作らず何も変えない', s:files() ==# s:before && s:file('u1.md') ==# s:u1)
" index.md の zn → p も何も作らない
execute 'edit ' . fnameescape(s:v . '/index.md')
let s:before = s:files()
let g:gnosis_test_keys = ['p']
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('index.md の zn p: 何も作らない', s:files() ==# s:before)
" 既存の c / t / Enter は p を足しても変わらない（za の Enter・c）
execute 'edit ' . fnameescape(s:v . '/t1.md')
let @" = '[ノートQ1](q1.md)'
let @0 = @"
let g:gnosis_test_keys = ["\r"]
call gnosis#add_clipboard_before_up_note()
call s:ok('za Enter は従来どおり（本文の最後に本文リンク・Branch は作らない）', s:count('t1.md', '^\[ノートQ1\](q1\.md)$') == 1 && s:count('q1.md', 'ChildBranch') == 0, string(s:file('t1.md')))

call writefile(s:res, s:work . '/result.txt')
qa!
