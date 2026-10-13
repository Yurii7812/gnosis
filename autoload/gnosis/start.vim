" =============================================================================
" autoload/gnosis/start.vim — 起動画面と vault の選択・管理（Vim 版）
"
" ふつうに起動したとき（ファイルを指定しないとき）、ノートを開く前に出す:
"   Chnoubis のシンボル（assets/chnoubis/*.txt の Unicode Braille）・「Gnosis」・
"   選択中の vault の名前とパス・「Enter で開始」・vault の選択と管理への入口。
" 配色は chnoubis3.sh の10番・夜空×水色（gnosis#theme#apply_start）。vault を開くと、その vault の
" 設定のテーマに切り替わる。
"
" 起動画面のキー:  Enter 開始 / v vault の一覧 / s 設定 / q 終了
" vault 一覧のキー: j k 移動 / Enter 選んで開始 / a 既存フォルダを登録 /
"                   n 新しい vault を作る / d 一覧から外す（ノートは消さない） / Esc 戻る
" 標準起動はターミナルの本物の Vim。
" =============================================================================

let s:art_dir = expand('<sfile>:p:h:h:h') . '/assets/chnoubis'
let s:active = 0
let s:mode = 'start'
let s:sel = 0
let s:message = ''

function! s:t(key, ...) abort
  return call('gnosis#i18n#t', [a:key] + a:000)
endfunction

function! gnosis#start#active() abort
  return s:active
endfunction

" 起動画面を出すか（ファイルを指定して起動したとき・アプリが自分の起動画面を出すときは出さない）
function! gnosis#start#should_show() abort
  if !get(g:, 'gnosis_start_screen', 1)
    return 0
  endif
  if argc() > 0 || !empty($GNOSIS_FILE) || !empty($PKM_FILE)
    return 0
  endif
  " Gnosis 専用 Vim では、前回の vault のルートがプラグイン初期化中に
  " g:gnosis_root へ復元される場合がある。これは「起動画面を省略する」
  " 指示ではない。画面を出さないのはファイル指定など明示的な場合だけ。
  " 旧 vimrc 統合環境では従来の root 指定による起動を維持する。
  if !get(g:, 'gnosis_managed', 0) && !empty(trim(get(g:, 'gnosis_root', '')))
    return 0
  endif
  " 標準入力からの読み込み（vim -）など、何かのバッファが既にあるとき
  if line('$') > 1 || !empty(getline(1)) || !empty(bufname('%'))
    return 0
  endif
  return 1
endfunction

" VimEnter: 起動画面を出すか、そのまま vault を開くか
function! gnosis#start#on_vim_enter() abort
  if gnosis#start#should_show()
    call gnosis#start#open()
  else
    call gnosis#startup_sequence()
  endif
endfunction

" アート（幅 a:width の行のリスト）。無ければ []
function! gnosis#start#art(width) abort
  let l:f = s:art_dir . '/chnoubis-' . a:width . '.txt'
  if !filereadable(l:f)
    return []
  endif
  let l:lines = readfile(l:f)
  while !empty(l:lines) && l:lines[-1] ==# ''
    call remove(l:lines, -1)
  endwhile
  return l:lines
endfunction

" 画面に収まる大きさのアートを選ぶ（大きいものから。下の情報欄の行数 a:reserve を残す）
function! gnosis#start#pick_art(cols, rows, reserve) abort
  for l:w in [80, 60, 44, 32]
    let l:art = gnosis#start#art(l:w)
    if empty(l:art)
      continue
    endif
    let l:aw = max(map(copy(l:art), 'strdisplaywidth(v:val)'))
    if l:aw + 2 <= a:cols && len(l:art) + a:reserve <= a:rows
      return l:art
    endif
  endfor
  return []
endfunction

" :GnosisVaults … vault の一覧から始める（使用中に vault を切り替える）
function! gnosis#start#open_vaults() abort
  call gnosis#start#open()
  let s:mode = 'vaults'
  call gnosis#start#render()
endfunction

