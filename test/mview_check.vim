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
call s:keys('R')
call s:ok('検索の結果が周りに出て、真ん中に検索の語が出る', s:text() =~# '1 ミント' && s:text() =~# '検索: ハーブ（2件）' && len(filter(split(s:text(), "\n"), 'v:val =~# "┃ *検索: ハ"')) == 1, s:text())
call s:keys('g')
call s:ok('モードを変えると検索は解ける', s:st.rquery ==# '' && s:text() !~# '検索:', s:text())
call s:keys('a')

" 移動して Enter: その索引が中心になる（カーソルは曼荼羅のまま）
call s:keys('1')
call s:ok('数字キー 1 でそのまま植物が中心になる', s:st.center ==# 'plant.md', s:st.center)
call s:ok('カーソルは曼荼羅に残る', &filetype ==# 'gnosis-mandala')
call s:ok('索引の周りに所属する Index が最初に出る', s:text() =~# '1 ◆Index', s:text())
call s:ok('そのあとに載っているノートが 8 つまで', s:text() =~# '2 ハーブ' && s:text() =~# '8 タイム', s:text())
call s:ok('1/2 枚目と出る', s:text() =~# '1/2', s:text())
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
" 1 2 3 / 4 _ 5 / 6 7 8 の並び（4 は中心の左・5 は右）
call s:ok('4 は中心の左・5 は右の同じ行', len(filter(split(s:text(), "\n"), 'v:val =~# "4 栽培 *┃ *◆植物"')) == 1 && s:text() =~# '5 ローズ', s:text())
" 数字キーでそのままノートのマスへ進む: 右にそのノートが開く
call s:keys('4')
call s:ok('数字キー 4 で栽培が中心に', s:st.center ==# 'grow.md', s:st.center)
call s:ok('右に栽培が開く', index(map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":t")'), 'grow.md') >= 0)
call s:ok('栽培の周りに所属の植物', s:text() =~# '1 ◆植物', s:text())
" 戻る
call s:keys('-')
call s:ok('- で植物に戻る', s:st.center ==# 'plant.md', s:st.center)
" 全画面 9×9
call s:keys('f')
call s:ok('f で 9×9', s:st.size == 9 && winnr('$') == 1, s:st.size . ' wins=' . winnr('$'))
call s:ok('9×9 は 9 行 9 列', len(filter(getbufline(s:st.buf, 1, '$'), 'v:val =~# "┃"')) >= 9 && s:text() =~# '╋')
call s:ok('9×9 に周りの曼荼羅の中身も出る', s:text() =~# 'ハ' && s:text() =~# 'ミ', s:text())
call s:ok('9×9 にも番号が出る', s:text() =~# '1 ◆' && s:text() =~# '8 ', s:text())
call s:keys('6')
call s:ok('9×9 の数字は中心を変えずカーソルだけ動く', s:st.center ==# 'plant.md' && s:st.cur == [7, 1], string(s:st.cur) . ' ' . s:st.center)
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
call s:keys('R')
call s:ok('絞り込むと題が合う索引だけ', s:text() =~# '1 ◆空の' && s:text() !~# '◆植物', s:text())
call s:keys('1')
call s:keys("\<CR>")
call s:ok('絞り込んだ索引へ進むと絞り込みは解ける', s:st.center ==# 'empty.md' && s:st.query ==# '', s:st.center)
call s:keys("\<CR>")
call s:ok('中心で Enter すると載る', join(readfile(s:v . '/empty.md'), "\n") =~# '\[雑記\](misc.md)', join(readfile(s:v . '/empty.md'), "\n"))
call s:ok('載せたあとは元のノートに戻り曼荼羅は閉じる', fnamemodify(expand('%:p'), ':t') ==# 'misc.md' && winnr('$') == 1, expand('%:p') . ' ' . winnr('$'))

call writefile(s:res, s:work . '/result.txt')
qa!
