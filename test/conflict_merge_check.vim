" 同期が書き換えたファイルと、未保存の編集が別々の場所なら、警告せずに両方を取り込む（test/conflict_merge_net.sh から）
set nomore
let s:work = $CM_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
  call writefile(s:res, s:work . '/result.txt')
endfunction
call mkdir(s:v, 'p')
call writefile(['---', 'time: 2026-01-01 00:00:00', '---', '', '# t', '', '', ''], s:v . '/n.md')
execute 'edit ' . s:v . '/n.md'
call gnosis#conflict#record()
" 1. 同期が BackLink: を末尾に足した。同時に、利用者は本文（真ん中の空行）に書いた（まだ保存していない）
sleep 1100m
call writefile(['---', 'time: 2026-01-01 00:00:00', '---', '', '# t', '', '', '', 'BackLink:', '[d](d.md)'], s:v . '/n.md')
call setline(7, 'あいう')
let g:msgs_before = execute('messages')
call s:ok('前提: 外で変わり、バッファは未保存', gnosis#conflict#disk_changed() && &modified)
let s:r = gnosis#conflict#safe_update()
let s:disk = readfile(s:v . '/n.md')
call s:ok('両方を取り込んで保存できる', s:r == 1 && index(s:disk, 'あいう') >= 0 && index(s:disk, 'BackLink:') >= 0 && index(s:disk, '[d](d.md)') >= 0, string(s:disk))
call s:ok('バッファも同じ内容・未保存でない', getline(1, '$') ==# s:disk && !&modified, string(getline(1, '$')))
call s:ok('警告（別のウィンドウが…）は出ていない', execute('messages') ==# g:msgs_before || execute('messages') !~# '別のウィンドウ\|another window', execute('messages'))
" 2. 同じ場所を変えた衝突は、これまでどおり保存せず警告して退避する
sleep 1100m
call writefile(['---', 'time: 2026-01-01 00:00:00', '---', '', '# 別の題', 'あいう'], s:v . '/n.md')
call setline(5, '# こちらの題')
let s:r2 = gnosis#conflict#safe_update()
call s:ok('同じ場所の衝突は保存しない', s:r2 == 0 && readfile(s:v . '/n.md')[4] ==# '# 別の題', string(readfile(s:v . '/n.md')))
