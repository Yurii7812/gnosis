set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
call gnosis#mandala_new('健康', '運動', '食事', '睡眠')
let s:m = expand('%:p')
call assert_true(filereadable(s:m))
let s:t = readfile(s:m)
call assert_true(index(s:t, 'mandala: true') >= 0)
call assert_equal(11, len(filter(copy(s:t), 'v:val =~# "^|"')))
" 「食事」のマスにカーソルを置いて、実ノートを作る
let s:ln = match(s:t, '食事') + 1
call cursor(s:ln, stridx(s:t[s:ln - 1], '食事') + 1)
call gnosis#mandala_cell(0)
let s:note = expand('%:p')
call assert_notequal(s:m, s:note)
call assert_equal('# 食事', readfile(s:note)[match(readfile(s:note), '^# ')])
execute 'edit ' . fnameescape(s:m)
call assert_equal(2, len(filter(readfile(s:m), 'v:val =~# "\\[食事\\]("')))    " 副題の 2 か所とも同じリンク
" 「睡眠」は別の曼荼羅へ
let s:t = readfile(s:m)
let s:ln = match(s:t, '睡眠') + 1
call cursor(s:ln, stridx(s:t[s:ln - 1], '睡眠') + 1)
call gnosis#mandala_cell(1)
call assert_true(index(readfile(expand('%:p')), 'mandala: true') >= 0)
call assert_true(index(readfile(expand('%:p')), '# 睡眠') >= 0)
execute 'edit ' . fnameescape(s:m)
call gnosis#mandala_sync()
" sync は揃っているものを変えず、リンクにした副題が食い違いにならない（運動はリンク無しのまま・食事は 2 か所リンク）
call assert_equal(2, len(filter(readfile(s:m), 'v:val =~# "\\[食事\\]("')))
call assert_equal(2, len(filter(readfile(s:m), 'v:val =~# "\\[睡眠\\]("')))
call assert_equal(0, len(filter(readfile(s:m), 'v:val =~# "\\[運動\\]("')))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
