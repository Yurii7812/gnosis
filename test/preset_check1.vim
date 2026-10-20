source <sfile>:h/preset_head.vim
let g:gnosis_root = $D . '/v/'
runtime plugin/gnosis.vim
let g:gnosis_test_speed = 5
let g:gnosis_test_name = 'abc'
let g:gnosis_test_list = [1, 2]
let g:gnosis_api_key = 'hunter2'
let g:gnosis_test_password = 'hunter2'
let c = gnosis#preset_collect()
call assert_equal(5, c.gnosis_test_speed)
call assert_equal('abc', c.gnosis_test_name)
call assert_false(has_key(c, 'gnosis_test_list'))        " リストは保存しない
call assert_false(has_key(c, 'gnosis_api_key'))          " 秘密らしい名前は保存しない
call assert_false(has_key(c, 'gnosis_test_password'))
call assert_false(has_key(c, 'gnosis_root'))             " vault ごとに違うもの
GnosisPreset save fast
let g:gnosis_test_speed = 99
GnosisPreset load fast
call assert_equal(5, g:gnosis_test_speed)
GnosisPreset list
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^- fast"')))
close
" 手で書き換えたファイルの不正な値(秘密・gnosis_ 以外・型違い)は読み込まない
call writefile([json_encode({'profiles': {'evil': {'gnosis_test_speed': 7, 'gnosis_password': 'x', 'gnosis_root': '/tmp/x', 'vim_evil': 1, 'gnosis_list': [1], 'gnosis_dict': {'a': 1}}}, 'auto': ''})], $D . '/v/.gnosis/presets.json')
GnosisPreset load evil
call assert_equal(7, g:gnosis_test_speed)
call assert_false(exists('g:gnosis_password'))
call assert_false(exists('g:vim_evil'))
call assert_false(exists('g:gnosis_list'))
call assert_notequal('/tmp/x', g:gnosis_root)
" 壊れたファイルでも落ちない
call writefile(['{broken'], $D . '/v/.gnosis/presets.json')
GnosisPreset list
close
GnosisPreset load nothing
" 保存し直して auto を指定
let g:gnosis_test_speed = 5
GnosisPreset save fast
GnosisPreset auto fast
GnosisPreset auto nothing
GnosisPreset save 'bad name!'
call assert_true(!empty(readfile($D . '/v/.gnosis/presets.json')))
GnosisPreset delete fast
GnosisPreset list
call assert_true(empty(filter(getline(1, '$'), 'v:val =~# "^- fast"')))
close
" delete したので、もう一度 save + auto
let g:gnosis_test_speed = 5
GnosisPreset save fast
GnosisPreset auto fast
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
