set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
GnosisHighlights
call assert_equal('# ハイライト 2 件', getline(1))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "知識は力である（p.12）"')))
call cursor(match(getline(1, '$'), '(book.md)') + 1, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/book.md', expand('%:p'))
" 草稿の表示と、新しいノートとしての保存（2 回目は上書きしない）
GnosisHighlightDigest
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^> — \\[知識の本\\](book.md)（p.12）"')))
close
GnosisHighlightDigest notes/digest.md
call assert_equal($D . '/v/notes/digest.md', expand('%:p'))
execute 'edit ' . fnameescape($D . '/v/book.md')
let s:size = getfsize($D . '/v/notes/digest.md')
GnosisHighlightDigest notes/digest.md
call assert_equal(s:size, getfsize($D . '/v/notes/digest.md'))
" 進捗（書名に空白を含んでよい）
GnosisReadProgress 吾輩は猫である 50 300
GnosisReadProgress
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "吾輩は猫である — 50/300（17%）"')))
close
GnosisReadProgress だめ
" 成熟度は今のノートに書く。未保存なら書かない
execute 'edit ' . fnameescape($D . '/v/memo.md')
set modified
GnosisMaturitySet growing
call assert_true(empty(filter(readfile($D . '/v/memo.md'), 'v:val =~# "^maturity:"')))
set nomodified
GnosisMaturitySet growing
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^maturity: growing$"')))
GnosisMaturity
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "メモ"')))
close
" 学習経路・出典
GnosisLearnPath alg.md
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^1\\. \\[基礎\\](basic.md)"')))
close
GnosisSources
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(memo.md)"')))
close
" 自己説明・インクリメンタルリーディング
execute 'edit ' . fnameescape($D . '/v/book.md')
GnosisExplain
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "初めて聞く人に説明"')))
close
GnosisIrNext
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "初回"')))
let s:id = matchstr(join(getline(1, '$'), "\n"), 'ID `\zs[0-9a-f]\{10}\ze`')
close
call assert_equal(10, len(s:id))
execute 'GnosisIrRate ' . s:id . ' good'
GnosisIrRate zzzz good
silent! GnosisIrRate
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
