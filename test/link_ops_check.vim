" リンク操作の回帰網（test/link_ops_net.sh から呼ぶ）。
"   zn / zk / za / \l の c → Enter / t / o、グループへの表示名、Esc の取り消し、
"   \l → n（表示名を入力）、zk → g（現ノートを新グループに登録）・zk → n（BranchGroup と ChildBranch に登録）、グループの \S。
" 結果は $LINKOPS_WORK/result.txt に「OK 名前」「NG 名前: 詳細」で書く。
set nomore
let s:work = $LINKOPS_WORK
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

" ------------------------------------------------------------------ zn → c → Enter
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:before = s:files()
let g:gnosis_test_keys = ['c', "\r"]
sleep 1100m
call gnosis#v2_new_plain()
let s:new = s:newest_except(s:before)
stopinsert
call s:ok('zn c Enter: 新ノートができる', !empty(s:new))
call s:ok('zn c Enter: A の Context に新ノート', s:has('a.md', '(' . s:new . ')') && !empty(gnosis#context#find_block(s:file('a.md'))) && index(s:file('a.md'), '### Context') < 0)
call s:ok('zn c Enter: 新ノートの本文に A へのリンク', s:has(s:new, '^\[ノートA\](a\.md)$'))

" ------------------------------------------------------------------ zn → c → o
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:before = s:files()
let g:gnosis_test_keys = ['c', 'o']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:new = s:newest_except(s:before)
call s:ok('zn c o: 新ノートができる', !empty(s:new))
call s:ok('zn c o: A の Context に新ノート（c の追加は維持）', s:has('a.md', '(' . s:new . ')'))
let s:b_lines = s:file(s:new)
let s:pb = index(s:b_lines, 'ParentBranch:')
call s:ok('zn c o: 本文には A を置かず ParentBranch のみ記録',
      \ s:pb > 0 && get(s:b_lines, s:pb + 1, '') ==# '[ノートA](a.md)'
      \ && index(s:b_lines, '### Context') < 0
      \ && index(s:b_lines[: s:pb - 1], '[ノートA](a.md)') < 0, string(s:b_lines))

" ------------------------------------------------------------------ zn → c → t（新ノートは見出しが無いので本文の最後）
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:before = s:files()
let g:gnosis_test_keys = ['c', 't']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:new = s:newest_except(s:before)
call s:ok('zn c t: 新ノートの本文に A へのリンク', !empty(s:new) && s:has(s:new, '^\[ノートA\](a\.md)$'))

" ------------------------------------------------------------------ zn → c → Esc（何も作らない）
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:before = s:files()
let s:a_before = s:file('a.md')
let g:gnosis_test_keys = ['c', "\x1b"]
sleep 1100m
call gnosis#v2_new_plain()
call s:ok('zn c Esc: 新ノートを作らない', s:files() ==# s:before)
call s:ok('zn c Esc: A は変わらない', s:file('a.md') ==# s:a_before)

" ------------------------------------------------------------------ zk → c → Enter → 表示名（空 Enter = A のタイトル）
execute 'edit ' . fnameescape(s:v . '/c.md')
let s:before = s:files()
let g:gnosis_test_keys = ['c', "\r"]
let g:gnosis_test_display_name = ['']
sleep 1100m
call gnosis#v2_new_group()
stopinsert
let s:new = s:newest_except(s:before)
call s:ok('zk c Enter 空表示名: グループの本文に [ノートC](c.md)', !empty(s:new) && s:has(s:new, '^\[ノートC\](c\.md)$'))
call s:ok('zk c Enter 空表示名: C の Context にグループ', s:has('c.md', '(' . s:new . ')'))

" ------------------------------------------------------------------ zk → c → Enter → 表示名を入力（日本語・空白・角かっこ）
execute 'edit ' . fnameescape(s:v . '/c.md')
let s:before = s:files()
let g:gnosis_test_keys = ['c', "\r"]
let g:gnosis_test_display_name = ['別の 名前 [注]']
sleep 1100m
call gnosis#v2_new_group()
stopinsert
let s:new2 = s:newest_except(s:before)
call s:ok('zk c 表示名入力: 入力した文字が表示名（[ ] はエスケープ）', !empty(s:new2) && s:has(s:new2, '^\[別の 名前 \\\[注\\\]\](c\.md)$'), string(s:file(s:new2)))
call s:ok('zk c 表示名入力: C のタイトルは変わらない', s:has('c.md', '^title: ノートC$'))

" ------------------------------------------------------------------ zk → c → Enter → Esc（表示名の取り消し = 何も変えない）
execute 'edit ' . fnameescape(s:v . '/c.md')
let s:before = s:files()
let s:c_before = s:file('c.md')
let g:gnosis_test_keys = ['c', "\r"]
let g:gnosis_test_display_name = ["\x1b"]
sleep 1100m
call gnosis#v2_new_group()
call s:ok('zk c 表示名 Esc: 何も作らない', s:files() ==# s:before)
call s:ok('zk c 表示名 Esc: C は変わらない', s:file('c.md') ==# s:c_before)

" ------------------------------------------------------------------ za → c → t（B の見出し「節1」の節の最後。小節の後、節2の前）
execute 'edit ' . fnameescape(s:v . '/a.md')
let @" = '[ノートB](b.md)'
let @0 = '[ノートB](b.md)'
let g:gnosis_test_keys = ['c', 't']
let g:gnosis_test_heading = '節1'
call gnosis#add_clipboard_before_up_note()
unlet g:gnosis_test_heading
let s:b = s:file('b.md')
let s:i_link = index(s:b, '[ノートA](a.md)')
call s:ok('za c t: A の Context に B', s:has('a.md', '^\[ノートB\](b\.md)$'))
call s:ok('za c t: B の「節1」の節の最後（小節の後・節2の前）に A', s:i_link > index(s:b, '小節の文。') && s:i_link < index(s:b, '## 節2'), string(s:b))

" ------------------------------------------------------------------ za → c → o（A 側は入る、B 側は入れない）
call s:mk('d.md', 'ノートD', ['D の本文。'])
execute 'edit ' . fnameescape(s:v . '/a.md')
let @" = '[ノートD](d.md)'
let @0 = @"
let g:gnosis_test_keys = ['c', 'o']
call gnosis#add_clipboard_before_up_note()
call s:ok('za c o: A の Context に D', s:has('a.md', '^\[ノートD\](d\.md)$'))
call s:ok('za c o: D に A へのリンクは無い', !s:has('d.md', '(a\.md)'))

" ------------------------------------------------------------------ za → c → Enter（相手がグループ: 表示名を聞く。本文の最後）
execute 'edit ' . fnameescape(s:v . '/c.md')
let @" = '[グループG](g.md)'
let @0 = @"
let g:gnosis_test_keys = ['c', "\r"]
let g:gnosis_test_display_name = ['C から']
call gnosis#add_clipboard_before_up_note()
call s:ok('za c Enter グループ: G の本文の最後に [C から](c.md)', s:has('g.md', '^\[C から\](c\.md)$'))
call s:ok('za c Enter グループ: C に G', s:has('c.md', '(g\.md)'))

" ------------------------------------------------------------------ \l → c → Enter（ピッカーから）
call s:mk('e.md', 'ノートE', ['E の本文。'])
execute 'edit ' . fnameescape(s:v . '/a.md')
let g:gnosis_test_keys = ['c', "\r"]
call gnosis#insert_links_pick(['[ノートE](e.md)'], getpos('.'))
call s:ok('\l c Enter: A の Context に E', s:has('a.md', '^\[ノートE\](e\.md)$'))
call s:ok('\l c Enter: E の本文の最後に A', s:has('e.md', '^\[ノートA\](a\.md)$'))

" ------------------------------------------------------------------ \l → c → o
call s:mk('f.md', 'ノートF', ['F の本文。'])
execute 'edit ' . fnameescape(s:v . '/a.md')
let g:gnosis_test_keys = ['c', 'o']
call gnosis#insert_links_pick(['[ノートF](f.md)'], getpos('.'))
call s:ok('\l c o: A の Context に F', s:has('a.md', '^\[ノートF\](f\.md)$'))
call s:ok('\l c o: F に A は入らない', !s:has('f.md', '(a\.md)'))

" ------------------------------------------------------------------ \l → n（表示名: 空 Enter = タイトル / 入力 / Esc）
call s:mk('h.md', 'ノートH', ['H の本文。'])
call s:mk('i.md', 'ノートI', ['I の本文。'])
execute 'edit ' . fnameescape(s:v . '/c.md')
let g:gnosis_test_keys = ['n']
let g:gnosis_test_display_name = ['']
call gnosis#insert_links_pick(['[h](h.md)'], getpos('.'))
call s:ok('\l n 空 Enter: リンク先のタイトルが表示名', s:has('c.md', '^\[ノートH\](h\.md)$'))
let g:gnosis_test_keys = ['n']
let g:gnosis_test_display_name = ['好きな*名前_']
call gnosis#insert_links_pick(['[ノートI](i.md)'], getpos('.'))
call s:ok('\l n 入力: 入力した文字が表示名', s:has('c.md', '^\[好きな\*名前_\](i\.md)$'), string(s:file('c.md')))
call s:ok('\l n 入力: I のタイトルは変わらない', s:has('i.md', '^title: ノートI$'))
let s:c_before = getline(1, '$')
let g:gnosis_test_keys = ['n']
let g:gnosis_test_display_name = ["\x1b"]
call gnosis#insert_links_pick(['[ノートE](e.md)'], getpos('.'))
call s:ok('\l n Esc: 何も入れない', getline(1, '$') ==# s:c_before)

" ------------------------------------------------------------------ \l → g（選んだノートを選んだグループの所属にする。表示名も聞く）
" g:gnosis_test_group_pick … 試験用にグループを選ぶ（空文字 = 取り消し）
execute 'edit ' . fnameescape(s:v . '/c.md')
" 直前の操作の非同期の同期（update_one）が終わるのを待つ（zk の試験と同じ）
sleep 1100m
let g:gnosis_test_keys = ['g']
let g:gnosis_test_group_pick = [s:v . '/g.md']
let g:gnosis_test_display_name = ['']
call gnosis#insert_links_pick(['[ノートH](h.md)'], getpos('.'))
call s:ok('\l g: グループ本文に表示名つきのリンク（空 Enter = タイトル）', s:has('g.md', '^\[ノートH\](h\.md)$'), string(s:file('g.md')))
call s:ok('\l g: 相手 H の Group: がそのグループ', index(s:file('h.md'), 'Group:') >= 0 && s:has('h.md', '(g\.md)'), string(s:file('h.md')))
call s:ok('\l g: 今のノート C の本文末にもリンク', s:has('c.md', '^\[ノートH\](h\.md)$'), string(s:file('c.md')))
call s:ok('\l g: H のタイトルは変わらない', s:has('h.md', '^title: ノートH$'))
let g:gnosis_test_keys = ['g']
let g:gnosis_test_group_pick = [s:v . '/g.md']
let g:gnosis_test_display_name = ['好きな*名前_']
call gnosis#insert_links_pick(['[ノートI](i.md)'], getpos('.'))
call s:ok('\l g 表示名入力: 入力した文字が表示名', s:has('g.md', '^\[好きな\*名前_\](i\.md)$'), string(s:file('g.md')))
execute 'edit ' . fnameescape(s:v . '/g.md')
let s:g_before = getline(1, '$')
execute 'edit ' . fnameescape(s:v . '/c.md')
let s:c_before3 = getline(1, '$')
let g:gnosis_test_keys = ['g']
let g:gnosis_test_group_pick = [s:v . '/g.md']
let g:gnosis_test_display_name = ["\x1b"]
call gnosis#insert_links_pick(['[ノートE](e.md)'], getpos('.'))
call s:ok('\l g 表示名 Esc: グループも今のノートも変えない', getline(1, '$') ==# s:c_before3 && readfile(s:v . '/g.md') ==# s:g_before)
let g:gnosis_test_keys = ['g']
let g:gnosis_test_group_pick = ['']
let g:gnosis_test_display_name = ['']
call gnosis#insert_links_pick(['[ノートE](e.md)'], getpos('.'))
call s:ok('\l g グループ未選択: 何も変えない', getline(1, '$') ==# s:c_before3 && readfile(s:v . '/g.md') ==# s:g_before)

" ------------------------------------------------------------------ za → g（za も同じ位置キーで所属にできる）
call s:mk('k.md', 'ノートK', ['K の本文。'])
execute 'edit ' . fnameescape(s:v . '/c.md')
sleep 1100m
let @" = '[ノートK](k.md)'
let @0 = '[ノートK](k.md)'
let g:gnosis_test_keys = ['g']
let g:gnosis_test_group_pick = [s:v . '/g.md']
let g:gnosis_test_display_name = ['']
call gnosis#add_clipboard_before_up_note()
call s:ok('za g: グループ本文に K のリンク', s:has('g.md', '^\[ノートK\](k\.md)$'), string(s:file('g.md')))
call s:ok('za g: K の Group: がそのグループ', index(s:file('k.md'), 'Group:') >= 0 && s:has('k.md', '(g\.md)'), string(s:file('k.md')))

" ------------------------------------------------------------------ \l → g の候補一覧（先頭を選ぶ。現ノート自身は出ない・隠しフォルダの外にある vault でも出る）
call s:mk('m2.md', 'ノートM2', ['M2 の本文。'])
execute 'edit ' . fnameescape(s:v . '/c.md')
sleep 1100m
let g:gnosis_test_keys = ['g']
let g:gnosis_test_group_pick = ['#first']
let g:gnosis_test_display_name = ['']
call gnosis#insert_links_pick(['[ノートM2](m2.md)'], getpos('.'))
let s:m2g = filter(map(glob(s:v . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")'), 's:has(v:val, "^attribute: group$") && s:has(v:val, "^\\[ノートM2\\](m2\\.md)$")')
call s:ok('\l g 候補の先頭（グループ）に入る', len(s:m2g) == 1, string(s:m2g))

" ------------------------------------------------------------------ za → Enter でクリップボードのグループに今のノートを入れる
call s:mk('jg.md', 'ノートJG', ['JG の本文。'])
call s:mk('jg2.md', 'ノートJG2', ['JG2 の本文。'])
call s:mk('jg3.md', 'ノートJG3', ['JG3 の本文。'])
execute 'edit ' . fnameescape(s:v . '/jg.md')
sleep 1100m
let @" = '[グループG](g.md)'
let @0 = @"
let g:gnosis_test_keys = ["\r"]
let g:gnosis_test_display_name = ['']
call gnosis#add_clipboard_before_up_note()
call s:ok('za Enter（グループ）: 空 Enter はタイトルが表示名で、グループの本文に入る', s:has('g.md', '^\[ノートJG\](jg\.md)$'), string(s:file('g.md')))
call s:ok('za Enter（グループ）: 今のノートの Group: にグループ', index(s:file('jg.md'), 'Group:') >= 0 && s:has('jg.md', '^\[グループG\](g\.md)$'), string(s:file('jg.md')))
call s:ok('za Enter（グループ）: 今のノートの本文にはグループへのリンクを置かない', len(filter(copy(s:file('jg.md')), 'v:val =~# "(g\\.md)"')) == 1, string(s:file('jg.md')))
execute 'edit ' . fnameescape(s:v . '/jg2.md')
let @" = '[グループG](g.md)'
let @0 = @"
let g:gnosis_test_keys = ["\r"]
let g:gnosis_test_display_name = ['好きな表示名']
call gnosis#add_clipboard_before_up_note()
call s:ok('za Enter（グループ）: 入力した表示名でグループに入る', s:has('g.md', '^\[好きな表示名\](jg2\.md)$'), string(s:file('g.md')))
execute 'edit ' . fnameescape(s:v . '/jg3.md')
let s:jg3 = getline(1, '$')
let s:gbefore = s:file('g.md')
let @" = '[グループG](g.md)'
let @0 = @"
let g:gnosis_test_keys = ["\r"]
let g:gnosis_test_display_name = ["\x1b"]
call gnosis#add_clipboard_before_up_note()
call s:ok('za Enter（グループ）: 表示名で Esc なら何も変えない', getline(1, '$') ==# s:jg3 && s:file('g.md') ==# s:gbefore)
" グループのノートからは、従来どおり本文にリンクを置く（グループをグループに入れる操作ではない）
execute 'edit ' . fnameescape(s:v . '/g.md')
let @" = '[ノートJG3](jg3.md)'
let @0 = @"
let g:gnosis_test_keys = ["\r"]
call gnosis#add_clipboard_before_up_note()
silent! write
call s:ok('za Enter（普通のノートへのリンク）: 従来どおり本文に入る', s:has('g.md', '^\[ノートJG3\](jg3\.md)$'))

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

" ------------------------------------------------------------------ za → c → Esc / 表示名 Esc（何も変えない）
call s:mk('k.md', 'ノートK', ['K の本文。'])
call s:mk('gk.md', 'グループK', ['K'], 1)
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:a_before = s:file('a.md')
let s:k_before = s:file('k.md')
let @" = '[ノートK](k.md)'
let @0 = @"
let g:gnosis_test_keys = ['c', "\x1b"]
call gnosis#add_clipboard_before_up_note()
call s:ok('za c Esc: A も K も変わらない', s:file('a.md') ==# s:a_before && s:file('k.md') ==# s:k_before && getline(1, '$') ==# s:a_before)
let s:gk_before = s:file('gk.md')
let @" = '[グループK](gk.md)'
let @0 = @"
let g:gnosis_test_keys = ['c', "\r"]
let g:gnosis_test_display_name = ["\x1b"]
call gnosis#add_clipboard_before_up_note()
call s:ok('za c 表示名 Esc: A もグループも変わらない', s:file('a.md') ==# s:a_before && s:file('gk.md') ==# s:gk_before && getline(1, '$') ==# s:a_before)

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
