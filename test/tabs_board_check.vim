" タブのボード（\q / \Q）の回帰網（test/tabs_board_net.sh から呼ぶ）。\h / \H と同じ仕組みで別のファイル。
" 結果は $TABS_WORK/result.txt に「OK 名前」「NG 名前: 詳細」で書く。
set nomore
let s:work = $TABS_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
function! s:mk(name, title) abort
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title, '---', '', '# ' . a:title, ''], s:v . '/' . a:name)
endfunction

call s:mk('a.md', 'ノートA')
call s:mk('b.md', 'ノートB')
execute 'edit ' . s:v . '/a.md'
call gnosis#hub_set('tabs')
execute 'edit ' . s:v . '/b.md'
call gnosis#hub_set('tabs')
call gnosis#hub_set('tabs')
call gnosis#hub_set()
let s:tabs = split(glob(s:v . '/.state/hubs/tabs-*.md'), "\n")
let s:hubs = filter(split(glob(s:v . '/.state/hubs/*.md'), "\n"), 'fnamemodify(v:val, ":t") !~# "^tabs-"')
call s:ok('タブのボードのファイルが 1 つできる', len(s:tabs) == 1, string(s:tabs))
call s:ok('ハブは別のファイル', len(s:hubs) == 1, string(s:hubs))
let s:tl = len(s:tabs) ? readfile(s:tabs[0]) : []
call s:ok('タブのボードには A と B が 1 行ずつ（二重登録しない）', len(s:tl) == 2 && s:tl[0] =~# 'ノートA' && s:tl[1] =~# 'ノートB', string(s:tl))
let s:hl = len(s:hubs) ? readfile(s:hubs[0]) : []
call s:ok('ハブには B だけ（ボードと混ざらない）', len(s:hl) == 1 && s:hl[0] =~# 'ノートB', string(s:hl))
call writefile(s:res, s:work . '/result.txt')
qa!
