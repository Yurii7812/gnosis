" =============================================================================
" autoload/gnosis/conflict.vim — 同じノートを複数のウィンドウ・プロセスで同時に編集したときの上書き防止
"
" 別のウィンドウ（や同期）が、このバッファを読んだあとに同じノートのファイルを書き換えたら、
"   - 自動保存はそのファイルを上書きしない（相手の変更を黙って消さない）
"   - このバッファの未保存の内容を <vault>/.state/conflicts/ に退避して、警告する
"   - 未保存の変更は読み直しで失わない（以前は FileChangedShell が常に reload にしていた）
" 利用者が :w で保存するときは Vim 自身の確認（変更されています。上書きしますか）が出る。
" =============================================================================

function! s:disk_state(path) abort
  return [getftime(a:path), getfsize(a:path)]
endfunction

function! s:path_of(buf) abort
  return fnamemodify(bufname(a:buf), ':p')
endfunction

" バッファを読んだ・書いた直後のファイルの状態を覚える（BufReadPost / BufWritePost / 読み直し後）。
" a:1 … バッファ番号（省略時は今のバッファ。FileChangedShell 系のイベントは <abuf> を渡す）
function! gnosis#conflict#record(...) abort
  let l:buf = a:0 && !empty(a:1) ? str2nr(a:1) : bufnr('%')
  let l:p = s:path_of(l:buf)
  if empty(bufname(l:buf)) || getbufvar(l:buf, '&buftype') !=# ''
    return
  endif
  call setbufvar(l:buf, 'gnosis_disk', s:disk_state(l:p))
  call setbufvar(l:buf, 'gnosis_conflict', [])
  " 読んだ・書いたときの中身（外の変更が同期の振った Folgezettel の番号だけかを見分けるのに使う）
  call setbufvar(l:buf, 'gnosis_disk_lines', filereadable(l:p) && l:p =~? '\.md$' ? readfile(l:p) : [])
endfunction

let s:id_pat = '^folgezettel\s*:'
let s:merge_py = expand('<sfile>:p:h:h:h') . '/python/merge3.py'

" 外の変更（同期が書いた BackLink: や番号など）と、このバッファの未保存の編集が、別々の場所の変更なら、
" 両方を取り込んだ行を返す（最後に読んだ・書いた内容を元にした 3 者マージ）。同じ場所を変えていたら v:null。
" これで「別のウィンドウが書き換えました。:e! …」の警告を出さずに済む
function! s:merged_lines(buf) abort
  let l:base = getbufvar(a:buf, 'gnosis_disk_lines', [])
  let l:p = s:path_of(a:buf)
  if empty(l:base) || !filereadable(l:p) || l:p !~? '\.md$' || !filereadable(s:merge_py)
    return v:null
  endif
  let l:dir = tempname()
  try
    call mkdir(l:dir, 'p')
    call writefile(l:base, l:dir . '/base')
    call writefile(getbufline(a:buf, 1, '$'), l:dir . '/ours')
    call writefile(readfile(l:p), l:dir . '/theirs')
    call gnosis#sh#system(join(map([gnosis#python_cmd(), s:merge_py, l:dir . '/base', l:dir . '/ours', l:dir . '/theirs', l:dir . '/out'], 'shellescape(v:val)'), ' '))
    if gnosis#sh#error() || !filereadable(l:dir . '/out')
      return v:null
    endif
    return readfile(l:dir . '/out')
  catch
    return v:null
  finally
    silent! call delete(l:dir, 'rf')
  endtry
endfunction

" front matter の folgezettel: の行を除いた行（なければそのまま）
function! s:without_id(lines) abort
  let l:lines = copy(a:lines)
  if get(l:lines, 0, '') ==# '---'
    let l:end = index(l:lines, '---', 1)
    if l:end > 0
      let l:at = match(l:lines[: l:end], s:id_pat)
      if l:at > 0
        call remove(l:lines, l:at)
      endif
    endif
  endif
  return l:lines
endfunction

