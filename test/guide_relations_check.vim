" 操作ガイドの所属関係（### Group など）の回帰網。test/guide_relations_net.sh から動かす。
" ガイドも vault の普通のノート: 本文はテンプレートで更新し、同期が書く関係の節は残す。
let s:w = $GR_WORK
let s:v = s:w . '/vault'
let s:out = []
function! s:is_grp(tail, name, file) abort
  " グループのリンクの表示名は「グループ名」か「グループ名:グループの中の表示名」
  return len(a:tail) == 2 && a:tail[0] ==# 'Group:' && a:tail[1] =~# '^\V[' . a:name . '\%(:\[^]]\*\)\=](' . a:file . ')\$'
endfunction
function! s:ok(name, cond) abort
  call add(s:out, (a:cond ? 'OK ' : 'NG ') . a:name)
endfunction
function! s:guide() abort
  return readfile(s:v . '/gnosis-guide.md')
endfunction
function! s:sync() abort
  return system(gnosis#python_cmd() . ' ' . shellescape(g:gnosis_python) . ' update ' . shellescape(s:v))
endfunction
function! s:count(lines, pat) abort
  return len(filter(copy(a:lines), 'v:val =~# a:pat'))
endfunction
" 関係の節（最初の見張り行から最後まで）
function! s:tail(lines) abort
  " Group: は本文冒頭へ移動した。BackLink と離れていても関係だけを返す。
  let l:out = []
  let l:i = match(a:lines, '^Group:$')
  if l:i < 0 | let l:i = match(a:lines, '^### Group$') | endif
  if l:i >= 0
    call add(l:out, 'Group:')
    let l:j = l:i + 1
    while l:j < len(a:lines) && a:lines[l:j] =~# '^\[[^]]*\]([^)]\+)$'
      call add(l:out, a:lines[l:j])
      let l:j += 1
    endwhile
  endif
  let l:k = match(a:lines, '^BackLink:$')
  if l:k >= 0 | call extend(l:out, a:lines[l:k :]) | endif
  return l:out
endfunction

try
  call gnosis#i18n#set_lang('ja')
  call gnosis#vault#create(s:v)
  let g:gnosis_root = s:v . '/'
  let s:g = s:guide()
  let s:idx0 = readfile(s:v . '/index.md')
  let s:header = index(s:idx0, '# Index')
  call s:ok('作成直後: # Index の次に空行', s:header >= 0 && get(s:idx0, s:header + 1, 'missing') ==# '')
  call s:ok('作成直後: Index に操作ガイドへのリンク', index(s:idx0, '[Gnosis 操作ガイド](gnosis-guide.md)') >= 0)
  let s:broken_index = copy(s:idx0)
  call remove(s:broken_index, s:header + 1)
  call writefile(s:broken_index, s:v . '/index.md')
  call gnosis#refresh_guide()
  call s:ok('既存 Index の # Index 直後の空行を復元',
        \ get(readfile(s:v . '/index.md'), s:header + 1, 'missing') ==# '')
  call s:ok('作成直後: ### Group に Index', s:is_grp(s:tail(s:g), 'Index', 'index.md'))

  " 既存の操作ガイドで Group が欠落していても、起動時更新で Index の所属を修復する
  let s:broken = s:guide()
  if s:tail(s:broken) ==# ['Group:', '[Index](index.md)']
    let s:at = index(s:broken, 'Group:')
    if s:at < 0 | let s:at = index(s:broken, '### Group') | endif
    if s:at >= 0
      call remove(s:broken, s:at + 1)
      call remove(s:broken, s:at)
    endif
  endif
  call writefile(s:broken, s:v . '/gnosis-guide.md')
  call gnosis#refresh_guide()
  call s:ok('欠落した Group / Index を修復', s:is_grp(s:tail(s:guide()), 'Index', 'index.md'))
  call s:ok('作成直後: 同期しても変わらない', s:sync() =~# 'updated 0 file')

  " 起動時の更新（プラグインの更新でテンプレートが変わった場合も含む）
  call writefile(s:guide()[: 10] + ['古い本文の行'] + s:tail(s:guide()), s:v . '/gnosis-guide.md')
  call gnosis#refresh_guide()
  let s:g = s:guide()
  call s:ok('更新: 本文はテンプレートに戻る', index(s:g, '古い本文の行') < 0 && index(s:g, '## 第 1 部　はじめての人のための基本') >= 0)
  call s:ok('更新: Group の Index が残る', s:is_grp(s:tail(s:g), 'Index', 'index.md'))
  call s:ok('更新: 見出しが重複しない', s:count(s:g, '^Group:$') == 1 && s:count(s:g, '^---$') == 2)
  call s:ok('更新: 同期しても変わらない', s:sync() =~# 'updated 0 file')
  let s:before = s:guide()
  call gnosis#refresh_guide()
  call s:ok('再起動（もう一度更新）: 変わらない', s:guide() ==# s:before)

  " 別のグループへ移す（Index の本文からガイドを外し、グループ「ハーブ」の本文に入れる）
  call writefile(['---', 'time: 2026-10-13 14:04:00', 'title: ハーブ', 'attribute: group', '---', '', '# ハーブ', '[Gnosis 操作ガイド](gnosis-guide.md)'], s:v . '/261013140400.md')
  let s:idx = filter(readfile(s:v . '/index.md'), 'v:val !~# "gnosis-guide.md"') + ['[ハーブ](261013140400.md)']
  call writefile(s:idx, s:v . '/index.md')
  call s:sync()
  let s:g = s:guide()
  call s:ok('移動: Group がハーブになる', s:is_grp(s:tail(s:g), 'ハーブ', '261013140400.md'))
  call s:ok('移動: 古い所属（Index）が残らない', s:count(s:tail(s:g), 'index\.md') == 0)
  call gnosis#refresh_guide()
  call s:ok('移動後の更新: ハーブが残る', s:is_grp(s:tail(s:guide()), 'ハーブ', '261013140400.md'))
  call s:ok('移動後の更新: 同期しても変わらない（相手側のリンクも消えない）',
        \ s:sync() =~# 'updated 0 file' && !empty(filter(readfile(s:v . '/261013140400.md'), 'v:val =~# "gnosis-guide.md"')))

  " 複数のグループに所属
  let s:idx = readfile(s:v . '/index.md') + ['[Gnosis 操作ガイド](gnosis-guide.md)']
  call writefile(s:idx, s:v . '/index.md')
  call s:sync()
  call gnosis#refresh_guide()
  let s:t = s:tail(s:guide())
  call s:ok('複数所属: Index とハーブの両方', s:count(s:t, '^\[Index\%(:[^]]*\)\=\](index\.md)$') == 1 && s:count(s:t, '^\[ハーブ\%(:[^]]*\)\=\](261013140400\.md)$') == 1)
  call s:ok('複数所属: 同期しても変わらない', s:sync() =~# 'updated 0 file')

  " 普通のノートの本文からガイドへリンク → ガイドに BackLink:（通常のノートと同じ）
  call writefile(['---', 'time: 2026-10-13 14:05:00', 'title: メモ', '---', '', '# メモ', '使い方は[Gnosis 操作ガイド](gnosis-guide.md)を見る'], s:v . '/261013140500.md')
  call s:sync()
  call gnosis#refresh_guide()
  let s:t = s:tail(s:guide())
  call s:ok('BackLink: 本文からのリンクが BackLink: に出る', index(s:t, 'BackLink:') >= 0 && s:count(s:t, '261013140500\.md') == 1)
  call s:ok('BackLink: 更新しても残り、同期しても変わらない', s:sync() =~# 'updated 0 file')
  call delete(s:v . '/261013140500.md')
  call s:sync()
  call s:ok('BackLink: リンク元を消すと消える', s:count(s:tail(s:guide()), '261013140500') == 0)

  " 言語を英語に: 題と本文は英語、関係の節はそのまま
  let s:t = s:tail(s:guide())
  call gnosis#i18n#set_lang('en')
  call gnosis#refresh_guide()
  " 題変更のリンク更新は非同期。完了前の状態をスナップショットにしない。
  for s:wait in range(50)
    let s:pending = 0
    for s:ref in [s:v . '/index.md', s:v . '/261013140400.md']
      if index(readfile(s:ref), '[Gnosis 操作ガイド](gnosis-guide.md)') >= 0
        let s:pending = 1
      endif
    endfor
    if !s:pending | break | endif
    sleep 100m
  endfor
  let s:g = s:guide()
  call s:ok('英語: 題が英語', index(s:g, '# Gnosis Guide') >= 0)
  " グループのリンクの表示名は「グループ名:グループの中の表示名」なので、題が変わればそこも変わる。リンク先で比べる
  call s:ok('英語: 関係の節が残る', map(copy(s:tail(s:g)), 'substitute(v:val, "^\\[[^]]*\\]", "", "")') ==# map(copy(s:t), 'substitute(v:val, "^\\[[^]]*\\]", "", "")'))
  let s:before_sync = {}
  for s:fp in glob(s:v . '/*.md', 1, 1)
    let s:before_sync[s:fp] = readfile(s:fp)
  endfor
  let s:english_update = s:sync()
  call s:ok('英語: 同期しても変わらない', s:english_update =~# 'updated 0 file')
  if s:english_update !~# 'updated 0 file'
    call add(s:out, 'INFO English sync: ' . substitute(s:english_update, '\\n', ' ', 'g'))
    for s:fp in keys(s:before_sync)
      if readfile(s:fp) !=# s:before_sync[s:fp]
        call add(s:out, 'INFO changed: ' . fnamemodify(s:fp, ':t'))
        let s:b = s:before_sync[s:fp]
        let s:a = readfile(s:fp)
        for s:k in range(0, max([len(s:b), len(s:a)]) - 1)
          if get(s:b, s:k, '<EOF>') !=# get(s:a, s:k, '<EOF>')
            call add(s:out, 'INFO first delta line ' . (s:k + 1) . ' before=' . string(get(s:b, s:k, '<EOF>')) . ' after=' . string(get(s:a, s:k, '<EOF>')))
            break
          endif
        endfor
      endif
    endfor
  endif
  call gnosis#i18n#set_lang('ja')

  " ガイド本文の説明（`### Group` などの書き方の説明）を関係の節と取り違えない
  for s:lang in ['ja', 'en']
    let s:body = readfile(expand('<sfile>:p:h:h') . '/guide/' . s:lang . '.md')
    call s:ok('本文（' . s:lang . '）に見張り行と同じ行が無い', empty(s:tail(s:body)))
  endfor
catch
  call add(s:out, 'NG 例外: ' . v:exception . ' @ ' . v:throwpoint)
endtry
call writefile(s:out, s:w . '/result.txt')
qa!
