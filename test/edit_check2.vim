source <sfile>:h/edit_head.vim
" ---- ED15 折りたたみ ----
call writefile(['# 題', '', '本文', '', '## 節A', '', '> 引用1', '> 引用2', '> 引用3', '', '短い引用', '> だけ', '', '```', '## コード内', 'x', '```', '', 'Group:', '[G](g.md)', '', '## 節B', '', 'end'], $D . '/v/fold.md')
execute 'edit ' . fnameescape($D . '/v/fold.md')
GnosisFold on
call assert_equal('expr', &l:foldmethod)
let s:lv = map(range(1, line('$')), 'foldlevel(v:val)')
call assert_equal(1, foldlevel(1))                     " # 題
call assert_equal(2, foldlevel(5))                     " ## 節A
call assert_equal(7, foldlevel(8))                     " 3 行の引用は折りたためる
call assert_equal(2, foldlevel(10))                    " 引用が終われば、いまの見出しの階層に戻る
call assert_equal(2, foldlevel(12))                    " 1 行だけの引用は折りたたまない
call assert_equal(7, foldlevel(15))                    " コードブロックの中
call assert_equal(7, foldlevel(20))                    " 関係ブロック
call assert_equal(2, foldlevel(23))                    " ## 節B の本文
normal! zM
call assert_true(foldclosed(8) > 0)
call assert_match('^▸ ', foldtextresult(foldclosed(8)))
normal! zR
GnosisFold off
call assert_equal('manual', &l:foldmethod)             " もとの設定に戻る
call assert_false(get(w:, 'gnosis_fold_on', 0))
GnosisFold toggle
call assert_equal('expr', &l:foldmethod)
GnosisFold bogus
GnosisFold off
" 編集で折りたたみが更新される(キャッシュが古いままにならない)
GnosisFold on
call append(line('$'), ['## 節C', 'x'])
call assert_equal(2, foldlevel(line('$') - 1))
GnosisFold off
set nomodified
" ---- ED16 集中モード ----
execute 'edit ' . fnameescape($D . '/v/fold.md')
setlocal number relativenumber
let s:ls = &laststatus
GnosisFocus
call assert_false(&l:number)
call assert_equal(0, &laststatus)
call assert_true(get(w:, 'gnosis_focus_on', 0))
call cursor(3, 1)
doautocmd CursorMoved
call assert_true(exists('w:gnosis_focus_match'))
GnosisFocus
call assert_true(&l:number)
call assert_true(&l:relativenumber)
call assert_equal(s:ls, &laststatus)                   " 元に戻る
call assert_false(exists('w:gnosis_focus_match'))
" ---- ED12 コピー履歴 ----
set nomodified
execute 'edit ' . fnameescape($D . '/v/fold.md')
call cursor(3, 1)
normal! yy
GnosisClip list
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^なし"')))   " 既定では記録しない
close
GnosisClip on
normal! yy
call cursor(1, 1)
normal! yy
call cursor(3, 1)
normal! yy                                             " 同じものは前に出す(重複しない)
call setline(2, 'password = hunter2')
call cursor(2, 1)
normal! yy
call setline(2, repeat('a', 45))
call cursor(2, 1)
normal! yy
GnosisClip list
let s:items = filter(getline(1, '$'), 'v:val =~# "^[0-9]\\+\\. "')
call assert_equal(['1. 本文', '2. # 題'], s:items)      " パスワード・長い鍵らしきものは記録しない
close
let s:n = line('$')
GnosisClip paste 1
call assert_equal(s:n + 1, line('$'))
GnosisClip paste 9
call assert_equal(s:n + 1, line('$'))
GnosisClip clear
GnosisClip list
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^なし"')))
close
GnosisClip off
silent edit!
set nomodified
" ---- ED18 補完 ----
" 通常モードのカーソルは最後の文字より後ろに置けないので、最後に 1 文字(z)を足し、その上に置く = 挿入モードで z の手前にいるのと同じ
call writefile(['---', 'title: 補完', '---', '', '[資](z', '[資z', 'ふつうの文z'], $D . '/v/comp.md')
execute 'edit ' . fnameescape($D . '/v/comp.md')
call cursor(5, col([5, '$']) - 1)
call assert_equal(strlen('[資]('), gnosis#complete(1, ''))
let s:r = gnosis#complete(0, '資')
call assert_true(!empty(s:r))
call assert_equal(1, len(filter(copy(s:r), 'v:val.word ==# "src.md"')))           " 同じフォルダのノートは src.md の形(../ なし)
call assert_true(empty(filter(copy(s:r), 'v:val.word =~# "comp.md"')))            " 自分自身は出さない
call assert_equal(0, len(filter(gnosis#complete(0, 'ありえない名前'), 'v:val.word =~# "src"')))   " 絞り込む
call cursor(6, col([6, '$']) - 1)
call assert_equal(strlen('['), gnosis#complete(1, ''))
call assert_true(!empty(filter(gnosis#complete(0, '資'), 'v:val.word ==# "資料](src.md)"')))   " 「題](パス)」の形
call cursor(7, col([7, '$']) - 1)
call assert_equal(-3, gnosis#complete(1, ''))                                       " リンクの途中でなければ補完しない
" サブフォルダのノートからは ../ つきになる
call mkdir($D . '/v/sub', 'p')
call writefile(['[x](z'], $D . '/v/sub/deep.md')
execute 'edit ' . fnameescape($D . '/v/sub/deep.md')
call cursor(1, col([1, '$']) - 1)
call gnosis#complete(1, '')
call assert_true(!empty(filter(gnosis#complete(0, 'src'), 'v:val.word ==# "../src.md"')))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
