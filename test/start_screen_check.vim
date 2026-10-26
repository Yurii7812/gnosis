" Vim の起動画面の回帰網（pty で起動して確かめる。test/start_screen_net.sh から）。
"   起動直後: 起動画面（Chnoubis・Gnosis・vault・Enter で開始）が10番の夜空×水色で出て、ノートはまだ開かない
"   Enter: 選択中の vault の Index が開き、その vault の設定のテーマ（ダーク）になる
let s:w = $START_WORK
let s:res = []

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
function! s:hl(attr) abort
  return synIDattr(synIDtrans(hlID('Normal')), a:attr . '#', 'gui')
endfunction
function! s:first(t) abort
  let l:text = join(getline(1, '$'), "\n")
  call s:ok('起動画面: ノートを開く前に出る', bufname('%') ==# 'Gnosis' && &buftype ==# 'nofile', bufname('%'))
  call s:ok('起動画面: Chnoubis（Braille）', l:text =~# '[⠀-⣿]', strpart(l:text, 0, 80))
  call s:ok('起動画面: Braille の GNOSIS ロゴ', !empty(gnosis#start#logo(&columns, &lines)) && l:text =~# gnosis#start#logo(&columns, &lines)[0])
  call s:ok('起動画面: vault の名前とパス', l:text =~# '保管庫' && stridx(l:text, $START_VAULT) >= 0)
  call s:ok('起動画面: Enter で開始の案内', l:text =~# 'Enter')
  call s:ok('起動画面: vault の選択・管理への入口', l:text =~# 'v ')
  " 背景はダークと同じ #1E1E1E、Chnoubis の図案はダークのリンクの色 #6CB6FF。案内の文字はダークの本文の色
  let s:art = tolower(synIDattr(synIDtrans(hlID('gnosisStartArt')), 'fg#', 'gui'))
  call s:ok('起動画面: ダークの背景に、ダークのリンクの色の Chnoubis', tolower(s:hl('bg')) ==# '#1e1e1e' && s:art ==# '#6cb6ff' && tolower(s:hl('fg')) ==# '#dadada', s:hl('bg') . ' ' . s:art . ' ' . s:hl('fg'))
  call s:ok('起動画面: 標準80x24端末でもロゴ+図案が収まる',
        \ len(gnosis#start#pick_art(80, 23, 2 + len(gnosis#start#logo(80, 23)) + 2))
        \ + len(gnosis#start#logo(80, 23)) + 2 + 2 <= 23)
  call s:ok('起動画面: アートが画面幅に収まる', max(map(getline(1, '$'), 'strdisplaywidth(v:val)')) <= &columns)
  call feedkeys('v', 't')
  call timer_start(400, function('s:vaults'))
endfunction
function! s:vaults(t) abort
  let l:text = join(getline(1, '$'), "\n")
  call s:ok('v: vault の一覧（登録・作成・一覧から外す の案内）', l:text =~# '保管庫' && l:text =~# 'a ' && l:text =~# 'n ' && l:text =~# 'd ', l:text)
  call feedkeys("\<Esc>s", 't')
  call timer_start(500, function('s:settings'))
endfunction
function! s:settings(t) abort
  let l:text = join(getline(1, '$'), "\n")
  call s:ok('s: 設定画面（英語で表示）', bufname('%') =~# 'Settings' && l:text =~# 'Language' && l:text =~# 'Font size' && l:text =~# 'Maximize', l:text)
  call feedkeys('q', 't')
  call timer_start(400, function('s:back'))
endfunction
function! s:back(t) abort
  call s:ok('q: 起動画面へ戻る', bufname('%') ==# 'Gnosis')
  call feedkeys("\<CR>", 't')
  call timer_start(1500, function('s:second'))
endfunction
function! s:second(t) abort
  " Index が開く（曼荼羅が左半分に出るので、Index は右の窓。どの窓でもよい）
  let l:paths = map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), ":p")')
  call s:ok('Enter: vault の Index が開く', !empty(filter(copy(l:paths), 'fnamemodify(v:val, ":t") ==# "index.md" && stridx(v:val, $START_VAULT) == 0')), string(l:paths))
  call s:ok('Enter: vault の設定のテーマ（ダーク）', &background ==# 'dark' && tolower(s:hl('bg')) ==# '#1e1e1e', &background . ' ' . s:hl('bg'))
  call s:ok('Enter: 言語は英語のまま', gnosis#i18n#lang() ==# 'en', execute('messages'))
  call writefile(s:res, s:w . '/result.txt')
  qa!
endfunction
" 前回の vault が plugin 初期化中に g:gnosis_root に復元された状況を再現。
" この状態でもファイル指定なしの Gnosis 起動は必ず Chnoubis メニューから始める。
let g:gnosis_root = $START_VAULT
call timer_start(1200, function('s:first'))
