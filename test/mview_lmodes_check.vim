" \l の置き場所の選択（e のあと）: q / Esc は選択だけを閉じて \l は続く。h / i / 見出し(t) は右の元のノートで場所を選んで Enter で決め、
" q でやめると置き場所の選択に戻る。c / g / m などサブの選択を q でやめても置き場所の選択に戻る。
" 結果は $LM_WORK/result.txt（test/mview_lmodes_net.sh から呼ぶ）
set nomore
let s:work = $LM_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1
let g:gnosis_mview_restore = 0
let g:gnosis_mview_border = 'line'

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
  call writefile(s:res, s:work . '/result.txt')
endfunction
function! s:keys(k) abort
  call feedkeys(a:k, 'xt')
endfunction
function! s:file(n) abort
  return join(readfile(s:v . '/' . a:n), "\n")
endfunction
function! s:mk(name, title, attr, body) abort
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title] + (a:attr ? ['attribute: group'] : []) + ['---', '', '# ' . a:title, ''] + a:body, s:v . '/' . a:name)
endfunction
function! s:st() abort
  return gnosis#mview#state()
endfunction
function! s:reset() abort
  call s:keys('Q')
  let g:gnosis_test_keys = []
  let g:gnosis_test_display_name = []
  let g:gnosis_test_yomi = []
endfunction
" 元のノートを開いて \l を始め、tgt.md を選んだ状態にする
function! s:start(line_pat) abort
  call s:reset()
  call s:mk('src.md', '元', 0, ['最初の行。', '', '## 節A', '節Aの本文。', '', '## 節B', '節Bの本文。'])
  call s:mk('tgt.md', '相手', 0, ['相手の本文。'])
  call s:mk('index.md', 'Index', 1, ['[元](src.md)', '[相手](tgt.md)'])
  call gnosis#clear_title_cache()
  execute 'edit ' . s:v . '/src.md'
  call cursor(search(a:line_pat, 'nw'), 1)
  call gnosis#mview#link_pick()
  let l:d = gnosis#mview#state()
  let l:d.center = 'tgt.md'
  call s:keys("\<C-l>")
endfunction

