" =============================================================================
" autoload/gnosis/session.vim — vault を使っているセッション（Vim・アプリ）の登録簿
"
" 複数のウィンドウで別々の vault（または同じ vault）を同時に開けるようにする。
" 暗号化 vault のロック（gocryptfs のアンマウント）は、その vault を使っている**最後の**
" セッションが終わるとき、または利用者が明示的に :GnosisLock! したときだけ行う。
" 別のウィンドウが使っている vault を、こちらの切り替えや終了で不意にロックしない。
"
"   <Gnosis ホーム>/sessions/<vault のパスのハッシュ>/<pid>.json   … 1 セッション 1 ファイル
"       {"pid": 1234, "start": "<プロセスの開始時刻>", "vault": "/path/to/note-root", "time": 1700000000}
"   <Gnosis ホーム>/sessions/<ハッシュ>/.lock/                      … 登録・解除・アンマウント判定の短い排他
"
" - vault ごとに別のフォルダ・別のロック。異なる vault 同士は何も共有しない。
" - 登録簿は vault の外（Gnosis ホーム）に置く。暗号化 vault の中には何も書かない。
" - 異常終了したプロセスの登録は残らない: 読むたびに「その pid が生きているか・同じプロセスか
"   （pid の使い回し対策に開始時刻を照合）」を調べ、死んでいれば消す。排他のロックも古ければ回収する。
" =============================================================================

let s:mine = {}   " このプロセスが登録した vault: {キー: root}

function! s:sep() abort
  return has('win32') ? '\' : '/'
endfunction

function! s:norm(root) abort
  return substitute(fnamemodify(a:root, ':p'), '[\\/]\+$', '', '')
endfunction

function! s:key(root) abort
  " シンボリックリンク経由の別名でも同じ vault と分かるよう、実体のパスでキーを作る
  let l:r = s:norm(resolve(s:norm(a:root)))
  return strpart(sha256(has('win32') ? tolower(l:r) : l:r), 0, 16)
endfunction

function! gnosis#session#dir(root) abort
  return gnosis#home#path('sessions', s:key(a:root))
endfunction