function! gnosis#start#open() abort
  " 前回のルート文字列が残っているだけでは、使用中の vault とは扱わない。
  " VimEnter の初回起動と、実際に開いた vault からの切り替えを区別する。
  let s:had_vault = !empty(get(g:, 'gnosis_active_vault', '')) && !s:active
  let s:active = 1
  let s:mode = 'start'
  let s:message = ''
  call gnosis#settings#deactivate()
  call gnosis#theme#apply_start()
  enew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nonumber norelativenumber
  setlocal nocursorline nolist nowrap nospell nofoldenable colorcolumn= signcolumn=no
  setlocal filetype=gnosisstart
  silent! file Gnosis
  let b:gnosis_start = 1
  call s:map_keys()
  augroup gnosis_start_resize
    autocmd! * <buffer>
    autocmd VimResized <buffer> call gnosis#start#render()
  augroup END
  let l:reg = gnosis#vault#list()
  let s:sel = 0
  for l:i in range(len(l:reg))
    if l:reg[l:i].last
      let s:sel = l:i
    endif
  endfor
  " 初回起動も Chnoubis を見せる。Enter/v で vault の作成・登録へ進む。
  if empty(l:reg)
    let s:message = s:t('start.first_run')
  endif
  call gnosis#start#render()
endfunction

function! s:map_keys() abort
  for l:k in ['<CR>', 'v', 's', 'q', 'j', 'k', '<Down>', '<Up>', 'a', 'n', 'd', '<Esc>', 'r', 'l', '?']
    execute printf('nnoremap <buffer><silent><nowait> %s <Cmd>call gnosis#start#key(%s)<CR>', l:k, substitute(string(l:k), '<', '<lt>', 'g'))
  endfor
  " 文字の上で i や o などを押しても編集しない
  for l:k in ['i', 'I', 'o', 'O', 'A', 'x', 'p', 'P', 'c', 'C', 'u']
    execute 'nnoremap <buffer><silent><nowait> ' . l:k . ' <Nop>'
  endfor
  nnoremap <buffer><silent> <LeftMouse> <LeftMouse><Cmd>call gnosis#start#click()<CR>
  nnoremap <buffer><silent> <2-LeftMouse> <LeftMouse><Cmd>call gnosis#start#click()<CR><Cmd>call gnosis#start#key('<lt>CR>')<CR>
endfunction

function! s:current_vault() abort
  let l:list = gnosis#vault#list()
  if empty(l:list)
    return {}
  endif
  return l:list[max([0, min([s:sel, len(l:list) - 1])])]
endfunction

function! s:center(text, width) abort
  let l:pad = max([0, (a:width - strdisplaywidth(a:text)) / 2])
  return repeat(' ', l:pad) . a:text
endfunction

