" Gnosis専用の検索・一時ハイライトをクリアしても本文を変えない回帰テスト
let s:out = []
function! s:ok(name, pass) abort
  call add(s:out, (a:pass ? 'OK ' : 'NG ') . a:name)
endfunction
let g:gnosis_root = $COLOR_TEST_VAULT
let g:gnosis_open_index_on_startup = 0
let g:gnosis_autosync = 0
let g:gnosis_managed = 1
try
  execute 'edit ' . fnameescape($COLOR_TEST_VAULT . '/index.md')
  setlocal filetype=markdown
  let s:before = getline(1, '$')
  call matchadd('Visual', 'Index')
  let @/ = 'Index'
  set hlsearch
  let v:hlsearch = 1
  call gnosis#color#on_note_enter()
  call s:ok('最初のノートで一時matchを削除', empty(getmatches()))
  call s:ok('検索の残留ハイライトを削除', !&hlsearch)
  call s:ok('ノートの本文は書き換えない', s:before ==# getline(1, '$'))
  call s:ok('Markdown の filetype を保持', &filetype ==# 'markdown')
  call s:ok('構文のリンク強調は存在', hlexists('gnosisLinkText'))
  call matchadd('Visual', 'Index')
  let v:hlsearch = 1
  call gnosis#color#refresh()
  call s:ok('再描画コマンドでマッチを消す', empty(getmatches()) && !&hlsearch)
  call s:ok('\\r の色修復マッピングを提供', !empty(maparg('\r', 'n')))
  call s:ok('手動色修復コマンドを提供', exists(':GnosisRefreshColors') == 2)
  call gnosis#color#doctor()
  let s:doctor = gnosis#home#path('logs', 'color-doctor.txt')
  call s:ok('診断ログをGnosisホームに出力', filereadable(s:doctor))
catch
  call add(s:out, 'NG exception ' . v:exception . ' @ ' . v:throwpoint)
endtry
call writefile(s:out, $COLOR_TEST_RESULTS)
qall!
