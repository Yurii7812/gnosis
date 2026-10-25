" =============================================================================
" autoload/gnosis/run.vim — 動いている Gnosis（CUI の Vim・GUI のアプリ）の登録と、キーボードだけで閉じる
"
"   \x  今いる画面を閉じる。GUI なら GUI を閉じる（CUI から開いたなら、閉じて CUI に戻る）。CUI なら CUI を閉じる
"   \X  CUI も GUI も全部閉じる（どちらから押しても、開いているかどうかに関わらず）
"
" 登録: Gnosis ホームの run/<kind>-<pid>.json（kind は cui か gui）。CUI の Vim は起動時に自分を登録し、終了時に消す。
" GUI（Electron アプリ）も同じ形で自分を登録する（web/electron/main.cjs）。GUI の中で動いている Vim は、CUI としては登録しない。
" 閉じてほしい相手には run/close-<kind>-<pid> というファイルを置く。相手は 0.5 秒ごとに見て、見つけたら（消してから）自分を閉じる
" （CUI は未保存のノートを書いてから終了、GUI はアプリの通常の終了の流れ）。死んだプロセスの登録は、見つけたときに消す。
" =============================================================================

let s:timer = 0

function! gnosis#run#dir() abort
  let l:d = gnosis#home#dir() . '/run'
  if !isdirectory(l:d)
    call mkdir(l:d, 'p')
  endif
  return l:d
endfunction

function! s:alive(pid) abort
  if a:pid <= 0 | return 0 | endif
  if isdirectory('/proc/' . a:pid) | return 1 | endif
  if isdirectory('/proc') | return 0 | endif
  call system('kill -0 ' . a:pid . ' 2>/dev/null')
  return v:shell_error == 0
endfunction

" 登録されている [{kind, pid, file}]（生きているものだけ。死んだものは登録を消す）
function! gnosis#run#list(...) abort
  let l:kind = a:0 ? a:1 : ''
  let l:out = []
  let l:dir = gnosis#run#dir()
  for l:f in glob(l:dir . '/*.json', 0, 1)
    let l:m = matchlist(fnamemodify(l:f, ':t'), '^\(cui\|gui\)-\(\d\+\)\.json$')
    if empty(l:m) | continue | endif
    let l:pid = str2nr(l:m[2])
    if !s:alive(l:pid)
      call delete(l:f)
      call delete(l:dir . '/close-' . l:m[1] . '-' . l:pid)
      continue
    endif
    if empty(l:kind) || l:kind ==# l:m[1]
      call add(l:out, {'kind': l:m[1], 'pid': l:pid, 'file': l:f})
    endif
  endfor
  return l:out
endfunction

" CUI の Vim として登録する（GUI の中の Vim は登録しない）。0.5 秒ごとに「閉じて」の依頼を見る
function! gnosis#run#register() abort
  if !empty($GNOSIS_GUI_PORT) || exists('s:registered') || !has('timers')
    return
  endif
  try
    let l:me = getpid()
    call writefile([json_encode({'kind': 'cui', 'pid': l:me, 'vault': get(g:, 'gnosis_root', ''), 'started': localtime()})], gnosis#run#dir() . '/cui-' . l:me . '.json')
    let s:registered = l:me
    let s:timer = timer_start(500, function('s:poll'), {'repeat': -1})
  catch
  endtry
endfunction

function! gnosis#run#unregister() abort
  if !exists('s:registered') | return | endif
  try
    call delete(gnosis#run#dir() . '/cui-' . s:registered . '.json')
    call delete(gnosis#run#dir() . '/close-cui-' . s:registered)
  catch
  endtry
  unlet s:registered
endfunction

function! s:poll(t) abort
  if !exists('s:registered') | return | endif
  let l:req = gnosis#run#dir() . '/close-cui-' . s:registered
  if filereadable(l:req)
    call delete(l:req)
    call s:quit_cui()
  endif
endfunction

" 未保存のノートを書いてから、CUI を閉じる
function! s:quit_cui() abort
  silent! wall
  call gnosis#run#unregister()
  qall!
endfunction

" 相手（kind と pid）に「閉じて」を依頼する
function! s:ask_close(kind, pid) abort
  call writefile([''], gnosis#run#dir() . '/close-' . a:kind . '-' . a:pid)
endfunction

" \x: 今いる画面を閉じる
function! gnosis#run#close_here() abort
  if !empty($GNOSIS_GUI_PORT)
    " GUI のアプリを閉じる（CUI から開いたなら、CUI はそのまま残って戻る）
    call s:request_gui_quit()
    return
  endif
  call s:quit_cui()
endfunction

" \X: CUI も GUI も全部閉じる
function! gnosis#run#close_all() abort
  let l:me = exists('s:registered') ? s:registered : 0
  for l:r in gnosis#run#list()
    if l:r.kind ==# 'cui' && l:r.pid != l:me
      call s:ask_close('cui', l:r.pid)
    elseif l:r.kind ==# 'gui'
      call s:ask_close('gui', l:r.pid)
    endif
  endfor
  if !empty($GNOSIS_GUI_PORT)
    call s:request_gui_quit()
    return
  endif
  call s:quit_cui()
endfunction

" GUI の中の Vim から、アプリへ「終了して」を伝える（web/vim/gui.vim が状態に quitReq として載せる）
function! s:request_gui_quit() abort
  let g:gnosis_gui_quit_req = get(g:, 'gnosis_gui_quit_req', 0) + 1
  silent! call GnosisGuiPush()
endfunction
