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
function! s:topic_note() abort
  return $D . '/v/' . json_decode(join(readfile($D . '/v/.state/capture_topic_notes.json'), "\n"))['アイデア']
endfunction
function! s:record_note() abort
  for l:f in glob($D . '/v/*.md', 0, 1)
    if join(readfile(l:f), "\n") =~# '空を飛ぶ夢' && join(readfile(l:f), "\n") =~# 'record:'
      return l:f
    endif
  endfor
  return ''
endfunction
function! s:hits(f, pat) abort
  return len(filter(readfile(a:f), 'v:val =~# a:pat'))
endfunction
let s:nn = len(glob($D . '/v/*.md', 0, 1))
call gnosis#capture_import($D . '/pack')
let s:T = s:topic_note()
let s:R = s:record_note()
call assert_true(!empty(s:R), 'record note exists')
call assert_equal(1, s:hits(s:T, '10:00 ひとつめのアイデア'))
call assert_equal(1, s:hits(s:T, '11:00 ふたつめ'))
call assert_equal(1, s:hits(s:R, '12:00 空を飛ぶ夢'))
let s:t1 = readfile(s:T)
let s:r1 = readfile(s:R)
let s:nn = len(glob($D . '/v/*.md', 0, 1))
for s:i in range(5)
  call gnosis#capture_import($D . '/pack')
endfor
call assert_equal(s:t1, readfile(s:T))
call assert_equal(s:r1, readfile(s:R))
call assert_equal(s:nn, len(glob($D . '/v/*.md', 0, 1)))
" PC がトピックのノートへ自分の文章を足し、スマホで 2 つめを書き直す → 同じ行が更新され、PC の文章は残る
let s:l = readfile(s:T)
call insert(s:l, 'PC で足した考え', index(s:l, '詳しく') + 1)
call writefile(s:l, s:T)
call s:phone(1, "ふたつめ(改)\n詳しく")
call s:phone(2, "空を飛ぶ夢(改)")
call gnosis#capture_import($D . '/pack')
call assert_equal(1, s:hits(s:T, '11:00 ふたつめ(改)'))
call assert_equal(0, s:hits(s:T, '11:00 ふたつめ$'))
call assert_equal(1, s:hits(s:T, 'PC で足した考え'))
call assert_equal(1, s:hits(s:T, '10:00 ひとつめのアイデア'))
call assert_equal(1, s:hits(s:R, '12:00 空を飛ぶ夢(改)'))
call assert_equal(0, s:hits(s:R, '12:00 空を飛ぶ夢$'))
call assert_equal(s:nn, len(glob($D . '/v/*.md', 0, 1)))
" 同じ編集の再実行は何も変えない
let s:t2 = readfile(s:T)
let s:r2 = readfile(s:R)
call gnosis#capture_import($D . '/pack')
call assert_equal(s:t2, readfile(s:T))
call assert_equal(s:r2, readfile(s:R))
" 同じ行を PC も変えていたら競合
let s:l = readfile(s:T)
let s:l[index(s:l, '10:00 ひとつめのアイデア')] = '10:00 ひとつめ(PC)'
call writefile(s:l, s:T)
call s:phone(0, "ひとつめ(スマホ)")
call gnosis#capture_import($D . '/pack')
call assert_equal(s:l, readfile(s:T))
call assert_true(filereadable($D . '/v/.state/capture_conflicts/261019100000.json'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
