" =============================================================================
" autoload/gnosis/home.vim — Gnosis ホーム（Gnosis 側で管理する状態の置き場所）
"
" vault の外に置く、Gnosis 自身の状態:
"   vaults.json   登録済みの vault と、最後に選んだ vault
"   plugins/      Gnosis 専用の Vim プラグイン（fzf / fzf.vim / vim-surround など）
"   themes/       設定画面から追加したテーマ（GitHub のリポジトリ）
"   state/        vault が決まる前の一時的な状態（viminfo など）
"   logs/         アプリのログ
" Git 管理下のソース（Gnosis 本体のフォルダ）には書かない。
"
" 場所の決め方（上ほど優先）:
"   1. $GNOSIS_HOME
"   2. g:gnosis_home
"   3. OS ごとの既定
"        Linux など  $XDG_DATA_HOME/gnosis（既定 ~/.local/share/gnosis）
"        macOS       ~/Library/Application Support/Gnosis
"        Windows     %APPDATA%\Gnosis
" =============================================================================

function! gnosis#home#dir() abort
  if !empty($GNOSIS_HOME)
    return s:strip(fnamemodify(expand($GNOSIS_HOME), ':p'))
  endif
  if !empty(get(g:, 'gnosis_home', ''))
    return s:strip(fnamemodify(expand(g:gnosis_home), ':p'))
  endif
  if has('win32')
    let l:base = !empty($APPDATA) ? $APPDATA : expand('~/AppData/Roaming')
    return s:strip(l:base) . '\Gnosis'
  endif
  if has('mac') || has('macunix')
    return expand('~/Library/Application Support/Gnosis')
  endif
  let l:base = !empty($XDG_DATA_HOME) ? $XDG_DATA_HOME : expand('~/.local/share')
  return s:strip(l:base) . '/gnosis'
endfunction

function! s:strip(p) abort
  return substitute(a:p, '[\\/]\+$', '', '')
endfunction

function! s:sep() abort
  return has('win32') ? '\' : '/'
endfunction

" Gnosis ホームの下のパス（作らない）
function! gnosis#home#path(...) abort
  let l:p = gnosis#home#dir()
  for l:part in a:000
    let l:p .= s:sep() . l:part
  endfor
  return l:p
endfunction

" Gnosis ホームと、よく使う下のフォルダを作る。
function! gnosis#home#init() abort
  for l:d in ['', 'plugins', 'themes', 'state', 'pack']
    let l:p = empty(l:d) ? gnosis#home#dir() : gnosis#home#path(l:d)
    if !isdirectory(l:p)
      try
        call mkdir(l:p, 'p')
      catch
      endtry
    endif
  endfor
endfunction

" Gnosis 専用のプラグイン（plugins/*）。インストーラーが入れる。
" 移行中の利用者のために、旧 simple-yurii-note の専用領域（~/.vim-simple-yurii-note）に
" 同じプラグインがあれば、それを読むだけで使う（そこへは書かない）。
function! gnosis#home#plugin_dirs() abort
  let l:dirs = []
  let l:names = {}
  for l:d in glob(gnosis#home#path('plugins', '*'), 1, 1)
    if isdirectory(l:d)
      call add(l:dirs, l:d)
      let l:names[fnamemodify(l:d, ':t')] = 1
    endif
  endfor
  let l:legacy = expand('~/.vim-simple-yurii-note')
  if get(g:, 'gnosis_use_legacy_plugins', 1) && isdirectory(l:legacy)
    for l:name in ['fzf', 'fzf.vim', 'vim-surround']
      let l:d = l:legacy . s:sep() . l:name
      if !has_key(l:names, l:name) && isdirectory(l:d)
        call add(l:dirs, l:d)
      endif
    endfor
  endif
  " テーマ（themes/*）も runtimepath に入れる（colors/ を見つけるため）
  for l:d in glob(gnosis#home#path('themes', '*'), 1, 1)
    if isdirectory(l:d)
      call add(l:dirs, l:d)
    endif
  endfor
  return l:dirs
endfunction

" fzf の実行ファイルが PATH に無ければ、プラグイン領域の fzf/bin を PATH に足す。
function! gnosis#home#ensure_fzf_path() abort
  if executable('fzf')
    return
  endif
  for l:d in gnosis#home#plugin_dirs()
    if fnamemodify(l:d, ':t') ==# 'fzf'
      let l:bin = l:d . s:sep() . 'bin'
      if executable(l:bin . s:sep() . (has('win32') ? 'fzf.exe' : 'fzf'))
        let $PATH = l:bin . (has('win32') ? ';' : ':') . $PATH
        return
      endif
    endif
  endfor
endfunction

" 起動時の viminfo の場所。前回の vault の .state/viminfo（vault の中に置き、暗号化 vault では
" いっしょに暗号化される）。vault が無ければ Gnosis ホームの state/viminfo。
" ロック中の暗号化 vault（マウント前）は読めないが、マウント後にプラグインが読み直す。
function! gnosis#home#setup_viminfo() abort
  let l:root = gnosis#vault#note_root(gnosis#vault#last())
  " 消した vault の場所には viminfo を置かない（フォルダを作り直さない）
  if !empty(l:root) && isdirectory(l:root)
    execute 'set viminfofile=' . fnameescape(l:root . s:sep() . '.state' . s:sep() . 'viminfo')
  else
    execute 'set viminfofile=' . fnameescape(gnosis#home#path('state', 'viminfo'))
  endif
endfunction

" JSON ファイルを読む（無い・壊れているときは a:default）
function! gnosis#home#read_json(path, default) abort
  if !filereadable(a:path)
    return a:default
  endif
  try
    let l:v = json_decode(join(readfile(a:path), "\n"))
    return type(l:v) == type(a:default) ? l:v : a:default
  catch
    return a:default
  endtry
endfunction

" JSON ファイルを書く（一時ファイルに書いてから置き換える）
function! gnosis#home#write_json(path, value) abort
  let l:dir = fnamemodify(a:path, ':h')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  let l:tmp = a:path . '.tmp'
  call writefile(split(gnosis#home#json_pretty(a:value), "\n"), l:tmp)
  if rename(l:tmp, a:path) != 0
    call writefile(split(gnosis#home#json_pretty(a:value), "\n"), a:path)
    call delete(l:tmp)
  endif
endfunction

" 人が読みやすい JSON（2 段インデント）。json_encode は 1 行なので整形する。
function! gnosis#home#json_pretty(v, ...) abort
  let l:ind = a:0 ? a:1 : ''
  let l:t = type(a:v)
  if l:t == v:t_dict
    if empty(a:v)
      return '{}'
    endif
    let l:items = []
    for l:k in sort(keys(a:v))
      call add(l:items, l:ind . '  ' . json_encode(l:k) . ': ' . gnosis#home#json_pretty(a:v[l:k], l:ind . '  '))
    endfor
    return "{\n" . join(l:items, ",\n") . "\n" . l:ind . '}'
  elseif l:t == v:t_list
    if empty(a:v)
      return '[]'
    endif
    let l:items = []
    for l:x in a:v
      call add(l:items, l:ind . '  ' . gnosis#home#json_pretty(l:x, l:ind . '  '))
    endfor
    return "[\n" . join(l:items, ",\n") . "\n" . l:ind . ']'
  endif
  return json_encode(a:v)
endfunction
