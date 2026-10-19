" 時系列記録（夢など）: Index > 時系列記録 > 日記 / 夢 > 月 > その日のノート・日記の上にリンク・移行
let s:out = []
function! s:ok(name, passed, ...) abort
  call add(s:out, (a:passed ? 'OK ' : 'NG ') . a:name . (a:passed || a:0 == 0 ? '' : ': ' . a:1))
endfunction
function! s:title(t) abort
  for l:f in glob(s:v . '/*.md', 0, 1)
    if index(readfile(l:f, '', 12), 'title: ' . a:t) >= 0 | return fnamemodify(l:f, ':t') | endif
  endfor
  return ''
endfunction
function! s:file(f) abort
  return readfile(s:v . '/' . a:f)
endfunction
function! s:has(f, pat) abort
  return match(s:file(a:f), a:pat) >= 0
endfunction
let s:v = $RECORD_VAULT
try
  " 旧形式: Index の直下に日記と夢日記（月グループは日記と同じ題 2026-10）
  execute 'edit ' . fnameescape(s:v . '/index.md')
  let s:today = strftime('%Y-%m-%d', localtime() - get(g:, 'gnosis_diary_day_start_hour', 5) * 3600)
  call gnosis#diary_today()
  stopinsert
  let s:diary = expand('%:t')
  let s:rec = s:title('時系列記録')
  let s:dg = s:title('日記')
  call s:ok('\d: Index に「時系列記録」、その中に「日記」', !empty(s:rec) && s:has('index.md', '^\[時系列記録\](' . s:rec . ')$')
        \ && s:has(s:rec, '^\[日記\](' . s:dg . ')$') && !s:has('index.md', '](' . s:dg . ')') && s:has(s:dg, '^\[時系列記録\](' . s:rec . ')$'))
  " 新しい時系列記録
  call gnosis#record_new('夢')
  let s:yg = s:title('夢')
  let s:wd = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'][str2nr(strftime('%u', strptime('%Y-%m-%d %H:%M:%S', s:today . ' 12:00:00'))) - 1]
  let s:dt = s:today . '-' . s:wd . '-夢'
  let s:day = s:title(s:dt)
  let s:mg = s:title(s:today[0:6] . '-夢')
  call s:ok(':GnosisRecordNew 夢: 時系列記録の中に「夢」', !empty(s:yg) && s:has(s:rec, '^\[夢\](' . s:yg . ')$') && s:has(s:yg, '^\[時系列記録\](' . s:rec . ')$'))
  call s:ok('今日のノートは 日付-曜日-夢 で、月のグループ（YYYY-MM-夢）の中', !empty(s:day) && !empty(s:mg) && s:has(s:mg, '^\[' . s:dt . '\](' . s:day . ')$') && s:has(s:yg, '^\[' . s:today[0:6] . '-夢\](' . s:mg . ')$'))
  call s:ok('今日のノートを開く・front matter に record', expand('%:t') ==# s:day && s:has(s:day, '^record: "夢"$'))
  call s:ok('日記の上（Group: の下・空行のあと）にリンク', s:has(s:diary, '^\[' . s:dt . '\](' . s:day . ')$')
        \ && match(s:file(s:diary), '](' . s:day . ')') < match(s:file(s:diary), '^## 今日のノート'), string(s:file(s:diary)))
  call s:ok('「今日のノート」には入れない', len(filter(s:file(s:diary), 'stridx(v:val, "](" . s:day . ")") >= 0')) == 1)
  " もう一つの記録・\R で選ぶ
  call gnosis#record_new('読書')
  let s:bd = s:title(s:today . '-' . s:wd . '-読書')
  let s:dl = s:file(s:diary)
  let s:i1 = match(s:dl, '](' . s:day . ')')
  call s:ok('二つ目の記録も日記の上に並ぶ（続けて）', !empty(s:bd) && match(s:dl, '](' . s:bd . ')') == s:i1 + 1, string(s:dl))
catch
  call add(s:out, 'NG 例外: ' . v:exception . ' @ ' . v:throwpoint)
endtry
" \R はふだん try の外で動く（try の中だと、ノートを開くときの silent! のエラーが例外になる）
enew
let g:gnosis_test_record_pick = '夢'
call gnosis#record_pick()
call s:ok('\R で選ぶと今日のノートを開く（重ねて作らない）', expand('%:t') ==# s:day, expand('%:p') . ' ' . s:day)
try
  call s:ok('同じ日の 2 回目でもリンクは 1 つ', len(filter(s:file(s:diary), 'stridx(v:val, "](" . s:day . ")") >= 0')) == 1)
  " 年越し: 前の年の月グループが記録の直下にあれば、年のグループ（YYYY-日誌）にまとめ、今年の年のグループの中に今月を作る
  let s:py = (str2nr(s:today[0:3]) - 1) . ''
  call writefile(['---', 'title: 日誌', 'attribute: group', '---', '', '# 日誌', '', 'Group:', '[時系列記録](' . s:rec . ')', '', '[' . s:py . '-12-日誌](j-old.md)'], s:v . '/j-kind.md')
  call writefile(['---', 'title: ' . s:py . '-12-日誌', 'attribute: group', '---', '', '# ' . s:py . '-12-日誌', '', 'Group:', '[日誌](j-kind.md)', ''], s:v . '/j-old.md')
  call writefile(s:file(s:rec) + ['[日誌](j-kind.md)'], s:v . '/' . s:rec)
  call gnosis#record_open('日誌')
  let s:oy = s:title(s:py . '-日誌')
  let s:ny = s:title(s:today[0:3] . '-日誌')
  let s:nm = s:title(s:today[0:6] . '-日誌')
  call s:ok('年越し: 前の年の月は前の年のグループへ、今月は今年のグループの中', !empty(s:oy) && !empty(s:ny) && !empty(s:nm)
        \ && s:has(s:oy, '](j-old.md)') && !s:has('j-kind.md', '](j-old.md)') && s:has('j-old.md', '^\[' . s:py . '-日誌\](' . s:oy . ')$')
        \ && s:has(s:ny, '](' . s:nm . ')') && s:has('j-kind.md', '](' . s:ny . ')') && s:has('j-kind.md', '](' . s:oy . ')'), string(s:file('j-kind.md')))
  " 移行: 夢日記（旧）→ 時系列記録「旧夢」
  call s:ok('移行の前: 旧夢日記は Index の直下', s:has('index.md', '^\[夢日記\](old-dream.md)$'))
  call gnosis#record_migrate('夢日記', '旧夢')
  call s:ok('移行: 題を改めて時系列記録の中へ', s:has('old-dream.md', '^title: 旧夢$') && s:has('old-dream.md', '^# 旧夢$') && !s:has('index.md', 'old-dream.md')
        \ && s:has(s:rec, '^\[旧夢\](old-dream.md)$') && s:has('old-dream.md', '^\[時系列記録\](' . s:rec . ')$'))
  call s:ok('移行: 月のグループは 2026-10-旧夢（日記の 2026-10 と分ける）', s:has('old-month.md', '^title: 2026-10-旧夢$') && s:has('old-dream.md', '^\[2026-10-旧夢\](old-month.md)$') && s:has('old-day.md', '^\[2026-10-旧夢\](old-month.md)$'))
  call s:ok('移行: その日のノートに record と、その日の日記の上にリンク・今日のノートから外す',
        \ s:has('old-day.md', '^record: "旧夢"$') && s:has('old-diary.md', '^\[2026-10-12-MO-夢-病院\](old-day.md)$')
        \ && len(filter(s:file('old-diary.md'), 'v:val =~# "^\\[.*\\](old-day\\.md)$"')) == 1, string(s:file('old-diary.md')))
  call s:ok('移行: 本文のリンクは残す', s:has('old-diary.md', '今日は\[病院の夢\](old-day.md)を見た'))
catch
  call add(s:out, 'NG 例外: ' . v:exception . ' @ ' . v:throwpoint)
endtry
call writefile(s:out, $RECORD_RESULT)
qall!