" 外での変更が、同期が振った Folgezettel の番号（front matter の folgezettel: の行）だけなら、その行（無ければ ''）を返す。
" 中身が同じで更新時刻だけ変わった場合は v:false、ほかも変わっていれば v:null
function! s:id_only_change(buf) abort
  let l:base = getbufvar(a:buf, 'gnosis_disk_lines', [])
  let l:p = s:path_of(a:buf)
  if empty(l:base) || !filereadable(l:p)
    return v:null
  endif
  let l:disk = readfile(l:p)
  if l:disk ==# l:base
    return v:false
  endif
  if s:without_id(l:disk) !=# s:without_id(l:base)
    return v:null
  endif
  let l:end = index(l:disk, '---', 1)
  return get(filter(l:disk[: l:end], {i, v -> v =~# s:id_pat}), 0, '')
endfunction

" 今のバッファの front matter の folgezettel: の行を a:line にする（'' なら外す）
function! s:apply_id_line(lines, line) abort
  let l:lines = copy(a:lines)
  if get(l:lines, 0, '') !=# '---'
    return l:lines
  endif
  let l:end = index(l:lines, '---', 1)
  if l:end < 0
    return l:lines
  endif
  let l:at = match(l:lines[: l:end], s:id_pat)
  if l:at > 0
    if empty(a:line)
      call remove(l:lines, l:at)
    else
      let l:lines[l:at] = a:line
    endif
  elseif !empty(a:line)
    call insert(l:lines, a:line, l:end)
  endif
  return l:lines
endfunction

" 外の変更を取り込んだ行で保存する（:w! でも確認が出るので、いったん読み直してからバッファの内容を戻す）
function! s:rewrite_with(lines) abort
  let l:view = winsaveview()
  silent! edit!
  silent! keepjumps %delete _
  call setline(1, a:lines)
  call winrestview(l:view)
  silent! update
  return !&modified
endfunction

" 覚えた状態から、ファイルが他のプロセスに書き換えられていたら 1
function! gnosis#conflict#disk_changed(...) abort
  let l:buf = a:0 && !empty(a:1) ? str2nr(a:1) : bufnr('%')
  let l:p = s:path_of(l:buf)
  let l:rec = getbufvar(l:buf, 'gnosis_disk', [])
  if empty(bufname(l:buf)) || !filereadable(l:p) || empty(l:rec)
    return 0
  endif
  return s:disk_state(l:p) !=# l:rec
endfunction

function! s:backup(buf, lines) abort
  let l:root = get(g:, 'gnosis_root', '')
  if empty(l:root) || !isdirectory(l:root)
    return ''
  endif
  let l:dir = substitute(fnamemodify(l:root, ':p'), '[\\/]\+$', '', '') . '/.state/conflicts'
  try
    call mkdir(l:dir, 'p')
    let l:f = l:dir . '/' . strftime('%Y%m%d-%H%M%S') . '-' . getpid() . '-' . fnamemodify(bufname(a:buf), ':t')
    call writefile(a:lines, l:f)
    return l:f
  catch
    return ''
  endtry
endfunction

" 他で書き換えられていたとき: 未保存の内容を退避して警告する（同じ状態では 1 回だけ）。保存はしない。
function! gnosis#conflict#handle(...) abort
  let l:buf = a:0 && !empty(a:1) ? str2nr(a:1) : bufnr('%')
  let l:state = s:disk_state(s:path_of(l:buf))
  if getbufvar(l:buf, 'gnosis_conflict', []) ==# l:state
    return
  endif
  call setbufvar(l:buf, 'gnosis_conflict', l:state)
  let l:bak = s:backup(l:buf, getbufline(l:buf, 1, '$'))
  echohl WarningMsg
  echom 'Gnosis: ' . gnosis#i18n#t('conflict.warn', fnamemodify(bufname(l:buf), ':t'), empty(l:bak) ? '-' : l:bak)
  echohl NONE
endfunction

" 保存のたびに起動する自分の自動同期（update_one）が、このバッファのファイルを書き直す。
" それを「別のウィンドウの書き換え」と見なして警告しないよう、同期を起動したバッファに印を付ける。
" 同期は保存の直後だけでなく、少し遅れて書き直すこともある（待ち合わせのあとの再実行など）ので、
" 印は「最後に同期を起動・完了した時刻」で持ち、30 秒以内なら自分の同期とみなす。
function! gnosis#conflict#mark_own_sync(...) abort
  let l:buf = a:0 && !empty(a:1) ? str2nr(a:1) : bufnr('%')
  if l:buf > 0
    call setbufvar(l:buf, 'gnosis_own_sync', localtime())
  endif
endfunction

function! s:own_sync_recent(buf) abort
  let l:t = getbufvar(a:buf, 'gnosis_own_sync', 0)
  return l:t > 0 && localtime() - l:t <= 30
endfunction

" 自動保存・各操作の保存に使う update。他で書き換えられていたら書かない。書けたら 1
function! gnosis#conflict#safe_update() abort
  if !&modified
    return 0
  endif
  if gnosis#conflict#disk_changed()
    " 自分の同期の時刻印が切れた後でも、内容不変・番号だけの更新は競合ではない。
    " FileChangedShell と同じ判定を使い、番号と未保存の本文を両方残す。
    let l:id = s:id_only_change(bufnr('%'))
    if l:id isnot v:null
      if mode() =~# '^[iR]'
        return 0
      endif
      return s:rewrite_with(l:id is v:false ? getline(1, '$') : s:apply_id_line(getline(1, '$'), l:id))
    endif
    " 同期の書き換えと、未保存の編集が別々の場所なら、両方を取り込んで保存する（警告も出さない）
    let l:merged = s:merged_lines(bufnr('%'))
    if l:merged isnot v:null
      if mode() =~# '^[iR]'
        return 0
      endif
      return s:rewrite_with(l:merged)
    endif
    if s:own_sync_recent(bufnr('%'))
      " 自分の同期が整えた内容。次の保存でまた同期が走って整え直すので、バッファ側を優先して書く。
      " 挿入中は :edit できない。Esc で抜けたときの保存で改めて試す（黙って待つ）。
      if mode() =~# '^[iR]'
        return 0
      endif
      " Vim は :w! でも「読込んだ後に変更がありました」と確認するので、いったんディスクの
      " 状態を読み直して（Vim の覚えている更新時刻を合わせて）から、バッファの内容を戻して保存する。
      let l:lines = getline(1, '$')
      let l:view = winsaveview()
      silent! edit!
      silent! keepjumps %delete _
      call setline(1, l:lines)
      call winrestview(l:view)
      silent! update
      return !&modified
    endif
    call gnosis#conflict#handle()
    return 0
  endif
  silent! update
  return !&modified
endfunction

" FileChangedShell: ファイルが外で変わった。未保存の変更が無ければ読み直し（今までどおり）。
" 未保存の変更があるとき（reason が conflict）は読み直さず、退避して警告する（変更を失わない）。
function! gnosis#conflict#on_changed_shell() abort
  let l:buf = str2nr(expand('<abuf>'))
  if s:own_sync_recent(l:buf) && (v:fcs_reason ==# 'conflict' || getbufvar(l:buf, '&modified'))
    let v:fcs_choice = ''
    return
  endif
  if v:fcs_reason ==# 'conflict' || (v:fcs_reason ==# 'changed' && getbufvar(l:buf, '&modified'))
    let v:fcs_choice = ''
    " 保存時は番号だけの同期を取り込めるので、外部変更の通知でも同じ扱いにする。
    " ここでは読み直さず、未保存の本文と比較元を次の保存まで残す。
    if s:id_only_change(l:buf) isnot v:null
      return
    endif
    " 別々の場所の変更なら、次の保存で両方を取り込む。警告は出さない
    if s:merged_lines(l:buf) isnot v:null
      return
    endif
    call gnosis#conflict#handle(l:buf)
    return
  endif
  let v:fcs_choice = 'reload'
endfunction
