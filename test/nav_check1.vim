source <sfile>:h/nav_head.vim
" 履歴: a → b → c と開き、戻る・進む
for s:n in ['a', 'b', 'c']
  execute 'edit ' . fnameescape($D . '/v/' . s:n . '.md')
endfor
GnosisBack
call assert_equal($D . '/v/b.md', expand('%:p'))
GnosisBack
call assert_equal($D . '/v/a.md', expand('%:p'))
GnosisBack
call assert_equal($D . '/v/a.md', expand('%:p'))     " これより前は無い
GnosisForward
call assert_equal($D . '/v/b.md', expand('%:p'))
" 途中から別のノートを開くと、その先の「進む」は捨てる
execute 'edit ' . fnameescape($D . '/v/d.md')
GnosisForward
call assert_equal($D . '/v/d.md', expand('%:p'))
GnosisBack
call assert_equal($D . '/v/b.md', expand('%:p'))
GnosisHistory
call assert_equal('# ノートを開いた履歴（新しい順）', getline(1))
call assert_match('(d.md)', getline(3))
call assert_match('(b.md)', getline(4))
call assert_match('(a.md)', getline(5))
call assert_true(empty(filter(getline(1, '$'), 'v:val =~# "(c.md)"')))     " 捨てた c は無い
call cursor(5, 1)
execute "normal \<CR>"
call assert_equal($D . '/v/a.md', expand('%:p'))
" ブックマーク
GnosisBookmark add 2
execute 'edit ' . fnameescape($D . '/v/c.md')
GnosisBookmark add
GnosisBookmark list
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "\\[2\\] \\[甲\\](a.md)"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "\\[丙\\](c.md)"')))
close
GnosisBookmark go 2
call assert_equal($D . '/v/a.md', expand('%:p'))
GnosisBookmark go 9
call assert_equal($D . '/v/a.md', expand('%:p'))      " 空のスロットでは動かない
GnosisBookmark remove
GnosisBookmark list
call assert_true(empty(filter(getline(1, '$'), 'v:val =~# "(a.md)"')))
close
" 最近・知識リマインダー
GnosisRecent created
call assert_equal('# 最近作ったノート', getline(1))
call assert_match('(d.md)', getline(3))               " 一番新しく作った
close
GnosisRecent imported
call assert_equal('# 最近スマホから取り込んだノート', getline(1))
call assert_equal('なし', getline(3))
close
GnosisRecent viewed
call assert_equal('# 最近開いたノート', getline(1))
close
GnosisKnowledge
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "昔に書いた問い"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "これは本当にそうなのか調べる"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "(b.md):"')))
close
" トレイル: 履歴から保存
GnosisTrail save 道筋 history
GnosisTrail list
" 履歴は a,b,a,c,a（履歴画面から開くのも新しく開いたのと同じ扱い）。連続した同じノートだけ 1 歩にまとめる
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "道筋（5 歩）"')))
close
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
