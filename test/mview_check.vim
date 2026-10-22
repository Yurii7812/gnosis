" 曼荼羅ビュー（<Space>）の回帰網（test/mview_net.sh から呼ぶ）。
" 結果は $MV_WORK/result.txt に「OK 名前」「NG 名前: 詳細」で書く。
set nomore
let s:work = $MV_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
function! s:keys(k) abort
  call feedkeys(a:k, 'xt')
endfunction
function! s:text() abort
  return join(getbufline(gnosis#mview#state().buf, 1, '$'), "\n")
endfunction
" 盤面だけ（凡例の行を除く）
function! s:grid() abort
  return join(filter(getbufline(gnosis#mview#state().buf, 1, '$'), 'v:val =~# "┃"'), "\n")
endfunction
function! s:note() abort
  return fnamemodify(bufname(winbufnr(win_id2win(win_getid()))), ':t')
endfunction
function! s:mk(name, title, attr, grp, body) abort
  let l:ls = ['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title] + (a:attr ? ['attribute: group'] : []) + ['---', '', '# ' . a:title, '']
  if !empty(a:grp)
    let l:ls += ['Group:'] + map(copy(a:grp), '"[" . v:val[0] . "](" . v:val[1] . ")"') + ['']
  endif
  call writefile(l:ls + a:body, s:v . '/' . a:name)
endfunction

call s:mk('index.md', 'Index', 0, [], ['[植物](plant.md)', '[料理](cook.md)'])
let s:members = ['ハーブ', 'バラ', '栽培', 'ローズマリー', 'ミント', 'バジル', 'タイム', 'サルビア', 'ラベンダー', '水やり']
let s:files = ['herb', 'rose', 'grow', 'rosemary', 'mint', 'basil', 'thyme', 'sage', 'lav', 'water']
call s:mk('plant.md', '植物', 1, [['Index', 'index.md']], map(copy(s:files), '"[" . s:members[v:key] . "](" . v:val . ".md)"'))
call s:mk('cook.md', '料理', 1, [['Index', 'index.md']], ['[カレー](curry.md)'])
call s:mk('herb.md', 'ハーブ', 0, [['植物', 'plant.md'], ['料理', 'cook.md']], ['ハーブの話', '[ミント](mint.md)'])
for s:i in range(1, len(s:files) - 1)
  call s:mk(s:files[s:i] . '.md', s:members[s:i], 0, [['植物', 'plant.md']], [])
endfor
call s:mk('curry.md', 'カレー', 0, [['料理', 'cook.md']], [])

" ふつうのノートから <Space>: そのノートを中心に、所属する索引が周りに出る
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
let s:st = gnosis#mview#state()
call s:ok('Space で曼荼羅が開く', &filetype ==# 'gnosis-mandala', &filetype)
call s:ok('中心は今のノート', s:st.center ==# 'herb.md', s:st.center)
call s:ok('周りに所属の索引が出る', s:text() =~# '1 ◆植物' && s:text() =~# '2 ◆料理', s:text())
call s:ok('ノートのつながりも出る（すべて）', s:text() =~# '3 ミント')
call s:ok('右にそのノートが開いている', fnamemodify(bufname(winbufnr(win_id2win(1) ? 2 : 1)), ':t') ==# 'herb.md' || index(map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":t")'), 'herb.md') >= 0)

" モード: 索引だけ → ノートだけ
call s:keys('g')
call s:ok('索引だけ: ミントは出ない', s:text() !~# 'ミント' && s:text() =~# '◆植物', s:text())
call s:keys('n')
call s:ok('ノートだけ: 索引は出ない', s:grid() !~# '◆' && s:text() =~# 'ミント', s:text())
call s:keys('a')
call s:ok('a ですべてに戻る', s:text() =~# '◆植物' && s:text() =~# 'ミント')
" 検索の結果を周りに並べる（s の入力そのものは試験できないので、状態を入れて描き直す）
let s:st.results = ['mint.md', 'herb.md']
let s:st.rquery = 'ハーブ'
call s:keys('u')
call s:ok('検索の結果が周りに出て、真ん中に検索の語が出る', s:text() =~# '1 ミント' && s:text() =~# '検索: ハーブ（2件）' && len(filter(split(s:text(), "\n"), 'v:val =~# "┃ *検索: ハ"')) == 1, s:text())
call s:keys('g')
call s:ok('モードを変えると検索は解ける', s:st.rquery ==# '' && s:text() !~# '検索:', s:text())
call s:keys('a')

" 移動して Enter: その索引が中心になる（カーソルは曼荼羅のまま）
call s:keys('1')
call s:ok('数字キー 1 でそのまま植物が中心になる', s:st.center ==# 'plant.md', s:st.center)
call s:ok('カーソルは曼荼羅に残る', &filetype ==# 'gnosis-mandala')
call s:ok('索引の周りに所属する Index が最初に出る', s:text() =~# '1 ◆Index', s:text())
call s:ok('そのあとに載っているノートが 8 つまで', s:text() =~# '2 ハーブ' && s:text() =~# '9 タイム', s:text())
call s:ok('1/2 枚目と出る', s:text() =~# '1/2', s:text())
call s:ok('ページ (1/2) が中央のマスの上に出る', s:text() =~# '(1/2)' && len(filter(split(s:text(), "\n"), 'v:val =~# "┃ *(1/2) *┃"')) == 1, s:text())
call s:keys('?')
call s:ok('? で下の案内が隠れる（1 行だけ残る）', s:text() =~# '? で案内を表示' && s:text() !~# 'q 閉じる', s:text())
call s:keys('?')
call s:ok('もう一度 ? で案内が出る', s:text() =~# 'q 閉じる')
" ページ送り
call s:keys(']')
call s:ok('] で 2 枚目: サルビア・ラベンダー・水やり', s:text() =~# '1 サルビ' && s:text() =~# '3 水やり' && s:text() =~# '2/2', s:text())
call s:keys(']')
call s:ok('最後の次へは進まない', s:st.page == 1)
call s:keys('[')
" / : ふつうの検索のようにヒットへ飛ぶ（複数枚あるときは別の枚へも）。入力そのものは試験できないので状態を入れる
let s:st.find = 'ラベンダー'
call s:keys("\<Tab>")
call s:ok('Tab で別の枚のヒットへ飛ぶ（植物の 2 枚目）', s:st.page == 1 && s:st.cur == [0, 1] && s:st.hit_n == 1, string(s:st.cur) . ' page=' . s:st.page . ' n=' . get(s:st, 'hit_n', -1))
call s:ok('ヒットの語がヘッダーに出る', s:text() =~# '/ラベンダー 1/1', s:text())
call s:keys("\<Esc>")
call s:ok('Esc で検索のハイライトを解く', s:st.find ==# '')
call s:keys('[')
" 1 2 3 / 4 5 6 / 7 8 9 の並び（真ん中が 5。4 は中心の左・6 は右）
call s:ok('4 は中心の左・5 は右の同じ行', len(filter(split(s:text(), "\n"), 'v:val =~# "4 栽培 *┃ *5 ◆植物"')) == 1 && s:text() =~# '6 ローズ', s:text())
" 数字キーでそのままノートのマスへ進む: 右にそのノートが開く
call s:keys('4')
call s:ok('数字キー 4 で栽培が中心に', s:st.center ==# 'grow.md', s:st.center)
call s:ok('右に栽培が開く', index(map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":t")'), 'grow.md') >= 0)
call s:ok('栽培の周りに所属の植物', s:text() =~# '1 ◆植物', s:text())
" 戻る
call s:keys('b')
call s:ok('b で植物に戻る', s:st.center ==# 'plant.md', s:st.center)
" カーソルを動かすだけで右のノートが切り替わる（曼荼羅の中心は変わらない）
call s:keys('k')
call s:ok('k で右のノートが切り替わる（ハーブ）', index(map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":t")'), 'herb.md') >= 0 && s:st.center ==# 'plant.md', s:st.center)
call s:keys('j')
" 数字キー: 既定は移動して中心に。t でカーソルだけ（右のノートは切り替わる）
call s:keys('t')
call s:keys('3')
call s:ok('カーソルだけ: 中心は変わらず、右のノートは切り替わる', s:st.center ==# 'plant.md' && s:st.cur == [0, 2] && index(map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":t")'), 'rose.md') >= 0, string(s:st.cur) . s:st.center)
call s:keys('t')
" < > で曼荼羅の幅を変える（盤面は作り直されて正方形のまま）
let s:w0 = winwidth(0)
call s:keys('<')
call s:ok('< で曼荼羅が狭くなる', winwidth(0) < s:w0, s:w0 . ' -> ' . winwidth(0))
call s:keys('>')
call s:keys('>')
call s:ok('> で曼荼羅が広くなる', winwidth(0) > s:w0, s:w0 . ' -> ' . winwidth(0))
call s:keys('<')
" どんな大きさでも盤面が窓に収まる。z で中央に戻る
for [s:ww, s:hh] in [[24, 14], [40, 12], [100, 30]]
  execute 'vertical resize ' . s:ww
  execute 'resize ' . s:hh
  call s:keys('l')
  call s:keys('z')
  let s:bl = getbufline(s:st.buf, 1, '$')
  call s:ok('窓 ' . s:ww . 'x' . s:hh . ': どの行も幅に収まり、行数も高さに収まる', len(filter(copy(s:bl), 'strdisplaywidth(v:val) > winwidth(0)')) == 0 && len(s:bl) <= winheight(0), winwidth(0) . 'x' . winheight(0) . ' lines=' . len(s:bl))
  call s:ok('z でカーソルは中心のマスへ戻る', s:st.cur == [1, 1], string(s:st.cur))
endfor
execute 'vertical resize ' . (&columns / 2)
execute 'resize ' . (&lines - 2)
call s:keys('z')
" 全画面 9×9
call s:keys('f')
call s:ok('f で 9×9', s:st.size == 9 && winnr('$') == 1, s:st.size . ' wins=' . winnr('$'))
call s:ok('9×9 は 9 行 9 列', len(filter(getbufline(s:st.buf, 1, '$'), 'v:val =~# "┃"')) >= 9 && s:text() =~# '╋')
call s:ok('9×9 に周りの曼荼羅の中身も出る', s:text() =~# 'ハ' && s:text() =~# 'ミ', s:text())
call s:ok('9×9 にも番号が出る', s:text() =~# '1 ◆' && s:text() =~# '8 ', s:text())
call s:keys('t')
call s:ok('t で数字キーはカーソルだけになる', s:st.digit ==# 'cursor' && s:text() =~# '数字:カーソルだけ(t)', s:text())
call s:keys('6')
call s:ok('9×9 の数字（カーソルだけ）は中心を変えない', s:st.center ==# 'plant.md' && s:st.cur == [4, 7], string(s:st.cur) . ' ' . s:st.center)
call s:keys('t')
call s:ok('もう一度 t で数字は移動に戻る', s:st.digit ==# 'jump')
call s:keys('f')
call s:ok('もう一度 f で 3×3 に戻る', s:st.size == 3 && winnr('$') == 2)
" Space でノートへ、もう一度で曼荼羅へ
call s:keys(' ')
call s:ok('Space でノートのウィンドウへ', &filetype !=# 'gnosis-mandala')
call s:keys(' ')
call s:ok('Space でまた曼荼羅へ', &filetype ==# 'gnosis-mandala')
" 閉じる
call s:keys('q')
call s:ok('q で閉じる', &filetype !=# 'gnosis-mandala' && winnr('$') == 1)

" c: 近い索引。すでに所属している索引が先に出る
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
call s:keys('c')
call s:ok('c: すでに所属している索引が先に出る', s:text() =~# '1 ◆植物' && s:text() =~# '2 ◆料理', s:text())
call s:keys('k')
call s:keys('h')
call s:ok('カーソルのマスの説明が下の 1 行に出る（索引・所属）', s:text() =~# '▶ 植物  \[索引\]  所属', s:text())
call s:keys('q')

" r: 関連。索引もノートも関連の強い順（herb: 本文でリンクしているミントが出る）
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
call s:keys('r')
call s:ok('r: 関連モード。ノートも索引も出る', s:text() =~# 'ミント' && s:text() =~# '◆植物', s:text())
call s:ok('モードの行に今のモードが出る', s:text() =~# '\[関連:r\]' && s:text() =~# '全体:a', s:text())
call s:ok('下の案内は見切れず全部出る（q 閉じる まで）', s:text() =~# 'q 閉じる', s:text())
call s:ok('どの行も窓の幅に収まる', len(filter(getbufline(s:st.buf, 1, '$'), 'strdisplaywidth(v:val) > winwidth(0)')) == 0)
call s:keys('q')

" 題を変えたら（zt など）閉じなくても曼荼羅が更新される: 書き換えて読み直す（保存や読み込みで少し待って呼ばれる）
execute 'edit ' . s:v . '/plant.md'
call s:keys(' ')
call s:keys('a')
call s:ok('更新前は古い題', s:text() =~# '栽培' && s:text() !~# '新しい題', s:text())
call s:mk('grow.md', '栽培の新しい題', 0, [['植物', 'plant.md']], [])
call gnosis#mview#refresh()
call s:ok('refresh で新しい題が出る（閉じなくてよい）', s:text() =~# '新しい' && &filetype ==# 'gnosis-mandala', s:text())
call s:keys('q')

" + - : 曼荼羅だけの文字サイズを保存する（端末が許せばその場で反映。試験では保存だけ確かめる）
let s:fs0 = gnosis#termfont#load().fontSize
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
call s:keys('+')
call s:ok('+ で曼荼羅の文字サイズが 1 つ大きく保存される', gnosis#termfont#load().mandalaFontSize == s:fs0 + 1, gnosis#termfont#load().mandalaFontSize . ' / ' . s:fs0)
call s:keys('-')
call s:keys('-')
call s:ok('- で小さく保存される', gnosis#termfont#load().mandalaFontSize == s:fs0 - 1)
call s:keys('q')

" \g: 曼荼羅で索引を選んで、今のノートを載せる
call s:mk('misc.md', '雑記', 0, [], [])
call s:mk('empty.md', '空の索引', 1, [['Index', 'index.md']], [])
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: Index', '---', '', '# Index', '', '[植物](plant.md)', '[料理](cook.md)', '[空の索引](empty.md)'], s:v . '/index.md')
let g:gnosis_test_display_name = ['雑記']
let g:gnosis_test_yomi = ['ざっき']
execute 'edit ' . s:v . '/misc.md'
call gnosis#mview#pick()
let s:st = gnosis#mview#state()
call s:ok('\g は今のノートが中心で近い索引から始まる（手がかりが無ければ Index の索引）', s:st.pick == 1 && s:st.center ==# 'misc.md' && s:st.mode ==# 'near' && s:text() =~# '1 ◆植物' && s:text() =~# '3 ◆空の', s:text())
call s:ok('選ぶ間は右のノートを入れ替えない', winnr('$') == 2)
let s:st.query = '空'
call s:keys('u')
call s:ok('絞り込むと題が合う索引だけ', s:text() =~# '1 ◆空の' && s:text() !~# '◆植物', s:text())
call s:keys('1')
call s:keys("\<CR>")
call s:ok('絞り込んだ索引へ進むと絞り込みは解ける', s:st.center ==# 'empty.md' && s:st.query ==# '', s:st.center)
call s:keys("\<CR>")
call s:ok('中心で Enter すると載る', join(readfile(s:v . '/empty.md'), "\n") =~# '\[雑記\](misc.md)', join(readfile(s:v . '/empty.md'), "\n"))
call s:ok('載せたあとは元のノートに戻り曼荼羅は閉じる', fnamemodify(expand('%:p'), ':t') ==# 'misc.md' && winnr('$') == 1, expand('%:p') . ' ' . winnr('$'))

call writefile(s:res, s:work . '/result.txt')
qa!
