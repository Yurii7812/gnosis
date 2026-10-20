" 複数ウィンドウで vault を同時に使うときの回帰網（test/session_net.sh から呼ぶ）。
"   - 別のウィンドウが使っている暗号化 vault を、切り替え・終了・:GnosisLock でロックしない
"   - 使っている最後のセッションが終わる（切り替える）ときだけロックする
"   - 異常終了したプロセスの登録は残らない（死んだ pid・使い回された pid）
"   - 異なる vault は排他を共有しない
"   - 別のプロセスが書き換えたノートを、自動保存が上書きしない・未保存の変更を読み直しで失わない
" gocryptfs の代わりに、PATH の偽の mountpoint / fusermount3（$STUB_DIR の記録）で動かす。
set nomore
let s:w = $SESSION_WORK
let s:stub = $STUB_DIR
let s:other = str2nr($OTHER_PID)
let s:res = []
function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
function! s:msgs() abort
  redir => l:m
  silent messages
  redir END
  return l:m
endfunction
function! s:log() abort
  return filereadable(s:stub . '/fusermount.log') ? readfile(s:stub . '/fusermount.log') : []
endfunction
function! s:mounted(root) abort
  return index(readfile(s:stub . '/mounted'), a:root) >= 0
endfunction
function! s:mount(root) abort
  call writefile(add(filereadable(s:stub . '/mounted') ? readfile(s:stub . '/mounted') : [], a:root), s:stub . '/mounted')
endfunction
function! s:fake_other(root, pid, start) abort
  let l:d = gnosis#session#dir(a:root)
  call mkdir(l:d, 'p')
  call writefile([json_encode({'pid': a:pid, 'start': a:start, 'vault': a:root, 'time': localtime()})], l:d . '/' . a:pid . '.json')
