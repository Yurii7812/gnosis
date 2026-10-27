" 再起動したとき、閉じたときのビュー（Folgezettel）で開く（test/mview_viewrestore_net.sh から呼ぶ）。結果は $FZ_WORK/result.txt
set nomore
let s:work = $FZ_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1
function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
  call writefile(s:res, s:work . '/result.txt')
endfunction
call mkdir(s:v, 'p')
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: Index', '---', '', '# Index', '', '[認識](n1.md)'], s:v . '/index.md')
call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: 認識', 'folgezettel: "1"', '---', '', '# 認識'], s:v . '/n1.md')
" 前回 Folgezettel ビューで閉じた、という記録
call writefile([json_encode({'tenths': 5, 'stretch': 1.0, 'open': 1, 'view': 'fz'})], $GNOSIS_HOME . '/mandala.json')
execute 'edit ' . s:v . '/index.md'
call gnosis#mview#toggle()
sleep 100m
call s:ok('前回 fz で閉じていたら、最初から Folgezettel ビューで開く', gnosis#mview#view() ==# 'fz', gnosis#mview#view())
call s:ok('カーソルは左の窓にある', &filetype ==# 'gnosis-mandala')
" 曼荼羅に切り替えて終了 → 次は曼荼羅で開く
call gnosis#mview#switch_view('mandala')
doautocmd VimLeavePre
call s:ok('曼荼羅で閉じたことが記録される', get(json_decode(join(readfile($GNOSIS_HOME . '/mandala.json'), "\n")), 'view', '') ==# 'mandala')
call gnosis#mview#switch_view('fz')
doautocmd VimLeavePre
call s:ok('Folgezettel で閉じたことが記録される', get(json_decode(join(readfile($GNOSIS_HOME . '/mandala.json'), "\n")), 'view', '') ==# 'fz')
