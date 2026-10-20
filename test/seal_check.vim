set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
let g:gnosis_seal_answer = 1
execute 'edit ' . fnameescape($D . '/v/a.md')
GnosisSeal 2999-01-01
call assert_true(!empty(filter(readfile($D . '/v/a.md'), 'v:val ==# "sealed_until: 2999-01-01"')))
call assert_equal(1, len(filter(readfile($D . '/v/a.md'), 'v:val =~# "^sealed_until:"')))
" 付け直しても 1 行だけ
GnosisSeal 2998-01-01
call assert_equal(['sealed_until: 2998-01-01'], filter(readfile($D . '/v/a.md'), 'v:val =~# "^sealed_until:"'))
" 開き直すと本文は見えない
bwipeout!
execute 'edit ' . fnameescape($D . '/v/a.md')
call assert_true(empty(filter(getline(1, '$'), 'v:val =~# "秘密の本文"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "封印中です。2998-01-01 まで"')))
call assert_false(&modifiable)
call assert_equal('nofile', &buftype)
call assert_equal('# 未来の自分へ', getline(1))
" 封印中のバッファは保存できない(ファイルは変わらない)
let s:sz = getfsize($D . '/v/a.md')
silent! write
call assert_equal(s:sz, getfsize($D . '/v/a.md'))
" 開封
GnosisUnseal
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "秘密の本文"')))
call assert_true(&modifiable)
" 日付が過ぎたノートは普通に開く
execute 'edit ' . fnameescape($D . '/v/old.md')
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "開ける本文"')))
" 封印中でないノートで開封しても何も起きない / front matter が無いノートには付けない
GnosisUnseal
execute 'edit ' . fnameescape($D . '/v/plain.md')
GnosisSeal 2999-01-01
call assert_equal(['front matter なし'], readfile($D . '/v/plain.md'))
GnosisSeal bogus
" ガードを止める
let g:gnosis_seal_guard = 0
" 封印を外す
bwipeout!
let g:gnosis_seal_guard = 1
let g:gnosis_seal_answer = 1
execute 'edit ' . fnameescape($D . '/v/a.md')
GnosisUnseal
GnosisSeal off
call assert_true(empty(filter(readfile($D . '/v/a.md'), 'v:val =~# "^sealed_until:"')))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
