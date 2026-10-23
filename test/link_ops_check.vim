" リンク操作の回帰網（test/link_ops_net.sh から呼ぶ）。
"   zn / zk / za / \l の c → Enter / t / o、グループへの表示名、Esc の取り消し、
"   \l → n（表示名を入力）、zk → g（現ノートを新グループに登録）・zk → n（BranchGroup と ChildBranch に登録）、グループの \S。
" 結果は $LINKOPS_WORK/result.txt に「OK 名前」「NG 名前: 詳細」で書く。
set nomore
call gnosis#i18n#set_lang('ja')
let s:work = $LINKOPS_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1
" よみの入力は既定値を使う(Vim 9.1.0016 など古い Vim は、-es で標準入力が空だと inputdialog() の所で終わってしまう。版に頼らない)
let g:gnosis_test_yomi = []

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

function! s:has(name, pat) abort
  return match(s:file(a:name), a:pat) >= 0
endfunction

function! s:newest_except(before) abort
  let l:now = map(glob(s:v . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")')
  call filter(l:now, 'index(a:before, v:val) < 0')
  return get(l:now, 0, '')
endfunction

function! s:files() abort
  return map(glob(s:v . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")')
endfunction

" ------------------------------------------------------------------ 準備
call s:mk('index.md', 'Index', ['[A](a.md)'], 1)
call s:mk('a.md', 'ノートA', ['本文の文。', ''])
call s:mk('b.md', 'ノートB', ['B の本文。', '', '## 節1', '', '節1の文。', '', '### 小節', '', '小節の文。', '', '## 節2', '', '節2の文。'])
call s:mk('g.md', 'グループG', ['[ノートA](a.md)', ''], 1)
call s:mk('c.md', 'ノートC', ['C の本文。'])

" ------------------------------------------------------------------ zn（通常のノート）→ Enter: Context を足さない
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:new = s:newest_except(s:before)
call s:ok('zn Enter: 新ノートができ、A の本文の最後にリンク', !empty(s:new) && s:has('a.md', '^\[' . fnamemodify(s:new, ':r') . '\](' . s:new . ')$'))
call s:ok('zn Enter: 新ノートに Context を足さない（ParentBranch だけ）', empty(gnosis#context#find_block(s:file(s:new))) && index(s:file(s:new), 'ParentBranch:') >= 0, string(s:file(s:new)))

" ------------------------------------------------------------------ zn → h / t / b / p / o: Context を足さない
for [s:k, s:hd] in [['h', ''], ['t', '節1'], ['b', ''], ['p', ''], ['o', '']]
  execute 'edit ' . fnameescape(s:v . (s:k ==# 'p' ? '/c.md' : '/b.md'))
  call cursor(search('^B の本文。$', 'nw') > 0 ? search('^B の本文。$', 'nw') : 1, 1)
  let s:before = s:files()
  let g:gnosis_test_keys = [s:k]
  if !empty(s:hd) | let g:gnosis_test_heading = s:hd | endif
  sleep 1100m
  call gnosis#v2_new_plain()
  stopinsert
  silent! unlet g:gnosis_test_heading
  let s:nk = s:newest_except(s:before)
  call s:ok('zn ' . s:k . ': 新ノートができ、Context は足さない', !empty(s:nk) && empty(gnosis#context#find_block(s:file(s:nk))) && index(s:file(s:nk), '### Context') < 0, string(s:file(s:nk)))
endfor

" ------------------------------------------------------------------ zn（通常のノート）: 決められたキー以外では何も作らない
" r は Related（正しいキー）なので含めない（含めると、ファイル名の時刻がぶつかったときだけ通る不安定な試験になる）
" i は行の中（2026-10-20 から zn でも使える）なので含めない
for s:k in ['n', 'g', 'x']
  execute 'edit ' . fnameescape(s:v . '/a.md')
  let s:before = s:files()
  let s:a_before = s:file('a.md')
  let g:gnosis_test_keys = [s:k]
  call gnosis#v2_new_plain()
  call s:ok('zn（通常のノート）' . s:k . ': 何も作らない・A は変わらない', s:files() ==# s:before && s:file('a.md') ==# s:a_before)
endfor

" ------------------------------------------------------------------ zn → c → Enter / t / h（B の Context に A、A に B へのリンク）
execute 'edit ' . fnameescape(s:v . '/b.md')
let s:before = s:files()
let g:gnosis_test_keys = ['c', "\r"]
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:new = s:newest_except(s:before)
call s:ok('zn c Enter: 新ノート B の Context: に A', !empty(s:new) && gnosis#context#links(s:file(s:new)) ==# ['[ノートB](b.md)'], string(s:file(s:new)))
call s:ok('zn c Enter: A の本文の最後に B へのリンク・A に Context を作らない', s:has('b.md', '^\[' . fnamemodify(s:new, ':r') . '\](' . s:new . ')$') && empty(gnosis#context#find_block(s:file('b.md'))))
call s:ok('zn c Enter: B の本文に A を置かない', count(s:file(s:new), '[ノートB](b.md)') <= 2 && index(s:file(s:new), '[ノートB](b.md)') < index(s:file(s:new), 'Context:') + 2)
call s:ok('zn c Enter: B を開く', fnamemodify(expand('%:p'), ':t') ==# s:new)
execute 'edit ' . fnameescape(s:v . '/b.md')
let s:before = s:files()
let g:gnosis_test_keys = ['c', 't']
let g:gnosis_test_heading = '節1'
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
unlet g:gnosis_test_heading
let s:new = s:newest_except(s:before)
let s:bl = s:file('b.md')
let s:i_link = index(s:bl, '[' . fnamemodify(s:new, ':r') . '](' . s:new . ')')
call s:ok('zn c t: A の「節1」の節の最後（zn → t と同じ位置: 節1の文の後・次の見出しの前）に B', s:i_link > index(s:bl, '節1の文。') && s:i_link < index(s:bl, '### 小節'), string(s:bl))
call s:ok('zn c t: B の Context に A', gnosis#context#links(s:file(s:new)) ==# ['[ノートB](b.md)'])
execute 'edit ' . fnameescape(s:v . '/b.md')
call cursor(search('^節2の文。$', 'nw'), 1)
let s:before = s:files()
let g:gnosis_test_keys = ['c', 'h']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:new = s:newest_except(s:before)
let s:bl = s:file('b.md')
call s:ok('zn c h: A のカーソル行の直下に B', get(s:bl, index(s:bl, '節2の文。') + 1, '') ==# '[' . fnamemodify(s:new, ':r') . '](' . s:new . ')', string(s:bl))
call s:ok('zn c h: B の Context に A', gnosis#context#links(s:file(s:new)) ==# ['[ノートB](b.md)'])

" ------------------------------------------------------------------ zn → c → Esc / 見出し選択の取り消し（何も作らない）
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:before = s:files()
let s:a_before = s:file('a.md')
let g:gnosis_test_keys = ['c', "\x1b"]
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('zn c Esc: 新ノートを作らない・A は変わらない', s:files() ==# s:before && s:file('a.md') ==# s:a_before)
execute 'edit ' . fnameescape(s:v . '/b.md')
let s:before = s:files()
let s:b_before = s:file('b.md')
let g:gnosis_test_keys = ['c', 't']
let g:gnosis_test_heading = 'そんな見出しは無い'
call gnosis#v2_new_plain()
unlet g:gnosis_test_heading
call s:ok('zn c t で見出しを選ばない: 新ノートを作らない・A は変わらない', s:files() ==# s:before && s:file('b.md') ==# s:b_before)

" ------------------------------------------------------------------ グループの上の zn: Enter（表示名を付けて登録）/ o（登録しない）
call s:mk('gz.md', 'グループZ', ['[ゼータ](zeta.md)', '[アルファ](alpha.md)'], 1)
call s:mk('zeta.md', 'ゼータ', ['本文。'])
call s:mk('alpha.md', 'アルファ', ['本文。'])
execute 'edit ' . fnameescape(s:v . '/gz.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
let g:gnosis_test_display_name = ['いちご']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:ng = s:newest_except(s:before)
let s:gl = s:file('gz.md')
call s:ok('グループの zn Enter: 入力した表示名でグループに登録', !empty(s:ng) && index(s:gl, '[いちご](' . s:ng . ')') >= 0, string(s:gl))
call s:ok('グループの zn Enter: 表示名でタイトル・ファイル名を変えない', s:has(s:ng, '^# ' . fnamemodify(s:ng, ':r') . '$') && s:ng =~# '^\d\{12}\.md$')
call s:ok('グループの zn Enter: 新ノートの Group: にグループ・Context と Branch は無い', index(s:file(s:ng), 'Group:') >= 0 && s:has(s:ng, '^\[グループZ\](gz\.md)$')
      \ && empty(gnosis#context#find_block(s:file(s:ng))) && index(s:file(s:ng), 'ParentBranch:') < 0 && !s:has('gz.md', '^ChildBranch:$'), string(s:file(s:ng)))
call s:ok('グループの zn Enter: 新ノートを開く', fnamemodify(expand('%:p'), ':t') ==# s:ng)
call s:ok('グループの zn Enter: 索引をよみ順に並べ替える（アルファ・いちご・ゼータ）',
      \ index(s:gl, '[アルファ](alpha.md)') < index(s:gl, '[いちご](' . s:ng . ')') && index(s:gl, '[いちご](' . s:ng . ')') < index(s:gl, '[ゼータ](zeta.md)'), string(s:gl))
" グループの zn は Enter（登録）と o（孤立）だけ（h・c・t・b・p は無い）。表示名の入力で Esc なら何も作らない
execute 'edit ' . fnameescape(s:v . '/gz.md')
let s:before = s:files()
let s:gz_before = s:file('gz.md')
let g:gnosis_test_keys = ["\r"]
let g:gnosis_test_display_name = ["\x1b"]
call gnosis#v2_new_plain()
call s:ok('グループの zn → 表示名で Esc: 何も作らない', s:files() ==# s:before && s:file('gz.md') ==# s:gz_before)
for s:k in ['h', 'c', 't', 'b', 'p']
  let g:gnosis_test_keys = [s:k]
  call gnosis#v2_new_plain()
  call s:ok('グループの zn ' . s:k . ': 何も作らない', s:files() ==# s:before && s:file('gz.md') ==# s:gz_before)
endfor
" グループ（Index も）の上でも o で孤立のノートを作れる（グループは変えない・新ノートに Group: も Branch も無い）
execute 'edit ' . fnameescape(s:v . '/gz.md')
let g:gnosis_test_keys = ['o']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:ng = s:newest_except(s:before)
call s:ok('グループの zn o: 孤立のノートを作る（グループは変わらない）', !empty(s:ng) && s:file('gz.md') ==# s:gz_before, string(s:ng))
call s:ok('グループの zn o: 新ノートに Group: も Context も Branch も無い', !empty(s:ng) && index(s:file(s:ng), 'Group:') < 0
      \ && empty(gnosis#context#find_block(s:file(s:ng))) && index(s:file(s:ng), 'ParentBranch:') < 0, string(s:ng is '' ? [] : s:file(s:ng)))

" ------------------------------------------------------------------ zk: 通常のノートは n だけ・グループの上では使えない
for s:k in ["\r", 'c', 'h', 'o', 'b', 'p', 't']
  execute 'edit ' . fnameescape(s:v . '/a.md')
  let s:before = s:files()
  let g:gnosis_test_keys = [s:k]
  call gnosis#v2_new_group()
  call s:ok('zk ' . (s:k ==# "\r" ? 'Enter' : s:k) . ': 何も作らない（n だけ）', s:files() ==# s:before)
endfor
execute 'edit ' . fnameescape(s:v . '/gz.md')
let s:before = s:files()
let g:gnosis_test_keys = ['n']
call gnosis#v2_new_group()
call s:ok('グループの上の zk: 使えない（何も作らない）', s:files() ==# s:before)
let g:gnosis_test_keys = []
execute "normal! ggVj\<Esc>"
call gnosis#v2_new_group_visual()
call s:ok('グループの上のビジュアル zk: 使えない（何も作らない・グループは変わらない）', s:files() ==# s:before && s:file('gz.md') ==# getline(1, '$'))

" ------------------------------------------------------------------ za → c → t / Enter（B の Context に A、A に B）
call s:mk('d.md', 'ノートD', ['D の本文。'])
execute 'edit ' . fnameescape(s:v . '/b.md')
let @" = '[ノートD](d.md)'
let @0 = @"
let g:gnosis_test_keys = ['c', 't']
let g:gnosis_test_heading = '節2'
call gnosis#add_clipboard_before_up_note()
unlet g:gnosis_test_heading
call s:ok('za c t: B（D）の Context に A', gnosis#context#links(s:file('d.md')) ==# ['[ノートB](b.md)'], string(s:file('d.md')))
call s:ok('za c t: A の「節2」の節の最後に D', s:file('b.md')[-1] ==# '[ノートD](d.md)' || index(s:file('b.md'), '[ノートD](d.md)') > index(s:file('b.md'), '## 節2'), string(s:file('b.md')))
call s:ok('za c t: D の本文に A は置かない（Context と、親が無かったので ParentBranch だけ）', count(s:file('d.md'), '[ノートB](b.md)') == 2 && index(s:file('d.md'), 'ParentBranch:') >= 0, string(s:file('d.md')))
" 相手がグループでも、c は Context（グループ登録にはしない）
execute 'edit ' . fnameescape(s:v . '/c.md')
let @" = '[グループG](g.md)'
let @0 = @"
let s:g_before = s:file('g.md')
let g:gnosis_test_keys = ['c', "\r"]
call gnosis#add_clipboard_before_up_note()
call s:ok('za c Enter（相手がグループ）: G の Context に C・G の本文には入れない', gnosis#context#links(s:file('g.md')) ==# ['[ノートC](c.md)'] && !s:has('g.md', '^\[ノートC\](c\.md)$') || index(s:file('g.md'), 'Context:') >= 0, string(s:file('g.md')))
call s:ok('za c Enter（相手がグループ）: C の本文の最後に G・C は G に所属しない', s:has('c.md', '^\[グループG\](g\.md)$') && index(s:file('c.md'), 'Group:') < 0, string(s:file('c.md')))

" ------------------------------------------------------------------ za → Enter（相手がグループでも、暗黙のグループ登録にしない）
call s:mk('ze.md', 'ノートZE', ['ZE の本文。'])
execute 'edit ' . fnameescape(s:v . '/ze.md')
let @" = '[グループG](g.md)'
let @0 = @"
let s:g_before = s:file('g.md')
let g:gnosis_test_keys = ["\r"]
call gnosis#add_clipboard_before_up_note()
call s:ok('za Enter（相手がグループ）: 本文の最後にリンク・グループの本文は変えない・Group: は作らない',
      \ s:has('ze.md', '^\[グループG\](g\.md)$') && s:file('g.md') ==# s:g_before && index(s:file('ze.md'), 'Group:') < 0, string(s:file('ze.md')))

" ------------------------------------------------------------------ \l → c → Enter / h（ピッカーから）
call s:mk('e.md', 'ノートE', ['E の本文。'])
execute 'edit ' . fnameescape(s:v . '/a.md')
let g:gnosis_test_keys = ['c', "\r"]
call gnosis#insert_links_pick(['[ノートE](e.md)'], getpos('.'))
call s:ok('\l c Enter: E の Context に A', gnosis#context#links(s:file('e.md')) ==# ['[ノートA](a.md)'], string(s:file('e.md')))
call s:ok('\l c Enter: A の本文の最後に E・A に Context は作らない', s:has('a.md', '^\[ノートE\](e\.md)$') && empty(gnosis#context#find_block(s:file('a.md'))))
call s:mk('f.md', 'ノートF', ['F の本文。'])
execute 'edit ' . fnameescape(s:v . '/a.md')
call cursor(search('^本文の文。$', 'nw'), 1)
let g:gnosis_test_keys = ['c', 'h']
call gnosis#insert_links_pick(['[ノートF](f.md)'], getpos('.'))
call s:ok('\l c h: A のカーソル行の直下に F', get(s:file('a.md'), index(s:file('a.md'), '本文の文。') + 1, '') ==# '[ノートF](f.md)', string(s:file('a.md')))
call s:ok('\l c h: F の Context に A', gnosis#context#links(s:file('f.md')) ==# ['[ノートA](a.md)'])

" ------------------------------------------------------------------ \l / za の位置キー: 決められたキー以外（旧 n）は何もしない
"（i は 2026-10-20 に復活: 行の中へそのまま入れる。requests_1020_net.sh で確かめる）
call s:mk('h.md', 'ノートH', ['H の本文。'])
for s:k in ['n', 'x']
  execute 'edit ' . fnameescape(s:v . '/c.md')
  let s:c_before = getline(1, '$')
  let g:gnosis_test_keys = [s:k]
  let g:gnosis_test_display_name = ['']
  call gnosis#insert_links_pick(['[ノートH](h.md)'], getpos('.'))
  call s:ok('\l ' . s:k . ': 何もしない', getline(1, '$') ==# s:c_before && s:file('h.md')[-1] ==# 'H の本文。')
endfor
let s:cols_save = &columns
let &columns = 200
call s:ok('\l の案内: 選択先がグループのときだけ g を出す', gnosis#insert_prompt_text(1, 1) =~# 'g=' && gnosis#insert_prompt_text(1, 0) !~# 'g=')
let &columns = s:cols_save

" ------------------------------------------------------------------ \l → 選ぶ → g（選んだノートを入れるグループを、曼荼羅で選ぶ）
" （グループへの追加そのものは test/mview_check.vim。ここでは g が曼荼羅の選ぶモードを始めることだけ）
call s:mk('jg4.md', 'ノートJG4', ['JG4 の本文。'])
execute 'edit ' . fnameescape(s:v . '/jg4.md')
let g:gnosis_test_keys = ['g']
let s:ret = gnosis#insert_links_pick(['[ノートJG4](jg4.md)'], getpos('.'))
let s:mst = gnosis#mview#state()
call s:ok('\l g: 入れ先のグループを選ぶモードが始まる', get(s:mst, 'pick', '') ==# 'group' && s:mst.src ==# fnamemodify(s:v . '/jg4.md', ':p'), string(get(s:mst, 'pick', '')) . ' ' . string(get(s:mst, 'src', '')))
call gnosis#mview#close()

" ------------------------------------------------------------------ キー待ちの案内は 1 行（2 行になると ENTER 待ちの画面が出て、次のキー g などが食われる）
let s:cols_save = &columns
for s:cols in [80, 100, 120]
  let &columns = s:cols
  let s:worst = gnosis#insert_prompt_text(1, 1)
  call s:ok('案内は 1 行に収まり g も見える（幅 ' . s:cols . '）', strdisplaywidth(s:worst) <= s:cols - 2 && s:worst =~# 'g=' && s:worst =~# 'r=Related', s:worst . ' / ' . strdisplaywidth(s:worst))
endfor
let &columns = 240
call s:ok('広い画面では詳しい案内のまま', gnosis#insert_prompt_text(1, 1) =~# 'g=グループに入れる' && gnosis#insert_prompt_text(1, 1) =~# 'カーソル直下')
let &columns = s:cols_save

" ------------------------------------------------------------------ zk → g は出ない（グループ作成の位置キーに g は無い → 何も作らない）
call s:mk('j.md', 'ノートJ', ['前の文 [ノートB](b.md) と [ノートC](c.md) の後ろ'])
execute 'edit ' . fnameescape(s:v . '/j.md')
call cursor(8, 1)
let s:before = s:files()
let s:j_before = getline(1, '$')
let g:gnosis_test_keys = ['g']
sleep 1100m
call gnosis#v2_new_group()
stopinsert
call s:ok('zk g: 位置キーに無いので何も作らない', s:files() ==# s:before)
call s:ok('zk g: 元ノート J は変わらない', getline(1, '$') ==# s:j_before)

" ------------------------------------------------------------------ zk → n（現在のノートの BranchGroup: に登録）
execute 'edit ' . fnameescape(s:v . '/j.md')
call cursor(8, 1)
let s:before = s:files()
let g:gnosis_test_keys = ['n']
sleep 1100m
call gnosis#v2_new_group()
stopinsert
let s:grp2 = s:newest_except(s:before)
call s:ok('zk n: グループができる', !empty(s:grp2) && s:has(s:grp2, '^attribute: group$'))
call s:ok('zk n: 元ノートの BranchGroup: に登録', index(s:file('j.md'), 'BranchGroup:') >= 0 && s:has('j.md', '(' . s:grp2 . ')'))
call s:ok('zk n: 新しいグループの ParentBranch に J', !empty(s:grp2)
      \ && index(s:file(s:grp2), 'ParentBranch:') >= 0
      \ && s:has(s:grp2, '^\[ノートJ\](j\.md)$'))
call s:ok('zk n: 元ノート J の ChildBranch にグループ', index(s:file('j.md'), 'ChildBranch:') >= 0
      \ && s:has('j.md', '(' . s:grp2 . ')'))
call s:ok('zk n: Context への余分な逆リンクを作らない',
      \ index(s:file(s:grp2), 'Context:') < 0 && index(s:file(s:grp2), '### Context') < 0)
" BranchGroup と ChildBranch の 2 か所だけ（同じグループを重ねて入れない）
call s:ok('zk n: グループへのリンクが重複しない（BranchGroup と ChildBranch の 2 か所）',
      \ len(filter(copy(s:file('j.md')), 'v:val =~# "(" . escape(s:grp2, ".") . ")"')) == 2)
call s:ok('zk n: 元の本文は変更しない', index(s:file('j.md'), '前の文 [ノートB](b.md) と [ノートC](c.md) の後ろ') >= 0)
let s:blocks = s:file('j.md')
call s:ok('ノートの見出し順: BranchGroup → Context',
      \ index(s:blocks, 'BranchGroup:') >= 0
      \ && (index(s:blocks, 'Context:') < 0 || index(s:blocks, 'BranchGroup:') < index(s:blocks, 'Context:')))

" ------------------------------------------------------------------ 旧 ThisNoteGroup から zk n
call s:mk('legacy.md', '旧ノート', ['ThisNoteGroup:', '[グループG](g.md)', ''])
execute 'edit ' . fnameescape(s:v . '/legacy.md')
let s:before = s:files()
let g:gnosis_test_keys = ['n']
sleep 1100m
call gnosis#v2_new_group()
stopinsert
let s:legacy_group = s:newest_except(s:before)
call s:ok('旧 ThisNoteGroup: zk n で BranchGroup に移行する',
      \ index(s:file('legacy.md'), 'ThisNoteGroup:') < 0
      \ && index(s:file('legacy.md'), 'BranchGroup:') >= 0
      \ && s:has('legacy.md', '(g\.md)')
      \ && s:has('legacy.md', '(' . s:legacy_group . ')'))
call s:ok('旧 ThisNoteGroup: 新グループへの Branch を構築',
      \ !empty(s:legacy_group) && index(s:file('legacy.md'), 'ChildBranch:') >= 0
      \ && index(s:file(s:legacy_group), 'ParentBranch:') >= 0
      \ && s:has(s:legacy_group, '^\[旧ノート\](legacy\.md)$'))

" ------------------------------------------------------------------ グループの \S（最後のブロックだけ）
call s:mk('n1.md', 'あ', [])
call s:mk('n2.md', 'い', [])
call s:mk('n3.md', 'う', [])
call s:mk('sg.md', 'ソート', ['文', '[う](n3.md)', '', '[い](n2.md)', '[あ](n1.md)', '', '', '### Context', '[ノートA](a.md)'], 1)
execute 'edit ' . fnameescape(s:v . '/sg.md')
let s:before_lines = getline(1, '$')
call gnosis#sort_yomi()
let s:after = getline(1, '$')
call s:ok('グループ \S: 最後のブロックだけ並べ替え', s:after[9:12] ==# ['[う](n3.md)', '', '[あ](n1.md)', '[い](n2.md)'], string(s:after))
call s:ok('グループ \S: 行数（空行）は変わらない', len(s:after) == len(s:before_lines))
call s:ok('グループ \S: タイトル・文・前のブロック・Context は不変', s:after[0:9] ==# s:before_lines[0:9] && s:after[13:] ==# s:before_lines[13:])
call s:mk('sg2.md', 'ソート2', ['[う](n3.md)', '[い](n2.md)', '', '```', '[い](n2.md)', '[あ](n1.md)', '```'], 1)
execute 'edit! ' . fnameescape(s:v . '/sg2.md')
let s:before_lines = getline(1, '$')
call gnosis#sort_yomi()
call s:ok('グループ \S: コードブロック内のリンクは並べない', getline(1, '$') ==# s:before_lines, string(getline(1, '$')))
call s:mk('sg3.md', 'ソート3', ['[う](n3.md)', '[い](n2.md)', '', '文', '[あ](n1.md)'], 1)
execute 'edit! ' . fnameescape(s:v . '/sg3.md')
let s:before_lines = getline(1, '$')
call gnosis#sort_yomi()
call s:ok('グループ \S: 最後のブロックのリンクが 1 本なら変えない', getline(1, '$') ==# s:before_lines)
" ビジュアル（選択範囲だけ）
call s:mk('sg4.md', 'ソート4', ['[う](n3.md)', '[い](n2.md)', '[あ](n1.md)'], 1)
execute 'edit! ' . fnameescape(s:v . '/sg4.md')
call setpos("'<", [0, 9, 1, 0])
call setpos("'>", [0, 10, 1, 0])
call gnosis#sort_selection()
call s:ok('\S ビジュアル: 選択の外は変えない', getline(9, 11) ==# ['[い](n2.md)', '[う](n3.md)', '[あ](n1.md)'], string(getline(9, 11)))

" ------------------------------------------------------------------ グループへ逆リンクを足したら \S と同じ規則でよみ順に並べ直す
call s:mk('ab1.md', 'あ', [])
call s:mk('ab2.md', 'い', [])
call s:mk('ab3.md', 'う', [])
call s:mk('abg.md', '逆グループ', ['文', '', '[あ](ab1.md)', '[う](ab3.md)'], 1)
let s:sid = matchstr(execute('scriptnames'), '\d\+\ze: [^\n]*autoload/gnosis\.vim')
let s:Apply = function('<SNR>' . s:sid . '_apply_back_link')
call s:Apply(s:v . '/abg.md', s:v . '/ab2.md', 'い', {'mode': 'end', 'lnum': 0, 'name': 'い'})
let s:abg = s:file('abg.md')
call s:ok('グループへ足したら末尾ブロックをよみ順に並べる', index(s:abg, '[あ](ab1.md)') < index(s:abg, '[い](ab2.md)') && index(s:abg, '[い](ab2.md)') < index(s:abg, '[う](ab3.md)') && s:abg[-5:] ==# ['文', '', '[あ](ab1.md)', '[い](ab2.md)', '[う](ab3.md)'], string(s:abg))

" ------------------------------------------------------------------ \k（一番上の関係の節）/ \m（一番下の関係の節）
call s:mk('jk.md', 'ジャンプ', ['Group:', '[g](g.md)', '', '本文', '', 'ChildBranch:', '[a](a.md)', '', '### Context', '[b](b.md)', '', 'BackLink:', '[c](c.md)', '', '```', 'BackLink:', '```'])
execute 'edit! ' . fnameescape(s:v . '/jk.md')
call cursor(1, 1)
call gnosis#jump_up_cursor()
call s:ok('\k: 一番上の「名前:」行（Group:）へ', getline('.') ==# 'Group:', getline('.'))
call gnosis#jump_last_section()
call s:ok('\m: 本文の終わりから一番近い「名前:」行（ChildBranch:）へ', getline('.') ==# 'ChildBranch:' && getline(line('.') + 1) ==# '[a](a.md)', getline('.') . ' @' . line('.'))

" （\l → e → g は曼荼羅でグループを選ぶ形に変わった。試験は test/mview_check.vim）

" ------------------------------------------------------------------ za → c → Esc（何も変えない）
call s:mk('k.md', 'ノートK', ['K の本文。'])
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:a_before = s:file('a.md')
let s:k_before = s:file('k.md')
let @" = '[ノートK](k.md)'
let @0 = @"
let g:gnosis_test_keys = ['c', "\x1b"]
call gnosis#add_clipboard_before_up_note()
call s:ok('za c Esc: A も K も変わらない', s:file('a.md') ==# s:a_before && s:file('k.md') ==# s:k_before && getline(1, '$') ==# s:a_before)

" ------------------------------------------------------------------ zk（ビジュアル）は従来どおり
call s:mk('vz.md', 'ビジュアル', ['一行目', '[ノートB](b.md)', '三行目'])
execute 'edit ' . fnameescape(s:v . '/vz.md')
let s:before = s:files()
call setpos("'<", [0, 9, 1, 0])
call setpos("'>", [0, 9, 1, 0])
call visualmode(1)
execute "normal! 9GV\<Esc>"
sleep 1100m
call gnosis#v2_new_group_visual()
stopinsert
let s:vg = s:newest_except(s:before)
call s:ok('zk ビジュアル: 選択行がグループの中身になり、元はグループへのリンク', !empty(s:vg) && s:has(s:vg, '^\[ノートB\](b\.md)$') && s:has('vz.md', '^\[' . fnamemodify(s:vg, ':r') . '\](' . s:vg . ')$'))

" ------------------------------------------------------------------ index.md から zn → Enter（親がグループなら最初から Group:）
execute 'edit ' . fnameescape(s:v . '/index.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
let g:gnosis_test_display_name = ['']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:ni = s:newest_except(s:before)
call s:ok('index から zn Enter: 新ノートの Group: に Index', !empty(s:ni) && index(s:file(s:ni), 'Group:') >= 0 && s:has(s:ni, '^\[Index\](index\.md)$'))
call s:ok('index から zn Enter: Context: を作らない', !empty(s:ni) && index(s:file(s:ni), 'Context:') < 0)
let s:nl = s:file(s:ni)
let s:lk = index(s:nl, '[Index](index.md)')
call s:ok('新ノート: ブロックの下は 空行 / カーソル行 / 空行', s:lk >= 0 && s:nl[s:lk + 1 :] ==# ['', '', ''], string(s:nl))
call s:ok('新ノート: カーソルは真ん中の空行', line('.') == s:lk + 3, line('.') . ' vs ' . (s:lk + 3))

" ------------------------------------------------------------------ ビジュアル \l: 選択範囲を、選んだノートへのリンクに置き換える（表示名は選択した文字列。位置キーは聞かない）
call s:mk('vl.md', 'ビジュアル L', ['ハーブガーデンを作ってみたい話。'])
call s:mk('herb.md', 'ハーブガーデンを作ってみたい', ['本文。'])
execute 'edit ' . fnameescape(s:v . '/vl.md')
let s:vl_ln = search('^ハーブガーデン', 'nw')
call setpos("'<", [0, s:vl_ln, 1, 0])
call setpos("'>", [0, s:vl_ln, strlen('ハーブガーデン'), 0])
execute "normal! " . s:vl_ln . "G0v" . (strchars('ハーブガーデン') - 1) . "l\<Esc>"
let g:gnosis_test_keys = ['x']
let g:gnosis_test_pick = [s:v . '/herb.md' . "\t" . 'ハーブガーデンを作ってみたい']
'<,'>call gnosis_search#pick_insert_link_visual()
call s:ok('ビジュアル \l: 選んだ文字が表示名のリンクに置き換わる', getline(s:vl_ln) ==# '[ハーブガーデン](herb.md)を作ってみたい話。', getline(s:vl_ln))
call s:ok('ビジュアル \l: 位置キーは聞かない（キーが残っている）', g:gnosis_test_keys ==# ['x'])
let g:gnosis_test_keys = []

" ------------------------------------------------------------------ ビジュアル \P: 選んだ範囲の複数のリンク先 B の Context: に、今のノート A を入れる
call s:mk('vp.md', 'ビジュアル P', ['[ノートP1](vp1.md) と [ノートP2](vp2.md)', '[自分](vp.md) と [無い](nothing.md)', '![画像](vp3.md)'])
call s:mk('vp1.md', 'ノートP1', ['P1。'])
call s:mk('vp2.md', 'ノートP2', ['Context:', '[ビジュアル P](vp.md)', '', 'P2。'])
call s:mk('vp3.md', 'ノートP3', ['P3。'])
execute 'edit ' . fnameescape(s:v . '/vp.md')
let s:vp_first = search('^\[ノートP1\]', 'nw')
let s:vp_before = s:file('vp.md')
let s:vp2_before = s:file('vp2.md')
let s:vp3_before = s:file('vp3.md')
call gnosis#add_current_as_parent_range(s:vp_first, s:vp_first + 2)
call s:ok('ビジュアル \P: P1 の Context: に A（今のノート）', gnosis#context#links(s:file('vp1.md')) ==# ['[ビジュアル P](vp.md)'], string(s:file('vp1.md')))
call s:ok('ビジュアル \P: 既に Context にある P2 は重複しない', s:file('vp2.md') ==# s:vp2_before)
call s:ok('ビジュアル \P: 画像のリンク先・自分自身・無いノートには何もしない', s:file('vp3.md') ==# s:vp3_before && gnosis#context#links(s:file('vp.md')) ==# [] && !filereadable(s:v . '/nothing.md'))
call s:ok('ビジュアル \P: A の本文は変えない（向きは B の Context に A）', s:file('vp.md')[5 :] ==# s:vp_before[5 :])

" ------------------------------------------------------------------ zw（日記でなくても本文の一番下から書き始める）
call s:mk('wb.md', 'ノートWB', ['最初の文。', '最後の文。', '', '', '', 'Related:', '[ノートA](a.md)'])
execute 'edit ' . fnameescape(s:v . '/wb.md')
call gnosis#write_at_bottom()
stopinsert
let s:wl = getline(1, '$')
let s:li = index(s:wl, '最後の文。')
call s:ok('zw: 最後の文の下は 空行 / カーソル行 / 空行 で関係の節の前', s:li >= 0 && s:wl[s:li + 1 : s:li + 4] ==# ['', '', '', 'Related:'], string(s:wl))
call s:ok('zw: カーソルは最後の文の 2 行下', line('.') == s:li + 3, line('.') . ' vs ' . (s:li + 3))

" ------------------------------------------------------------------ リンクの番号（読み直し・外からの書き換えのあとも出る）
call s:mk('hn.md', 'ノートHN', ['[ノートA](a.md) と [ノートB](b.md)'])
execute 'edit ' . fnameescape(s:v . '/hn.md')
function! s:hint_count() abort
  let l:n = 0
  for l:i in range(1, line('$'))
    let l:n += len(prop_list(l:i, {'types': ['gnosisLinkHint']}))
  endfor
  return l:n
endfunction
call s:ok('リンクの番号: 開いたときに出る', s:hint_count() == 2, string(s:hint_count()))
call writefile(readfile(s:v . '/hn.md') + ['[ノートC](c.md)'], s:v . '/hn.md')
silent edit!
call s:ok('リンクの番号: 外から書き換えて読み直したあとも出る（リンク 3 本）', s:hint_count() == 3, string(s:hint_count()))

" ------------------------------------------------------------------ 端末の制御文字列が本文に混ざらない（一切残さない）
enew
let s:e = "\x1b"
call setline(1, [
      \ '定' . s:e . 'OD、矢印',
      \ '焦点' . s:e . '[O と ' . s:e . '[I',
      \ '応答' . s:e . '[24;80R と ' . s:e . '[?64;1;2c と ' . s:e . '[<35;10;5M',
      \ '色' . s:e . ']10;rgb:ffff/ffff/ffff' . s:e . '\ のあと',
      \ '残り' . s:e . 'だけ',
      \ '断片 [?64;1;2c と [24;80R と [O[O[O と [<35;10;5M',
      \ 'ふつう [[wiki]] と [ノート](a.md) と 配列[0] と [?] と [OK] と a[i] と OO',
      \ ])
call gnosis#strip_stray_escape_all()
call s:ok('制御文字列: 矢印', getline(1) ==# '定、矢印', getline(1))
call s:ok('制御文字列: フォーカス通知 ESC[O / ESC[I', getline(2) ==# '焦点 と ', getline(2))
call s:ok('制御文字列: 端末の応答（カーソル位置・DA・マウス）', getline(3) ==# '応答 と  と ', getline(3))
call s:ok('制御文字列: OSC', getline(4) ==# '色 のあと', getline(4))
call s:ok('制御文字列: 残った ESC 1 文字', getline(5) ==# '残りだけ', getline(5))
call s:ok('制御文字列: ESC が消えて残った断片', getline(6) ==# '断片  と  と  と ', getline(6))
call s:ok('制御文字列: ふつうの文章（[[wiki]]・[0]・[OK]）は変えない', getline(7) ==# 'ふつう [[wiki]] と [ノート](a.md) と 配列[0] と [?] と [OK] と a[i] と OO', getline(7))
bwipeout!

call writefile(s:res, s:work . '/result.txt')
qa!
