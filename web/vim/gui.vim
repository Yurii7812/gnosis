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
    elseif type(l:m) == v:t_dict && type(get(l:m, 'id', '')) == v:t_number
      call s:gui_command(l:m)
    endif
  endwhile
endfunction

" GUI 編集モード（アプリ）からの知らせ。どれも id つきで、終わったら {"ack": id, ...} を 1 行返す。
"   save   … 今のバッファに未保存の変更があれば、ふだんの保存（gnosis#save_current_note）をする
"   commit … GUI が編集した本文 text を file のバッファに入れて、ふだんの :write で保存する（保存時の処理が全部走る）
"            reload=1 なら先にディスクから読み直す（外の変更を取り込んでから上書きするとき）
"   open   … file を開く（ふだんのジャンプ履歴に積む）
"   reload … 外で変わったファイルを読み直す（GUI 編集から Vim に戻るとき）
function! s:ack(id, d) abort
  if ch_status(s:ch) ==# 'open'
    call ch_sendraw(s:ch, json_encode(extend({'ack': a:id}, a:d)) . "\n")
  endif
endfunction

function! s:same_file(a, b) abort
  return fnamemodify(a:a, ':p') ==# fnamemodify(a:b, ':p')
endfunction

function! s:gui_command(m) abort
  let l:t = get(a:m, 'type', '')
  let l:r = {'ok': 0, 'file': expand('%:p')}
  try
    if l:t ==# 'save'
      if &modified && &buftype ==# '' && !empty(expand('%:p'))
        silent! call gnosis#save_current_note()
      endif
      let l:r.ok = !&modified
    elseif l:t ==# 'commit' && type(get(a:m, 'file', 0)) == v:t_string && type(get(a:m, 'text', 0)) == v:t_string
      if !s:same_file(expand('%:p'), a:m.file)
        if &modified | throw 'unsaved changes in the current buffer' | endif
        execute 'silent! edit ' . fnameescape(a:m.file)
      endif
      if get(a:m, 'reload', 0) && !&modified
        silent! edit!
      endif
      if &modified | throw 'the buffer has unsaved changes' | endif
      let l:lines = split(a:m.text, "\n", 1)
      if len(l:lines) > 1 && l:lines[-1] ==# ''
        call remove(l:lines, -1)
      endif
      call setline(1, l:lines)
      if line('$') > len(l:lines)
        silent execute (len(l:lines) + 1) . ',$delete _'
      endif
      let v:errmsg = ''
      silent! write
      let l:r.ok = !&modified && empty(v:errmsg)
      if !l:r.ok | let l:r.error = v:errmsg | endif
    elseif l:t ==# 'open' && type(get(a:m, 'file', 0)) == v:t_string
      if &modified && &buftype ==# '' && !empty(expand('%:p'))
        silent! call gnosis#save_current_note()
      endif
      if !s:same_file(expand('%:p'), a:m.file)
        silent! call gnosis#push_history()
        execute 'silent! edit ' . fnameescape(a:m.file)
      endif
      let l:r.ok = s:same_file(expand('%:p'), a:m.file)
    elseif l:t ==# 'reload'
      silent! checktime
      if !&modified && &buftype ==# '' && !empty(expand('%:p')) && filereadable(expand('%:p'))
        let l:v = winsaveview()
        silent! edit
        call winrestview(l:v)
      endif
      let l:r.ok = 1
    endif
  catch
    let l:r.error = v:exception
  endtry
  let l:r.file = expand('%:p')
  let l:r.mod = &modified ? 1 : 0
  call s:ack(a:m.id, l:r)
  call s:snapshot(1)
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
  " 曼荼羅が開いているとき: アプリは曼荼羅を自分で描き、ノートはノートの窓（右）のバッファを映す
  " （曼荼羅の窓のバッファは罫線の文字なので、マークダウンとしては描けない）
  let l:ms = {}
  try
    let l:ms = gnosis#mview#gui_state()
  catch
  endtry
  let l:wid = win_getid()
  if !empty(l:ms)
    let l:wid = l:ms.noteWin > 0 ? l:ms.noteWin : -1
  endif
  let l:b = l:wid > 0 ? winbufnr(l:wid) : -1
  let l:cur = l:wid > 0 ? getcurpos(l:wid)[1 : 2] : [1, 1]
  let l:d = {
        \ 'file': l:b > 0 ? fnamemodify(bufname(l:b), ':p') : '',
        \ 'buf': l:b,
        \ 'mode': l:m,
        \ 'focus': empty(l:ms) ? 'note' : (win_getid() == l:ms.win ? 'mandala' : 'note'),
        \ 'copyStack': get(g:, 'gnosis_stack_copy_mode', 0),
        \ 'linkSource': l:b > 0 ? getbufvar(l:b, 'gnosis_link_source_on', 0) : 0,
        \ 'cur': l:cur,
        \ 'bt': l:b > 0 ? getbufvar(l:b, '&buftype') : '',
        \ 'ft': l:b > 0 ? getbufvar(l:b, '&filetype') : '',
        \ 'mod': l:b > 0 && getbufvar(l:b, '&modified') ? 1 : 0,
        \ 'popups': len(popup_list()),
        \ 'rows': &lines,
        \ 'cols': &columns,
        \ 'cmdtype': getcmdtype(),
        \ 'mandala': l:ms,
        \ 'scanReq': get(g:, 'gnosis_gui_scan_req', 0),
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
  if l:m =~# '^[vV\x16sS\x13]' && l:wid == win_getid()
    let l:p = getpos('v')
    let l:d.vis = [l:p[1], l:p[2]]
  endif
  " 仮想テキスト（テキストプロパティ）: リンクの数字のしるしなど。バッファの文字ではないので別に送る。
  let l:vt = []
  if has('textprop') && l:b > 0 && getbufvar(l:b, '&buftype') ==# ''
    for l:p in prop_list(1, {'bufnr': l:b, 'end_lnum': getbufinfo(l:b)[0].linecount})
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
  " 全行は、バッファか内容が変わったときだけ送る。隠す行（YAML・上下の「名前:」系）も、行が変わったときに一緒に送る
  let l:h = gnosis#hide#get()
  let l:key = l:b . ':' . (l:b > 0 ? getbufvar(l:b, 'changedtick') : 0) . ':' . (empty(l:ms) ? 0 : 1) . ':' . string(l:h)
  if a:force || l:key !=# s:sent_key
    let l:lines = l:b > 0 ? getbufline(l:b, 1, '$') : []
    let l:d.lines = l:lines
    let l:hide = []
    if l:b > 0 && getbufvar(l:b, '&buftype') ==# '' && fnamemodify(bufname(l:b), ':e') ==# 'md'
      for l:r in gnosis#hide#regions(l:lines)
        if l:h[l:r.kind]
          call add(l:hide, [l:r.from, l:r.to])
        endif
      endfor
    endif
    let l:d.hide = l:hide
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

" \F（紙のスキャンの番号付け）をアプリの画面で開く合図。gnosis#paper_scan が呼ぶ
function! GnosisGuiScan() abort
  let g:gnosis_gui_scan_req = get(g:, 'gnosis_gui_scan_req', 0) + 1
  call s:snapshot(1)
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
