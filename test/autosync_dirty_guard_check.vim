" バックグラウンド同期と自動保存の競合を再現する回帰テスト。
let s:v = $SYNC_GUARD_VAULT
let s:result = $SYNC_GUARD_WORK . '/guard-result.txt'
let g:gnosis_root = s:v
let g:gnosis_open_index_on_startup = 0
let g:gnosis_autosync = 0
let g:gnosis_autosave = 1
let s:out = []
function! s:ok(name, passed) abort
  call add(s:out, (a:passed ? 'OK ' : 'NG ') . a:name)
endfunction

try
  execute 'edit ' . fnameescape(s:v . '/child.md')
  call setline(8, 'User edit must be preserved')
  doautocmd TextChanged
  let s:marker = get(b:, 'gnosis_sync_dirty_guard', '')
  call s:ok('編集開始時に dirty guard が作成される', !empty(s:marker) && filereadable(s:marker))
  let s:cmd = 'python3 ' . shellescape($SYNC_GUARD_PY) . ' update ' . shellescape(s:v)
  let s:before = readfile(s:v . '/child.md')
  call system(s:cmd)
  call s:ok('未保存のノートを Python 同期が書き換えない', s:before ==# readfile(s:v . '/child.md'))
  call s:ok('ディスク上の元本文を維持', index(readfile(s:v . '/child.md'), 'User edit must be preserved') < 0)

  " 通常の手動/自動保存後には再同期できる。上書き確認は生じない。
  silent write
  call s:ok('保存後にガードを解除', !filereadable(s:marker))
  call s:ok('ユーザーの本文編集が保存された', index(readfile(s:v . '/child.md'), 'User edit must be preserved') >= 0)
  call system(s:cmd)
  let s:after = readfile(s:v . '/child.md')
  call s:ok('保存後の再同期で Group が更新される', index(s:after, 'Group:') >= 0 && match(s:after, '^\[Index\%(:[^]]*\)\=\](index.md)$') >= 0)
  call s:ok('同期後もユーザーの編集は保持', index(s:after, 'User edit must be preserved') >= 0)
catch
  call add(s:out, 'NG exception: ' . v:exception . ' at ' . v:throwpoint)
endtry
call writefile(s:out, s:result)
qall!
