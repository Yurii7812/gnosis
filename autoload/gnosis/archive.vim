" autoload/gnosis/archive.vim — zip / 7z を開いている vault に取り込む（:GnosisImportArchive）
"   書庫の場所を指定 → パスワードが要れば入力 → 増えるもの・変わるものを見て確認 → vault を更新 → 完了。
"   本体は python/archive_import.py。ドット始まりの場所（.state・.trash・.git・.crypt）は取り込まない。
"   既定は「置き換え」: 書庫の内容を vault の正とし、書庫に無い古いファイルは消す。置き換わる・消えるファイルの元は
"   <vault>/.trash/archive-import-<時刻>/ に先に退避する（戻せる）。守って触らないもの: 書庫より新しい vault のファイル
"   （書庫のあとの作業・古い記録での上書き）と、書庫側の中身が壊れていそうなファイル。別の vault の書庫・古い書庫は強く警告する。

let s:here = expand('<sfile>:p:h:h:h')

function! s:py(args, ...) abort
  let l:cmd = join(map([gnosis#python_cmd(), s:here . '/python/archive_import.py'] + a:args, 'shellescape(v:val)'), ' ')
  let l:out = a:0 ? gnosis#sh#system(l:cmd . ' < ' . shellescape(a:1) . ' 2>/dev/null') : gnosis#sh#system(l:cmd . ' </dev/null 2>/dev/null')
  try
    let l:d = json_decode(l:out)
  catch
    return {'error': gnosis#i18n#tr('取り込みの処理が失敗しました')}
  endtry
  return type(l:d) == v:t_dict ? l:d : {'error': gnosis#i18n#tr('取り込みの処理が失敗しました')}
endfunction

function! s:root() abort
  let l:r = trim(get(g:, 'gnosis_root', ''))
  return empty(l:r) ? '' : substitute(fnamemodify(l:r, ':p'), '/$', '', '')
endfunction

" 展開して、増える・変わるものを調べる。パスワードは一時ファイル（自分だけ読める）で渡し、コマンドラインに出さない
function! s:plan(root, file, pw) abort
  if a:pw is v:null
    return s:py(['plan', a:root, a:file])
  endif
  let l:pf = tempname()
  call system('install -m 600 /dev/null ' . shellescape(l:pf))
  call writefile([a:pw], l:pf)
  try
    return s:py(['plan', a:root, a:file, '--pw-stdin'], l:pf)
  finally
    call delete(l:pf)
  endtry
endfunction

" 反映まで（確認なし）。試験はここを直接呼ぶ。opts: {'merge': 1} 足す・更新するだけ／{'force': 1} 守って残すものも上書き。
" 返り値: {'added','updated','removed','same','held','protected','backup','files'} か {'error'} か {'need_password'}
function! gnosis#archive#run(file, pw, ...) abort
  let l:root = s:root()
  if empty(l:root)
    return {'error': gnosis#i18n#tr('vault が開かれていません')}
  endif
  let l:p = s:plan(l:root, a:file, a:pw)
  if has_key(l:p, 'error') || has_key(l:p, 'need_password')
    return l:p
  endif
  return s:apply(l:root, l:p.stage, a:0 ? a:1 : {})
endfunction

function! s:apply(root, stage, opts) abort
  let l:r = s:py(['apply', a:root, a:stage] + (get(a:opts, 'merge', 0) ? ['--merge'] : []) + (get(a:opts, 'force', 0) ? ['--force'] : []))
  if !has_key(l:r, 'error')
    call s:after(a:root, l:r.files)
  endif
  return l:r
endfunction

" 取り込んだノートを画面側の一覧・曼荼羅にも反映させる
function! s:after(root, files) abort
  silent! call gnosis#fznav#invalidate()
  silent! call gnosis#listnav#invalidate()
  let l:md = filter(copy(a:files), 'v:val =~? "\\.md$"')
  if !empty(l:md) && gnosis#mview#is_open()
    for l:i in range(0, len(l:md) - 1, 100)
      call system(join(map([gnosis#python_cmd(), s:here . '/python/mandala_cache.py', 'refresh', a:root, '--only'] + l:md[l:i : l:i + 99], 'shellescape(v:val)'), ' ') . ' >/dev/null 2>&1')
    endfor
    silent! call gnosis#mview#refresh()
  endif
endfunction

function! s:say(msg) abort
  redraw
  echo a:msg
endfunction

function! gnosis#archive#import(...) abort
  let l:root = s:root()
  if empty(l:root)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: vault が開かれていません') | echohl NONE
    return
  endif
  if gnosis#vault_locked_flag() == 1
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: vault がロック中です（先に開いてください）') | echohl NONE
    return
  endif
  if !executable('7z') && !executable('7zz') && !executable('7za')
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 7z が必要です（p7zip-full など）') | echohl NONE
    return
  endif
  let l:file = a:0 ? trim(a:1) : ''
  if empty(l:file)
    let l:file = trim(input(gnosis#i18n#tr('取り込む zip / 7z の場所: '), '', 'file'))
  endif
  let l:file = fnamemodify(expand(substitute(l:file, '^["'']\|["'']$', '', 'g')), ':p')
  if empty(l:file) || !filereadable(l:file)
    echohl WarningMsg | echo "\n" . gnosis#i18n#tr('Gnosis: 書庫が見つかりません: ') . l:file | echohl NONE
    return
  endif
  call s:say(gnosis#i18n#tr('Gnosis: 展開しています…'))
  let l:p = s:plan(l:root, l:file, v:null)
  let l:tries = 0
  while has_key(l:p, 'need_password')
    if l:tries >= 3
      echohl WarningMsg | echo "\n" . gnosis#i18n#tr('Gnosis: パスワードが合いません。取り込みをやめました') | echohl NONE
      return
    endif
    let l:pw = inputsecret(gnosis#i18n#tr(l:tries ? 'パスワードが違います。もう一度: ' : 'パスワード: '))
    if empty(l:pw)
      echo "\n" . gnosis#i18n#tr('Gnosis: 取り込みをやめました')
      return
    endif
    let l:tries += 1
    call s:say(gnosis#i18n#tr('Gnosis: 展開しています…'))
    let l:p = s:plan(l:root, l:file, l:pw)
  endwhile
  if has_key(l:p, 'error')
    echohl WarningMsg | echo "\n" . 'Gnosis: ' . l:p.error | echohl NONE
    return
  endif
  let l:n = len(l:p.new) + len(l:p.changed) + len(l:p.removed)
  if l:n == 0 && empty(l:p.held)
    call s:py(['discard', l:p.stage])
    echo "\n" . printf(gnosis#i18n#tr('Gnosis: 変わるものはありません（同じ %d 件）'), len(l:p.same))
    return
  endif
  let l:lines = [printf(gnosis#i18n#tr('追加 %d 件・更新 %d 件・削除 %d 件・同じ %d 件'), len(l:p.new), len(l:p.changed), len(l:p.removed), len(l:p.same))]
  for [l:tag, l:list] in [['更新', l:p.changed], ['削除', l:p.removed], ['追加', l:p.new]]
    for l:f in l:list[0 : 3]
      call add(l:lines, '  ' . gnosis#i18n#tr(l:tag) . ' ' . l:f)
    endfor
  endfor
  if len(l:p.new) + len(l:p.changed) + len(l:p.removed) > 12
    call add(l:lines, '  …')
  endif
  if !empty(l:p.protected)
    call add(l:lines, printf(gnosis#i18n#tr('書庫のあとに書いた vault のファイル %d 件は、消さずに残します'), len(l:p.protected)))
  endif
  if !empty(l:p.held)
    call add(l:lines, printf(gnosis#i18n#tr('守って上書きしないもの %d 件:'), len(l:p.held)))
    for l:h in l:p.held[0 : 4]
      call add(l:lines, '  ' . l:h.rel . '  — ' . join(l:h.why, ' / '))
    endfor
    if len(l:p.held) > 5
      call add(l:lines, '  …')
    endif
  endif
  if l:n > 0
    call add(l:lines, gnosis#i18n#tr('（置き換わる・消えるファイルの元は、先に .trash/archive-import-… に退避します）'))
  endif
  echo "\n" . join(l:lines, "\n")
  let l:strong = !empty(l:p.strong)
  if l:strong
    echohl ErrorMsg
    echo "\n" . gnosis#i18n#tr('⚠ 警告: 取り込む前によく確認してください')
    for l:w in l:p.strong
      echo '  ・' . l:w
    endfor
    echohl NONE
    let l:ask = gnosis#i18n#tr('置き換えるには yes と入力（足す・更新するだけは m、やめるは Enter）: ')
  else
    let l:ask = gnosis#i18n#tr('vault を置き換えますか？ [y 置き換え / m 足す・更新するだけ / N やめる]') . (empty(l:p.held) ? ' ' : gnosis#i18n#tr('（! で守っているものも上書き）') . ' ')
  endif
  let l:ans = trim(input(l:ask))
  let l:opts = {}
  if l:strong
    if l:ans ==# 'yes' || (l:ans ==# 'yes!' && !empty(l:p.held))
      let l:opts.force = l:ans ==# 'yes!'
    elseif l:ans ==? 'm'
      let l:opts.merge = 1
    else
      let l:opts = v:null
    endif
  else
    if l:ans ==? 'y' || (l:ans ==# '!' && !empty(l:p.held)) || (l:ans ==? 'y!' && !empty(l:p.held))
      let l:opts.force = l:ans =~# '!'
    elseif l:ans ==? 'm'
      let l:opts.merge = 1
    else
      let l:opts = v:null
    endif
  endif
  if l:opts is v:null
    call s:py(['discard', l:p.stage])
    echo "\n" . gnosis#i18n#tr('Gnosis: 取り込みをやめました')
    return
  endif
  let l:r = s:apply(l:root, l:p.stage, l:opts)
  if has_key(l:r, 'error')
    echohl WarningMsg | echo "\n" . 'Gnosis: ' . l:r.error | echohl NONE
    return
  endif
  echo "\n" . printf(gnosis#i18n#tr('Gnosis: 取り込みました（追加 %d 件・更新 %d 件・削除 %d 件。守って残したもの %d 件）'), l:r.added, l:r.updated, l:r.removed, l:r.held)
  if !empty(l:r.backup)
    echo printf(gnosis#i18n#tr('元のファイルは %s にあります'), l:r.backup)
  endif
endfunction
