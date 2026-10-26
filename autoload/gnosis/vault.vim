" =============================================================================
" autoload/gnosis/vault.vim — vault の登録簿（Gnosis ホームの vaults.json）
"
"   {
"     "version": 1,
"     "last": "/path/to/vault",                    最後に選んだ vault
"     "vaults": [ {"path": "/path/to/vault", "name": "表示名"}, ... ]
"   }
"
" - 登録簿は vault の外（Gnosis ホーム）に置く。vault の中身は書き換えない。
" - 「一覧から外す」は登録簿から消すだけで、ノートやフォルダは消さない。
" - vault の「パス」は利用者が選んだフォルダ（A）。A/note があれば、ノートの root は
"   A/note（暗号化 vault の形）。設定は A/.gnosis/settings.json（gnosis#settings）。
" - 旧 simple-yurii-note の root.txt（~/.vim/simple_yurii_note/root.txt）があれば、
"   登録簿が無い最初の 1 回だけ取り込む（root.txt は消さない）。
" =============================================================================

function! s:sep() abort
  return has('win32') ? '\' : '/'
endfunction

function! gnosis#vault#file() abort
  return gnosis#home#path('vaults.json')
endfunction

" パスを絶対パスにし、末尾の区切りを外す
function! gnosis#vault#normalize(path) abort
  if empty(a:path)
    return ''
  endif
  let l:p = fnamemodify(expand(a:path), ':p')
  let l:p = substitute(l:p, '[\\/]\+$', '', '')
  if has('win32') && l:p =~# '^\a:$'
    let l:p .= '\'
  endif
  return empty(l:p) ? '/' : l:p
endfunction

function! gnosis#vault#same(a, b) abort
  let l:a = gnosis#vault#normalize(a:a)
  let l:b = gnosis#vault#normalize(a:b)
  return has('win32') ? l:a ==? l:b : l:a ==# l:b
endfunction

function! s:empty_registry() abort
  return {'version': 1, 'last': '', 'vaults': []}
endfunction

" 旧 root.txt の場所（stdpath が無い Vim では ~/.vim/simple_yurii_note）
function! gnosis#vault#legacy_root_file() abort
  let l:base = exists('*stdpath') ? stdpath('data') : expand('~/.vim')
  return l:base . s:sep() . 'simple_yurii_note' . s:sep() . 'root.txt'
endfunction

" ノートの root（A/note があれば A/note）から、登録する vault のパス（A）を求める
function! gnosis#vault#of_root(root) abort
  let l:r = gnosis#vault#normalize(a:root)
  if empty(l:r)
    return ''
  endif
  if fnamemodify(l:r, ':t') ==# 'note'
    let l:parent = fnamemodify(l:r, ':h')
    " 登録済みなら親（A）。暗号化 vault（A/.crypt）も A。
    for l:v in get(s:load_raw(), 'vaults', [])
      if gnosis#vault#same(l:v.path, l:parent)
        return l:v.path
      endif
    endfor
    if isdirectory(l:parent . s:sep() . '.crypt') || isdirectory(l:parent . s:sep() . '.gnosis')
      return l:parent
    endif
  endif
  return l:r
endfunction

" vault のパス（A）から、ノートの root（A/note があれば A/note）
function! gnosis#vault#note_root(path) abort
  let l:p = gnosis#vault#normalize(a:path)
  if empty(l:p)
    return ''
  endif
  if fnamemodify(l:p, ':t') !=# 'note' && isdirectory(l:p . s:sep() . 'note')
    return l:p . s:sep() . 'note'
  endif
  return l:p
endfunction

function! s:load_raw() abort
  return gnosis#home#read_json(gnosis#vault#file(), s:empty_registry())
endfunction

