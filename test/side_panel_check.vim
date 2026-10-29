" 右のパネル（\s・アウトライン/タブ/ハブの統合・検索/絞り込み/ハイライト・\l の e 決定）の回帰網（test/side_panel_net.sh から呼ぶ）。
" 結果は $SP_WORK/result.txt に「OK 名前」「NG 名前: 詳細」で書く。
set nomore
call gnosis#i18n#set_lang('ja')
let s:work = $SP_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1
let g:gnosis_test_yomi = []

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
function! s:mk(name, title, body) abort
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title, '---', '', '# ' . a:title, ''] + a:body, s:v . '/' . a:name)
endfunction
function! s:pw() abort
  return gnosis#panel#kind() ==# 'outline' ? gnosis#outline#win() : win_findbuf(bufnr('%'))[0]
endfunction

call s:mk('a.md', 'ノートA', ['A の本文。', '', '## 節1', '', '節1の文。', '', '## 節2', ''])
call s:mk('b.md', 'ノートB', ['B の本文。'])
call s:mk('c.md', 'ノートC', ['C の本文。'])
execute 'edit ' . fnameescape(s:v . '/a.md')
call gnosis#hub_set('tabs')
execute 'edit ' . fnameescape(s:v . '/b.md')
call gnosis#hub_set('tabs')
execute 'edit ' . fnameescape(s:v . '/c.md')
call gnosis#hub_set('tabs')
call gnosis#hub_set()
execute 'edit ' . fnameescape(s:v . '/a.md')

