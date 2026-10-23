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
" 開くたびに今のノートが中心（覚えた位置は専用の試験でだけ使う）
let g:gnosis_mview_restore = 0
" 既存の試験は罫線の文字で盤面を読む（色の線は専用の試験で確かめる）
let g:gnosis_mview_border = 'line'

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
call s:ok('上に状態の 1 行（モード・重ね）。案内や凡例は出ない', s:text() =~# '\[a\] c:オフ r:オフ' && s:text() !~# 'q 閉じる' && s:text() !~# 'グループ  親', s:text())
call s:keys('?')
call s:ok('? で案内が画面中央のポップアップに出る', len(popup_list()) == 1 && join(getbufline(winbufnr(popup_list()[0]), 1, '$'), "\n") =~# 'Tab / S-Tab', string(popup_list()))
call s:keys('q')
call s:ok('q でポップアップが閉じる（曼荼羅は閉じない）', len(popup_list()) == 0 && &filetype ==# 'gnosis-mandala', string(popup_list()))
call s:ok('中心は今のノート', s:st.center ==# 'herb.md', s:st.center)
call s:ok('周りに所属の索引が出る', s:text() =~# '1 植物' && s:text() =~# '2 料理', s:text())
call s:ok('ノートのつながりも出る（すべて）', s:text() =~# '3 ミント')
call s:ok('右にそのノートが開いている', fnamemodify(bufname(winbufnr(win_id2win(1) ? 2 : 1)), ':t') ==# 'herb.md' || index(map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":t")'), 'herb.md') >= 0)

" モード: 索引だけ → ノートだけ
call s:keys('i')
call s:ok('索引だけ: ミントは出ない', s:text() !~# 'ミント' && s:text() =~# '植物', s:text())
call s:keys('a')
call s:ok('全体: 索引もノートも出る', s:grid() =~# '植物' && s:grid() =~# '料理' && s:text() =~# 'ミント', s:text())
call s:keys('a')
call s:ok('a ですべてに戻る', s:text() =~# '植物' && s:text() =~# 'ミント')
" 検索の結果を周りに並べる（s の入力そのものは試験できないので、状態を入れて描き直す）
let s:st.results = ['mint.md', 'herb.md']
let s:st.rquery = 'ハーブ'
call s:keys('u')
call s:ok('検索の結果が周りに出て、真ん中に検索の語が出る', s:text() =~# '1 ミント' && s:text() =~# '検索: ハーブ（2件）' && len(filter(split(s:text(), "\n"), 'v:val =~# "┃ *検索: ハ"')) == 1, s:text())
call s:keys('i')
call s:ok('モードを変えると検索は解ける', s:st.rquery ==# '' && s:text() !~# '検索:', s:text())
call s:keys('a')

" 移動して Enter: その索引が中心になる（カーソルは曼荼羅のまま）
call s:keys('1')
call s:ok('数字キー 1 でそのまま植物が中心になる', s:st.center ==# 'plant.md', s:st.center)
call s:ok('カーソルは曼荼羅に残る', &filetype ==# 'gnosis-mandala')
call s:ok('索引の周りに所属する Index が最初に出る', s:text() =~# '1 Index', s:text())
call s:ok('そのあとに載っているノートが 8 つまで', s:text() =~# '2 ハーブ' && s:text() =~# '9 タイム', s:text())
call s:ok('1/2 枚目と出る', s:text() =~# '1/2', s:text())
call s:ok('ページ (1/2) が中央のマスの上に出る', s:text() =~# '(1/2)' && len(filter(split(s:text(), "\n"), 'v:val =~# "┃ *(1/2) *┃"')) == 1, s:text())
call s:ok('ページ (1/2) は盤面に残る', s:text() =~# '(1/2)', s:text())
" ページ送り
call s:keys(']')
call s:ok('] で 2 枚目: サルビア・ラベンダー・水やり', s:text() =~# '1 サルビ' && s:text() =~# '3 水やり' && s:text() =~# '2/2', s:text())
call s:keys(']')
call s:ok('最後の次へは進まない', s:st.page == 1)
call s:keys('[')
" / : ふつうの検索のようにヒットへ飛ぶ（複数枚あるときは別の枚へも）。入力そのものは試験できないので状態を入れる
let s:st.find = 'ラベンダー'
call s:keys('n')
call s:ok('n で別の枚のヒットへ飛ぶ（植物の 2 枚目）', s:st.page == 1 && s:st.cur == [0, 1] && s:st.hit_n == 1, string(s:st.cur) . ' page=' . s:st.page . ' n=' . get(s:st, 'hit_n', -1))
call s:ok('ヒットの語がヘッダーに出る', s:text() =~# '/ラベンダー 1/1', s:text())
call s:keys('q')
call s:ok('q でハイライトをやめる（曼荼羅は閉じない）', s:st.find ==# '' && &filetype ==# 'gnosis-mandala')
call s:keys('[')
" 1 2 3 / 4 5 6 / 7 8 9 の並び（真ん中が 5。4 は中心の左・6 は右）
call s:ok('4 は中心の左・5 は右の同じ行', len(filter(split(s:text(), "\n"), 'v:val =~# "4 栽培 *┃ *5 植物"')) == 1 && s:text() =~# '6 ローズ', s:text())
" 数字キーでそのままノートのマスへ進む: 右にそのノートが開く
call s:keys('4')
call s:ok('数字キー 4 で栽培が中心に', s:st.center ==# 'grow.md', s:st.center)
call s:ok('右に栽培が開く', index(map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":t")'), 'grow.md') >= 0)
call s:ok('栽培の周りに所属の植物', s:text() =~# '1 植物', s:text())
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
call s:ok('9×9 にも番号が出る', s:text() =~# '1 Index' && s:text() =~# '8 ', s:text())
call s:keys('t')
call s:ok('t で数字キーはカーソルだけになる', s:st.digit ==# 'cursor', s:st.digit)
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
call s:ok('c: すでに所属している索引が先に出て、近いグループが後ろに重なる', s:text() =~# '1 植物' && s:text() =~# '2 料理', s:text())
call s:keys('k')
call s:keys('h')
call s:ok('カーソルのマスの説明が下の 1 行に出る', s:text() =~# '▶ 植物  \[グループ\]', s:text())
call s:keys('q')

" ダブルインデックスの道: Index → 最初のノート → BranchGroup のトピック索引 → ノート
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 最初のノート', '---', '', '# 最初のノート', '', 'BranchGroup:', '[トピック](topic.md)', '', 'Group:', '[Index](index.md)', '', '本文'], s:v . '/first.md')
call s:mk('topic.md', 'トピック', 1, [], ['[中身のノート](item.md)'])
call s:mk('item.md', '中身のノート', 0, [['トピック', 'topic.md']], [])
execute 'edit ' . s:v . '/first.md'
call s:keys(' ')
call s:keys('a')
call s:ok('最初のノートが中心: 進む先のトピック索引が先、戻る方向の Index が後', s:text() =~# '1 トピック' && s:text() =~# '2 Index', s:text())
call s:keys('1')
call s:ok('トピック索引が中心: その索引を持つ最初のノートに戻れる', s:st.center ==# 'topic.md' && s:text() =~# '1 最初', s:text())
call s:ok('トピック索引が中心: 載っているノートも出る', s:text() =~# '中身のノ', s:text())
call s:keys('q')

" r: 関連。索引もノートも関連の強い順（herb: 本文でリンクしているミントが出る）
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
call s:keys('r')
call s:ok('r: 関連モード。ノートも索引も出る', s:text() =~# 'ミント' && s:text() =~# '植物', s:text())
call s:ok('モードの行に今のモードと重ねるもののオン/オフが出る', s:text() =~# '\[a\] c:オン r:オン', s:text())
call s:ok('どの行も窓の幅に収まる', len(filter(getbufline(s:st.buf, 1, '$'), 'strdisplaywidth(v:val) > winwidth(0)')) == 0)
call s:keys('q')

" 題を変えたら（zr など）閉じなくても曼荼羅が更新される: 書き換えて読み直す（保存や読み込みで少し待って呼ばれる）
" （ノートが中心のときは題で出る。索引が中心のときは、その索引に書かれた索引語で出る）
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
call s:keys('a')
call s:ok('更新前は古い題', s:text() =~# '植物' && s:text() !~# '新しい題', s:text())
call s:mk('plant.md', '植物の新しい題', 1, [['Index', 'index.md']], map(copy(s:files), '"[" . s:members[v:key] . "](" . v:val . ".md)"'))
call gnosis#mview#refresh()
call s:ok('refresh で新しい題が出る（閉じなくてよい）', s:text() =~# '新しい' && &filetype ==# 'gnosis-mandala', s:text())
call s:mk('plant.md', '植物', 1, [['Index', 'index.md']], map(copy(s:files), '"[" . s:members[v:key] . "](" . v:val . ".md)"'))
call gnosis#mview#refresh()
call s:keys('q')

" 索引（グループ）が中心のときの名前は、その索引に書かれた索引語
call s:mk('kw.md', 'キーワードの長い正式な題', 0, [['語の索引', 'kwidx.md']], [])
call s:mk('kwidx.md', '語の索引', 1, [], ['[短い索引語](kw.md)'])
execute 'edit ' . s:v . '/kwidx.md'
call s:keys(' ')
call s:keys('i')
call s:ok('i: 索引の項目は索引語の名前で出る（ノートの題ではない）', s:text() =~# '短い' && s:text() !~# '正式', s:text())
call s:keys('q')

" 同じノートが同じ索引に別の索引語で載っていれば、載っている回数だけ別のマスに出る
call s:mk('dupnote.md', 'ひとつだけのノート', 0, [['重複の索引', 'dupidx.md']], [])
call s:mk('dupidx.md', '重複の索引', 1, [], ['[アイコン](dupnote.md)', '[デザイン](dupnote.md)'])
execute 'edit ' . s:v . '/dupidx.md'
call s:keys(' ')
call s:keys('i')
call s:ok('同じノートの 2 つの索引語が、別々のマスに出る', s:text() =~# '1 アイコン' && s:text() =~# '2 デザイン' && s:text() !~# 'ひとつだけ', s:text())
call s:keys('q')

" 曼荼羅の幅を覚える: < > で変えた幅が、閉じて開き直しても、別のノートから開いても、そのまま（中心は今のノート）
let g:gnosis_mview_restore = 1
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
call s:keys('<')
call s:keys('<')
let s:st = gnosis#mview#state()
let s:t0 = s:st.tenths
call s:keys('q')
call s:ok('幅を保存する（mandala.json）', filereadable(gnosis#home#path('mandala.json')) && join(readfile(gnosis#home#path('mandala.json')), '') =~# '"tenths"')
unlet s:st.tenths
execute 'edit ' . s:v . '/curry.md'
call s:keys(' ')
let s:st = gnosis#mview#state()
call s:ok('開き直すと前回の幅のまま', s:st.tenths == s:t0 && s:t0 == 3, string(get(s:st, 'tenths', 'none')) . ' / ' . s:t0)
call s:ok('中心は今のノート（位置は覚えない）', s:st.center ==# 'curry.md', s:st.center)
call s:keys('q')
let g:gnosis_mview_restore = 0

" \l → e → g: 入れるノートを選び、置き場所のキー g で、入れるグループを曼荼羅で選ぶ（e で決定。曼荼羅は閉じない）
call s:mk('misc.md', '雑記', 0, [], [])
call s:mk('empty.md', '空の索引', 1, [['Index', 'index.md']], [])
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: Index', '---', '', '# Index', '', '[植物](plant.md)', '[料理](cook.md)', '[空の索引](empty.md)'], s:v . '/index.md')
let g:gnosis_test_display_name = ['雑記']
let g:gnosis_test_yomi = ['ざっき']
execute 'edit ' . s:v . '/misc.md'
call gnosis#mview#link_pick()
let s:st = gnosis#mview#state()
call s:ok('\l は今のノートが中心で、入れるノートを選ぶモードになる', s:st.pick ==# 'link' && s:st.center ==# 'misc.md' && s:text() =~# '入れるノートを選ぶ', s:text())
let g:gnosis_test_keys = ['g']
call s:keys('e')
call s:ok('e → g で、入れ先のグループを選ぶモードになる（近いグループが重なる）', s:st.pick ==# 'group' && s:st.center ==# 'misc.md' && s:st.near_on == 1 && s:st.mode ==# 'groups' && s:text() =~# '1 植物' && s:text() =~# '3 空の', s:text())
call s:ok('曼荼羅は開いたまま', &filetype ==# 'gnosis-mandala')
call s:keys('o')
call s:ok('o で入れるノート（元のノート）を右に見る', index(map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":t")'), 'misc.md') >= 0 && s:st.origin_view == 1)
call s:keys('o')
call s:ok('もう一度 o で中心のノートに戻る', s:st.origin_view == 0)
let s:st.query = '空'
call s:keys('z')
call s:ok('絞り込むと題が合う索引だけ', s:text() =~# '1 空の' && s:text() !~# '植物', s:text())
call s:keys('1')
call s:ok('絞り込んだ索引へ進むと絞り込みは解ける', s:st.center ==# 'empty.md' && s:st.query ==# '', s:st.center)
call s:ok('Enter だけではまだ載らない', join(readfile(s:v . '/empty.md'), "\n") !~# '\[雑記\]', 'x')
call s:keys('e')
call s:ok('e で載る', join(readfile(s:v . '/empty.md'), "\n") =~# '\[雑記\](misc.md)', join(readfile(s:v . '/empty.md'), "\n"))
call s:ok('載せたあとも曼荼羅は閉じず、選ぶモードだけ終わる', &filetype ==# 'gnosis-mandala' && s:st.pick ==# '', &filetype . ' pick=' . string(s:st.pick))
call s:ok('右の窓は入れ先のグループ（中心）を見せる', index(map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":t")'), 'empty.md') >= 0)
call s:keys('Q')

" I: グループを選ぶ最中に、Index に追加する（そのトピックの入り口にする）
call s:mk('entry.md', '入り口のノート', 0, [], [])
execute 'edit ' . s:v . '/entry.md'
call gnosis#mview#link_pick()
let g:gnosis_test_keys = ['g']
let g:gnosis_test_display_name = ['入り口']
let g:gnosis_test_yomi = ['いりぐち']
call s:keys('e')
call s:keys('I')
call s:ok('I で Index に載る', join(readfile(s:v . '/index.md'), "\n") =~# '\[入り口\](entry.md)', join(readfile(s:v . '/index.md'), "\n"))
call s:keys('Q')

" t: 入れるノートの見出しを選んで、その見出しへ飛ぶリンクで入れる（表示名はそのまま）。q（取り消し）でも選ぶモードは続く
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 見出しのあるノート', '---', '', '# 見出しのあるノート', '', '## 第一の話', '本文', '## 第二の話', '本文'], s:v . '/outline.md')
execute 'edit ' . s:v . '/outline.md'
call gnosis#mview#link_pick()
let g:gnosis_test_keys = ['g']
let g:gnosis_test_display_name = ['見出しのあるノート']
let g:gnosis_test_yomi = ['みだしのあるのーと']
call s:keys('e')
let s:st = gnosis#mview#state()
call s:keys('2')
call s:keys('1')
let s:st.center = 'empty.md'
call s:keys('z')
let g:gnosis_test_heading = '第二の話'
call s:keys('t')
call s:ok('t で見出しへ飛ぶリンクが入る（表示名は題のまま）', join(readfile(s:v . '/empty.md'), "\n") =~# '\[見出しのあるノート\](outline.md#第二の話)', join(readfile(s:v . '/empty.md'), "\n"))
unlet g:gnosis_test_heading
call s:keys('Q')

" 安定化: 全画面で q → 開いていたノートに戻り、曼荼羅の窓設定が残らない
%bwipeout!
execute 'edit ' . s:v . '/misc.md'
call gnosis#mview#toggle()
call s:keys('f')
call s:ok('全画面は窓が 1 つ', winnr('$') == 1)
call s:keys('q')
call s:ok('全画面で q すると元のノートに戻る', fnamemodify(expand('%:p'), ':t') ==# 'misc.md' && &filetype !=# 'gnosis-mandala', expand('%:p') . ' ' . &filetype)
call s:ok('戻ったノートに曼荼羅の窓設定（nowrap）が残らない', &wrap == 1, string(&wrap))
call s:ok('戻ったノートに曼荼羅の色づけが残らない', empty(filter(getmatches(), 'v:val.group =~# "Gnosis"')), string(getmatches()))
" 全画面で Space → 分割に戻ってノートの窓へ
call gnosis#mview#toggle()
call s:keys('f')
call s:keys(' ')
call s:ok('全画面で Space すると分割に戻りノートの窓へ', gnosis#mview#state().size == 3 && winnr('$') == 2 && &filetype !=# 'gnosis-mandala', string(gnosis#mview#state().size) . ' ' . winnr('$'))
" ノートの窓にいるまま画面の大きさが変わっても、曼荼羅は今の窓の大きさで描き直される
let s:mw = bufwinid(gnosis#mview#state().buf)
let s:before = join(getbufline(gnosis#mview#state().buf, 1, '$'), "\n")
call win_execute(s:mw, 'vertical resize 40')
call gnosis#mview#rerender()
let s:after = join(getbufline(gnosis#mview#state().buf, 1, '$'), "\n")
call s:ok('別の窓にいても曼荼羅が描き直される', s:before !=# s:after && max(map(getbufline(gnosis#mview#state().buf, 1, '$'), 'strdisplaywidth(v:val)')) <= 40, string(max(map(getbufline(gnosis#mview#state().buf, 1, '$'), 'strdisplaywidth(v:val)'))))
call gnosis#mview#close()

" 罫線の文字を使わず、空白の背景色で線にする（端末のフォント・大きさに左右されない）
let g:gnosis_mview_border = 'color'
call gnosis#mview#toggle()
let s:cb = gnosis#mview#state().buf
let s:ctext = join(getbufline(s:cb, 1, '$'), "\n")
call s:ok('色の線では罫線の文字を使わない', s:ctext !~# '[┃━┏┓┗┛┣┫┳┻╋│─]', s:ctext[0 : 80])
let s:bw = bufwinid(s:cb)
let s:hg = filter(getmatches(s:bw), 'v:val.group =~# "^GnosisMviewBar"')
call s:ok('色の線の位置にハイライトが付く', len(s:hg) > 0 && len(filter(copy(s:hg), 'v:val.group ==# "GnosisMviewBarH"')) > 0, string(len(s:hg)))
call s:ok('色の線でも題が盤面に出る', s:ctext =~# '雑記', s:ctext[0 : 80])
call gnosis#mview#close()
let g:gnosis_mview_border = 'line'

" f で全画面にして f で戻すと、右のノートが残り、配色が読み込み直されても選択の色が消えない
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
call s:keys('f')
call s:keys('f')
let s:wn = map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":t")')
call s:ok('f → f で右のノートが残る', index(s:wn, 'herb.md') >= 0, string(s:wn))
silent! colorscheme gnosis
call s:keys('k')
call s:ok('配色を読み込み直しても選択の色の定義が残る', len(filter(map(['Index', 'Group', 'Parent', 'Child', 'Context', 'Cite', 'Related', 'Pred'], 'execute("highlight GnosisMv" . v:val . "S")'), 'v:val =~# "cleared"')) == 0, 'cleared')
call gnosis#mview#close()

" 種類: 親 → 文脈 → 引用 → 子 → 関連 の順。相手にだけ書かれた親子・関連も出る。引用（文中のリンクだけ）に色が付く
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: ハブ', '---', '', '# ハブ', '', 'ParentBranch:', '[親](kp.md)', '', 'Context:', '[文脈](kx.md)', '', '本文で[引用先](cit.md)に触れる', '', 'ChildBranch:', '[子](kc.md)', '', 'Related:', '[関連](kr.md)'], s:v . '/hub.md')
for [s:f, s:t] in [['kp.md', '親'], ['kx.md', '文脈'], ['cit.md', '引用先'], ['kc.md', '子'], ['kr.md', '関連']]
  call s:mk(s:f, s:t, 0, [], [])
endfor
" 相手のファイルにだけ書かれた親子（こちらには書かれていない）と関連
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 隠れた子', '---', '', '# 隠れた子', '', 'ParentBranch:', '[ハブ](hub.md)'], s:v . '/hidden_kid.md')
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 隠れた関連', '---', '', '# 隠れた関連', '', 'Related:', '[ハブ](hub.md)'], s:v . '/hidden_rel.md')
execute 'edit ' . s:v . '/hub.md'
call gnosis#mview#refresh()
call s:keys(' ')
call s:keys('a')
let s:st = gnosis#mview#state()
let s:items = gnosis#mview#items(s:st.data, 'hub.md', 'all')
call s:ok('並びは 親 → 文脈 → 引用 → 子 → 関連', s:items[0 : 4] ==# ['kp.md', 'kx.md', 'cit.md', 'kc.md', 'hidden_kid.md'] && index(s:items, 'kr.md') > 4, string(s:items))
call s:ok('相手にだけ書かれた子・関連も出る', index(s:items, 'hidden_kid.md') >= 0 && index(s:items, 'hidden_rel.md') >= 0, string(s:items))
let s:kinds = {}
for s:row in s:st.cells
  for s:cell in s:row
    if !empty(s:cell.id) | let s:kinds[s:cell.id] = s:cell.kind | endif
  endfor
endfor
call writefile(['---', 'time: x', '---', '', '# 逆', '', '本文で[ハブ](hub.md)を引用'], s:v . '/bl.md')
call writefile(['---', 'time: 2026-01-01 00:00:00', '---', '', '# ハブ', '', 'ParentBranch:', '[親](kp.md)', '', 'Context:', '[文脈](kx.md)', '', '本文で[引用先](cit.md)に触れる', '', 'ChildBranch:', '[子](kc.md)', '', 'Related:', '[関連](kr.md)', '', 'BackLink:', '[逆](bl.md)'], s:v . '/hub.md')
call s:keys('u')
call s:ok('BackLink は引用とは別の種類・色', get(s:kinds, 'bl.md', 'x') ==# 'x' || get(s:kinds, 'bl.md') ==# 'back', string(s:kinds))
call s:ok('種類の色: 親・文脈・引用・子・関連', get(s:kinds, 'kp.md') ==# 'parent' && get(s:kinds, 'kx.md') ==# 'context' && get(s:kinds, 'cit.md') ==# 'cite' && get(s:kinds, 'kc.md') ==# 'child' && get(s:kinds, 'kr.md') ==# 'related', string(s:kinds))
call s:keys('c')
call s:keys('r')
call s:keys('i')
call s:ok('i は索引だけ（ノートは出ない）', s:grid() !~# '引用先' && s:grid() !~# '文脈', s:grid())
call s:keys('a')
call s:keys('q')

" Tab / Shift-Tab: 順次表示（1 2 3 4 6 7 8 9 → 次の曼荼羅の 1 …、最後まで行ったら最初に戻る）
execute 'edit ' . s:v . '/plant.md'
call s:keys(' ')
call s:keys('a')
let s:st = gnosis#mview#state()
call s:ok('Tab 前は中心のマス', s:st.cur == [1, 1] && s:st.page == 0, string(s:st.cur))
let s:path = []
for s:i in range(9)
  call s:keys("\<Tab>")
  call add(s:path, [s:st.page, s:st.cur])
endfor
call s:ok('Tab は 1 2 3 4 6 7 8 9 の順（5 の中心は飛ばす）', s:path[0 : 7] ==# [[0, [0, 0]], [0, [0, 1]], [0, [0, 2]], [0, [1, 0]], [0, [1, 2]], [0, [2, 0]], [0, [2, 1]], [0, [2, 2]]], string(s:path))
call s:ok('次の曼荼羅の 1 へ進む', s:path[8] ==# [1, [0, 0]], string(s:path[8]))
call s:keys("\<S-Tab>")
call s:ok('Shift-Tab で戻る（前の曼荼羅の最後 9）', s:st.page == 0 && s:st.cur == [2, 2], string(s:st.cur) . s:st.page)
for s:i in range(20)
  call s:keys("\<Tab>")
endfor
call s:ok('最後まで行ったら最初へ戻って回り続ける', s:st.page >= 0 && s:st.page <= 1 && &filetype ==# 'gnosis-mandala')
call s:keys('q')

" q は新しいほうから 1 つずつ。何もなければ閉じる。Q はすぐ閉じる
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
let s:st = gnosis#mview#state()
let s:st.query = '植'
let s:st.find = 'ミ'
let s:st.stamp = {'query': 1, 'find': 2}
execute 'vertical resize 110'
call s:keys('z')
call s:ok('かかっているものと q の案内が上の行に出る', s:text() =~# 'q でハイライトをやめる', s:text())
call s:keys('q')
call s:ok('q は新しいほう（ハイライト）から', s:st.find ==# '' && s:st.query ==# '植' && &filetype ==# 'gnosis-mandala', string([s:st.find, s:st.query]))
call s:keys('q')
call s:ok('次の q で絞り込みをやめる', s:st.query ==# '' && &filetype ==# 'gnosis-mandala', s:st.query)
let s:st.find = 'ミ'
let s:st.query = '植'
call s:keys('Q')
call s:ok('Q は何がかかっていても閉じる', &filetype !=# 'gnosis-mandala' && winnr('$') == 1, &filetype)

" x: 絞り込み（入力は試験できないので状態を入れる）。q で解除
execute 'edit ' . s:v . '/plant.md'
call s:keys(' ')
let s:st = gnosis#mview#state()
let s:st.query = 'ラベ'
call s:keys('z')
call s:ok('x の絞り込み: 題が合うものだけ', s:grid() =~# 'ラベンダー' && s:grid() !~# 'タイム', s:grid())
call s:keys('q')
call s:ok('q で絞り込みを解く', s:st.query ==# '' && s:grid() =~# 'タイム', s:grid())
call s:keys('q')

" gs: 全文検索で選んだノートを、曼荼羅の中心にする（fzf の画面は試験できないので、選んだ後の処理を呼ぶ）
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
let s:st = gnosis#mview#state()
let s:gs_done = function('gnosis#mview#gs_done')
call s:gs_done(s:v . '/cook.md', 1)
sleep 50m
call s:ok('gs で選んだノートが中心になる', s:st.center ==# 'cook.md' && &filetype ==# 'gnosis-mandala', s:st.center)
call s:keys('b')
call s:ok('b で戻れる', s:st.center ==# 'herb.md', s:st.center)
call s:mk('brandnew.md', '作ったばかり', 0, [], [])
call s:gs_done(s:v . '/brandnew.md', 1)
sleep 50m
call s:ok('載っていない新しいノートも読み直して中心になる', s:st.center ==# 'brandnew.md', s:st.center)
call s:keys('q')

" 9×9 の背景: 周りの 8 マスと、それぞれの曼荼羅の中心のマスが同じ薄い色で塗られる
execute 'edit ' . s:v . '/plant.md'
call s:keys(' ')
call s:keys('f')
let s:st = gnosis#mview#state()
let s:bw = bufwinid(s:st.buf)
let s:groups = map(getmatches(s:bw), 'v:val.group')
call s:ok('9×9: 周りの 8 色の背景が付く', len(filter(copy(s:groups), 'v:val =~# "B[0-7]$" || v:val =~# "Bg[0-7]$"')) >= 2, string(s:groups))
let s:c1 = s:st.cells[3][3]
let s:c2 = s:st.cells[1][1]
call s:ok('周りのマスとその曼荼羅の中心のマスは同じ色の番号', s:c1.bgi == 0 && s:c2.bgi == 0 && s:c1.id ==# s:c2.id, string([s:c1, s:c2]))
call s:ok('真ん中の中心には背景色の番号が無い', !has_key(s:st.cells[4][4], 'bgi'))
call s:keys('f')
call s:keys('q')

" 右のノートは上から表示して、カーソルは画面のいちばん下の行に置く
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 長いノート', '---', '', '# 長いノート'] + map(range(1, 200), '"行 " . v:val'), s:v . '/long.md')
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
call gnosis#mview#gs_done(s:v . '/long.md', 1)
sleep 100m
let s:nw = filter(range(1, winnr('$')), 'getbufvar(winbufnr(v:val), "&filetype") !=# "gnosis-mandala"')[0]
let s:info = getwininfo(win_getid(s:nw))[0]
let s:cur = getcurpos(win_getid(s:nw))
call s:ok('カーソルは先頭から数えて窓の高さの行（画面のいちばん下）', s:cur[1] == winheight(s:nw), string(s:cur) . ' h=' . winheight(s:nw))
call s:keys('q')

" 曼荼羅の窓が選ばれたまま \i などでノートを開いても、曼荼羅の窓は壊れず、右の窓に開く
call s:mk('guard.md', '守る', 0, [], [])
execute 'edit ' . s:v . '/herb.md'
call s:keys(' ')
let s:st = gnosis#mview#state()
call s:ok('曼荼羅の窓にいる', &filetype ==# 'gnosis-mandala')
execute 'edit ' . fnameescape(s:v . '/guard.md')
sleep 100m
let s:ft = map(range(1, winnr('$')), 'getbufvar(winbufnr(v:val), "&filetype")')
let s:nm = map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":t")')
call s:ok('曼荼羅の窓は曼荼羅のまま', index(s:ft, 'gnosis-mandala') >= 0, string(s:ft))
call s:ok('開いたノートは右の窓に出る', index(s:nm, 'guard.md') >= 0, string(s:nm))
call s:ok('曼荼羅の中心も開いたノートに合う', s:st.center ==# 'guard.md', s:st.center)
call s:keys('Q')

" 起動時に曼荼羅を左半分に出す（設定 mandalaOnStart・既定オン。g:gnosis_mandala_on_start で止められる）
%bwipeout!
execute 'edit ' . s:v . '/herb.md'
let g:gnosis_mandala_on_start = 0
call gnosis#mview#start()
call s:ok('止めていれば出ない', &filetype !=# 'gnosis-mandala' && winnr('$') == 1)
let g:gnosis_mandala_on_start = 1
call gnosis#mview#start()
call s:ok('オンなら左に曼荼羅、右にノート', &filetype ==# 'gnosis-mandala' && winnr('$') == 2 && winnr() == 1)
call gnosis#mview#start()
call s:ok('すでに出ていれば二重に出さない', winnr('$') == 2)
call s:keys('Q')
unlet g:gnosis_mandala_on_start

call writefile(s:res, s:work . '/result.txt')
qa!
