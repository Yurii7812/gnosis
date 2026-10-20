set nocp
set nomore
let g:gnosis_language = "ja"
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_open_index_on_startup = 0
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
let g:gnosis_root = $D . '/v/'
GnosisTimerStatus
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "動いていません"')))
close
GnosisTimerStart! 資料作り
GnosisTimerStatus
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "計測中: 資料作り"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "ポモドーロ 1 回目・作業中"')))
close
" 動いている間に 2 つ目は始められない
GnosisTimerStart 別の
" 1 分未満で止めると記録しない
GnosisTimerStop
call assert_false(filereadable($D . '/v/記録.md'))
" 古い開始時刻のタイマーを直接作って、止めると行が追記される
call mkdir($D . '/v/.state', 'p')
call writefile(['{"label": "実験", "start": "2020-01-01T09:00", "pomodoro": false}'], $D . '/v/.state/timer.json')
GnosisTimerStop
call assert_true(filereadable($D . '/v/記録.md'))
call assert_true(!empty(filter(readfile($D . '/v/記録.md'), 'v:val =~# "^- ⏱ 2020-01-01 09:00-.* 実験$"')))
GnosisHabit 運動
GnosisHabit 運動
GnosisLog 昼食 カレー
GnosisHabitStats
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "^## 運動"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "連続 1 日"')))
close
GnosisDayRecord
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "昼食 カレー"')))
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "✔ 運動"')))
close
GnosisDayRecord 2020-01-01
call assert_true(!empty(filter(getline(1, '$'), 'v:val =~# "実験"')))
close
GnosisTimeReport 年
call assert_match('^# 時間の記録 ', getline(1))
call assert_true(empty(filter(getline(1, '$'), 'v:val =~# "実験"')))   " 今年の集計に 2020 年の記録は入らない
close
let s:w = winnr('$')
GnosisHabitStats 存在しない習慣
call assert_equal(s:w, winnr('$'))
call writefile(v:errors, $D . '/errors')
if !empty(v:errors) | cquit | endif
qa!