endfunction
function! s:drop_other(root, pid) abort
  call delete(gnosis#session#dir(a:root) . '/' . a:pid . '.json')
endfunction

let s:A = s:w . '/A/note'
let s:B = s:w . '/B/note'
let s:C = s:w . '/C/note'
for s:v in [s:A, s:B, s:C]
  call mkdir(s:v, 'p')
  call writefile(['---', 'title: Index', 'attribute: group', '---', '', '# Index'], s:v . '/index.md')
  call writefile(['---', 'title: N', '---', '', '# N', '', 'body'], s:v . '/n.md')
endfor
call writefile([], s:stub . '/mounted')
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
" 偽の mountpoint（PATH の先頭）で調べる（ふだんは /proc の一覧を読む）
let g:gnosis_mount_check = 'mountpoint'
let g:gnosis_root = s:A . '/'

" ---------------------------------------------------------------- 登録簿
call s:ok('登録簿: 異なる vault は別のフォルダ', gnosis#session#dir(s:A) !=# gnosis#session#dir(s:B))
call s:ok('登録簿: Gnosis ホームの下（vault の中ではない）', stridx(gnosis#session#dir(s:A), $GNOSIS_HOME) == 0 && stridx(gnosis#session#dir(s:A), s:A) < 0)
call gnosis#session#register(s:A)
call s:ok('登録: 自分だけなら他のセッションは無い', empty(gnosis#session#others(s:A)) && index(gnosis#session#mine(), s:A) >= 0)
call s:fake_other(s:A, s:other, '')
call s:ok('登録: 生きている別プロセスは「使用中」と数える', len(gnosis#session#others(s:A)) == 1)
call s:ok('登録: 別の vault には影響しない', empty(gnosis#session#others(s:B)))
" 死んだ pid の登録は消える
call s:fake_other(s:A, 999999, '')
call s:ok('異常終了: 死んだ pid は数えない', len(gnosis#session#others(s:A)) == 1)
call s:ok('異常終了: 死んだ pid の登録ファイルは掃除される', !filereadable(gnosis#session#dir(s:A) . '/999999.json'))
" pid が使い回されて別のプロセスになっていたら、使用中と数えない
call s:drop_other(s:A, s:other)
call s:fake_other(s:A, s:other, 'bogus-start-time')
call s:ok('異常終了: pid が使い回された登録（開始時刻が違う）は数えない', empty(gnosis#session#others(s:A)) && !filereadable(gnosis#session#dir(s:A) . '/' . s:other . '.json'))
call s:fake_other(s:A, s:other, '')
" 古いロックは回収される・別の vault のロックは待たない
let s:ldir = gnosis#session#dir(s:A) . '/.lock'
call mkdir(s:ldir, 'p')
call system('touch -d "2 minutes ago" ' . shellescape(s:ldir))
let s:t0 = reltimefloat(reltime())
call gnosis#session#register(s:A)
call s:ok('異常終了: 古いロックは回収されて登録できる', isdirectory(gnosis#session#dir(s:A)) && !isdirectory(s:ldir) && reltimefloat(reltime()) - s:t0 < 3)
call mkdir(gnosis#session#dir(s:A) . '/.lock', 'p')
let s:t0 = reltimefloat(reltime())
call gnosis#session#register(s:B)
call s:ok('独立: A のロック中でも B の登録は待たされない', reltimefloat(reltime()) - s:t0 < 1.0)
call delete(gnosis#session#dir(s:A) . '/.lock', 'd')
call gnosis#session#unregister(s:B)

" ---------------------------------------------------------------- 切り替えでロックしない
call s:mount(s:A)
execute 'edit ' . fnameescape(s:A . '/n.md')
call gnosis#switch_vault(s:B)
call s:ok('切り替え: 別ウィンドウが A を使っているので、A をロックしない（アンマウントしない）', s:mounted(s:A) && s:log() ==# [], string(s:log()))
call s:ok('切り替え: A の使用登録は外れ、B が登録される', index(gnosis#session#mine(), s:A) < 0 && index(gnosis#session#mine(), s:B) >= 0, string(gnosis#session#mine()))
call s:ok('切り替え: 他のウィンドウの登録は残る', len(gnosis#session#others(s:A)) == 1)
call s:ok('切り替え: 使っているウィンドウがあることを知らせる', s:msgs() =~# '1', '')
call s:ok('切り替え: root は B になる', fnamemodify(g:gnosis_root, ':p') ==# fnamemodify(s:B, ':p') . '/' || fnamemodify(g:gnosis_root, ':p') ==# fnamemodify(s:B . '/', ':p'), g:gnosis_root)
" 最後の 1 人が切り替えるときだけロックする（今までどおり）
call s:drop_other(s:A, s:other)
call gnosis#switch_vault(s:A)
call s:mount(s:B)
call gnosis#session#register(s:A)
call gnosis#switch_vault(s:B)
call s:ok('切り替え: A を使う最後のセッションが離れるときは、今までどおり A をロックする', !s:mounted(s:A) && len(filter(s:log(), 'v:val =~# s:A')) >= 1, string(s:log()))
call s:ok('切り替え: 切り替え先の B はロックしない', s:mounted(s:B))

" ---------------------------------------------------------------- 終了（quit_unmount）
let g:gnosis_root = s:B . '/'
call gnosis#session#register(s:B)
call s:fake_other(s:B, s:other, '')
let s:n = len(s:log())
call gnosis#quit_unmount()
call s:ok('終了: 別ウィンドウが B を使っていれば、B をロックしない', s:mounted(s:B) && len(s:log()) == s:n)
call s:ok('終了: 自分の登録は外れる・他のウィンドウの登録は残る', index(gnosis#session#mine(), s:B) < 0 && len(gnosis#session#others(s:B)) == 1)
call s:drop_other(s:B, s:other)
call gnosis#session#register(s:B)
call gnosis#quit_unmount()
call s:ok('終了: 最後の 1 人なら B をロックする', !s:mounted(s:B))
" この Vim が使っていない vault（登録していない）には触らない
call s:mount(s:C)
let g:gnosis_root = s:C . '/'
let s:n = len(s:log())
call gnosis#quit_unmount()
call s:ok('終了: 登録していない vault（前回の vault など）はロックしない', s:mounted(s:C) && len(s:log()) == s:n)
" 異常終了した他のウィンドウの登録は、最後の 1 人の判定を妨げない
call gnosis#session#register(s:C)
call s:fake_other(s:C, 999998, '')
call gnosis#quit_unmount()
call s:ok('異常終了した別ウィンドウの登録があっても、最後の 1 人はロックできる', !s:mounted(s:C))

" ---------------------------------------------------------------- 明示的なロック
call s:mount(s:A)
let g:gnosis_root = s:A . '/'
execute 'edit ' . fnameescape(s:A . '/n.md')
call gnosis#session#register(s:A)
call s:fake_other(s:A, s:other, '')
let s:n = len(s:log())
call gnosis#lock_vault()
call s:ok(':GnosisLock: 別ウィンドウが使っていれば、ロックしない', s:mounted(s:A) && len(s:log()) == s:n)
call s:ok(':GnosisLock: 理由を伝える', s:msgs() =~# ':GnosisLock!' || s:msgs() =~# 'GnosisLock!')
call gnosis#lock_vault(1)
call s:ok(':GnosisLock!: 明示すれば（強制）ロックする', !s:mounted(s:A))

" ---------------------------------------------------------------- 排他が要る操作は共有中に行わない
call s:mount(s:A)
execute 'edit ' . fnameescape(s:A . '/n.md')
let s:n = len(s:log())
let s:before = readfile(s:A . '/n.md')
call gnosis#vault_mounted(s:A, 1)
call gnosis#remove_password()
call s:ok('暗号化の解除: 別ウィンドウが使っている間は行わず、何も変えない', s:mounted(s:A) && len(s:log()) == s:n && readfile(s:A . '/n.md') ==# s:before && s:msgs() =~# '1', '')
call s:drop_other(s:A, s:other)

" ---------------------------------------------------------------- 同じノートを別のプロセスが書き換えた
execute 'edit ' . fnameescape(s:A . '/n.md')
call gnosis#conflict#record()
call setline(line('$'), 'このウィンドウで書いた行')
sleep 1100m
call writefile(['---', 'title: N', '---', '', '# N', '', '別のプロセスが書いた'], s:A . '/n.md')
let s:ok_write = gnosis#conflict#safe_update()
call s:ok('同時編集: 他で書き換えられたノートは、自動保存が上書きしない', s:ok_write == 0 && readfile(s:A . '/n.md')[-1] ==# '別のプロセスが書いた' && &modified)
call s:ok('同時編集: 未保存の内容を退避する', !empty(glob(s:A . '/.state/conflicts/*-n.md', 1, 1)) && join(readfile(glob(s:A . '/.state/conflicts/*-n.md', 1, 1)[0]), "\n") =~# 'このウィンドウで書いた行')
call s:ok('同時編集: 警告を出す', s:msgs() =~# '別のウィンドウ' || s:msgs() =~# 'Another window')
" 読み直し（:edit!）のあとは、新しいファイルの状態を覚え直すので、普通に保存できる
edit!
call s:ok('同時編集: 読み直したあとは外の内容になっている', getline('$') ==# '別のプロセスが書いた', getline('$'))
call setline(line('$'), '普通の保存')
call s:ok('同時編集: 他で書き換えられていなければ今までどおり保存できる', gnosis#conflict#safe_update() && readfile(s:A . '/n.md')[-1] ==# '普通の保存')
" 外のプロセスが書いたあと、自分が保存する前に読み直して（未保存なし）から編集した場合も保存できる
sleep 1100m
call writefile(['---', 'title: N', '---', '', '# N', '', '外で更新'], s:A . '/n.md')
edit!
call setline(line('$'), '外の更新のあとに編集')
call s:ok('同時編集: 外の更新を読み込んでから編集すれば保存できる', gnosis#conflict#safe_update() && readfile(s:A . '/n.md')[-1] ==# '外の更新のあとに編集')

" 自分の自動同期が書き直したファイルは、警告せずバッファ側を優先して保存する
sleep 1100m
call gnosis#conflict#record()
call gnosis#conflict#mark_own_sync()
sleep 1100m
call writefile(['---', 'title: N', '---', '', '# N', '', '同期が整えた'], s:A . '/n.md')
call setline(line('$'), '同期中に打った文字')
let s:msgs_before = s:msgs()
call s:ok('自分の同期: 警告せずに保存できる', gnosis#conflict#safe_update() && readfile(s:A . '/n.md')[-1] ==# '同期中に打った文字' && s:msgs() ==# s:msgs_before)

call writefile(s:res, s:w . '/result.txt')
qa!
