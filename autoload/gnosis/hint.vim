" =============================================================================
" autoload/gnosis/hint.vim — リストビューと右のパネルの共通部品
"
"   ヒント行 … 窓の一番上に「今のモード」と最低限のキーを 1 行で出す（バッファの行は増やさない仮想テキスト）。
"              K、またはメニューの最後の項目でオン・オフ（設定は hint.json に残る）。
"   メニュー … m で開く。選択肢を番号付きで並べ、番号か j k Enter で選ぶ。
" =============================================================================

let s:type = 'gnosis_hint'

function! gnosis#hint#on() abort
  if !exists('s:on')
    let l:d = gnosis#home#read_json(gnosis#home#path('hint.json'), {})
    let s:on = type(get(l:d, 'on', '')) == v:t_number ? !!l:d.on : get(g:, 'gnosis_hint', 1)
  endif
  return s:on
endfunction

function! s:ensure_type() abort
  if empty(prop_type_get(s:type))
    highlight default link GnosisHint Comment
    call prop_type_add(s:type, {'highlight': 'GnosisHint'})
  endif
endfunction

" 現在の窓のバッファの先頭に、ヒント行を付け直す（オフなら外すだけ）。text が空でも外す。
function! gnosis#hint#put(text) abort
  call s:ensure_type()
  silent! call prop_remove({'type': s:type, 'all': 1}, 1, line('$'))
  if gnosis#hint#on() && !empty(a:text) && line('$') >= 1
    call prop_add(1, 0, {'type': s:type, 'text': a:text, 'text_align': 'above'})
  endif
endfunction

" 内容が違っていたら付け直す（アウトラインのように、中身ごと書き換えられるバッファ用）
function! gnosis#hint#ensure(text) abort
  call s:ensure_type()
  let l:now = prop_list(1, {'types': [s:type]})
  if gnosis#hint#on() ? (!empty(l:now) && l:now[0].text ==# a:text) : empty(l:now) | return | endif
  call gnosis#hint#put(a:text)
endfunction

" 「キー:名前」を並べ、今のものを [ ] で囲む。items = [[キー, 名前], …]
function! gnosis#hint#line(items, current, tail) abort
  let l:parts = []
  for [l:key, l:name] in a:items
    let l:s = l:key . ':' . gnosis#i18n#tr(l:name)
    call add(l:parts, l:key ==# a:current ? '[' . l:s . ']' : l:s)
  endfor
  return ' ' . join(l:parts, ' ') . '  |  ' . a:tail
endfunction

" ヒント行のオン・オフ。after は、付け直しに呼ぶ関数（無ければ何もしない）
function! gnosis#hint#toggle(After) abort
  let s:on = !gnosis#hint#on()
  call gnosis#home#write_json(gnosis#home#path('hint.json'), {'on': s:on})
  if type(a:After) == v:t_func | call a:After() | endif
  echo gnosis#i18n#tr(s:on ? 'ヒント行: オン' : 'ヒント行: オフ')
endfunction

" メニュー。entries = [[見出し, Funcref または {'sub': entries, 'title': …}], …]。選んだものを実行する
" 見出しが空の項目は区切りとして出さない。
function! gnosis#hint#menu(title, entries) abort
  let l:lines = [a:title]
  for l:i in range(len(a:entries))
    call add(l:lines, a:entries[l:i][0])
  endfor
  let l:n = gnosis#ui#inputlist(l:lines)
  if l:n < 1 || l:n > len(a:entries) | return | endif
  let l:Act = a:entries[l:n - 1][1]
  if type(l:Act) == v:t_dict
    call gnosis#hint#menu(get(l:Act, 'title', a:entries[l:n - 1][0]), l:Act.sub)
  elseif type(l:Act) == v:t_func
    call l:Act()
  endif
endfunction

" メニューの見出し: 今の選択に ● を付ける
function! gnosis#hint#mark(on, text) abort
  return (a:on ? '● ' : '  ') . gnosis#i18n#tr(a:text)
endfunction
