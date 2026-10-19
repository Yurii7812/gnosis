set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
call gnosis#create_vault_files($D . '/v')
call gnosis#capture_import($D . '/pack')
let s:n = $D . '/v/261019100000.md'
let s:original = readfile(s:n)
call assert_true(index(s:original, 'title: こんにちは今日はいい天気だと思ったけどそ...') >= 0)
call assert_true(index(s:original, 'こんにちは今日はいい天気だと思ったけどそうでもないかもしれない') >= 0)
call assert_true(index(s:original, 'ところで最近はいい感じ。') >= 0)
call assert_true(index(s:original, 'topic: ""') >= 0)
call gnosis#capture_import($D . '/pack')
call assert_false(filereadable($D . '/v/261019100000-2.md'))
" 別の vault へ切り替えても、同じスマホの原本を独立して取り込める。
let g:gnosis_root = $D . '/other/'
call gnosis#create_vault_files($D . '/other')
call gnosis#capture_import($D . '/pack')
call assert_true(filereadable($D . '/other/261019100000.md'))
call assert_equal(s:original, readfile(s:n))
let g:gnosis_root = $D . '/v/'
" 取り込み先を消しても、記録だけで再取り込みを妨げない。
call delete(s:n)
call gnosis#capture_import($D . '/pack')
call assert_true(filereadable(s:n))
" PC の追記は残し、スマホ側のトピック変更だけを反映する。
let s:body = readfile(s:n)
call insert(s:body, 'PC での追記', index(s:body, 'BackLink:') - 1)
call writefile(s:body, s:n)
let s:data = json_decode(join(readfile($D . '/pack/capture.json'), "\n"))
let s:data.entries[0].topic = '仕事'
call writefile([json_encode(s:data)], $D . '/pack/capture.json')
call gnosis#capture_import($D . '/pack')
call assert_true(index(readfile(s:n), 'topic: "仕事"') >= 0)
call assert_true(index(readfile(s:n), 'PC での追記') >= 0)
call assert_false(filereadable($D . '/v/261019100000-2.md'))
" 本文の変更時は元の PC ファイルを上書きせず別版として残す。
let s:data.entries[0].text .= "\nスマホの追記"
call writefile([json_encode(s:data)], $D . '/pack/capture.json')
call gnosis#capture_import($D . '/pack')
call assert_true(filereadable($D . '/v/261019100000-2.md'))
call assert_true(index(readfile(s:n), 'PC での追記') >= 0)
call assert_true(index(readfile($D . '/v/261019100000-2.md'), 'スマホの追記') >= 0)
" PC で作ったメモもスマホと同じ分類になる。複数行の選択からまとめて移動できる。
call writefile(['# PC のメモ', '', 'そのままの本文'], $D . '/v/pc.md')
call gnosis#orphans_open()
sleep 100m
call assert_true(index(getline(1, '$'), '## 仕事') >= 0)
call assert_true(index(getline(1, '$'), '## 未所属') >= 0)
call assert_false(index(getline(1, '$'), '## ノート') >= 0)
call assert_true(exists('b:gnosis_topic_list'))
call gnosis#topic#assign(1, line('$'), 'アイデア')
sleep 100m
call assert_true(index(readfile($D . '/v/pc.md'), 'topic: "アイデア"') >= 0)
call assert_true(index(readfile(s:n), 'topic: "アイデア"') >= 0)
call assert_true(index(readfile($D . '/v/pc.md'), 'そのままの本文') >= 0)
call gnosis#topic#assign(1, line('$'), '未所属')
sleep 100m
call assert_true(index(readfile(s:n), 'topic: ""') >= 0)
call assert_true(index(getline(1, '$'), '## 未所属') >= 0)
call assert_false(index(getline(1, '$'), '## 仕事') >= 0)
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
