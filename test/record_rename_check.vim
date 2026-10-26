set nomore
call gnosis#i18n#set_lang('ja')
let g:gnosis_autosave = 0
let g:gnosis_autosync = 0
let g:gnosis_diary_auto = 0
let g:gnosis_skip_interactive_mount = 1
let s:results = []

function! s:ok(name, condition) abort
  call add(s:results, (a:condition ? 'OK ' : 'NG ') . a:name)
  call writefile(s:results, $RECORD_RENAME_WORK . '/result.txt')
endfunction

function! s:put(file, title, body, timeline) abort
  call writefile(['---', 'time: 2026-10-19 12:00:00'] + (a:timeline ? ['timeline: true'] : [])
        \ + ['---', '', '# ' . a:title, ''] + a:body, s:root . '/' . a:file)
endfunction

function! s:init(name) abort
  silent! %bwipeout!
  let s:root = $RECORD_RENAME_WORK . '/' . a:name
  call mkdir(s:root, 'p')
  let g:gnosis_root = s:root . '/'
  call s:put('index.md', 'Index', ['[時系列記録](rec.md)'], 0)
  call s:put('rec.md', '時系列記録', ['[夢](kind.md)', '[日記](diary.md)'], 1)
  call s:put('kind.md', '夢', ['ParentBranch:', '[時系列記録](rec.md)', '', '[2026-夢](year.md)'], 1)
  call s:put('year.md', '2026-夢', ['ParentBranch:', '[夢](kind.md)', '', '[2026-10-夢](month.md)'], 1)
  call s:put('month.md', '2026-10-夢', ['ParentBranch:', '[2026-夢](year.md)', '', '[2026-10-19-MO-夢](day.md)'], 1)
  call s:put('day.md', '2026-10-19-MO-夢', ['ParentBranch:', '[2026-10-夢](month.md)', '', '日ごとの本文'], 0)
  call s:put('diary.md', '日記', ['ParentBranch:', '[時系列記録](rec.md)'], 1)
  execute 'edit ' . fnameescape(s:root . '/kind.md')
endfunction

function! s:rename(key, title, answer) abort
  let l:keys = (a:key ==# 'zR' ? "\<C-u>" : '') . a:title . "\<CR>"
  if !empty(a:answer) | let l:keys .= a:answer . "\<CR>" | endif
  call feedkeys(a:key . l:keys, 'xt')
  " 普通の zr は従来どおり非同期でリンクを同期する。次の操作は完了後に行う。
  sleep 300m
  silent checktime
endfunction

function! s:title(file, title) abort
  return index(readfile(s:root . '/' . a:file), '# ' . a:title) >= 0
endfunction

try
  call s:init('yes')
  call s:rename('zr', '夢日記', 'y')
  call s:ok('zr y: 種類を改題', s:title('kind.md', '夢日記'))
  call s:ok('zr y: 年月日を改題', s:title('year.md', '2026-夢日記') && s:title('month.md', '2026-10-夢日記') && s:title('day.md', '2026-10-19-MO-夢日記'))
  call s:ok('既存同期がリンク表示名を更新', index(readfile(s:root . '/year.md'), '[2026-10-夢日記](month.md)') >= 0)
  call s:ok('開いていた種類のバッファも更新', gnosis#current_title() ==# '夢日記')
  call s:ok('件数を表示', execute('messages') =~# '年 1・月 1・日 1')
  " 今日の追記でも月を再利用することを、実行日が変わっても確かめる。
  call s:init('reuse')
  let s:year = strftime('%Y')
  let s:month = strftime('%Y-%m')
  let s:day = strftime('%Y-%m-%d')
  call s:put('kind.md', '夢', ['ParentBranch:', '[時系列記録](rec.md)', '', '[' . s:year . '-夢](year.md)'], 1)
  call s:put('year.md', s:year . '-夢', ['ParentBranch:', '[夢](kind.md)'], 1)
  call s:put('month.md', s:month . '-夢', ['ParentBranch:', '[' . s:year . '-夢](year.md)'], 1)
  call s:put('day.md', s:day . '-MO-夢', ['ParentBranch:', '[' . s:month . '-夢](month.md)', '', '本文'], 0)
  silent edit!
  call s:rename('zr', '夢日記', 'y')
  call gnosis#record_open('夢日記')
  stopinsert
  let s:months = filter(glob(s:root . '/*.md', 1, 1), 'index(readfile(v:val), "# " . s:month . "-夢日記") >= 0')
  call s:ok('改題後の記録追記でも同じ月を再利用', len(s:months) == 1 && fnamemodify(s:months[0], ':t') ==# 'month.md')

  call s:init('no')
  call s:rename('zr', '夢日記', 'n')
  call s:ok('zr n: 種類だけを改題', s:title('kind.md', '夢日記') && s:title('year.md', '2026-夢') && s:title('month.md', '2026-10-夢') && s:title('day.md', '2026-10-19-MO-夢'))

  call s:init('capital')
  call s:rename('zR', '夢日記', 'y')
  call s:ok('zRでも一括改題', s:title('kind.md', '夢日記') && s:title('day.md', '2026-10-19-MO-夢日記'))

  call s:init('collision')
  call s:put('other.md', '筋トレ', ['ParentBranch:', '[時系列記録](rec.md)'], 1)
  call s:rename('zr', '筋トレ', '')
  call s:ok('衝突なら種類も子孫も変更しない', s:title('kind.md', '夢') && s:title('year.md', '2026-夢'))
  call s:rename('zr', '日記', '')
  call s:ok('予約名も拒否', s:title('kind.md', '夢'))

  call s:init('protected')
  execute 'edit ' . fnameescape(s:root . '/diary.md')
  call s:rename('zr', '別の日記', '')
  call s:ok('日記を保護', s:title('diary.md', '日記'))
  execute 'edit ' . fnameescape(s:root . '/rec.md')
  call s:rename('zr', '別の記録', '')
  call s:ok('時系列記録を保護', s:title('rec.md', '時系列記録'))

  call s:init('ordinary')
  call s:put('normal.md', '普通', ['本文'], 0)
  execute 'edit ' . fnameescape(s:root . '/normal.md')
  call s:rename('zr', '普通の新名', '')
  call s:ok('普通のノートには確認を追加しない', s:title('normal.md', '普通の新名'))
  execute 'edit ' . fnameescape(s:root . '/year.md')
  call s:rename('zr', '年のメモ', '')
  call s:ok('種類でないtimelineノートにも確認を追加しない', s:title('year.md', '年のメモ') && s:title('day.md', '2026-10-19-MO-夢'))

  call s:init('dirty')
  let s:nr = bufadd(s:root . '/day.md')
  call bufload(s:nr)
  call setbufline(s:nr, 8, '未保存の本文')
  call s:rename('zr', '夢日記', 'y')
  call s:ok('未保存の子孫を上書きせず一括改題を中止', s:title('kind.md', '夢') && s:title('day.md', '2026-10-19-MO-夢') && getbufvar(s:nr, '&modified'))

  call add(s:results, 'DONE')
catch
  call add(s:results, 'NG exception: ' . v:exception . ' @ ' . v:throwpoint)
endtry
call writefile(s:results, $RECORD_RENAME_WORK . '/result.txt')
qa!
