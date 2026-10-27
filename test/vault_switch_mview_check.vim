" 曼荼羅・Folgezettel ビュー・アウトラインを開いたまま :GnosisVaults で vault を切り替えても壊れない
" （test/vault_switch_mview_net.sh から呼ぶ）。結果は $FZ_WORK/result.txt
set nomore
let s:work = $FZ_WORK
let s:res = []
let s:A = s:work . '/A'
let s:B = s:work . '/B'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1
let g:gnosis_open_index_on_startup = 0
function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
  call writefile(s:res, s:work . '/result.txt')
endfunction
function! s:mk(dir, tag) abort
  call mkdir(a:dir, 'p')
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: Index', '---', '', '# Index', '', '[' . a:tag . '1](' . a:tag . '1.md)'], a:dir . '/index.md')
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:tag . '1', 'folgezettel: "1"', '---', '', '# ' . a:tag . '1', '', '## 見出し'], a:dir . '/' . a:tag . '1.md')
endfunction
call s:mk(s:A, 'a')
call s:mk(s:B, 'b')
let g:gnosis_root = s:A . '/'
call gnosis#vault#add(s:A)
call gnosis#vault#add(s:B)
call gnosis#settings#activate(s:A)
execute 'edit ' . s:A . '/index.md'
call gnosis#mview#toggle()
sleep 100m
call gnosis#mview#switch_view('fz')
call gnosis#outline#open()
call s:ok('前提: 曼荼羅・本文・アウトラインの 3 窓が出ている', winnr('$') == 3 && gnosis#mview#state().root =~# '/A', winnr('$') . ' ' . get(gnosis#mview#state(), 'root', ''))
" :GnosisVaults（切り替え画面）
call gnosis#start#open_vaults()
call s:ok('切り替え画面は窓 1 つで出る（曼荼羅の窓が上書きされない）', winnr('$') == 1 && &filetype ==# 'gnosisstart', winnr('$') . ' ' . &filetype)
call s:ok('前の vault の曼荼羅の状態は捨てられる', empty(gnosis#mview#state()))
" B を選ぶ
call gnosis#start#begin(s:B)
sleep 400m
call s:ok('B に切り替わる', fnamemodify(g:gnosis_root, ':p') =~# '/B/$', g:gnosis_root)
call s:ok('B の曼荼羅が開く', get(gnosis#mview#state(), 'root', '') =~# '/B', get(gnosis#mview#state(), 'root', ''))
call s:ok('曼荼羅の中心は B のノート（A のノートではない）', get(gnosis#mview#state(), 'center', '') !~# '^a1', get(gnosis#mview#state(), 'center', ''))
call s:ok('Folgezettel ビューで閉じていたので、そのビューで開く', gnosis#mview#view() ==# 'fz', gnosis#mview#view())
let s:lines = getbufline(gnosis#mview#state().buf, 1, '$')
call s:ok('Folgezettel の行は B のノートだけ', join(s:lines, "\n") =~# 'b1' && join(s:lines, "\n") !~# 'a1', string(s:lines[0 : 5]))