" ---- \s: 最初はアウトライン。もう一度押すとノート ⇔ パネル
call gnosis#panel#open_last()
call s:ok('\s: 最初はアウトラインが開く', gnosis#panel#kind() ==# 'outline', gnosis#panel#kind())
call s:ok('パネルは 1 つだけ（本文 + パネルの 2 窓）', winnr('$') == 2, string(winnr('$')))
" ---- Tab / Shift+Tab / o t h
call gnosis#panel#cycle(1)
call s:ok('Tab: アウトライン → タブ', gnosis#panel#kind() ==# 'tabs', gnosis#panel#kind())
call gnosis#panel#cycle(1)
call s:ok('Tab: タブ → ハブ', gnosis#panel#kind() ==# 'hub', gnosis#panel#kind())
call gnosis#panel#cycle(1)
call s:ok('Tab: ハブ → アウトライン（一周）', gnosis#panel#kind() ==# 'outline', gnosis#panel#kind())
call gnosis#panel#cycle(-1)
call s:ok('Shift+Tab: アウトライン → ハブ（逆回り）', gnosis#panel#kind() ==# 'hub', gnosis#panel#kind())
call gnosis#panel#switch('tabs')
call s:ok('t: タブへ直接', gnosis#panel#kind() ==# 'tabs')
call s:ok('切り替えても窓は 2 つのまま（パネルが増えない）', winnr('$') == 2, string(winnr('$')))
call s:ok('切り替えたあともカーソルはパネルにある', &filetype !=# 'markdown' || bufname('%') =~# 'tabs')

" ---- 状態行に 3 つの中身と、今のもの
let g:statusline_winid = win_getid()
let s:st = gnosis#panel#status()
call s:ok('状態行に 3 つの中身が出て、今のものが [ ] で囲まれる', s:st =~# '\[タブ\]' && s:st =~# 'アウトライン' && s:st =~# 'ハブ', s:st)

" ---- 絞り込み（x）: 合わない行が畳まれる。バッファの中身は変わらない
let s:before = getline(1, '$')
call gnosis#panel#set('f', 'ノートB')
let s:fold = map(range(1, line('$')), 'foldclosed(v:val) != -1')
let s:keep = filter(range(1, line('$')), 'getline(v:val) =~# "ノートB"')
call s:ok('x: 合う行は畳まれず、合わない行は畳まれる', len(s:keep) == 1 && !s:fold[s:keep[0] - 1] && count(s:fold, 1) >= 1, string([s:fold, s:keep]))
call s:ok('x: バッファの中身は変わらない', getline(1, '$') ==# s:before)
call s:ok('状態行に絞り込みの語が出る', gnosis#panel#status() =~# 'x:ノートB')
" ---- 検索（s）と n / N
call gnosis#panel#set('f', '')
call s:ok('x: 空にすると畳みが外れる', count(map(range(1, line('$')), 'foldclosed(v:val) != -1'), 1) == 0)
call cursor(1, 1)
call gnosis#panel#set('q', 'ノートC')
call s:ok('s: 語に合う行へ動く', getline('.') =~# 'ノートC', getline('.'))
call gnosis#panel#set('q', 'ノート')
let s:l1 = line('.')
call gnosis#panel#next(1)
let s:l2 = line('.')
call gnosis#panel#next(-1)
call s:ok('n / N: 次・前のヒットへ', s:l2 != s:l1 && line('.') == s:l1, string([s:l1, s:l2, line('.')]))
call gnosis#panel#set('q', '-ノートA ノートB')
call s:ok('検索の書き方は共通（-語 は NOT・空白は AND）', getline('.') =~# 'ノートB' && getline('.') !~# 'ノートA', getline('.'))
" ---- ハイライト（m）
call gnosis#panel#set('h', 'ノートB')
call s:ok('m: ハイライトが付く', !empty(filter(getmatches(), 'v:val.group ==# "Search"')))
call gnosis#panel#clear()
call s:ok('Esc: 検索・絞り込み・ハイライトを全部やめる', empty(filter(getmatches(), 'v:val.group ==# "Search"')) && empty(gnosis#panel#info().query) && empty(gnosis#panel#info().filter))
" ---- 3 つの中身どれでも同じ（アウトラインでも）
call gnosis#panel#switch('outline')
call gnosis#panel#set('f', '節2')
call s:ok('アウトラインでも絞り込みできる', count(map(range(1, line('$')), 'foldclosed(v:val) != -1'), 1) >= 1)
call gnosis#panel#clear()

" ---- \l の最中の e: パネルで選んだノートに決める（決めずに切り替えても \l は続く）
call gnosis#panel#key('tabs')
call gnosis#panel#close()
execute 'edit ' . fnameescape(s:v . '/a.md')
call s:ok('\l の前は e は何も決めない', !gnosis#mview#pick_active())
call gnosis#mview#link_pick()
call s:ok('\l の選ぶモードが始まる', gnosis#mview#pick_active())
call gnosis#panel#open_last()
call gnosis#panel#switch('tabs')
call s:ok('選ぶモードのまま、パネルを開いて切り替えられる', gnosis#mview#pick_active() && gnosis#panel#kind() ==# 'tabs')
call gnosis#panel#switch('hub')
call gnosis#panel#switch('tabs')
call s:ok('切り替えても \l は続く', gnosis#mview#pick_active())
let s:lnb = search('ノートB', 'nw')
call cursor(s:lnb, 1)
let g:gnosis_test_keys = ["\r"]
call gnosis#panel#decide()
let s:a = readfile(s:v . '/a.md')
call s:ok('e: パネルで選んだノート B へのリンクが、元のノート A に入る', !empty(filter(copy(s:a), 'v:val =~# "(b.md)"')), string(s:a))
" ---- ? のヘルプ
let s:help = join(gnosis#panel#help_lines(), "\n")
call s:ok('? のヘルプに、切り替え・検索・絞り込み・ハイライト・決定・Shift+矢印の説明がある', s:help =~# 'Tab' && s:help =~# '検索' && s:help =~# '絞り込み' && s:help =~# 'ハイライト' && s:help =~# 'Shift+←' && s:help =~# '\\l', s:help)
" ---- Shift+矢印: 端で何も無ければ開く（右 = 右のパネル・左 = 左のビュー）
call gnosis#mview#close()
silent! only
execute 'edit ' . fnameescape(s:v . '/a.md')
call s:ok('（準備）ノートだけ: パネルも曼荼羅も無い', empty(gnosis#panel#kind()) && !gnosis#mview#is_open())
call gnosis#panel#move(1)
call s:ok('Shift+→: 右に何も無ければ右のパネルが開く', !empty(gnosis#panel#kind()), gnosis#panel#kind())
call gnosis#panel#move(1)
call s:ok('Shift+→: すでにパネルの中なら動かない（増えない）', winnr('$') == 2, string(winnr('$')))
call gnosis#panel#close()
execute 'edit ' . fnameescape(s:v . '/a.md')
call gnosis#panel#move(-1)
call s:ok('Shift+←: 左に何も無ければ左のビュー（曼荼羅）が開く', gnosis#mview#is_open())
call writefile(s:res, s:work . '/result.txt')
qa!
