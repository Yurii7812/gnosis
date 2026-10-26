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
      call delete(l:dir . '/focus-' . l:m[1] . '-' . l:pid)
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
    call writefile([json_encode({'kind': 'cui', 'pid': l:me, 'vault': get(g:, 'gnosis_root', ''), 'started': localtime(), 'window': $WINDOWID})], gnosis#run#dir() . '/cui-' . l:me . '.json')
    let s:registered_root = get(g:, 'gnosis_root', '')
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
    call delete(gnosis#run#dir() . '/focus-cui-' . s:registered)
  catch
  endtry
  unlet s:registered
endfunction

function! s:poll(t) abort
  if !exists('s:registered') | return | endif
  if get(g:, 'gnosis_root', '') !=# s:registered_root
    let s:registered_root = get(g:, 'gnosis_root', '')
    call writefile([json_encode({'kind': 'cui', 'pid': getpid(), 'vault': s:registered_root, 'window': $WINDOWID})], gnosis#run#dir() . '/cui-' . getpid() . '.json')
  endif
  let l:focus = gnosis#run#dir() . '/focus-cui-' . s:registered
  if filereadable(l:focus) && mode() ==# 'n' && empty(state('moxS'))
    call gnosis#run#receive(l:focus)
  endif
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
    call gnosis#run#switch("cui", "", 1)
    call s:request_gui_quit()
    return
  endif
  call gnosis#run#switch("gui", "", 1)
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

" 明示的な画面切替で状態を渡す。別の vault へは渡さない。
function! gnosis#run#export() abort
  silent wall
  let l:d = {'root': get(g:, 'gnosis_root', ''), 'mandala': gnosis#mview#handoff(), 'file': ''}
  if gnosis#is_vault_note(expand('%:p'))
    let l:d.file = expand('%:p')
  endif
  if empty(l:d.file)
    let l:ms = gnosis#mview#gui_state()
    if get(l:ms, 'noteWin', 0) > 0
      let l:d.file = fnamemodify(bufname(winbufnr(l:ms.noteWin)), ':p')
    elseif get(l:d.mandala, 'open', 0)
      let l:d.file = l:d.root . '/' . substitute(get(l:d.mandala, 'center', ''), '#.*$', '', '')
    endif
  endif
  let l:path = gnosis#run#dir() . '/handoff-' . getpid() . '.json'
  call writefile([json_encode(l:d)], l:path)
  return l:path
endfunction

function! gnosis#run#receive(path) abort
  if !filereadable(a:path) | return 0 | endif
  try
    let l:d = json_decode(join(readfile(a:path), "\n"))
    let l:root = substitute(fnamemodify(get(g:, 'gnosis_root', ''), ':p'), '[/\\]$', '', '')
    if substitute(fnamemodify(get(l:d, 'root', ''), ':p'), '[/\\]$', '', '') !=# l:root
      call delete(a:path)
      return 0
    endif
    if get(l:d, 'focusOnly', 0)
      call delete(a:path)
      if empty($GNOSIS_GUI_PORT) | call gnosis#run#focus(getpid(), $WINDOWID) | endif
      return 1
    endif
    let g:gnosis_handoff_loading = 1
    silent wall
    " 凡例など vault の表示設定も、相手が保存した最新版にそろえる。
    silent call gnosis#settings#activate(gnosis#vault#of_root(l:root))
    silent! checktime
    if filereadable(get(l:d, 'file', ''))
      let l:ms = gnosis#mview#gui_state()
      if get(l:ms, 'noteWin', 0) > 0
        call win_gotoid(l:ms.noteWin)
      elseif &filetype ==# 'gnosis-mandala'
        vertical rightbelow new
      endif
      execute 'silent edit ' . fnameescape(l:d.file)
    endif
    silent call gnosis#mview#restore_handoff(get(l:d, 'mandala', {}))
    call delete(a:path)
    if empty($GNOSIS_GUI_PORT)
      call gnosis#run#focus(getpid(), $WINDOWID)
    endif
    return 1
  catch
    echohl WarningMsg | echom 'Gnosis switch: ' . v:exception | echohl None
    call delete(a:path)
    return 0
  finally
    let g:gnosis_handoff_loading = 0
    silent! call GnosisGuiChanged()
  endtry
endfunction

function! gnosis#run#startup() abort
  if !empty($GNOSIS_HANDOFF)
    if mode() !=# 'n' || !empty(state('moxS'))
      call timer_start(100, {-> gnosis#run#startup()})
      return
    endif
    call gnosis#run#receive($GNOSIS_HANDOFF)
    let $GNOSIS_HANDOFF = ''
  endif
endfunction

function! gnosis#run#focus(pid, window) abort
  let l:script = fnamemodify(g:gnosis_python, ':h') . '/focus_window.py'
  call job_start(split(gnosis#python_cmd()) + [l:script, string(a:pid), a:window], {'out_io': 'null', 'err_io': 'null', 'stoponexit': ''})
endfunction

" 戻り値 1: 切替済み。GUI の新規起動だけは open_web に任せる。
function! gnosis#run#switch(kind, ...) abort
  let l:root = a:0 && !empty(a:1) ? a:1 : get(g:, 'gnosis_root', '')
  let l:root = substitute(fnamemodify(l:root, ':p'), '[/\\]$', '', '')
  let l:only_existing = a:0 > 1 ? a:2 : 0
  let l:here = empty($GNOSIS_GUI_PORT) ? 'cui' : 'gui'
  if a:kind ==# l:here && !(a:0 && !empty(a:1))
    if a:kind ==# 'gui' | return 1 | endif
    call gnosis#run#focus(getpid(), $WINDOWID)
    return 1
  endif
  for l:r in gnosis#run#list(a:kind)
    let l:meta = gnosis#home#read_json(l:r.file, {})
    let l:v = substitute(fnamemodify(get(l:meta, 'vault', ''), ':p'), '[/\\]$', '', '')
    if l:v !=# l:root | continue | endif
    if a:0 && !empty(a:1)
      " 起動画面の g: 選んだ vault の既存GUIを出すだけ。起動画面の状態は渡さない。
      let l:path = gnosis#run#dir() . '/handoff-' . getpid() . '.json'
      call writefile([json_encode({'root': l:root, 'focusOnly': 1})], l:path)
    else
      let l:path = gnosis#run#export()
    endif
    call rename(l:path, gnosis#run#dir() . '/focus-' . a:kind . '-' . l:r.pid)
    return 1
  endfor
  if l:only_existing | return 0 | endif
  if a:kind ==# 'gui' | return 0 | endif
  let l:launcher = fnamemodify(g:gnosis_python, ':h:h') . '/bin/gnosis'
  let l:handoff = gnosis#run#export()
  let l:env = {'GNOSIS_VIMRC': empty($GNOSIS_VIMRC) ? $MYVIMRC : $GNOSIS_VIMRC, 'GNOSIS_TEST_SCRIPT': '', 'GNOSIS_SCAN_ONLY': '', 'GNOSIS_GUI_PORT': '', 'GNOSIS_FILE': '', 'GNOSIS_HANDOFF': l:handoff, 'GNOSIS_HOME': gnosis#home#dir(), 'GNOSIS_PARENT_PID': ''}
  let l:args = ['--cmd', 'let g:gnosis_start_screen = 0', '--cmd', 'let g:gnosis_root = ' . string(l:root . '/')]
  if has('win32')
    let l:cmd = ['cmd.exe', '/c', 'start', '', fnamemodify(l:launcher, ':r') . '.cmd', '--tui'] + l:args
  else
    let l:cmd = [l:launcher, '--new-terminal'] + l:args
  endif
  call job_start(l:cmd, {'env': l:env, 'out_io': 'null', 'err_io': 'null', 'stoponexit': ''})
  return 1
endfunction
