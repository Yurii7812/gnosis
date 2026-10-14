" Gnosis 専用の表示状態クリア。通常の Vim / Konsole には影響しない。
" ノートを開いたあとに残る Search や一時 matchadd の背景を消す。
" 通常の構文強調やリンク番号の text property は変更しない。
function! gnosis#color#refresh() abort
  if &buftype !=# ''
    return
  endif
  " 関数内の :nohlsearch は復帰時に v:hlsearch が戻る。
  " typeahead に <Cmd>nohlsearch を積み関数外で実行する。
  " &hlsearch 自体は維持し、ユーザーが新たに検索した結果は引き続き表示する。
  call feedkeys("\<Cmd>nohlsearch\<CR>", 'n')
  call clearmatches()
  if get(g:, 'colors_name', '') ==# 'gnosis'
    " 再描画だけでは回復しない古いハイライト属性を再設定する。
    silent! colorscheme gnosis
    if exists('*gnosis#link_highlight')
      call gnosis#link_highlight()
    endif
  endif
  redraw!
endfunction

" 最初のノート表示で、一時的な検索・選択強調が前画面から残るのを防ぐ。
function! gnosis#color#on_note_enter() abort
  if &buftype !=# '' || (&filetype !=# 'markdown' && &filetype !=# 'vimwiki')
    return
  endif
  " 関数内の :nohlsearch は復帰時に v:hlsearch が戻る。
  " typeahead に <Cmd>nohlsearch を積み関数外で実行する。
  " &hlsearch 自体は維持し、ユーザーが新たに検索した結果は引き続き表示する。
  call feedkeys("\<Cmd>nohlsearch\<CR>", 'n')
  call clearmatches()
  " 各ウィンドウの初回だけパレットを再適用。通常のカーソル移動では重い処理をしない。
  if !get(w:, 'gnosis_color_entered', 0)
    let w:gnosis_color_entered = 1
    if get(g:, 'colors_name', '') ==# 'gnosis'
      silent! colorscheme gnosis
    endif
    redraw!
  endif
endfunction

" スクリーンショットに映る色が Vim のハイライトか確認する診断ログ。
" 生のノート本文は書かず、カーソル上の highlight ID 等だけ保存する。
function! gnosis#color#doctor() abort
  let l:hl_id = synID(line('.'), col('.'), 1)
  let l:hl = synIDtrans(l:hl_id)
  let l:details = [
        \ 'filetype=' . &filetype,
        \ 'syntax=' . &syntax,
        \ 'colorscheme=' . get(g:, 'colors_name', ''),
        \ 'termguicolors=' . &termguicolors,
        \ 'hlsearch=' . &hlsearch . ' active=' . v:hlsearch,
        \ 'syntax_raw=' . synIDattr(l:hl_id, 'name'),
        \ 'syntax_resolved=' . synIDattr(l:hl, 'name'),
        \ 'syntax_fg=' . synIDattr(l:hl, 'fg#', 'gui'),
        \ 'syntax_bg=' . synIDattr(l:hl, 'bg#', 'gui'),
        \ 'matches=' . string(getmatches()),
        \ 'props=' . string(prop_list(line('.'))),
        \ ]
  let l:dir = gnosis#home#path('logs')
  if !isdirectory(l:dir) | call mkdir(l:dir, 'p') | endif
  let l:path = l:dir . '/color-doctor.txt'
  call writefile(l:details, l:path)
  echom 'Gnosis: highlight diagnostics -> ' . l:path
endfunction

" ---------------------------------------------------------------------------
" 色の計算（カスタムテーマの編集・コントラストの確認で使う。#rrggbb の文字列を扱う）
" ---------------------------------------------------------------------------

" 入力を #rrggbb（小文字）にそろえる。'abc' '#ABC' 'aabbcc' '#AABBCC' を受ける。だめなら ''。
function! gnosis#color#normalize(text) abort
  let l:t = substitute(trim(a:text), '^#', '', '')
  if l:t =~# '^\x\{3}$'
    let l:t = substitute(l:t, '\(\x\)\(\x\)\(\x\)', '\1\1\2\2\3\3', '')
  endif
  return l:t =~# '^\x\{6}$' ? '#' . tolower(l:t) : ''
endfunction

function! s:rgb(hex) abort
  return [str2nr(a:hex[1:2], 16), str2nr(a:hex[3:4], 16), str2nr(a:hex[5:6], 16)]
endfunction

" a と b を t（0〜1）の割合で混ぜる
function! gnosis#color#mix(a, b, t) abort
  let l:x = s:rgb(a:a)
  let l:y = s:rgb(a:b)
  let l:out = '#'
  for l:i in range(3)
    let l:out .= printf('%02x', float2nr(l:x[l:i] + (l:y[l:i] - l:x[l:i]) * a:t + 0.5))
  endfor
  return l:out
endfunction

" 相対輝度（WCAG）。0（黒）〜1（白）
function! gnosis#color#luminance(hex) abort
  let l:c = []
  for l:v in s:rgb(a:hex)
    let l:s = l:v / 255.0
    call add(l:c, l:s <= 0.03928 ? l:s / 12.92 : pow((l:s + 0.055) / 1.055, 2.4))
  endfor
  return 0.2126 * l:c[0] + 0.7152 * l:c[1] + 0.0722 * l:c[2]
endfunction

" コントラスト比（1〜21）。本文と背景は 4.5 以上が読みやすい目安
function! gnosis#color#contrast(a, b) abort
  let l:la = gnosis#color#luminance(a:a)
  let l:lb = gnosis#color#luminance(a:b)
  return l:la > l:lb ? (l:la + 0.05) / (l:lb + 0.05) : (l:lb + 0.05) / (l:la + 0.05)
endfunction

" 背景の明るさから 'light' / 'dark' を決める（カスタム配色の base）
function! gnosis#color#base_of(bg) abort
  return gnosis#color#luminance(a:bg) < 0.4 ? 'dark' : 'light'
endfunction
