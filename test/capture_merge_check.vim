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
function! s:phone(text) abort
  let l:d = json_decode(join(readfile(s:pack), "\n"))
  let l:d.entries[0].text = a:text
  call writefile([json_encode(l:d)], s:pack)
endfunction
function! s:count() abort
  return len(filter(glob($D . '/v/2610*.md', 0, 1), 'v:val !~# "/2610\\d\\{8\\}[.]md$" || 1'))
endfunction
let s:n = $D . '/v/261019100000.md'
" 1. 初回取り込み → 1 件。再実行しても同じ内容・同じ更新時刻のまま
call gnosis#capture_import($D . '/pack')
call assert_true(filereadable(s:n))
let s:first = readfile(s:n)
let s:mt = getftime(s:n)
let s:notes = len(glob($D . '/v/*.md', 0, 1))
sleep 1100m
call gnosis#capture_import($D . '/pack')
call gnosis#capture_import($D . '/pack')
call assert_equal(s:first, readfile(s:n))
call assert_equal(s:mt, getftime(s:n))
call assert_equal(s:notes, len(glob($D . '/v/*.md', 0, 1)))
" 2. PC が末尾に追記・スマホが別の行を変更 → 同じノートに両方残る・ノートは増えない
let s:body = readfile(s:n)
let s:at = index(s:body, '三行目')
call insert(s:body, 'PC の追記', s:at + 1)
call writefile(s:body, s:n)
call s:phone("一行目(スマホ)\n二行目\n三行目")
call gnosis#capture_import($D . '/pack')
let s:now = readfile(s:n)
call assert_true(index(s:now, '一行目(スマホ)') >= 0)
call assert_true(index(s:now, '一行目') < 0)
call assert_true(index(s:now, 'PC の追記') >= 0)
call assert_equal(s:notes, len(glob($D . '/v/*.md', 0, 1)))
" 3. 同じ変更をもう一度取り込んでも変わらない（冪等）
call gnosis#capture_import($D . '/pack')
call assert_equal(s:now, readfile(s:n))
" 3b. PC でノートのファイル名を変えても、同じノートとして追跡する（新しいノートを作らない）
call assert_true(index(readfile(s:n), 'capture_id: 261019100000') >= 0)
call assert_equal(0, rename(s:n, $D . '/v/renamed-by-user.md'))
let s:n = $D . '/v/renamed-by-user.md'
let s:count0 = len(glob($D . '/v/*.md', 0, 1))
call s:phone("一行目(スマホ)\n二行目\n三行目\nリネーム後の追記")
call gnosis#capture_import($D . '/pack')
call assert_true(index(readfile(s:n), 'リネーム後の追記') >= 0)
call assert_false(filereadable($D . '/v/261019100000.md'))
call assert_false(filereadable($D . '/v/261019100000-2.md'))
call assert_equal(s:count0, len(glob($D . '/v/*.md', 0, 1)))
call assert_true(index(readfile(s:n), 'PC の追記') >= 0)
" 4. 同じ行を PC とスマホが別々に変更 → ノートは変えず、新しいノートも作らず、競合の記録が残る
let s:body = readfile(s:n)
let s:body[index(s:body, '二行目')] = '二行目(PC)'
call writefile(s:body, s:n)
call s:phone("一行目(スマホ)\n二行目(スマホ)\n三行目\nリネーム後の追記")
call gnosis#capture_import($D . '/pack')
call assert_equal(s:body, readfile(s:n))
call assert_equal(s:notes, len(glob($D . '/v/*.md', 0, 1)))
call assert_true(filereadable($D . '/v/.state/capture_conflicts/261019100000.json'))
" 競合は取り込み済みにならない（もう一度実行しても同じ競合）
call gnosis#capture_import($D . '/pack')
call assert_equal(s:body, readfile(s:n))
call assert_true(filereadable($D . '/v/.state/capture_conflicts/261019100000.json'))
call assert_equal(s:notes, len(glob($D . '/v/*.md', 0, 1)))
" 5. 競合の解決: append でスマホの行を引用で足し、了解済みにする → 次の取り込みで競合も変更も起きない
call gnosis#capture_resolve('261019100000', 'append')
let s:res = readfile(s:n)
call assert_true(index(s:res, '> 二行目(スマホ)') >= 0)
call assert_true(index(s:res, '二行目(PC)') >= 0)
call assert_false(filereadable($D . '/v/.state/capture_conflicts/261019100000.json'))
call gnosis#capture_import($D . '/pack')
call assert_equal(s:res, readfile(s:n))
call assert_false(filereadable($D . '/v/.state/capture_conflicts/261019100000.json'))
call assert_equal(s:notes, len(glob($D . '/v/*.md', 0, 1)))
" 6. keep: PC を残して了解済み（もう一度スマホで同じ行を変えても、了解した版からの差分で判断される）
let s:body = readfile(s:n)
let s:body[index(s:body, '二行目(PC)')] = '二行目(PC2)'
call writefile(s:body, s:n)
call s:phone("一行目(スマホ)\n二行目(スマホ2)\n三行目\nリネーム後の追記")
call gnosis#capture_import($D . '/pack')
call assert_true(filereadable($D . '/v/.state/capture_conflicts/261019100000.json'))
call gnosis#capture_resolve('261019100000', 'keep')
call assert_equal(s:body, readfile(s:n))
call gnosis#capture_import($D . '/pack')
call assert_equal(s:body, readfile(s:n))
call assert_false(filereadable($D . '/v/.state/capture_conflicts/261019100000.json'))
" 診断コマンドが動く（別版は無いので何も作らない・capture_id は既にあるので足す件数は 0）
let s:nb = len(glob($D . '/v/*.md', 0, 1))
try
  call gnosis#capture_backfill()
  call gnosis#capture_backfill('apply')
  call gnosis#capture_duplicates()
catch
  call add(v:errors, '診断コマンドが失敗: ' . v:exception)
endtry
call assert_equal(s:nb, len(glob($D . '/v/*.md', 0, 1)))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