" ---- e → Esc: 選択だけ閉じる。\l は続く
call s:start('^節Aの本文')
let g:gnosis_test_keys = ["\<Esc>"]
call s:keys('e')
call s:ok('e → Esc: \l は続く（選ぶモードのまま・曼荼羅に戻る・中心は相手）', s:st().pick ==# 'link' && &filetype ==# 'gnosis-mandala' && s:st().center ==# 'tgt.md', string([s:st().pick, &filetype, s:st().center]))
call s:ok('e → Esc: 何も書き換わっていない', s:file('src.md') !~# 'tgt.md')
call s:keys('q')
call s:ok('続けて q で選ぶモードをやめる', s:st().pick ==# '' && &filetype ==# 'gnosis-mandala')

" ---- e → h: 右の元のノートで場所を選び、Enter で決める
call s:start('^節Aの本文')
let g:gnosis_test_keys = ['h']
call s:keys('e')
call s:ok('e → h: 右の元のノートで場所を選ぶモードになる（曼荼羅は開いたまま・選ぶモードのまま）', has_key(s:st(), 'place') && fnamemodify(bufname('%'), ':t') ==# 'src.md' && s:st().pick ==# 'link', string([has_key(s:st(), 'place'), bufname('%'), s:st().pick]))
call s:ok('e → h: まだ書き込まれていない', s:file('src.md') !~# 'tgt.md')
call cursor(search('^最初の行', 'nw'), 1)
call gnosis#mview#place_decide()
call s:ok('h: Enter で、カーソルの行の下にリンクが入る', s:file('src.md') =~# "最初の行。\n\\[相手\\](tgt.md)", s:file('src.md'))
call s:ok('h: 決めたら \l は終わる（曼荼羅に戻る・選ぶモードは終わる）', &filetype ==# 'gnosis-mandala' && s:st().pick ==# '' && !has_key(s:st(), 'place'), string([&filetype, s:st().pick]))

" ---- e → h → q: h だけやめて、置き場所の選択に戻る（\l は続く）
call s:start('^節Aの本文')
let g:gnosis_test_keys = ['h', "\<Esc>"]
call s:keys('e')
call gnosis#mview#place_cancel()
call s:ok('e → h → q: h をやめると置き場所の選択に戻る（ここでは Esc で閉じた）。\l は続く', s:st().pick ==# 'link' && !has_key(s:st(), 'place') && &filetype ==# 'gnosis-mandala', string([s:st().pick, has_key(s:st(), 'place'), &filetype]))
call s:ok('e → h → q: 何も書き換わっていない', s:file('src.md') !~# 'tgt.md')
" 戻った選択でもう一度 h → 今度は i
let g:gnosis_test_keys = ['h', "\<Esc>"]
call s:keys('e')
call s:ok('e → h → q → （選択）h: もう一度 h のモードに入れる', has_key(s:st(), 'place') && s:st().place.kind ==# 'h', string(get(s:st(), 'place', {})))
call gnosis#mview#place_cancel()
call s:keys('q')

" ---- e → i: カーソルの文字のすぐ後ろに入る
call s:start('^最初の行')
let g:gnosis_test_keys = ['i']
call s:keys('e')
call cursor(search('^最初の行', 'nw'), 1)
normal! 3l
call gnosis#mview#place_decide()
call s:ok('i: Enter で、カーソルの文字（行）のすぐ後ろにリンクが入る', s:file('src.md') =~# '最初の行\[相手\](tgt.md)。', s:file('src.md'))
call s:ok('i: 決めたら \l は終わる', s:st().pick ==# '' && &filetype ==# 'gnosis-mandala')

" ---- e → t: 右の元のノートで、カーソルがある節の最後に入る。見出しの上では決められない
call s:start('^節Bの本文')
let g:gnosis_test_keys = ['t']
call s:keys('e')
call s:ok('e → t: 右の元のノートで節を選ぶモードになる', has_key(s:st(), 'place') && s:st().place.kind ==# 'head', string(get(s:st(), 'place', {})))
call cursor(1, 1)
call gnosis#mview#place_decide()
call s:ok('t: 見出しの上より前では決められない（モードのまま・まだ書き込まれていない）', has_key(s:st(), 'place') && s:file('src.md') !~# 'tgt.md')
call cursor(search('^節Bの本文', 'nw'), 1)
call gnosis#mview#place_decide()
call s:ok('t: 節Bの最後にリンクが入る', s:file('src.md') =~# '節Bの本文。\n\n\[相手\](tgt.md)' || s:file('src.md') =~# '節Bの本文。\n\[相手\](tgt.md)', s:file('src.md'))

" ---- e → c → q: c の置き場所を取り消すと、置き場所の選択に戻る
call s:start('^節Aの本文')
let g:gnosis_test_keys = ['c', 'q', "\<Esc>"]
call s:keys('e')
call s:ok('e → c → q: 置き場所の選択に戻り（そこで Esc）、\l は続く。何も書き換わらない', s:st().pick ==# 'link' && &filetype ==# 'gnosis-mandala' && s:file('src.md') !~# 'tgt.md' && s:file('tgt.md') !~# 'src.md', string([s:st().pick, &filetype]))
call s:keys('q')

" ---- e → c → h: c の置き場所も右のノートで選ぶ
call s:start('^節Aの本文')
let g:gnosis_test_keys = ['c', 'h']
call s:keys('e')
call s:ok('e → c → h: 右の元のノートで場所を選ぶモード', has_key(s:st(), 'place'), string(get(s:st(), 'place', {})))
call cursor(search('^最初の行', 'nw'), 1)
call gnosis#mview#place_decide()
call s:ok('c → h: Enter で、元のノートにリンクが入り、相手の Context に元のノートが入る', s:file('src.md') =~# '\[相手\](tgt.md)' && s:file('tgt.md') =~# 'src.md', s:file('src.md') . ' // ' . s:file('tgt.md'))

" ---- 選ぶモードで s / x / m をかけて q: かけたものだけやめる（選ぶモードは残る）
call s:start('^節Aの本文')
let s:d = gnosis#mview#state()
let s:d.find = 'ハ'
let s:d.stamp = {'pick': 1, 'find': 2}
let s:d.tick = 2
call s:keys('q')
call s:ok('m（ハイライト）をかけて q: ハイライトだけやめる。選ぶモードは続く', s:st().find ==# '' && s:st().pick ==# 'link', string([s:st().find, s:st().pick]))
call s:keys('q')
call s:ok('もう一度 q で、選ぶモードをやめる（曼荼羅は閉じない）', s:st().pick ==# '' && &filetype ==# 'gnosis-mandala')

call s:reset()
call writefile(s:res, s:work . '/result.txt')
qa!
