" リンク操作の回帰網（test/link_ops_net.sh から呼ぶ）。
"   zn / zk / za / \l の c → Enter / t / o、グループへの表示名、Esc の取り消し、
"   \l → n（表示名を入力）、zk → g（カーソル下のリンクをグループ化）、グループの \S。
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
let s:pb = index(s:b_lines, '### ParentBranch')
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

" ------------------------------------------------------------------ zk → g（カーソル下のリンク 1 本をグループ化）
call s:mk('j.md', 'ノートJ', ['前の文 [ノートB](b.md) と [ノートC](c.md) の後ろ'])
execute 'edit ' . fnameescape(s:v . '/j.md')
call cursor(8, 1)
call search('ノートC', '', 8)
let s:before = s:files()
let g:gnosis_test_keys = ['g']
sleep 1100m
call gnosis#v2_new_group()
let s:grp = s:newest_except(s:before)
let s:jl = get(filter(copy(s:file('j.md')), 'v:val =~# "前の文"'), 0, '')
call s:ok('zk g: グループができる', !empty(s:grp) && s:has(s:grp, '^attribute: group$'))
call s:ok('zk g: グループの本文にリンク 1 本だけ', !empty(s:grp) && s:has(s:grp, '^\[ノートC\](c\.md)$') && !s:has(s:grp, 'b\.md'))
call s:ok('zk g: 元の行は前後の文と他のリンクを保ち、グループへのリンクに置換', s:jl ==# '前の文 [ノートB](b.md) と [' . fnamemodify(s:grp, ':r') . '](' . s:grp . ') の後ろ', s:jl)
call s:ok('zk g: グループの Context は元のノート', !empty(s:grp) && s:has(s:grp, '^\[ノートJ\](j\.md)$'))
execute 'edit ' . fnameescape(s:v . '/j.md')
call cursor(8, 1)
let s:before = s:files()
let s:j_before = s:file('j.md')
let g:gnosis_test_keys = ['g']
sleep 1100m
call gnosis#v2_new_group()
call s:ok('zk g リンク無し: 何も作らない・変えない', s:files() ==# s:before && s:file('j.md') ==# s:j_before)

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

call writefile(s:res, s:work . '/result.txt')
qa!
