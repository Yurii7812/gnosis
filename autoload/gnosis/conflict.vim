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
  call setbufvar(l:buf, 'gnosis_own_sync', 0)
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
function! gnosis#conflict#mark_own_sync(...) abort
  let l:buf = a:0 && !empty(a:1) ? str2nr(a:1) : bufnr('%')
  call setbufvar(l:buf, 'gnosis_own_sync', 1)
endfunction

" 自動保存・各操作の保存に使う update。他で書き換えられていたら書かない。書けたら 1
function! gnosis#conflict#safe_update() abort
  if !&modified
    return 0
  endif
  if gnosis#conflict#disk_changed()
    if get(b:, 'gnosis_own_sync', 0)
      " 自分の同期が整えた内容。次の保存でまた同期が走って整え直すので、バッファ側を優先して書く。
      " 挿入中は :edit できない。Esc で抜けたときの保存で改めて試す（黙って待つ）。
      if mode() =~# '^[iR]'
        return 0
      endif
      " Vim は :w! でも「読込んだ後に変更がありました」と確認するので、いったんディスクの
      " 状態を読み直して（Vim の覚えている更新時刻を合わせて）から、バッファの内容を戻して保存する。
      let l:lines = getline(1, '$')
      let l:view = winsaveview()
      let b:gnosis_own_sync = 0
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
  if getbufvar(l:buf, 'gnosis_own_sync', 0) && (v:fcs_reason ==# 'conflict' || getbufvar(l:buf, '&modified'))
    let v:fcs_choice = ''
    return
  endif
  if v:fcs_reason ==# 'conflict' || (v:fcs_reason ==# 'changed' && getbufvar(l:buf, '&modified'))
    let v:fcs_choice = ''
    call gnosis#conflict#handle(l:buf)
    return
  endif
  let v:fcs_choice = 'reload'
endfunction
