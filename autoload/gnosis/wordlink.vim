" =============================================================================
" autoload/gnosis/wordlink.vim — ノートの中の単語を、同じ題のノートへのリンクにする
"
"   \K（:GnosisWordLink） … 今のノートの本文で、ほかのノートの題と同じ単語を探し、チェックボックスのポップアップで選ばせる。
"                           ビジュアルモードで選んだ行だけを対象にもできる（選んだ行の範囲）。
"   ポップアップ … j k で動く / Space で付け外し / a で全部の付け外し / Enter で決定 / Esc・q でやめる
"   単語の探し方・リンクの作り方は python/word_link.py（大文字小文字は区別しない・コードやリンクの中は触らない）。
" =============================================================================

let s:here = expand('<sfile>:p:h:h:h')

function! s:root() abort
  return substitute(trim(get(g:, 'gnosis_root', '')), '/\+$', '', '')
endfunction

function! s:run(args) abort
  let l:cmd = join(map([gnosis#python_cmd(), s:here . '/python/word_link.py'] + a:args, 'shellescape(v:val)'), ' ')
  let l:out = system(l:cmd)
  return v:shell_error ? v:null : l:out
endfunction

function! s:label(w, on) abort
  return (a:on ? '[x] ' : '[ ] ') . a:w.title . '  (' . a:w.count . ')  ' . a:w.sample
endfunction

" チェックボックスのポップアップ。選んだ単語（題）の配列を返す。やめたら v:null
function! gnosis#wordlink#choose(words) abort
  let l:on = repeat([1], len(a:words))
  let l:sel = 0
  let l:id = popup_create(map(copy(a:words), 's:label(v:val, 1)'), {
        \ 'title': ' ' . gnosis#i18n#tr('リンクにする単語') . '  (Space ' . gnosis#i18n#tr('付け外し') . ' / Enter ' . gnosis#i18n#tr('決定') . ') ',
        \ 'pos': 'center', 'minwidth': 50, 'maxheight': max([5, &lines - 10]), 'padding': [0, 1, 0, 1],
        \ 'border': [1, 1, 1, 1], 'highlight': 'Pmenu', 'cursorline': 1, 'wrap': 0, 'zindex': 300, 'mapping': 0})
  let l:result = v:null
  try
    while 1
      call popup_settext(l:id, map(copy(a:words), 's:label(v:val, l:on[v:key])'))
      call win_execute(l:id, 'call cursor(' . (l:sel + 1) . ', 1)')
      redraw
      let l:k = gnosis#ui#getkey()
      if l:k ==# 'j' || l:k ==# "\<Down>" || l:k ==# "\<C-n>"
        let l:sel = min([l:sel + 1, len(a:words) - 1])
      elseif l:k ==# 'k' || l:k ==# "\<Up>" || l:k ==# "\<C-p>"
        let l:sel = max([l:sel - 1, 0])
      elseif l:k ==# ' '
        let l:on[l:sel] = !l:on[l:sel]
      elseif l:k ==# 'a'
        let l:to = index(l:on, 0) >= 0 ? 1 : 0
        let l:on = repeat([l:to], len(a:words))
      elseif l:k ==# "\<CR>" || l:k ==# "\<NL>"
        let l:result = []
        for l:i in range(len(a:words))
          if l:on[l:i] | call add(l:result, a:words[l:i].title) | endif
        endfor
        break
      elseif l:k ==# "\<Esc>" || l:k ==# 'q' || l:k ==# "\<C-c>"
        break
      endif
    endwhile
  finally
    call popup_close(l:id)
    redraw
  endtry
  return l:result
endfunction

" a:first, a:last … 対象の行（無ければノート全体）
function! gnosis#wordlink#run(...) abort
  let l:root = s:root()
  let l:file = expand('%:p')
  if empty(l:root) || stridx(l:file, l:root . '/') != 0
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: vault の中のノートで使ってください') | echohl NONE
    return
  endif
  call gnosis#save_current_note()
  let l:range = a:0 >= 2 ? ['--lines', string(a:1), string(a:2)] : []
  let l:out = s:run(['candidates', l:root, l:file] + l:range)
  if l:out is v:null
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 単語を調べられませんでした') | echohl NONE
    return
  endif
  let l:words = json_decode(l:out).words
  if empty(l:words)
    echo gnosis#i18n#tr('Gnosis: リンクにできる単語はありません（ほかのノートの題と同じ単語が無い）')
    return
  endif
  let l:chosen = gnosis#wordlink#choose(l:words)
  if l:chosen is v:null || empty(l:chosen)
    echo ''
    return
  endif
  let l:new = s:run(['apply', l:root, l:file] + l:range + ['--words', json_encode(l:chosen)])
  if l:new is v:null
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: リンクにできませんでした') | echohl NONE
    return
  endif
  " バッファを書き換える（u で戻せる）。保存は普段の自動保存に任せる
  let l:lines = split(l:new, "\n", 1)
  if len(l:lines) > 1 && l:lines[-1] ==# ''
    call remove(l:lines, -1)   " 末尾の改行は、行の終わり（空の行ではない）
  endif
  let l:view = winsaveview()
  call setline(1, l:lines)
  if line('$') > len(l:lines)
    silent execute (len(l:lines) + 1) . ',$delete _'
  endif
  call winrestview(l:view)
  echo printf(gnosis#i18n#tr('Gnosis: %d 個の単語をリンクにしました'), len(l:chosen))
endfunction
