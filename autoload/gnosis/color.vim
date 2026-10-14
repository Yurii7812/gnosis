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
