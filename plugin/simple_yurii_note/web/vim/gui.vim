" gui.vim — アプリ（Electron）の画面へ、Vim の状態を送る。
" アプリは Vim を擬似端末の中で動かし、このファイルを -S で読み込ませる。
" 状態（バッファの全行・カーソル・モード など）が変わるたびに、アプリが開いた TCP の
" ポート（$SYN_GUI_PORT）へ JSON を 1 行で送る。表示はアプリ側がマークダウンの見た目で行う。
" 操作は一切ここでは行わない（キーは擬似端末から Vim にそのまま届く）。
if !exists('$SYN_GUI_PORT') || !has('channel')
  finish
endif

let s:ch = ch_open('127.0.0.1:' . $SYN_GUI_PORT, {'mode': 'raw', 'waittime': 3000})
if ch_status(s:ch) !=# 'open'
  finish
endif

" Esc を押したあと、Vim は続きのキー（矢印などのエスケープシーケンス）を待つ。端末アプリは
" 続きを一度に送ってくるので、待ち時間を短くして、Esc がすぐ効くようにする。
set ttimeout
set ttimeoutlen=20

let s:sent_key = ''
let s:last = ''

function! s:snapshot(force) abort
  if ch_status(s:ch) !=# 'open'
    return
  endif
  let l:m = mode(1)
  let l:d = {
        \ 'file': expand('%:p'),
        \ 'buf': bufnr('%'),
        \ 'mode': l:m,
        \ 'cur': [line('.'), col('.')],
        \ 'bt': &buftype,
        \ 'ft': &filetype,
        \ 'mod': &modified ? 1 : 0,
        \ 'popups': len(popup_list()),
        \ 'rows': &lines,
        \ 'cols': &columns,
        \ 'cmdtype': getcmdtype(),
        \ }
  if l:m =~# '^[vV\x16sS\x13]'
    let l:p = getpos('v')
    let l:d.vis = [l:p[1], l:p[2]]
  endif
  " 仮想テキスト（テキストプロパティ）: リンクの数字のしるしなど。バッファの文字ではないので別に送る。
  let l:vt = []
  if has('textprop') && &buftype ==# ''
    for l:p in prop_list(1, {'end_lnum': line('$')})
      if has_key(l:p, 'text')
        call add(l:vt, [l:p.lnum, l:p.col, l:p.text, l:p.type])
      endif
    endfor
  endif
  let l:d.vtext = l:vt
  " 全行は、バッファか内容が変わったときだけ送る
  let l:key = bufnr('%') . ':' . b:changedtick
  if a:force || l:key !=# s:sent_key
    let l:d.lines = getline(1, '$')
    let s:sent_key = l:key
  endif
  let l:json = json_encode(l:d)
  " 同じ内容（カーソルも含め）は送らない
  let l:cmp = has_key(l:d, 'lines') ? '' : l:json
  if l:cmp !=# '' && l:cmp ==# s:last
    return
  endif
  let s:last = l:cmp
  call ch_sendraw(s:ch, l:json . "\n")
endfunction

function! s:push() abort
  call s:snapshot(0)
endfunction

function! s:push_force() abort
  call s:snapshot(1)
endfunction

function! s:tick(t) abort
  call s:snapshot(0)
endfunction

augroup syn_gui
  autocmd!
  autocmd TextChanged,TextChangedI,TextChangedP,CursorMoved,CursorMovedI,InsertEnter,InsertLeave,CmdlineEnter,CmdlineLeave,WinEnter,BufEnter,FocusGained * call s:push()
  autocmd BufEnter,BufWinEnter,VimResized,TerminalOpen,TerminalWinOpen * call s:push_force()
  if exists('##ModeChanged')
    autocmd ModeChanged * call s:push()
  endif
augroup END

" 取りこぼし（ポップアップ・確認の待ち・端末ジョブなど）を拾う保険
call timer_start(120, function('s:tick'), {'repeat': -1})
call s:push_force()
