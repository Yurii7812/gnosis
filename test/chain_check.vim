set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
let s:hub = readfile($D . '/v/hub.md')
" 試走(! なし): 何を書くかを見せるだけ
GnosisChain related hub.md 水やり
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "試走。何も書いていません"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "\\[ハーブ2\\](h2.md)"')))
close
call assert_equal(s:hub, readfile($D . '/v/hub.md'))
" 番号で選ぶ(1 件だけ)
GnosisChain related hub.md #1 水やり
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "1 件を足す"')))
close
" 適用(!)
GnosisChain! related hub.md 水やり
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "書きました"')))
close
let s:after = readfile($D . '/v/hub.md')
call assert_true(index(s:after, 'Related:') >= 0)
call assert_true(index(s:after, '[ハーブ1](h1.md)') >= 0 && index(s:after, '[ハーブ2](h2.md)') >= 0)
" 取り消し: そのあと手で変えると拒否 → ! で戻す
call writefile(s:after + ['手書き'], $D . '/v/hub.md')
GnosisChainUndo
call assert_equal(s:after + ['手書き'], readfile($D . '/v/hub.md'))
GnosisChainUndo!
call assert_equal(s:hub, readfile($D . '/v/hub.md'))
" 索引案(新規)
GnosisChain! index idx.md 水やり
call assert_true(filereadable($D . '/v/idx.md'))
close
" 不正・拒否: 画面を開かない
let s:w = winnr('$')
GnosisChain related hub.md
GnosisChain related ../x.md 水やり
GnosisChain bogus hub.md 水やり
GnosisChain related hub.md #9 水やり
GnosisChain! index idx.md 水やり
call assert_equal(s:w, winnr('$'))
call assert_equal(1, len(glob($D . '/v/idx.md', 0, 1)))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
