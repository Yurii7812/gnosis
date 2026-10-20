
" ---------------------------------------------------------
" 文字コード
" ---------------------------------------------------------
set encoding=utf-8
set fileencoding=utf-8
set fileencodings=utf-8,euc-jp,sjis,cp932
set fileformats=unix,dos,mac

filetype plugin indent on
syntax on

" =========================================================
" 表示
" =========================================================
set number
set wrap
set linebreak
set breakindent
set showmatch
set matchtime=1
set laststatus=2

" =========================================================
" 検索
" =========================================================
set ignorecase
set smartcase
set incsearch
set hlsearch
" viminfo が前回のハイライト状態を復元して、開くたびに同じ語が光るのを防ぐ
set viminfo^=h

" =========================================================
" インデント
" =========================================================
set autoindent
set smartindent
set expandtab
set tabstop=2
set shiftwidth=2

" =========================================================
" クリップボード
" =========================================================
" Vim の +/* レジスタ（XWayland 側）は使わない。大きなヤンクを XWayland の
" クリップボードブリッジに通すと KWin / Klipper ごと固まることがあるため。
" システムクリップボードとの受け渡しは wl-copy / wl-paste（SYN 連携）で行う。
if exists('g:gnosis_wsl_use_system_clipboard') && g:gnosis_wsl_use_system_clipboard
  set clipboard=unnamedplus
else
  set clipboard=
endif

inoremap <C-v> <C-r><C-o>=gnosis#clipboard_paste()<CR>
vnoremap <C-v> "_d<Cmd>call gnosis#paste_clipboard('P')<CR>
nnoremap <C-v> <Cmd>call gnosis#paste_clipboard('p')<CR>
vnoremap <C-c> y


" =========================================================
" WSL パフォーマンス調整
" =========================================================
if has('wsl')
  " Windows クリップボード同期は Insert 中の体感遅延を起こしやすいので既定OFF
  let g:gnosis_wsl_use_system_clipboard = get(g:, 'gnosis_wsl_use_system_clipboard', 0)
  if !g:gnosis_wsl_use_system_clipboard
    set clipboard=
  endif

  " 入力中イベントの発火頻度を下げる
  set updatetime=500
  set timeoutlen=500
  set ttimeoutlen=10
endif

" =========================================================
" 移動
" =========================================================
nnoremap j gj
nnoremap k gk
nnoremap <Up> gk
nnoremap <Down> gj
" <C-o> は InsertLeave/InsertLeavePre を発火するため、fcitx の自動 OFF
" (InsertLeavePre → fcitx5-remote -c) が走り、日本語入力が終わってしまう。
" 挿入モードのまま画面行を移動できる <C-g><Up>/<C-g><Down> を使う。
" <C-g><Up>/<C-g><Down> は論理行単位（折り返した行をひとまとまりで動く）なので、
" 画面行（折り返した行を 1 行ずつ）で動く関数を <Cmd> で呼ぶ。<Cmd> は挿入モードを
" 抜けないので InsertLeave も発火せず、IME は維持される。
function! s:insert_screen_move(down) abort
  let l:ve = &virtualedit
  set virtualedit=onemore
  try
    execute 'normal! ' . (a:down ? 'gj' : 'gk')
  finally
    let &virtualedit = l:ve
  endtry
endfunction
inoremap <silent> <Up> <Cmd>call <SID>insert_screen_move(0)<CR>
inoremap <silent> <Down> <Cmd>call <SID>insert_screen_move(1)<CR>

" =========================================================
" 設定編集
" =========================================================
" 固定パスに依存させない。必要な場合だけ .vimrc 側で
"   let g:gnosis_vimrc = expand('~/.vimrc')
" のように指定する。
if exists('g:gnosis_vimrc') && !empty(trim(get(g:, "gnosis_vimrc", "")))
  execute "nnoremap <silent> <leader>ev :edit " . fnameescape(expand(g:gnosis_vimrc)) . "<CR>"
  execute "nnoremap <silent> <leader>sv :source " . fnameescape(expand(g:gnosis_vimrc)) . "<CR>"
endif

" =========================================================
" Gnosis 見た目設定
" =========================================================
" リンクの色はテーマ（autoload/gnosis/theme.vim）が g:gnosis_link_color_* に入れる。

" =========================================================
" 自作プラグイン
" =========================================================

set backspace=indent,eol,start


" WSL かどうかを Vim/Neovim のビルドに依存せず判定する。
" has('wsl') を持たない Vim でも WSL_DISTRO_NAME / /proc から判定できる。
function! s:is_wsl() abort
  if has('wsl') || exists('$WSL_DISTRO_NAME') || exists('$WSL_INTEROP')
    return 1
  endif
  if filereadable('/proc/sys/kernel/osrelease')
    return join(readfile('/proc/sys/kernel/osrelease'), '') =~? 'microsoft\|wsl'
  endif
  return 0
