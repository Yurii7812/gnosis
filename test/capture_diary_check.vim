set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
call gnosis#create_vault_files($D . '/v')
let s:pack = $D . '/pack/capture.json'
function! s:phone(i, text) abort
  let l:d = json_decode(join(readfile(s:pack), "\n"))
  let l:d.entries[a:i].text = a:text
  call writefile([json_encode(l:d)], s:pack)
endfunction
function! s:day() abort
  let l:days = json_decode(join(readfile($D . '/v/.state/diary_days.json'), "\n")).days
  return $D . '/v/' . l:days['2026-10-19']
endfunction
function! s:hits(pat) abort
  return len(filter(readfile(s:day()), 'v:val =~# a:pat'))
endfunction
" 1. 初回 → 日記に 1 行ずつ。10 回取り込んでも増えない・ファイルを書き換えない
call gnosis#capture_import($D . '/pack')
call assert_equal(1, s:hits('朝の記録'))
call assert_equal(1, s:hits('昼の記録'))
let s:first = readfile(s:day())
let s:notes = len(glob($D . '/v/*.md', 0, 1))
for s:i in range(9)
  call gnosis#capture_import($D . '/pack')
endfor
call assert_equal(s:first, readfile(s:day()))
call assert_equal(s:notes, len(glob($D . '/v/*.md', 0, 1)))
" 2. PC で日記に自分の文章を足す。スマホで 2 番目を編集 → 同じ位置の行だけ更新・PC の文章は残る・二重にならない
let s:l = readfile(s:day())
call insert(s:l, 'PC で書いた夜の文章', index(s:l, '昼の記録') + 3)
call writefile(s:l, s:day())
call s:phone(1, "昼の記録(改)\n二行目")
call gnosis#capture_import($D . '/pack')
let s:now = readfile(s:day())
call assert_equal(1, s:hits('昼の記録(改)'))
call assert_equal(0, s:hits('昼の記録$'))
call assert_equal(1, s:hits('朝の記録'))
call assert_equal(1, s:hits('PC で書いた夜の文章'))
call assert_equal(s:notes, len(glob($D . '/v/*.md', 0, 1)))
" 3. 同じ編集をもう一度 → 変わらない
call gnosis#capture_import($D . '/pack')
call assert_equal(s:now, readfile(s:day()))
" 取り込み記録だけが失われた状態で再実行しても、日記の行は二重に入らない
call delete($D . '/v/.state/capture_imported.json')
let s:d3 = readfile(s:day())
call gnosis#capture_import($D . '/pack')
call assert_equal(s:d3, readfile(s:day()))
" 4. PC がその行を書き換えていたら競合（日記は変えず、二重にも入れない）
let s:l = readfile(s:day())
let s:l[index(s:l, '12:00 昼の記録(改)')] = '12:00 昼の記録(PC)'
call writefile(s:l, s:day())
call s:phone(1, "昼の記録(スマホ再編集)\n二行目")
call gnosis#capture_import($D . '/pack')
call assert_equal(s:l, readfile(s:day()))
call assert_true(filereadable($D . '/v/.state/capture_conflicts/261019120000.json'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