" 画面を描く
function! gnosis#start#render() abort
  if !get(b:, 'gnosis_start', 0)
    return
  endif
  let l:cols = winwidth(0)
  let l:rows = winheight(0)
  " 文言は選択中の vault の言語。配色は Chnoubis #10（夜空×水色）。
  let l:sv = s:current_vault()
  let l:lang = !empty(l:sv) && l:sv.exists ? gnosis#settings#load(l:sv.path).language : gnosis#settings#defaults().language
  call gnosis#i18n#set_lang(l:lang)
  let l:lines = []
  let l:hl = []
  if s:mode ==# 'start'
    let l:v = s:current_vault()
    let l:info = []
    let l:info += [['Gnosis', 'gnosisStartTitle'], ['', '']]
    if empty(l:v)
      let l:info += [[s:t('start.no_vault'), 'gnosisStartDim']]
    else
      let l:info += [[s:t('start.vault_label') . ' ' . l:v.name, 'gnosisStartTitle'], [l:v.path, 'gnosisStartDim']]
      if !l:v.exists
        let l:info += [[s:t('start.vault_missing'), 'gnosisStartWarn']]
      endif
    endif
    let l:info += [['', '']]
    if !empty(l:v) && l:v.exists
      let l:info += [[s:t('start.enter'), 'gnosisStartKey']]
    endif
    let l:info += [[s:t('start.keys'), 'gnosisStartDim']]
    if !empty(s:message)
      let l:info += [['', ''], [s:message, 'gnosisStartWarn']]
    endif
    " 小さい端末（例: 80x24）でも、必ず優先して Chnoubis の32幅版を表示する。
    " 既存の詳しい案内は、行数に余裕のある画面ではそのまま残す。
    if l:rows < 30
      let l:heading = 'Gnosis' . (empty(l:v) ? '' : ' — ' . l:v.name)
      let l:info = [[l:heading, 'gnosisStartTitle']]
      if !empty(l:v) && !l:v.exists
        let l:info += [[s:t('start.vault_missing'), 'gnosisStartWarn']]
      endif
      let l:info += [['Enter  |  v  |  s  |  q', 'gnosisStartKey']]
    endif
    let l:art = gnosis#start#pick_art(l:cols, l:rows, len(l:info) + 2)
    let l:top = max([0, (l:rows - len(l:art) - len(l:info) - 1) / 2])
    let l:lines += repeat([''], l:top)
    for l:a in l:art
      call add(l:lines, s:center(l:a, l:cols))
      call add(l:hl, 'gnosisStartArt')
    endfor
    if !empty(l:art)
      call add(l:lines, '')
    endif
    let l:hl = repeat([''], l:top) + l:hl + (empty(l:art) ? [] : [''])
    for [l:text, l:group] in l:info
      call add(l:lines, s:center(l:text, l:cols))
      call add(l:hl, l:group)
    endfor
  else
    let l:list = gnosis#vault#list()
    call add(l:lines, ' Gnosis — ' . s:t('vaults.title'))
    call add(l:hl, 'gnosisStartTitle')
    call add(l:lines, '')
    call add(l:hl, '')
    if empty(l:list)
      call add(l:lines, '   ' . s:t('vaults.empty'))
      call add(l:hl, 'gnosisStartDim')
    endif
    let s:list_top = len(l:lines)
    for l:i in range(len(l:list))
      let l:v = l:list[l:i]
      let l:mark = l:i == s:sel ? ' > ' : '   '
      let l:tail = l:v.exists ? '' : '  ' . s:t('vaults.missing')
      call add(l:lines, l:mark . l:v.name . '  —  ' . l:v.path . l:tail)
      call add(l:hl, l:i == s:sel ? 'gnosisStartSel' : (l:v.exists ? '' : 'gnosisStartWarn'))
    endfor
    call add(l:lines, '')
    call add(l:hl, '')
    for l:k in ['vaults.key_enter', 'vaults.key_add', 'vaults.key_new', 'vaults.key_remove', 'vaults.key_back']
      call add(l:lines, '   ' . s:t(l:k))
      call add(l:hl, 'gnosisStartKey')
    endfor
    if !empty(s:message)
      call add(l:lines, '')
      call add(l:hl, '')
      call add(l:lines, '   ' . s:message)
      call add(l:hl, 'gnosisStartWarn')
    endif
  endif
  setlocal modifiable
  silent %delete _
  call setline(1, l:lines)
  setlocal nomodifiable
  call clearmatches()
  for l:i in range(len(l:hl))
    if !empty(l:hl[l:i])
      call matchaddpos(l:hl[l:i], [l:i + 1], 10)
    endif
  endfor
  if s:mode ==# 'vaults' && !empty(gnosis#vault#list())
    call cursor(s:list_top + s:sel + 1, 4)
  else
    call cursor(1, 1)
  endif
  redraw
endfunction

