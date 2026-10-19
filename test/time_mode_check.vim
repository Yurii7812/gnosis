" 時刻: Ctrl-T で「時:分 」を入れる・\T の時刻モードで Enter のたびに空行と次の時刻
let s:out = []
function! s:ok(name, passed, ...) abort
  call add(s:out, (a:passed ? 'OK ' : 'NG ') . a:name . (a:passed || a:0 == 0 ? '' : ': ' . a:1))
endfunction
let s:t = '\d\d:\d\d '
try
  execute 'edit ' . fnameescape($TIME_VAULT . '/t.md')
  setlocal filetype=markdown
  doautocmd BufRead
  call feedkeys("Gox\<C-t>abc\<Esc>", 'xt')
  call s:ok('Ctrl-T（挿入）: 時刻と半角スペース', getline('$') =~# '^x' . s:t . 'abc$', getline('$'))
  call feedkeys("Go\<Esc>\<C-t>def\<Esc>", 'xt')
  call s:ok('Ctrl-T（ノーマル）: 挿入モードに入って時刻', getline('$') =~# '^' . s:t . 'def$', getline('$'))
  " 時刻モード
  call feedkeys("\\T", 'xt')
  call s:ok('\T で時刻モードがオン', get(b:, 'gnosis_time_mode', 0) == 1)
  call s:ok('時刻モードはステータスラインに出る', gnosis#ui#statusline() =~# '時刻')
  call feedkeys("Go一つ目\<CR>二つ目\<CR>\<Esc>", 'xt')
  let s:l = getline(1, '$')
  let s:n = len(s:l)
  call s:ok('書き始めた行の頭に時刻・Enter で空行をはさむ', s:l[s:n - 5] =~# '^' . s:t . '一つ目$' && s:l[s:n - 4] ==# '' && s:l[s:n - 3] =~# '^' . s:t . '二つ目$' && s:l[s:n - 2] ==# '', string(s:l[-5:]))
  call s:ok('Enter のあとはまだ時刻を入れない（空の行）', s:l[s:n - 1] ==# '', string(s:l[-2:]))
  call feedkeys("Go# 見出し\<Esc>", 'xt')
  call s:ok('見出しの書き始めには時刻を入れない', getline('$') ==# '# 見出し', getline('$'))
  call feedkeys("Go12:00 \<CR>\<Esc>", 'xt')
  call s:ok('時刻だけの行で Enter: 時刻を消してふつうの空行', getline('$') =~# '^$', string(getline(1, '$')[-3:]))
  call feedkeys("Goabcdef\<Esc>hhi\<CR>\<Esc>", 'xt')
  call s:ok('行の途中で Enter: 後ろを次の時刻の行へ', getline(line('$') - 2) =~# '^' . s:t . 'abc$' && getline('$') =~# '^' . s:t . 'def$', string(getline(1, '$')[-3:]))
  call feedkeys("Go- [ ] やること\<CR>\<Esc>", 'xt')
  call s:ok('時刻モードでもチェックボックスの行は次のチェックボックス', getline('$') =~# '^- \[ \] $', getline('$'))
  call feedkeys("\\T", 'xt')
  call feedkeys("Gofoo\<CR>bar\<Esc>", 'xt')
  call s:ok('\T でオフ: ふつうの Enter', getline(line('$') - 1) ==# 'foo' && getline('$') ==# 'bar', string(getline(1, '$')[-2:]))
  " 時系列記録のノートは開くとオン・ほかのノートへ移るとそのノートはオフ
  call feedkeys("\\T", 'xt')
  call s:ok('\T でもう一度オン', get(b:, 'gnosis_time_mode', 0) == 1)
  " 検索の画面などで別のウィンドウを開いて閉じても（ノートが出し直されても）切れない
  split
  enew
  close
  call s:ok('ウィンドウを開いて閉じても時刻モードは切れない', get(b:, 'gnosis_time_mode', 0) == 1)
  silent write
  execute 'edit ' . fnameescape($TIME_VAULT . '/rec.md')
  sleep 200m
  call s:ok('時系列記録のノートは開くと時刻モード', get(b:, 'gnosis_time_mode', 0) == 1)
  call feedkeys("Go見た夢\<Esc>", 'xt')
  call s:ok('時系列記録: 書き始めると時刻', getline('$') =~# '^' . s:t . '見た夢$', getline('$'))
  silent write
  execute 'edit ' . fnameescape($TIME_VAULT . '/t.md')
  call s:ok('オンのまま離れたノートへ戻ると、時刻モードは切れている', get(b:, 'gnosis_time_mode', 0) == 0)
  call feedkeys("Gobaz\<Esc>", 'xt')
  call s:ok('切れているので時刻は入らない', getline('$') ==# 'baz', getline('$'))
catch
  call add(s:out, 'NG 例外: ' . v:exception . ' @ ' . v:throwpoint)
endtry
call writefile(s:out, $TIME_RESULT)
qall!