function! s:pid_alive(pid) abort
  if a:pid <= 0
    return 0
  endif
  if isdirectory('/proc')
    return isdirectory('/proc/' . a:pid)
  endif
  if has('win32')
    return stridx(gnosis#sh#system('tasklist /FI "PID eq ' . a:pid . '" /NH'), string(a:pid)) >= 0
  endif
  call gnosis#sh#system('kill -0 ' . a:pid . ' 2>/dev/null')
  return gnosis#sh#error() == 0
endfunction

" プロセスの開始時刻（pid が使い回されていないかの照合用）。分からなければ ''。
function! s:proc_start(pid) abort
  let l:f = '/proc/' . a:pid . '/stat'
  if filereadable(l:f)
    try
      let l:s = readfile(l:f, '', 1)[0]
      " `pid (comm) state …`。comm は括弧つきで空白を含みうるので、最後の ')' のあとから数える（22 番目 = 開始時刻）
      return get(split(strpart(l:s, strridx(l:s, ')') + 2)), 19, '')
    catch
      return ''
    endtry
  endif
  if !has('win32') && executable('ps')
    return trim(gnosis#sh#system('ps -o lstart= -p ' . a:pid . ' 2>/dev/null'))
  endif
  return ''
endfunction

function! gnosis#session#alive(entry) abort
  let l:pid = type(get(a:entry, 'pid', 0)) == v:t_number ? a:entry.pid : 0
  if !s:pid_alive(l:pid)
    return 0
  endif
  let l:st = get(a:entry, 'start', '')
  if !empty(l:st)
    let l:now = s:proc_start(l:pid)
    if !empty(l:now) && l:now !=# l:st
      return 0   " 同じ pid が別のプロセスに使い回された
    endif
  endif
  return 1
endfunction

" ---- 短い排他（mkdir は原子的）。持ち主が死んで残ったロックは 30 秒たてば回収する。
function! s:lock(root) abort
  let l:d = gnosis#session#dir(a:root)
  silent! call mkdir(l:d, 'p')
  let l:lock = l:d . s:sep() . '.lock'
  for l:i in range(120)
    let l:ok = 0
    try
      call mkdir(l:lock)
      let l:ok = 1
    catch
    endtry
    if l:ok
      return l:lock
    endif
    let l:t = getftime(l:lock)
    if l:t > 0 && localtime() - l:t > 30
      silent! call delete(l:lock, 'd')
    endif
    execute 'sleep 50m'
  endfor
  return ''
endfunction

function! s:unlock(lock) abort
  if !empty(a:lock)
    silent! call delete(a:lock, 'd')
  endif
endfunction

function! s:file(root, pid) abort
  return gnosis#session#dir(a:root) . s:sep() . a:pid . '.json'
endfunction

function! s:write_self(root) abort
  let l:e = {'pid': getpid(), 'start': s:proc_start(getpid()), 'vault': s:norm(a:root), 'time': localtime()}
  let l:f = s:file(a:root, getpid())
  let l:tmp = l:f . '.tmp'
  call writefile([json_encode(l:e)], l:tmp, 'S')
  call rename(l:tmp, l:f)
endfunction

" 自分をこの vault の使用者として登録する（何度呼んでもよい）。排他の中で行うので、別のセッションが
" 「最後の 1 人」としてアンマウントしている最中なら、それが終わるまで待ってから登録する。
function! gnosis#session#register(root) abort
  if empty(a:root)
    return 0
  endif
  let l:lock = s:lock(a:root)
  try
    call s:write_self(a:root)
    let s:mine[s:key(a:root)] = s:norm(a:root)
  catch
    return 0
  finally
    call s:unlock(l:lock)
  endtry
  return 1
endfunction

" この vault を使っている、自分以外の生きているセッション（死んだものの登録は消す）
function! gnosis#session#others(root) abort
  let l:out = []
  if empty(a:root)
    return l:out
  endif
  let l:d = gnosis#session#dir(a:root)
  if !isdirectory(l:d)
    return l:out
  endif
  for l:f in glob(l:d . s:sep() . '*.json', 1, 1)
    let l:e = {}
    try
      let l:e = json_decode(join(readfile(l:f), "\n"))
    catch
    endtry
    if type(l:e) != v:t_dict || empty(l:e)
      silent! call delete(l:f)
      continue
    endif
    if get(l:e, 'pid', 0) == getpid() && (empty(get(l:e, 'start', '')) || l:e.start ==# s:proc_start(getpid()))
      continue
    endif
    if gnosis#session#alive(l:e)
      call add(l:out, l:e)
    else
      silent! call delete(l:f)
    endif
  endfor
  return l:out
endfunction

" 自分が登録している vault の一覧（root のパス）
function! gnosis#session#mine() abort
  return values(s:mine)
endfunction

function! s:forget(root) abort
  silent! call delete(s:file(a:root, getpid()))
  silent! call remove(s:mine, s:key(a:root))
endfunction

" 自分の登録だけを外す（ロックはしない）
function! gnosis#session#unregister(root) abort
  if empty(a:root)
    return
  endif
  let l:lock = s:lock(a:root)
  try
    call s:forget(a:root)
  finally
    call s:unlock(l:lock)
  endtry
endfunction

" 自分の登録を外し、他のセッションが残っていなければ a:Last を呼ぶ（アンマウントなど）。
" 外すところから a:Last が終わるまでを 1 つの排他の中で行うので、判定とアンマウントのあいだに
" 別のセッションが入り込んでも、使用中の vault を切られない。
" 戻り値: {'last': 自分が最後だったか, 'others': 残っている他のセッション}
function! gnosis#session#release(root, Last) abort
  let l:lock = s:lock(a:root)
  try
    call s:forget(a:root)
    let l:others = gnosis#session#others(a:root)
    if empty(l:others)
      call a:Last()
      return {'last': 1, 'others': []}
    endif
    return {'last': 0, 'others': l:others}
  finally
    call s:unlock(l:lock)
  endtry
endfunction
