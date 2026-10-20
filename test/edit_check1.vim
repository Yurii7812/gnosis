source <sfile>:h/edit_head.vim
execute 'edit ' . fnameescape($D . '/v/main.md')
" ---- ED14 計算 ----
let s:l = search('{{= 2 \* 3 }}')
call cursor(s:l, 1)
GnosisCalc
call assert_equal('計算 {{= 2 * 3 => 6 }} と', getline(s:l))
call cursor(search('12 / 4 ='), 1)
GnosisCalc
call assert_equal('12 / 4 = 3', getline('.'))
call cursor(search('1 / 0 ='), 1)
let s:before = getline('.')
GnosisCalc
call assert_equal(s:before, getline('.'))             " 計算できない式は触らない
" 範囲(計算する式が無い行だけ)は何も変えず案内する
call cursor(search('ハーブ ハーブ'), 1)
let s:t = getline('.')
GnosisCalc
call assert_equal(s:t, getline('.'))
silent write
" ---- ED04 ブロック ID ----
execute 'edit ' . fnameescape($D . '/v/src.md')
call cursor(search('水やりは控えめに。'), 1)
GnosisBlockId
call assert_match('^水やりは控えめに。 \^[0-9a-f]\{6}$', getline('.'))
call assert_match('^\[src\](src.md#^[0-9a-f]\{6})$', getreg('"'))
let s:line = getline('.')
GnosisBlockId                                          " すでにある段落では増やさない
call assert_equal(s:line, getline('.'))
call cursor(search('^$'), 1)
GnosisBlockId                                          " 空行では付けない
call assert_equal('', getline('.'))
GnosisBlockCheck
call assert_equal('# 壊れた見出し／ブロックのリンク', getline(1))
close
" ---- ED05 取り込み表示 ----
execute 'edit ' . fnameescape($D . '/v/main.md')
GnosisInclude
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^> 水やりは控えめに。"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "出典: \\[資料\\](src.md#栽培)"')))
call assert_true(empty(filter(getline(1, '$'), 'v:val =~# "\\^[0-9a-f]\\{6}"')))   " ID の印は表示に出ない
close
GnosisIncludeCheck
call assert_match('問題 0 件', join(getline(1, '$'), "\n"))
close
" ---- ED13 テンプレート ----
GnosisTemplates
call assert_true(!empty(filter(getline(1, '$'), 'v:val ==# "- 会議"')))
close
execute 'edit ' . fnameescape($D . '/v/main.md')
let s:n = line('$')
call cursor(1, 1)
GnosisTemplate 会議
call assert_equal(s:n + 3, line('$'))
call assert_match('^# main \d\{4}-\d\{2}-\d\{2}$', getline(2))
call assert_equal('- 参加者: ', getline(4))
call assert_equal(4, line('.'))
call assert_equal(col('$'), col('.') + 0 * 1 + (col('$') - col('.')))
GnosisTemplate 存在しない
silent edit!
GnosisTemplateNew 会議 新規 打ち合わせ
call assert_equal($D . '/v/新規.md', expand('%:p'))
call assert_match('^title: 打ち合わせ$', get(filter(getline(1, '$'), 'v:val =~# "^title:"'), 0, ''))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^# 打ち合わせ "')))
let s:sz = getfsize($D . '/v/新規.md')
GnosisTemplateNew 会議 新規
call assert_equal(s:sz, getfsize($D . '/v/新規.md'))   " 上書きしない
" ---- ED03 プレビュー ----
execute 'edit ' . fnameescape($D . '/v/main.md')
call cursor(search('\[資料\](src.md)'), 1)
call search('資料', 'c')
let s:pk = gnosis#peek_lines(5)
call assert_equal('src.md', s:pk[0])
call assert_true(index(s:pk, '導入の文。') >= 0)
call assert_true(index(s:pk, '---') < 0)              " front matter は出さない
call cursor(1, 1)
call assert_equal([], gnosis#peek_lines())
" ---- ED08 複数箇所の編集 ----
call cursor(search('ハーブ ハーブ'), 1)
GnosisMulti ハーブ
call assert_equal('ハーブ', b:gnosis_multi_word)
GnosisMultiApply 薬草
call assert_equal('薬草 薬草 薬草 と [資料](src.md) の話', getline(search('薬草')))
call assert_false(exists('b:gnosis_multi_word'))
silent undo
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^ハーブ ハーブ ハーブ"')))   " u 1 回で全部戻る
GnosisMultiApply 何か                                   " 語を選んでいなければ何もしない
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^ハーブ ハーブ ハーブ"')))
silent write
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
