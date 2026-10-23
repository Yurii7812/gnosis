" plugin/gnosis_search.vim

if exists('g:loaded_gnosis_search')
  finish
endif
let g:loaded_gnosis_search = 1

" python スクリプトのパス（プラグインロード時に確定）
let s:pydir = expand('<sfile>:p:h:h') . '/python'
if !exists('g:gnosis_search_tui')
  let g:gnosis_search_tui = s:pydir . '/fsearch_tui.py'
endif
if !exists('g:gnosis_search_index')
  let g:gnosis_search_index = s:pydir . '/notes_index.py'
endif
if !exists('g:gnosis_search_preview')
  let g:gnosis_search_preview = s:pydir . '/preview_highlight.py'
endif
if !exists('g:gnosis_search_titles')
  let g:gnosis_search_titles = s:pydir . '/note_titles.py'
endif
if !exists('g:gnosis_search_notesearch')
  let g:gnosis_search_notesearch = s:pydir . '/note_search.py'
endif

command! -nargs=0 FSearch call gnosis_search#run()
command! -nargs=0 LinkPick call gnosis_search#pick_insert_link()
command! -nargs=0 GnosisLocalLinks call gnosis_search#search_local()

if !exists('g:gnosis_search_no_mappings')
  " gs = go search（rg 感覚の 2 打）。g 始まりなので他キーを遅延させない。
  " gs … vault を ripgrep で全文検索（:Rg と同じ見た目・挙動）。
  nnoremap <silent> gs        <Cmd>FSearch<CR>
  " <Space> は曼荼羅ビュー（plugin/gnosis.vim → autoload/gnosis/mview.vim）。旧「今のノートのリンクを fzf で一覧」は
  " アーカイブして、:GnosisLocalLinks だけ残した。
  " \l … タイトル優先の全文検索 → カーソル位置に [タイトル](相対.md) を挿入。
  " ビジュアルでは選択範囲をリンクで置き換える（表示テキストは選択文字列）。
  nnoremap <silent> \l        <Cmd>call gnosis#mview#link_pick()<CR>
  xnoremap <silent> \l        :<C-u>call gnosis_search#pick_insert_link_visual()<CR>
endif
