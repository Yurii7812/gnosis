" gui.vim — Gnosis のアプリ（Electron）の画面へ、Vim の状態を送る。
" アプリは Vim を擬似端末の中で動かし、このファイルを -S で読み込ませる。
" 状態（バッファの全行・カーソル・モード など）が変わるたびに、アプリが開いた TCP の
" ポート（$GNOSIS_GUI_PORT）へ JSON を 1 行で送る。表示はアプリ側がマークダウンの見た目で行う。
" 操作は一切ここでは行わない（キーは擬似端末から Vim にそのまま届く）。
if !exists('$GNOSIS_GUI_PORT') || !has('channel')
  finish
endif

" アプリからの知らせ（1 行 1 つの JSON）。受け付けるのは決まった種類だけ:
"   {"type": "settings", "vault": パス} … 設定画面で保存された vault の設定を読み直す
let s:inbuf = ''
function! s:on_msg(ch, msg) abort
  let s:inbuf .= a:msg
  while stridx(s:inbuf, "\n") >= 0
    let l:i = stridx(s:inbuf, "\n")
    let l:line = strpart(s:inbuf, 0, l:i)
    let s:inbuf = strpart(s:inbuf, l:i + 1)
    try
      let l:m = json_decode(l:line)
    catch
      continue
    endtry
    if type(l:m) == v:t_dict && get(l:m, 'type', '') ==# 'settings' && type(get(l:m, 'vault', 0)) == v:t_string
      call gnosis#settings#activate(l:m.vault)
      redraw!
      call s:snapshot(1)
    endif
  endwhile
endfunction

let s:ch = ch_open('127.0.0.1:' . $GNOSIS_GUI_PORT, {'mode': 'raw', 'waittime': 3000, 'callback': function('s:on_msg')})
if ch_status(s:ch) !=# 'open'
  finish
endif

" Esc を押したあと、Vim は続きのキー（矢印などのエスケープシーケンス）を待つ。端末アプリは
" 続きを一度に送ってくるので、待ち時間を短くして、Esc がすぐ効くようにする。
set ttimeout
set ttimeoutlen=20

" 最初に開くノート（$GNOSIS_FILE）。Gnosis は起動時に Index を開き直すので、起動が済んだあとで開く。
function! s:open_start_file(t) abort
  let l:f = fnamemodify($GNOSIS_FILE, ':p')
  if filereadable(l:f) && fnamemodify(expand('%:p'), ':p') !=# l:f
    execute 'silent! edit ' . fnameescape(l:f)
  endif
endfunction
if $GNOSIS_FILE !=# ''
  autocmd VimEnter * ++once call timer_start(400, function('s:open_start_file'))
endif

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
  " ポップアップの位置（端末の桁・行、1 始まり）。アプリは背景の表示を変えず、ここだけ端末を重ねる。
  let l:pp = []
  for l:id in popup_list()
    let l:g = popup_getpos(l:id)
    if !empty(l:g) && get(l:g, 'visible', 0)
      call add(l:pp, [l:g.col, l:g.line, l:g.width, l:g.height])
    endif
  endfor
  let l:d.popuppos = l:pp
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
  " 配色（テーマ）・文字サイズ・vault: 変わったときだけ送る
  try
    let l:look = {'palette': get(g:, 'gnosis_palette', {}), 'fontSize': get(gnosis#settings#current(), 'fontSize', 16),
          \ 'vault': get(g:, 'gnosis_active_vault', ''), 'lang': gnosis#i18n#lang()}
  catch
    let l:look = {'palette': get(g:, 'gnosis_palette', {})}
  endtry
  if a:force || l:look !=# get(s:, 'sent_look', {})
    call extend(l:d, l:look)
    let s:sent_look = l:look
  endif
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
