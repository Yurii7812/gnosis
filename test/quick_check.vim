source <sfile>:h/restore_head.vim
let s:before = glob($D . '/v/*.md', 0, 1)
GnosisQuick
let s:after = glob($D . '/v/*.md', 0, 1)
let s:new = filter(copy(s:after), 'index(s:before, v:val) < 0')
" 何も聞かずに、新しいノートができる(時系列記録の親ノートが無ければ、それも一緒にできる = 最大 2 件)
call assert_true(len(s:new) >= 1 && len(s:new) <= 2)
call assert_true(index(s:new, expand('%:p')) >= 0)               " いま開いているのが、新しいノート
let s:cur = expand('%:p')
call assert_match('^\d\{12,\}\.md$', fnamemodify(s:cur, ':t'))
call assert_true(!empty(filter(readfile(s:cur), 'v:val =~# "^time: "')))
call assert_true(!empty(filter(readfile(s:cur), 'v:val =~# "^# "')))
call assert_true(empty(filter(readfile(s:cur), 'v:val =~# "^\\(ParentBranch\\|Group\\|Context\\|Related\\):"')))   " 関係のブロックは付けない(つなぐのは後)
if len(s:new) == 2                                                " もう 1 つは、時系列記録の親ノート(まだ無いときだけ作られる)
  let s:root_note = filter(copy(s:new), 'v:val !=# s:cur')[0]
  call assert_true(!empty(filter(readfile(s:root_note), 'v:val ==# "timeline: true"')))
endif
stopinsert
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
