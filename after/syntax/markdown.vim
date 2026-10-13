" Gnosis: Markdown の構文ファイルの後に、リンクの構文（表示名だけを見せる）を足す。
" Gnosis が読み込まれていないとき（ふだんの Vim の runtimepath に入っていないとき）は何もしない。
if exists('g:gnosis_markdown_conceal_links')
  call gnosis#link_syntax()
endif
