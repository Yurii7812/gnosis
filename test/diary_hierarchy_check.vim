" Journal hierarchy test: October 2026 -> January 2027 -> February 2028.
let s:root = $DIARY_TREE_VAULT
let s:results = []
let g:gnosis_root = s:root
let g:gnosis_open_index_on_startup = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_autosync = 0
let g:gnosis_diary_auto = 0
function! s:assert(name, pass) abort
  call add(s:results, (a:pass ? 'OK ' : 'NG ') . a:name)
endfunction
try
  " Script-local diary helpers must be loaded from the actual Gnosis autoload.
  runtime autoload/gnosis.vim
  redir => s:names
  silent scriptnames
  redir END
  let s:sid = ''
  for s:ln in split(s:names, "\n")
    if s:ln =~# 'autoload/gnosis.vim'
      let s:sid = matchstr(s:ln, '^\s*\zs\d\+')
    endif
  endfor
  let s:create = function('<SNR>' . s:sid . '_diary_create')
  let s:scan = function('<SNR>' . s:sid . '_diary_scan')
  let s:find = function('<SNR>' . s:sid . '_diary_find_group')
  let s:parent_has = function('<SNR>' . s:sid . '_diary_parent_has')
  let s:notes = s:scan(s:root)
  let s:oct14 = s:create(s:root, '2026-10-14', s:notes, '2026-10-14 09:00:00')
  let s:top = s:find(s:notes, '日記')
  let s:month10 = s:find(s:notes, '2026-10')
  call s:assert('初回に 日記 グループが作成される', filereadable(s:root . '/' . s:top))
  call s:assert('Index 本文に 日記 リンク', index(readfile(s:root . '/index.md'), '[日記](' . s:top . ')') >= 0)
  call s:assert('日記 の ### Group に Index', s:parent_has(s:root, s:top, 'index.md'))
  call s:assert('10月は日記の直下', s:parent_has(s:root, s:month10, s:top))
  call s:assert('2026年内に年グループは作られない', empty(s:find(s:notes, '2026')))
  call s:assert('日記ノートは10月グループに属する', s:parent_has(s:root, s:oct14, s:month10))

  let s:oct15 = s:create(s:root, '2026-10-15', s:notes, '2026-10-15 09:00:00')
  call s:assert('同じ月のグループを再利用する', len(filter(copy(s:notes), 'v:val.title ==# "2026-10"')) == 1)
  call s:assert('10月グループに複数のノート', s:parent_has(s:root, s:oct15, s:month10))
  let s:nov = s:create(s:root, '2026-11-05', s:notes, '2026-11-05 09:00:00')
  let s:month11 = s:find(s:notes, '2026-11')
  call s:assert('2026年11月も年グループ無し', empty(s:find(s:notes, '2026')) && s:parent_has(s:root, s:month11, s:top))

  let s:jan = s:create(s:root, '2027-01-01', s:notes, '2027-01-01 09:00:00')
  let s:y2026 = s:find(s:notes, '2026')
  let s:y2027 = s:find(s:notes, '2027')
  let s:m2027 = s:find(s:notes, '2027-01')
  call s:assert('年越しで2026と2027のグループ作成', !empty(s:y2026) && !empty(s:y2027))
  call s:assert('日記直下に2026/2027の年グループ', s:parent_has(s:root, s:y2026, s:top) && s:parent_has(s:root, s:y2027, s:top))
  call s:assert('以前の月を2026年に移動', s:parent_has(s:root, s:month10, s:y2026) && s:parent_has(s:root, s:month11, s:y2026))
  call s:assert('以前の月は日記直下から除外', !s:parent_has(s:root, s:month10, s:top) && !s:parent_has(s:root, s:month11, s:top))
  call s:assert('2027年1月の日記が正しい階層', s:parent_has(s:root, s:m2027, s:y2027) && s:parent_has(s:root, s:jan, s:m2027))
  call s:assert('既存日記ノート本文は維持', index(readfile(s:root . '/' . s:oct14), '# 2026-10-14-WE') >= 0)

  let s:feb = s:create(s:root, '2028-02-01', s:notes, '2028-02-01 09:00:00')
  let s:y2028 = s:find(s:notes, '2028')
  let s:m2028 = s:find(s:notes, '2028-02')
  call s:assert('3年目も月を直下にせず年グループ', !empty(s:y2028) && s:parent_has(s:root, s:y2028, s:top) && s:parent_has(s:root, s:m2028, s:y2028) && s:parent_has(s:root, s:feb, s:m2028))
  call s:assert('Index に 日記 は一件のみ', len(filter(readfile(s:root . '/index.md'), 'v:val =~# "^\\[日記\\]("')) == 1)
catch
  call add(s:results, 'NG exception: ' . v:exception . ' at ' . v:throwpoint)
endtry
call writefile(s:results, $DIARY_TREE_RESULT)
qall!
