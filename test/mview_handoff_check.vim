" 曼荼羅ビュー（<Space>）の回帰網（test/mview_net.sh から呼ぶ）。
" 結果は $MV_WORK/result.txt に「OK 名前」「NG 名前: 詳細」で書く。
set nomore
let s:work = $MV_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1
" 開くたびに今のノートが中心（覚えた位置は専用の試験でだけ使う）
let g:gnosis_mview_restore = 0
" 既存の試験は罫線の文字で盤面を読む（色の線は専用の試験で確かめる）
let g:gnosis_mview_border = 'line'

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
  call writefile(s:res, s:work . '/result.txt')
endfunction
function! s:keys(k) abort
  call feedkeys(a:k, 'xt')
endfunction
function! s:text() abort
  return join(getbufline(gnosis#mview#state().buf, 1, '$'), "\n")
endfunction
" 盤面だけ（凡例の行を除く）
function! s:grid() abort
  return join(filter(getbufline(gnosis#mview#state().buf, 1, '$'), 'v:val =~# "┃"'), "\n")
endfunction
function! s:note() abort
  return fnamemodify(bufname(winbufnr(win_id2win(win_getid()))), ':t')
endfunction
function! s:mk(name, title, attr, grp, body) abort
  let l:ls = ['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title] + (a:attr ? ['attribute: group'] : []) + ['---', '', '# ' . a:title, '']
  if !empty(a:grp)
    let l:ls += ['Group:'] + map(copy(a:grp), '"[" . v:val[0] . "](" . v:val[1] . ")"') + ['']
  endif
  call writefile(l:ls + a:body, s:v . '/' . a:name)
endfunction

call s:mk('index.md', 'Index', 0, [], ['[植物](plant.md)', '[料理](cook.md)'])
let s:members = ['ハーブ', 'バラ', '栽培', 'ローズマリー', 'ミント', 'バジル', 'タイム', 'サルビア', 'ラベンダー', '水やり']
let s:files = ['herb', 'rose', 'grow', 'rosemary', 'mint', 'basil', 'thyme', 'sage', 'lav', 'water']
call s:mk('plant.md', '植物', 1, [['Index', 'index.md']], map(copy(s:files), '"[" . s:members[v:key] . "](" . v:val . ".md)"'))
call s:mk('cook.md', '料理', 1, [['Index', 'index.md']], ['[カレー](curry.md)'])
call s:mk('herb.md', 'ハーブ', 0, [['植物', 'plant.md'], ['料理', 'cook.md']], ['ハーブの話', '[ミント](mint.md)'])
for s:i in range(1, len(s:files) - 1)
  call s:mk(s:files[s:i] . '.md', s:members[s:i], 0, [['植物', 'plant.md']], [])
endfor
call s:mk('curry.md', 'カレー', 0, [['料理', 'cook.md']], [])


execute 'edit ' . s:v . '/plant.md'
call s:keys(' ')
call s:keys('f#>D')
call gnosis#mview#gui_click(3, 5, 0)
let s:before = gnosis#mview#handoff()
call gnosis#settings#set('mandalaLegend', v:false)
let s:path = gnosis#run#export()
let s:settings = gnosis#settings#current()
let s:settings.mandalaLegend = v:true
call s:keys('f#<')
let s:ok_receive = gnosis#run#receive(s:path)
call s:ok('状態ファイルを受信できる', s:ok_receive == 1)
let s:after = gnosis#mview#handoff()
for s:k in keys(s:before)
  call s:ok('引き継ぎ: ' . s:k, get(s:after, s:k, v:null) ==# s:before[s:k], string([get(s:after, s:k, v:null), s:before[s:k]]))
endfor
call s:ok('受信後は曼荼羅にフォーカス', &filetype ==# 'gnosis-mandala')
call s:ok('受信ファイルを削除', !filereadable(s:path))
call s:ok('凡例の表示設定も読み直す', gnosis#mview#gui_state().legend == 0)
let s:focused_state = gnosis#mview#handoff()
call writefile([json_encode({'root': g:gnosis_root, 'focusOnly': 1})], s:path)
call s:ok('起動画面から既存画面へ切り替え', gnosis#run#receive(s:path) == 1)
call s:ok('起動画面からの切り替えで盤面を変えない', gnosis#mview#handoff() ==# s:focused_state)
let s:gui_info = gnosis#mview#gui_state().info
call s:ok('GUI説明はCUIの説明と同じ', stridx(join(getline(1, '$'), "\n"), s:gui_info) >= 0)
" プレビューを隠した状態の往復。
call s:keys('p')
let s:hidden = gnosis#mview#handoff()
call s:keys('pf')
call gnosis#mview#restore_handoff(s:hidden)
call s:ok('9x9 と右ノート非表示を復元', gnosis#mview#state().size == 9 && gnosis#mview#gui_state().noteWin < 0)
call s:ok('選択マスを復元', gnosis#mview#state().cur ==# s:hidden.cur)
" GUIが端末カーソルを動かさない場合も、状態と説明は更新する。
let $GNOSIS_GUI_PORT = 'test'
call gnosis#mview#gui_click(4, 4, 0)
call s:ok('GUI用の移動', gnosis#mview#gui_state().cur ==# [4, 4])
let $GNOSIS_GUI_PORT = ''
" 閉じていた場合は、受信側の曼荼羅も閉じる。
call gnosis#mview#restore_handoff({'open': 0})
call s:ok('閉じた状態も同期', !gnosis#mview#is_open())
call s:ok('閉じたあとにノートの窓がある', &buftype ==# '')
call s:ok('新しいCUIキー', maparg('\C', 'n') =~# 'run#switch')
call s:ok('GUIキーを維持', maparg('\c', 'n') =~# 'open_web')
call writefile(s:res + ['DONE'], s:work . '/result.txt')
qa!