endfunction

" Windows 側のブラウザに渡す file URI を作る。cmd.exe のメタ文字も
" URI エンコードし、空白や & を含むパスでも start の解釈を壊さない。
function! s:windows_file_uri(path) abort
  let l:uri = substitute(a:path, '\\', '/', 'g')
  let l:uri = substitute(l:uri, '%', '%25', 'g')
  let l:uri = substitute(l:uri, ' ', '%20', 'g')
  let l:uri = substitute(l:uri, '#', '%23', 'g')
  let l:uri = substitute(l:uri, '&', '%26', 'g')
  let l:uri = substitute(l:uri, '?', '%3F', 'g')
  return 'file:///' . l:uri
endfunction

" 外部コマンドを端末に縛られず起動する（Vim 終了時に巻き込まれないよう
" job_start を使う。無ければ shell のバックグラウンド）。
function! s:spawn(cmd) abort
  if has('job') && has('channel')
    call job_start(a:cmd, {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
  else
    call gnosis#sh#system(join(map(copy(a:cmd), 'shellescape(v:val)'), ' ') . ' >/dev/null 2>&1 &')
  endif
endfunction

" 開く対象（URL / ファイル）の既定アプリの desktop ファイル名（拡張子なし）を返す。
function! s:app_base_for(path_or_url) abort
  if a:path_or_url =~? '^https\?://'
    let l:df = trim(gnosis#sh#system('xdg-settings get default-web-browser 2>/dev/null'))
  else
    let l:mime = trim(gnosis#sh#system('xdg-mime query filetype ' . shellescape(a:path_or_url) . ' 2>/dev/null'))
    let l:df = l:mime =~# '/' ? trim(gnosis#sh#system('xdg-mime query default ' . shellescape(l:mime) . ' 2>/dev/null')) : ''
  endif
  return substitute(l:df, '\.desktop$', '', '')
endfunction

" KWin スクリプトで、指定 desktop 名に一致するウィンドウを前面化（アクティブ化）する。
" 既にアプリが起動していて新規タブが裏で開くだけ、という場合でも前面に出す。
function! s:activate_app_window(base) abort
  if empty(a:base) || !executable('qdbus6') || $XDG_SESSION_TYPE !=# 'wayland'
    return
  endif
  let l:dir = gnosis#home#path('state')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  let l:js = l:dir . '/activate_window.js'
  let l:target = tolower(a:base)
  call writefile([
        \ 'var t = ' . string(l:target) . ';',
        \ 'var wins = (typeof workspace.windowList === "function") ? workspace.windowList() : workspace.clientList();',
        \ 'for (var i = 0; i < wins.length; i++) {',
        \ '  var w = wins[i];',
        \ '  var rc = ("" + (w.resourceClass || "")).toLowerCase();',
        \ '  var df = ("" + (w.desktopFileName || "")).toLowerCase();',
        \ '  if ((rc && rc.indexOf(t) >= 0) || (df && df.indexOf(t) >= 0) || (rc && t.indexOf(rc) >= 0)) {',
        \ '    workspace.activeWindow = w; break;',
        \ '  }',
        \ '}',
        \ ], l:js)
  let l:name = 'gnosis_activate'
  call gnosis#sh#system('qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript ' . shellescape(l:js) . ' ' . l:name . ' >/dev/null 2>&1')
  call gnosis#sh#system('qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1')
  if has('timers')
    call timer_start(600, {-> gnosis#sh#system('qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript ' . l:name . ' >/dev/null 2>&1')})
  else
    call gnosis#sh#system('qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript ' . l:name . ' >/dev/null 2>&1')
  endif
endfunction

" 起動の直後にウィンドウを前面化（立ち上がりを待って数回試す）。
function! s:schedule_activate(base) abort
  if empty(a:base)
    return
  endif
  if has('timers')
    call timer_start(300, {-> s:activate_app_window(a:base)})
    call timer_start(1000, {-> s:activate_app_window(a:base)})
  else
    call s:activate_app_window(a:base)
  endif
endfunction

" 既定アプリで開く。WSL では Windows 側の既定ブラウザを使う。
function! s:open_with_default_app(path) abort
  let l:path = empty(a:path) ? expand('%:p') : a:path
  if empty(l:path)
    echohl WarningMsg | echom 'open-default: path is empty' | echohl None
    return
  endif

  if s:is_wsl()
    if executable('wslview')
      call s:spawn(['wslview', l:path])
      return
    endif

    if !executable('wslpath') || !executable('cmd.exe')
      echohl WarningMsg | echom 'open-default: wslview or Windows interop is required' | echohl None
      return
    endif

    let l:winpath = trim(gnosis#sh#system('wslpath -w ' . shellescape(l:path)))
    if gnosis#sh#error() != 0 || empty(l:winpath)
      echohl WarningMsg | echom 'open-default: failed to convert WSL path' | echohl None
      return
    endif
    let l:uri = s:windows_file_uri(l:winpath)
    call s:spawn(['cmd.exe', '/C', 'start', '', l:uri])
    return
  endif

  if has('win32')
    call s:spawn(['cmd.exe', '/C', 'start', '', l:path])
    return
  endif
  if has('mac') || has('macunix')
    call s:spawn(['open', l:path])
    return
  endif
  if executable('xdg-open')
    call s:spawn(['xdg-open', l:path])
  elseif executable('gio')
    call s:spawn(['gio', 'open', l:path])
  else
    echohl WarningMsg | echom gnosis#i18n#tr('open-default: xdg-open / gio が見つかりません') | echohl None
    return
  endif
  " 既にアプリが起動中で裏にタブが増えるだけのときも、前面に出す。
  call s:schedule_activate(s:app_base_for(l:path))
endfunction

" gm: 今開いているノートを既定アプリで開く。
" （カーソル下のリンクは見ない。行内にリンクがあるだけで別のノートが
"   開いてしまう事故を防ぐため、2026-10-04 にリンク追従を廃止した）
" 既定アプリ（.md → ブラウザ、.csv → LibreOffice 等）は disk を読むので、
" 未保存の変更があれば先に書き出してから開く。
function! s:open_current_note() abort
  call gnosis#save_current_note()
  call s:open_with_default_app(expand('%:p'))
endfunction

nnoremap <silent> gm :<C-u>call <SID>open_current_note()<CR>

" すべての変更済みバッファを保存するショートカット
nnoremap \w :wa<CR>
" UpdateAllのショート
nnoremap \ua :UpdateAll<CR>
" 画面の残像（前の画面の文字の重なり）を消す
nnoremap <silent> \r :redraw!<CR>

" 未保存の変更がある状態で別ファイルへ移動するときは、自動保存してから続行する
set autowriteall

" バックアップファイル無効化
set nobackup
set nowritebackup

" index を最初から開く処理は gnosis#startup_sequence() が行う
" （起動画面で Enter を押したあと。不要なら let g:gnosis_open_index_on_startup = 0）

" エラーを表示しない
autocmd FileType markdown highlight markdownError cterm=NONE gui=NONE
autocmd FileType markdown syntax clear markdownError
autocmd FileType markdown highlight link markdownError Normal
autocmd FileType markdown highlight link htmlError NONE
autocmd FileType markdown highlight htmlError cterm=NONE gui=NONE
autocmd FileType markdown syntax clear htmlError
autocmd FileType markdown highlight link htmlError Normal

" Rg検索のショートカット
nnoremap rg :Rg<CR>

" 配色: Gnosis のランチャー（vimrc_gnosis）で起動したときは、vault の設定のテーマ
" （gnosis#theme#apply）が決める。旧 simple-yurii-note の vimrc で起動したときだけ、
" Gnosis 組み込みの配色（colors/gnosis.vim）を使う。外部の配色プラグインは要らない。
if !get(g:, 'gnosis_managed', 0)
  if !exists('g:gnosis_link_color_gui')
    let g:gnosis_link_color_gui = '#2F6690'
    let g:gnosis_link_color_cterm = '24'
  endif
  set background=light
  silent! colorscheme gnosis
endif

" !系コマンドを常にsilentで実行
cmap <expr> <CR> getcmdtype() == ':' && getcmdline() =~ '^\s*!' ? '<C-\>e"silent " . getcmdline()<CR><CR>' : '<CR>'

function! s:RedrawAfterShell(...) abort
  redrawstatus
  redraw!
endfunction

function! s:ScheduleRedrawAfterShell() abort
  " ShellCmdPost can run before Vim has restored the terminal after :silent !.
  " Deferring the forced redraw prevents the shell's cleared screen from being
  " left visible, including when the command removes the current file.
  if exists('*timer_start')
    call timer_start(0, function('s:RedrawAfterShell'))
  else
    call s:RedrawAfterShell()
  endif
endfunction

" :! 系コマンドは silent 実行後に画面が再描画されないことがあるため、
" 端末復帰後に強制 redraw を既定で行います。特に :!rm % のように現在の
" ファイルを外部コマンドで削除した場合、端末の内容が黒いまま残るのを防ぎます。
" ちらつきが気になる場合は g:gnosis_redraw_after_silent_shell = 0 で無効化できます。
if get(g:, 'gnosis_redraw_after_silent_shell', 1)
  augroup gnosis_shell_redraw
    autocmd!
    autocmd ShellCmdPost * call s:ScheduleRedrawAfterShell()
  augroup END
elseif get(g:, 'gnosis_force_redraw_after_shell', 0)
  augroup gnosis_shell_redraw
    autocmd!
    autocmd ShellCmdPost * redraw
  augroup END
endif