" 登録簿を読む。無ければ旧 root.txt から 1 回だけ取り込む。
function! gnosis#vault#load() abort
  let l:file = gnosis#vault#file()
  if !filereadable(l:file)
    let l:reg = s:empty_registry()
    let l:legacy = gnosis#vault#legacy_root_file()
    if filereadable(l:legacy) && !get(g:, 'gnosis_skip_legacy_import', 0)
      let l:root = trim(get(readfile(l:legacy), 0, ''))
      if !empty(l:root) && isdirectory(gnosis#vault#normalize(l:root))   " 消えた場所の vault は取り込まない
        let l:path = gnosis#vault#normalize(l:root)
        if fnamemodify(l:path, ':t') ==# 'note'
          let l:path = fnamemodify(l:path, ':h')
        endif
        call add(l:reg.vaults, {'path': l:path, 'name': fnamemodify(l:path, ':t')})
        let l:reg.last = l:path
        let l:reg.imported_from = l:legacy
        try
          call gnosis#home#write_json(l:file, l:reg)
        catch
        endtry
      endif
    endif
    return s:fix(l:reg)
  endif
  return s:fix(s:load_raw())
endfunction

function! s:fix(reg) abort
  let l:reg = a:reg
  if type(get(l:reg, 'vaults', 0)) != v:t_list
    let l:reg.vaults = []
  endif
  call filter(l:reg.vaults, 'type(v:val) == v:t_dict && !empty(get(v:val, "path", ""))')
  for l:v in l:reg.vaults
    if empty(get(l:v, 'name', ''))
      let l:v.name = fnamemodify(l:v.path, ':t')
    endif
  endfor
  if type(get(l:reg, 'last', '')) != v:t_string
    let l:reg.last = ''
  endif
  return l:reg
endfunction

function! gnosis#vault#save(reg) abort
  call gnosis#home#write_json(gnosis#vault#file(), a:reg)
endfunction

" 一覧: [{path, name, exists, last}]
function! gnosis#vault#list() abort
  let l:reg = gnosis#vault#load()
  let l:out = []
  for l:v in l:reg.vaults
    call add(l:out, {'path': l:v.path, 'name': l:v.name,
          \ 'exists': isdirectory(l:v.path),
          \ 'last': gnosis#vault#same(l:v.path, l:reg.last)})
  endfor
  return l:out
endfunction

" 最後に選んだ vault のパス（登録されていて、まだ一覧にあるもの）。無ければ ''。
function! gnosis#vault#last() abort
  let l:reg = gnosis#vault#load()
  for l:v in l:reg.vaults
    if gnosis#vault#same(l:v.path, l:reg.last)
      return l:v.path
    endif
  endfor
  return ''
endfunction

" 登録簿にある vault の項目（無ければ {}）
function! gnosis#vault#find(path) abort
  for l:v in gnosis#vault#load().vaults
    if gnosis#vault#same(l:v.path, a:path)
      return l:v
    endif
  endfor
  return {}
endfunction

" 既存のフォルダを登録する。フォルダが無ければエラー（勝手に作らない）。
" 戻り値: 登録したパス
function! gnosis#vault#add(path, ...) abort
  let l:p = gnosis#vault#normalize(a:path)
  if empty(l:p) || !isdirectory(l:p)
    throw 'gnosis-vault: ' . gnosis#i18n#t('vault.not_found', l:p)
  endif
  if fnamemodify(l:p, ':t') ==# 'note' && isdirectory(fnamemodify(l:p, ':h') . s:sep() . '.crypt')
    let l:p = fnamemodify(l:p, ':h')
  endif
  let l:reg = gnosis#vault#load()
  let l:name = a:0 && !empty(a:1) ? a:1 : fnamemodify(l:p, ':t')
  let l:found = 0
  for l:v in l:reg.vaults
    if gnosis#vault#same(l:v.path, l:p)
      let l:found = 1
      if a:0 && !empty(a:1)
        let l:v.name = a:1
      endif
    endif
  endfor
  if !l:found
    call add(l:reg.vaults, {'path': l:p, 'name': l:name})
  endif
  call gnosis#vault#save(l:reg)
  return l:p
endfunction

" 新しい vault を作る。フォルダが無ければ作る。既にノートがあるフォルダには作らない
" （既存のフォルダは「登録」を使う）。Index と操作ガイド、vault の設定を書く。
function! gnosis#vault#create(path, ...) abort
  let l:p = gnosis#vault#normalize(a:path)
  if empty(l:p)
    throw 'gnosis-vault: ' . gnosis#i18n#t('vault.path_empty')
  endif
  if isdirectory(l:p) && !empty(glob(l:p . s:sep() . '*.md', 1, 1))
    throw 'gnosis-vault: ' . gnosis#i18n#t('vault.create_has_notes', l:p)
  endif
  if filereadable(l:p)
    throw 'gnosis-vault: ' . gnosis#i18n#t('vault.not_dir', l:p)
  endif
  if !isdirectory(l:p)
    call mkdir(l:p, 'p')
  endif
  " 新しい vault の設定（言語は今の言語を引き継ぐ）
  let l:settings = gnosis#settings#defaults()
  let l:settings.language = gnosis#i18n#lang()
  call gnosis#settings#save(l:p, l:settings)
  call gnosis#create_vault_files(l:p)
  call gnosis#vault#add(l:p, a:0 ? a:1 : '')
  return l:p
endfunction

" 一覧から外す（登録簿から消すだけ。ノート・フォルダは消さない）
function! gnosis#vault#remove(path) abort
  let l:reg = gnosis#vault#load()
  let l:n = len(l:reg.vaults)
  call filter(l:reg.vaults, '!gnosis#vault#same(v:val.path, a:path)')
  if gnosis#vault#same(l:reg.last, a:path)
    let l:reg.last = ''
  endif
  call gnosis#vault#save(l:reg)
  return l:n != len(l:reg.vaults)
endfunction

" 最後に選んだ vault として覚える（登録されていなければ登録する）
function! gnosis#vault#select(path) abort
  let l:p = gnosis#vault#normalize(a:path)
  if empty(gnosis#vault#find(l:p))
    call gnosis#vault#add(l:p)
  endif
  let l:reg = gnosis#vault#load()
  let l:reg.last = l:p
  for l:v in l:reg.vaults
    if gnosis#vault#same(l:v.path, l:p)
      let l:reg.last = l:v.path
    endif
  endfor
  call gnosis#vault#save(l:reg)
  return l:reg.last
endfunction