function! gnosis#start#click() abort
  if s:mode !=# 'vaults' || !exists('s:list_top')
    return
  endif
  let l:i = line('.') - s:list_top - 1
  if l:i >= 0 && l:i < len(gnosis#vault#list())
    let s:sel = l:i
    call gnosis#start#render()
  endif
endfunction

" パスの入力（Tab でフォルダを補完。Esc・空は取り消し）
function! s:input(prompt, default, ...) abort
  try
    let l:r = input(a:prompt, a:default, 'dir')
  catch /^Vim:Interrupt$/
    let l:r = ''
  endtry
  redraw
  return empty(trim(l:r)) ? "\x01gnosis-cancel" : l:r
endfunction

function! gnosis#start#key(k) abort
  let s:message = ''
  let l:list = gnosis#vault#list()
  if s:mode ==# 'start'
    if a:k ==# '<CR>'
      let l:v = s:current_vault()
      if empty(l:v)
        let s:mode = 'vaults'
        let s:message = s:t('start.first_run')
      elseif !l:v.exists
        let s:mode = 'vaults'
        let s:message = s:t('start.missing_choose', l:v.path)
      else
        call gnosis#start#begin(l:v.path)
        return
      endif
    elseif a:k ==# 'v' || a:k ==# 'l'
      let s:mode = 'vaults'
    elseif a:k ==# 's'
      call gnosis#settings_ui#open({'from_start': 1})
      return
    elseif a:k ==# 'q'
      qall
      return
    endif
  else
    if a:k ==# 'j' || a:k ==# '<Down>'
      let s:sel = min([s:sel + 1, max([0, len(l:list) - 1])])
    elseif a:k ==# 'k' || a:k ==# '<Up>'
      let s:sel = max([s:sel - 1, 0])
    elseif a:k ==# '<CR>'
      if !empty(l:list)
        let l:v = l:list[s:sel]
        if !l:v.exists
          let s:message = s:t('start.missing_choose', l:v.path)
        else
          call gnosis#vault#select(l:v.path)
          call gnosis#start#begin(l:v.path)
          return
        endif
      endif
    elseif a:k ==# 'a'
      let l:p = s:input(s:t('vaults.prompt_add'), getcwd() . (has('win32') ? '\' : '/'), 'dir')
      if l:p !=# "\x01gnosis-cancel" && !empty(trim(l:p))
        try
          let l:added = gnosis#vault#add(trim(l:p))
          let s:sel = s:index_of(l:added)
          let s:message = s:t('vaults.added', l:added)
        catch /^gnosis-vault:/
          let s:message = substitute(v:exception, '^gnosis-vault: ', '', '')
        endtry
      endif
    elseif a:k ==# 'n'
      let l:p = s:input(s:t('vaults.prompt_new'), fnamemodify('~', ':p') . 'Gnosis', 'dir')
      if l:p !=# "\x01gnosis-cancel" && !empty(trim(l:p))
        try
          let l:made = gnosis#vault#create(trim(l:p))
          let s:sel = s:index_of(l:made)
          let s:message = s:t('vaults.created', l:made)
        catch /^gnosis-vault:/
          let s:message = substitute(v:exception, '^gnosis-vault: ', '', '')
        endtry
      endif
    elseif a:k ==# 'd'
      if !empty(l:list)
        let l:v = l:list[s:sel]
        if confirm(s:t('vaults.confirm_remove', l:v.name, l:v.path), "&Yes\n&No", 2) == 1
          call gnosis#vault#remove(l:v.path)
          let s:sel = max([0, s:sel - 1])
          let s:message = s:t('vaults.removed', l:v.path)
        endif
      endif
    elseif a:k ==# '<Esc>' || a:k ==# 'q'
      if empty(l:list) && a:k ==# 'q'
        qall
        return
      endif
      let s:mode = 'start'
    elseif a:k ==# 's'
      call gnosis#settings_ui#open({'from_start': 1})
      return
    endif
  endif
  call gnosis#start#render()
endfunction

function! s:index_of(path) abort
  let l:list = gnosis#vault#list()
  for l:i in range(len(l:list))
    if gnosis#vault#same(l:list[l:i].path, a:path)
      return l:i
    endif
  endfor
  return 0
endfunction

" 起動画面から戻る（設定画面を閉じたとき）
function! gnosis#start#return() abort
  if s:active
    call gnosis#start#open()
  endif
endfunction

" vault を開く: 登録簿に覚え、root を切り替え、その vault の設定を反映して、起動の続きを行う
function! gnosis#start#begin(path) abort
  let l:path = gnosis#vault#select(a:path)
  let l:root = gnosis#vault#note_root(l:path)
  let s:active = 0
  if get(s:, 'had_vault', 0)
    " 使用中の切り替え: 前の vault のバッファを閉じ、暗号化 vault ならロックしてから移る
    let s:had_vault = 0
    call gnosis#switch_vault(l:path)
    return
  endif
  let g:gnosis_root = fnamemodify(l:root, ':p')
  call gnosis#settings#activate(l:path)
  " 履歴（viminfo）をこの vault のものに（暗号化 vault はマウント後にプラグインが向け直す）
  if isdirectory(l:root . '/.state') || !isdirectory(l:root . '/../.crypt')
    let l:vi = l:root . (has('win32') ? '\' : '/') . '.state' . (has('win32') ? '\' : '/') . 'viminfo'
    if &viminfofile !=# l:vi && filereadable(l:vi)
      execute 'set viminfofile=' . fnameescape(l:vi)
      silent! rviminfo!
    endif
  endif
  call gnosis#startup_sequence()
endfunction
