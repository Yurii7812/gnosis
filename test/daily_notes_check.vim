" DailyNotes:（時系列記録の包含関係と、同じ日付のノートへの自動リンク）、日付指定の作成、上位の設定・継承
let s:out = []
function! s:ok(name, passed, ...) abort
  call add(s:out, (a:passed ? 'OK ' : 'NG ') . a:name . (a:passed || a:0 == 0 ? '' : ': ' . a:1))
endfunction
let s:v = $DN_VAULT
function! s:day(kind, date) abort
  for l:f in glob(s:v . '/*.md', 0, 1)
    if index(readfile(l:f, '', 14), '# ' . a:date . '-' . s:wd(a:date) . '-' . a:kind) >= 0 | return fnamemodify(l:f, ':t') | endif
  endfor
  return ''
endfunction
function! s:wd(date) abort
  return ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'][str2nr(strftime('%u', strptime('%Y-%m-%d %H:%M:%S', a:date . ' 12:00:00'))) - 1]
endfunction
function! s:diary(date) abort
  for l:f in glob(s:v . '/*.md', 0, 1)
    if index(readfile(l:f, '', 14), '# ' . a:date . '-' . s:wd(a:date)) >= 0 && join(readfile(l:f, '', 8), "\n") !~# 'record:' | return fnamemodify(l:f, ':t') | endif
  endfor
  return ''
endfunction
function! s:links(f) abort
  if empty(a:f) | return v:null | endif
  let l:lines = readfile(s:v . '/' . a:f)
  let l:i = index(l:lines, 'DailyNotes:')
  if l:i < 0 | return v:null | endif
  let l:out = []
  let l:i += 1
  while l:i < len(l:lines) && l:lines[l:i] =~# '^\['
    call add(l:out, matchstr(l:lines[l:i], '^\[\zs[^]]*'))
    let l:i += 1
  endwhile
  return l:out
endfunction
function! s:fm(f, key) abort
  for l:ln in readfile(s:v . '/' . a:f, '', 14)
    if l:ln =~# '^' . a:key . ':' | return trim(substitute(l:ln, '^' . a:key . ':', '', '')) | endif
  endfor
  return v:null
