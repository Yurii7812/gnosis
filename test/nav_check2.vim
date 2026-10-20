source <sfile>:h/nav_head.vim
" 前回の履歴(a,b,a,c,a)が読み戻される。最後と同じノートを開いても履歴は増えない
execute 'edit ' . fnameescape($D . '/v/a.md')
GnosisHistory
call assert_match('(a.md)', getline(3))
call assert_match('(c.md)', getline(4))
call assert_equal(5, len(filter(getline(1, '$'), 'v:val =~# "^- .*\\](.*\\.md)"')))
close
GnosisBack
call assert_equal($D . '/v/c.md', expand('%:p'))
GnosisTrail show 道筋
call assert_match('^# トレイル: 道筋', getline(1))
call assert_equal(5, len(filter(getline(1, '$'), 'v:val =~# "^[0-9]\\. "')))
close
GnosisTrail export 道筋 trails/route.md
call assert_equal($D . '/v/trails/route.md', expand('%:p'))
let s:size = getfsize($D . '/v/trails/route.md')
GnosisTrail export 道筋 trails/route.md
call assert_equal(s:size, getfsize($D . '/v/trails/route.md'))   " 上書きしない
GnosisTrail remove 道筋
let s:w = winnr('$')
GnosisTrail show 道筋
call assert_equal(s:w, winnr('$'))                  " 消したトレイルは開けない
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
