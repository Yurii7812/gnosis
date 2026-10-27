" ノートを作る・題を変えると、Folgezettel ビューと曼荼羅が（保存/同期のあと）自動で更新される（test/view_live_net.sh から）
set nomore
let s:work = $VL_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_test_review_skip = 1
let g:gnosis_diary_auto = 0
let g:gnosis_mview_restore = 0
function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
  call writefile(s:res, s:work . '/result.txt')
endfunction
function! s:lines() abort
  return getbufline(gnosis#mview#state().buf, 1, '$')
endfunction
function! s:wait(cond) abort
  for l:i in range(60)
    if eval(a:cond) | return 1 | endif
    sleep 100m
  endfor
  return 0
endfunction
call mkdir(s:v, 'p')
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: Index', 'attribute: group', '---', '', '# Index', '', '[親](a.md)'], s:v . '/index.md')
call writefile(['---', 'time: 2026-01-01 00:00:00', 'folgezettel: "1"', '---', '', '# 親', '', '本文'], s:v . '/a.md')
execute 'edit ' . s:v . '/a.md'
call gnosis#mview#toggle()
sleep 200m
call gnosis#mview#switch_view('fz')
call s:ok('前提: Folgezettel ビューに 親 が出ている', join(s:lines(), "\n") =~# '親')
" 1. zn で子ノートを作る → すぐ一覧に出る（番号 1a）
call win_gotoid(gnosis#mview#note_win())
let g:gnosis_test_keys = ["\<CR>"]
call gnosis#v2_new_plain()
stopinsert
let s:new = expand('%:t')
call s:ok('zn: 子ノートが Folgezettel ビューに出る（1a）', s:wait('join(s:lines(), "\n") =~# "1a"'), string(s:lines()[0 : 6]))
" 2. 題を変えて保存 → 一覧の題が変わる
call setline(search('^#\s', 'nw'), '# 新しい題')
write
call s:ok('題を変えて保存: 一覧の題が変わる', s:wait('join(s:lines(), "\n") =~# "新しい題"'), string(s:lines()[0 : 6]))
" 3. 親を外して保存 → 番号が外れ、一覧から消える
let s:lines0 = readfile(s:v . '/' . s:new)
call writefile(filter(s:lines0, 'v:val !~# "ParentBranch:\\|(a.md)"'), s:v . '/' . s:new)
execute 'edit! ' . fnameescape(s:v . '/' . s:new)
" 同期（保存のたびに裏で走るもの）が終わったことにして、ビューを読み直させる
call gnosis#sh#system('env -u GNOSIS_SYNC_GUARD_DIR ' . gnosis#python_cmd() . ' ' . shellescape(g:gnosis_python) . ' update ' . shellescape(s:v))
call gnosis#mview#sync_done()
call s:ok('親を外して保存: 一覧から消える（番号が外れる）', s:wait('join(s:lines(), "\n") !~# "新しい題"'), string(s:lines()[0 : 6]))