endfunction
try
  execute 'edit ' . fnameescape(s:v . '/index.md')
  let s:today = strftime('%Y-%m-%d', localtime() - get(g:, 'gnosis_diary_day_start_hour', 5) * 3600)
  let s:d20 = '2026-10-20'
  let s:d27 = '2026-10-27'
  let s:d_next = '2026-12-02'
  call gnosis#record_new('ビジネス')
  call gnosis#record_new('せどり')
  call gnosis#record_new('商品開発')
  stopinsert
  " ---- 上位を設定する（\E。今日のせどりを開いて、ビジネスを選ぶ）
  call gnosis#record_create('せどり', s:today)
  stopinsert
  let g:gnosis_test_record_pick = 'ビジネス'
  call gnosis#record_parent()
  let s:sed = s:day('せどり', s:today)
  let s:biz = s:day('ビジネス', s:today)
  call s:ok('\E: せどりの上位をビジネスに設定すると、YAML に parent_record: ビジネス が入る', s:fm(s:sed, 'parent_record') ==# 'ビジネス', string(s:fm(s:sed, 'parent_record')))
  call gnosis#record_create('ビジネス', s:today)
  stopinsert
  let s:biz = s:day('ビジネス', s:today)
  call s:ok('同じ日付のビジネスに、せどりへのリンクが DailyNotes: で出る', s:links(s:biz) ==# ['せどり'], string(s:links(s:biz)))
  call s:ok('せどり（下位が無い）には DailyNotes: が出ない', s:links(s:sed) is v:null)
  let s:dia = s:diary(s:today)
  call s:ok('日記には最上位だけ出る（ビジネスと、上位の無い商品開発。せどりは出ない）', !empty(s:dia) && sort(copy(s:links(s:dia))) ==# sort(['ビジネス', '商品開発']), string(s:links(s:dia)))
  call s:ok('日記の名前は変わらない（# 日付-曜日 のまま）', join(readfile(s:v . '/' . s:dia, '', 14), "\n") =~# '# ' . s:today . '-' . s:wd(s:today) . '\n')
  " ---- 解除する
  let g:gnosis_test_record_pick = '（上位なし）'
  call gnosis#record_create('せどり', s:today)
  stopinsert
  call gnosis#record_parent()
  call s:ok('\E: 上位なしを選ぶと解除され、ビジネスの DailyNotes: が消える', s:fm(s:sed, 'parent_record') ==# '' && s:links(s:biz) is v:null, string([s:fm(s:sed, 'parent_record'), s:links(s:biz)]))
  call s:ok('解除すると日記にせどりが直接出る', sort(copy(s:links(s:dia))) ==# sort(['せどり', 'ビジネス', '商品開発']), string(s:links(s:dia)))
  let g:gnosis_test_record_pick = 'ビジネス'
  call gnosis#record_parent()
  " ---- 日付指定の作成（\D）: 過去の日付は、その時点より前の設定を継承する（未来の設定は使わない）
  unlet! g:gnosis_test_record_pick
  let g:gnosis_test_record_pick = 'せどり'
  let g:gnosis_test_record_date = s:d20
  call gnosis#record_date()
  stopinsert
  let s:sed20 = s:day('せどり', s:d20)
  call s:ok('\D: 2026-10-20 のせどりが作られる', !empty(s:sed20))
  call s:ok('過去の日付は、未来（今日）の上位設定を引き継がない', s:fm(s:sed20, 'parent_record') is v:null, string(s:fm(s:sed20, 'parent_record')))
  let s:n_before = len(glob(s:v . '/*.md', 0, 1))
  call gnosis#record_date()
  stopinsert
  call s:ok('同じ日付がすでにあれば、新しく作らず開く', len(glob(s:v . '/*.md', 0, 1)) == s:n_before && expand('%:t') ==# s:sed20, expand('%:t'))
  let g:gnosis_test_record_date = '2026-13-45'
  let s:n_before = len(glob(s:v . '/*.md', 0, 1))
  call gnosis#record_date()
  call s:ok('不正な日付はエラーで、何も作らない', len(glob(s:v . '/*.md', 0, 1)) == s:n_before)
  " ---- 今日より後の日付は、今日の設定を継承する
  let g:gnosis_test_record_date = s:d_next
  call gnosis#record_date()
  stopinsert
  let s:sed_next = s:day('せどり', s:d_next)
  call s:ok('未来の日付のせどりは、直近（今日）の上位 ビジネス を引き継ぐ', s:fm(s:sed_next, 'parent_record') ==# 'ビジネス', string(s:fm(s:sed_next, 'parent_record')))
  call s:ok('別の日付のビジネスにはリンクが出ない', s:links(s:biz) ==# ['せどり'] && s:links(s:day('ビジネス', s:d_next)) is v:null || empty(s:day('ビジネス', s:d_next)))
  " ---- 上位に記録が無くても、下位へのリンクが 2 つ以上つくなら、その日の上位のノートを作る
  let g:gnosis_test_record_pick = 'ビジネス'
  call gnosis#record_create('商品開発', s:today)
  stopinsert
  call gnosis#record_parent()
  let g:gnosis_test_record_pick = '商品開発'
  let g:gnosis_test_record_date = s:d_next
  call gnosis#record_date()
  stopinsert
  let s:biz_next = s:day('ビジネス', s:d_next)
  call s:ok('ビジネスの記録が無い日でも、せどりと商品開発の 2 つがつくなら、ビジネスの日のノートを作る', !empty(s:biz_next), string(s:biz_next))
  call s:ok('作ったビジネスに せどり・商品開発 が並ぶ', !empty(s:biz_next) && s:links(s:biz_next) ==# ['せどり', '商品開発'], string(s:links(s:biz_next)))
  call s:ok('日記（その日）にはビジネスだけが出る（せどり・商品開発は出ない）', s:links(s:diary(s:d_next)) ==# ['ビジネス'], string(s:links(s:diary(s:d_next))))
  " ---- \R の動き（今日の記録を開く）は変わらない
  unlet! g:gnosis_test_record_date
  let g:gnosis_test_record_pick = 'せどり'
  let s:n_before = len(glob(s:v . '/*.md', 0, 1))
  call gnosis#record_pick()
  stopinsert
  call s:ok('\R は今日の記録を開く（新しく作らない）', expand('%:t') ==# s:sed && len(glob(s:v . '/*.md', 0, 1)) == s:n_before, expand('%:t'))
  " ---- 繰り返しても変わらない・手書きの本文は残る
  call writefile(readfile(s:v . '/' . s:biz) + ['', '手書きのメモ'], s:v . '/' . s:biz)
  let s:snap = {}
  for s:f in glob(s:v . '/*.md', 0, 1) | let s:snap[s:f] = readfile(s:f) | endfor
  call gnosis#daily_notes_sync()
  call gnosis#daily_notes_sync()
  let s:same = 1
  for s:f in keys(s:snap)
    if readfile(s:f) !=# s:snap[s:f] | let s:same = 0 | endif
  endfor
  call s:ok('整え直しても何も変わらない（冪等）・手書きのメモは残る', s:same && join(readfile(s:v . '/' . s:biz), "\n") =~# '手書きのメモ')
catch
  call s:ok('例外', 0, v:exception . ' @ ' . v:throwpoint)
endtry
call writefile(s:out + ['DONE'], $DN_RESULT)
qa!
