" Folgezettel ビュー・アウトライン窓の回帰網（test/fznav_net.sh から呼ぶ）。結果は $FZ_WORK/result.txt。
set nomore
let s:work = $FZ_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1
let g:gnosis_mview_restore = 0

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
  call writefile(s:res, s:work . '/result.txt')
endfunction
function! s:keys(k) abort
  call feedkeys(a:k, 'xt')
endfunction
function! s:lines() abort
  return getbufline(gnosis#mview#state().buf, 1, '$')
endfunction
function! s:cursor_text() abort
  return getbufline(gnosis#mview#state().buf, line('.'), line('.'))[0]
endfunction
function! s:mk(name, title, fz, attr, bg, body) abort
  let l:ls = ['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title] + (a:attr ? ['attribute: group'] : []) + (empty(a:fz) ? [] : ['folgezettel: "' . a:fz . '"']) + ['---', '', '# ' . a:title, '']
  if !empty(a:bg)
    let l:ls += ['BranchGroup:'] + map(copy(a:bg), '"[" . v:val[0] . "](" . v:val[1] . ")"') + ['']
  endif
  call writefile(l:ls + a:body, s:v . '/' . a:name)
endfunction

call mkdir(s:v, 'p')
call s:mk('index.md', 'Index', '', 0, [], ['[認識](n1.md)'])
call s:mk('n1.md', '認識', '1', 0, [['認識G', 'g1.md']], [])
call s:mk('g1.md', '認識G', '1', 1, [], ['[知覚](n1a.md)'])
call s:mk('n1a.md', '知覚', '1a', 0, [['知覚G', 'g1a.md']], [])
call s:mk('g1a.md', '知覚G', '1a', 1, [], [])
call s:mk('n1a1a.md', '言語', '1a1a', 0, [], ['## 意味', '本文', '### 細部', '## 用法'])
call s:mk('n1a1b.md', '意味', '1a1b', 0, [], [])
call s:mk('n1a2.md', '記憶', '1a2', 0, [], [])
call s:mk('n1b.md', '意識', '1b', 0, [], [])
call s:mk('n2.md', '二番', '2', 0, [], [])
call s:mk('deep.md', '深い', '1a2b3c4d5e6f', 0, [], [])
call s:mk('free.md', '番号なし', '', 0, [], [])
" 大量: 3000 件（画面に収まらない）
for s:i in range(1, 3000)
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: B' . s:i, 'folgezettel: "5a' . s:i . '"', '---', '', '# B' . s:i], s:v . '/bulk' . s:i . '.md')
endfor
call s:mk('n5.md', '五', '5', 0, [], [])

execute 'edit ' . s:v . '/n1a1a.md'
call s:keys(' ')
let s:st = gnosis#mview#state()
call s:ok('Space で曼荼羅（ナビゲーション）が開く', &filetype ==# 'gnosis-mandala' && gnosis#mview#view() ==# 'mandala')
call s:keys("\<C-Right>")
call s:ok('Ctrl-→ で Folgezettel ビューに切り替わる', gnosis#mview#view() ==# 'fz' && s:lines()[0] ==# 'FOLGEZETTEL', string(s:lines()[0 : 2]))
let s:note = fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t')
call s:ok('切り替えても右のノートはそのまま', s:note ==# 'n1a1a.md', s:note)
let s:L = s:lines()
call s:ok('番号と題が固定幅の列に揃う（題は全行で同じ桁から）', len(filter(copy(s:L[2 : 12]), 'strdisplaywidth(matchstr(v:val, "^.\\{2}\\S\\+\\s*")) > 0')) > 0
      \ && len(uniq(sort(map(filter(copy(s:L[2 : 12]), 'v:val =~# "^[▸ ] \\S"'), 'strdisplaywidth(matchstr(v:val, "^.\\{2}\\S*\\s*"))')))) >= 1, string(s:L[0 : 14]))
let s:col = {}
for s:l in s:L[2 : 14]
  let s:m = matchlist(s:l, '^\(. \)\(\S\+\)\( \+\)')
  if !empty(s:m) | let s:col[strdisplaywidth(s:m[1] . s:m[2] . s:m[3])] = 1 | endif
endfor
call s:ok('題の開始桁は 1 種類（2+8+2=12）', keys(s:col) ==# ['12'], string(s:col) . string(s:L[0 : 12]))
call s:ok('Group の行が上・Note の行が下（同じ番号）', s:L[2] =~# '^  1 \+認識G' && s:L[3] =~# '^  1 \+認識$' && s:L[4] =~# '^  1a \+知覚G' && s:L[5] =~# '^  1a \+知覚$', string(s:L[2 : 6]))
call s:ok('番号の自然順（1a1a が 1a2 の前・1b の前・10 以外の 2 の前）', index(s:L, '  1a2       記憶') > index(s:L, '  1a1b      意味') && index(s:L, '  2         二番') > index(s:L, '  1b        意識'), string(s:L[0 : 14]))
call s:ok('現在のノートに ▸（1a1a）', len(filter(copy(s:L), 'v:val =~# "^▸ 1a1a  "')) == 1, string(s:L[0 : 10]))
let s:deep = filter(copy(s:L), 'v:val =~# "深い"')
call s:ok('長い番号は先頭を ~ で省く（番号欄 8 桁・題の桁は変わらない）', len(s:deep) == 1 && s:deep[0] =~# '^  \~c4d5e6f  深い$', string(s:deep))
call s:ok('番号なしのノートは行にならない', len(filter(copy(s:L), 'v:val =~# "番号なし"')) == 0)
" 現在位置が縦の中央に（フォーカスが他の窓のとき）
call win_gotoid(gnosis#mview#note_win())
call gnosis#mview#rerender()
let s:wi = getwininfo(s:st.win)[0]
let s:curl = 0
for s:i in range(len(s:L))
  if s:L[s:i] =~# '^▸ ' | let s:curl = s:i + 1 | endif
endfor
call s:ok('現在位置の行は窓に見える', s:curl >= s:wi.topline && s:curl <= s:wi.botline, string([s:curl, s:wi.topline, s:wi.botline]))
" 移動
call win_gotoid(s:st.win)
call s:keys('gg')
call s:keys('j')
call s:ok('j で先頭の項目から次へ（見出しの行は飛ばす）', line('.') >= 3, string(line('.')))
call s:keys('G')
call s:ok('G で最後の項目（大量でも）', line('.') == line('$') && s:cursor_text() =~# '5a3000', s:cursor_text())
let s:before = line('.')
call s:keys('k')
call s:ok('k で 1 つ戻る', line('.') == s:before - 1)
" 先頭から j を 200 回: 画面外まで動ける
call s:keys('gg')
call s:keys('200j')
redraw
call s:ok('200j: 画面に収まらない分まで移動し、窓が追従する', line('.') > 100 && line('.') >= getwininfo(s:st.win)[0].topline && line('.') <= getwininfo(s:st.win)[0].botline, string([line('.'), getwininfo(s:st.win)[0]]))
call s:keys('gg')
call s:keys('3j')
" 1a の Note 行（Group 行, Note 行の順）で h / l
call cursor(5, 1)
call s:keys('j')
call s:ok('Note 1a に居る', s:cursor_text() =~# '1a \+知覚$', s:cursor_text())
call s:keys('l')
call s:ok('l: 下位の番号へ（欠番 1a1 を飛ばして 1a1a）', s:cursor_text() =~# '1a1a \+言語', s:cursor_text())
call s:keys('h')
call s:ok('h: 上位の番号へ（Note からは Note）', s:cursor_text() =~# '1a \+知覚$', s:cursor_text())
call s:keys('h')
call s:ok('h: さらに上位 1 の Note', s:cursor_text() =~# '1 \+認識$', s:cursor_text())
call s:keys('h')
call s:ok('最上位でさらに h しても留まる（新規作成しない）', s:cursor_text() =~# '1 \+認識$' && !filereadable(s:v . '/new.md'))
call s:keys('2j')
call s:keys('l')
" 1b は 1a の子孫ではない
call cursor(index(s:lines(), '  1b        意識') + 1, 1)
call s:keys('l')
call s:ok('子孫の無い 1b で l は動かない', s:cursor_text() =~# '1b \+意識', s:cursor_text())
call s:keys('h')
call s:ok('1b の上位は 1（1a ではない）', s:cursor_text() =~# '^  1 \+認識$', s:cursor_text())
" Enter で開く
call cursor(index(s:lines(), '  1a2       記憶') + 1, 1)
call s:keys("\<CR>")
call s:ok('Enter でそのノートが右に開く', fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t') ==# 'n1a2.md')
call s:ok('Enter のあと現在位置の ▸ が移る', len(filter(copy(s:lines()), 'v:val =~# "^▸ 1a2 "')) == 1, string(filter(copy(s:lines()), 'v:val =~# "^▸"')))
call s:ok('Enter のあと、カーソルは開いたノートの窓にある', win_getid() == gnosis#mview#note_win(), string([win_getid(), gnosis#mview#note_win()]))
call win_gotoid(s:st.win)
" Group の行を開く
call cursor(index(s:lines(), '  1a        知覚G') + 1, 1)
call s:keys("\<CR>")
call s:ok('Group の行 Enter でトピック索引（グループ）が開く', fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t') ==# 'g1a.md')
call win_gotoid(s:st.win)
" 本文側で別のノートを開いたら追従
call win_gotoid(gnosis#mview#note_win())
execute 'edit ' . s:v . '/n1b.md'
sleep 100m
doautocmd BufEnter
call timer_start(0, {-> 0})
sleep 50m
call s:ok('本文側で別のノートを開くと、ビューが追従する', len(filter(copy(s:lines()), 'v:val =~# "^▸ 1b "')) == 1, string(filter(copy(s:lines()), 'v:val =~# "^▸"')))
call win_gotoid(s:st.win)
" 現在のノートを n1a1a にしておく（折りたたみのキーは廃止した）
call win_gotoid(gnosis#mview#note_win())
execute 'edit ' . s:v . '/n1a1a.md'
sleep 50m
call win_gotoid(s:st.win)
call s:ok('現在のノートの行に ▸ が付く', len(filter(copy(s:lines()), 'v:val =~# "^▸ 1a1a "')) == 1, string(filter(copy(s:lines()), 'v:val =~# "^▸"')))
" 動かすと右のノートが追従する（印・中心は変わらない）。c で印の行と右のノートに戻る
call cursor(index(s:lines(), '  1a2       記憶') + 1, 1)
call s:keys('j')
call s:keys('k')
sleep 200m
call timer_start(0, {-> 0})
sleep 50m
call s:ok('動かすと右のノートが、カーソルの項目に変わる', fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t') ==# 'n1a2.md', fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t'))
call s:ok('印（▸）は動かさない', len(filter(copy(s:lines()), 'v:val =~# "^▸ 1a1a "')) == 1)
call s:keys('c')
call s:ok('c で印のついたノートの行にカーソルが戻る', s:cursor_text() =~# '1a1a', s:cursor_text())
call s:ok('c で右のノートも印のノートに戻る', fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t') ==# 'n1a1a.md')
" 兄弟移動
call cursor(index(s:lines(), '  1a1a      言語') + 1, 1)
call s:keys(']')
call s:ok('] で次の兄弟へ', s:cursor_text() =~# '1a1b', s:cursor_text())
call s:keys('[')
call s:ok('[ で前の兄弟へ', s:cursor_text() =~# '1a1a', s:cursor_text())
" 上位表示
call s:keys('u')
let s:U = s:lines()
call s:ok('上位表示: 祖先の Group（1・1a）→ 現在のノート', s:U[2] =~# '^  1 \+認識G' && s:U[3] =~# '^  1a \+知覚G' && s:U[4] =~# '^▸ 1a1a \+言語', string(s:U[0 : 9]))
call s:ok('上位表示: 欠番 1a1 や Group の無い番号は出さない', len(filter(copy(s:U[2 : 4]), 'v:val =~# "^  1a1 "')) == 0)
call s:ok('上位表示: 関連グループの見出し（無ければ空の候補を作らない）', join(s:U, "\n") =~# '関連グループ', string(s:U))
call s:keys('h')
call s:ok('上位表示で h: 祖先を 1 つ上へ', s:cursor_text() =~# '1a \+知覚G', s:cursor_text())
call s:keys('u')
" 曼荼羅へ戻る
call s:keys("\<C-Left>")
call s:ok('Ctrl-← でも切り替わる（曼荼羅へ）', gnosis#mview#view() ==# 'mandala' && join(s:lines(), "\n") =~# '┃')
call s:ok('曼荼羅に戻っても右のノートは同じ', fnamemodify(bufname(winbufnr(gnosis#mview#note_win())), ':t') ==# 'n1a1a.md')
call s:keys("\<C-Left>")
call s:ok('Ctrl-← でリストビューへ（3ビューを逆順）', gnosis#mview#view() ==# 'list')
call s:keys("\<C-Left>")
call s:ok('リストから逆順でFolgezettelへ', gnosis#mview#view() ==# 'fz')
call s:keys('gv')
call s:ok('gv（互換キー）は次のリストへ', gnosis#mview#view() ==# 'list')
call s:keys('gv')
call s:ok('gvでリストの次は曼荼羅', gnosis#mview#view() ==# 'mandala')
call s:keys('gv')
" \l（入れるノートを選ぶモード）は Folgezettel ビューでも使え、ビューを切り替えても続く
call win_gotoid(s:st.win)
call s:keys('\l')
call s:ok('Folgezettel ビューで \l: 選ぶモードになる', gnosis#mview#state().pick ==# 'link' && s:lines()[0] =~# 'FOLGEZETTEL.*入れるノートを選ぶ', s:lines()[0])
call s:keys("\<C-Left>")
call s:ok('選ぶモードのまま曼荼羅ビューに切り替えられる', gnosis#mview#view() ==# 'mandala' && gnosis#mview#state().pick ==# 'link')
call s:keys("\<C-Right>")
call s:ok('選ぶモードのまま Folgezettel ビューへ戻れる', gnosis#mview#view() ==# 'fz' && gnosis#mview#state().pick ==# 'link')
call s:keys('o')
call s:ok('o: 元のノートを右に見る', gnosis#mview#state().origin_view == 1)
call s:keys('o')
call s:ok('もう一度 o で戻る', gnosis#mview#state().origin_view == 0)
call s:keys('q')
call s:ok('q: 選ぶモードをやめる（ビューは閉じない）', empty(gnosis#mview#state().pick) && gnosis#mview#view() ==# 'fz' && winnr('$') >= 2)
" アウトライン窓
call win_gotoid(gnosis#mview#note_win())
call s:keys('\o')
call s:ok('\o でアウトライン窓が開く', gnosis#outline#is_open() && &filetype ==# 'gnosis-outline', &filetype)
let s:O = getbufline(bufnr('%'), 1, '$')
call s:ok('見出しが階層で出る', s:O[0] ==# 'OUTLINE' && s:O[2] ==# '言語' && s:O[3] ==# '  意味' && s:O[4] ==# '    細部' && s:O[5] ==# '  用法', string(s:O))
call s:ok('3 つの窓（Folgezettel・本文・アウトライン）が同時に出る', len(filter(map(range(1, winnr('$')), 'getbufvar(winbufnr(v:val), "&filetype")'), 'v:val =~# "gnosis-"')) == 2 && winnr('$') == 3)
" 見出しへジャンプ
call cursor(4, 1)
call s:keys("\<CR>")
call s:ok('Enter で本文の見出しへジャンプ', fnamemodify(bufname('%'), ':t') ==# 'n1a1a.md' && getline('.') =~# '^## 意味', getline('.') . ' @' . bufname('%'))
" 本文のカーソルの見出しを強調
call cursor(search('細部', 'nw'), 1)
doautocmd CursorMoved
sleep 150m
call timer_start(0, {-> 0})
sleep 50m
call s:ok('本文のカーソルがある見出しを強調（アクティブ）', gnosis#outline#state().active == 2, string(gnosis#outline#state().active))
" 編集で更新
call append('$', ['## 追加', '### 孫'])
doautocmd TextChanged
sleep 200m
call s:ok('本文の編集に応じて自動更新', index(getbufline(gnosis#outline#state().buf, 1, '$'), '  追加') >= 0 && index(getbufline(gnosis#outline#state().buf, 1, '$'), '    孫') >= 0, string(getbufline(gnosis#outline#state().buf, 1, '$')))
silent! undo
" 折りたたみ
call win_gotoid(gnosis#outline#win())
call cursor(4, 1)
call s:keys('zc')
call s:ok('見出しの折りたたみ（意味の下の 細部 が隠れる）', index(getbufline(bufnr('%'), 1, '$'), '    細部') < 0 && join(getbufline(bufnr('%'), 1, '$'), "\n") =~# '意味  +1', string(getbufline(bufnr('%'), 1, '$')))
call s:keys('zR')
call s:ok('zR で展開', index(getbufline(bufnr('%'), 1, '$'), '    細部') >= 0)
call s:keys('q')
call s:ok('q でアウトライン窓が閉じる', !gnosis#outline#is_open() && winnr('$') == 3 - 1 + 0 || !gnosis#outline#is_open())
call s:keys('Q')
" \W: ノートだけを表示する（どの窓にカーソルがあっても、全部の窓を閉じてノートの窓 1 つにする）
function! s:reopen() abort
  if winnr('$') == 1
    call gnosis#mview#toggle()
    sleep 100m
  endif
  if !gnosis#outline#is_open()
    call win_gotoid(gnosis#mview#note_win())
    call s:keys('\o')
  endif
endfunction
call s:reopen()
call s:ok('前提: 曼荼羅（またはビュー）・ノート・アウトラインが出ている', winnr('$') >= 3, string(winnr('$')))
call win_gotoid(gnosis#outline#win())
call s:keys('\W')
call s:ok('\W: アウトライン窓から押しても、ノートの窓 1 つになる', winnr('$') == 1 && &buftype ==# '' && &filetype !~# '^gnosis-', winnr('$') . ' ' . &filetype)
call s:reopen()
call win_gotoid(gnosis#mview#state().win)
call s:keys('\W')
call s:ok('\W: 曼荼羅・Folgezettel の窓から押しても、ノートの窓 1 つになる', winnr('$') == 1 && &filetype !~# '^gnosis-', winnr('$') . ' ' . &filetype)
call s:reopen()
call win_gotoid(gnosis#mview#note_win())
call s:keys('\W')
call s:ok('\W: ノートの窓から押しても、ノートの窓 1 つになる', winnr('$') == 1 && &filetype !~# '^gnosis-' && !gnosis#outline#is_open(), winnr('$') . ' ' . &filetype)
" アウトラインを閉じて開き直しても、中身が出る（以前は 2 回目から空だった）。go でアウトライン ⇔ ノート
call s:reopen()
call win_gotoid(gnosis#mview#note_win())
execute 'edit ' . s:v . '/n1a1a.md'
sleep 100m
if gnosis#outline#is_open() | call gnosis#outline#close() | endif
call gnosis#outline#open()
sleep 200m
call s:ok('アウトライン: 開き直しても見出しが出る', index(getbufline(gnosis#outline#state().buf, 1, '$'), '言語') >= 0, string(getbufline(gnosis#outline#state().buf, 1, '$')))
call gnosis#outline#close()
call gnosis#outline#open()
sleep 200m
call s:ok('アウトライン: 3 回目でも見出しが出る', index(getbufline(gnosis#outline#state().buf, 1, '$'), '言語') >= 0)
call s:ok('アウトラインの中で \o: ノートの窓へ戻る', 1)
call win_gotoid(gnosis#outline#win())
call s:keys('\o')
call s:ok('\o（アウトラインの中）: ノートの窓へ', win_getid() != gnosis#outline#win() && &filetype !=# 'gnosis-outline' && gnosis#outline#is_open(), &filetype)
call s:keys('\o')
call s:ok('\o（ノートの窓）: アウトラインへ', win_getid() == gnosis#outline#win())
call s:keys('q')
call s:ok('パネルの中の q: 閉じて、ノートの窓へ', !gnosis#outline#is_open() && &filetype !=# 'gnosis-outline')
" 右のパネルは 1 つだけ。\h でハブ、\q でタブのボードに差し替わり、同じキーでノート ⇔ パネル、q で閉じる
call s:keys('\o')
call s:keys('\h')
call s:ok('\h: アウトラインが消えて、ハブが右に出る（パネルは 1 つ）', !gnosis#outline#is_open() && gnosis#panel#kind() ==# 'hub' && win_screenpos(win_getid())[1] > win_screenpos(gnosis#mview#note_win())[1], gnosis#panel#kind())
call s:keys('\h')
call s:ok('\h をもう一度: ノートの窓へ', win_getid() == gnosis#mview#note_win() && gnosis#panel#kind() ==# 'hub')
call s:keys('\h')
call s:keys('q')
call s:ok('ハブの中の q: 閉じる', gnosis#panel#kind() ==# '' && win_getid() == gnosis#mview#note_win())
call s:keys('\q')
call s:ok('\q: タブのボードが右に出る', gnosis#panel#kind() ==# 'tabs')
call setline(1, ['[a](a.md)', '[b](b.md)'])
let g:gnosis_test_tabs_clear = 'n'
call s:keys('D')
call s:ok('D: n ならタブを消さない', len(filter(getline(1, '$'), 'v:val =~# "]("')) == 2)
let g:gnosis_test_tabs_clear = 'y'
call s:keys('D')
unlet g:gnosis_test_tabs_clear
call s:ok('D: y なら全部のタブを消す', len(filter(getline(1, '$'), 'v:val =~# "]("')) == 0)
call s:keys('q')
" 窓の行き来（Shift+矢印 / gh gl）: 左のビュー・ノート・右のパネルの順。端では止まる
call s:keys('\o')
call win_gotoid(gnosis#mview#state().win)
call s:keys('gl')
call s:ok('gl: 左のビュー → ノート', win_getid() == gnosis#mview#note_win())
call s:keys('gl')
call s:ok('gl: ノート → 右のパネル', win_getid() == gnosis#outline#win())
call s:keys('gl')
call s:ok('gl: 右の端では動かない', win_getid() == gnosis#outline#win())
call s:keys('gh')
call s:ok('gh: パネル → ノート', win_getid() == gnosis#mview#note_win())
call s:keys('gh')
call s:ok('gh: ノート → 左のビュー', win_getid() == gnosis#mview#state().win)
call s:keys('gh')
call s:ok('gh: 左の端では動かない', win_getid() == gnosis#mview#state().win)
call feedkeys("\<S-Right>", 'xt')
call s:ok('Shift+→ も同じ（左のビュー → ノート）', win_getid() == gnosis#mview#note_win())
call gnosis#outline#close()
" 窓の幅は勝手に動かない: パネルを開けたり閉じたりしても、左のビューの幅は変わらない
call gnosis#mview#switch_view('fz')
call win_gotoid(gnosis#mview#note_win())
if gnosis#outline#is_open() | call gnosis#outline#close() | endif
let s:vw = winwidth(gnosis#mview#state().win)
call s:keys('\o')
call s:ok('パネルを開けても、ビューの幅は変わらない', winwidth(gnosis#mview#state().win) == s:vw, string([s:vw, winwidth(gnosis#mview#state().win)]))
call s:keys('q')
call s:ok('パネルを閉じても、ビューの幅は変わらない', winwidth(gnosis#mview#state().win) == s:vw, string([s:vw, winwidth(gnosis#mview#state().win)]))
call s:keys('\h')
call s:keys('q')
call s:keys('\q')
call s:keys('q')
call s:ok('ハブ・ボードを開け閉めしても、ビューの幅は変わらない', winwidth(gnosis#mview#state().win) == s:vw)
" < > は境目を動かす向き。右のパネルでは < で広く、> で狭く
call s:keys('\o')
let s:pw = winwidth(0)
call s:keys('<')
call s:ok('パネルで <: 境目が左へ（パネルが広がる）', winwidth(0) > s:pw, string([s:pw, winwidth(0)]))
let s:pw = winwidth(0)
call s:keys('>')
call s:ok('パネルで >: 境目が右へ（パネルが狭まる）', winwidth(0) < s:pw, string([s:pw, winwidth(0)]))
call s:keys('q')
