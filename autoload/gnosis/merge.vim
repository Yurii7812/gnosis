" ---------------------------------------------------------------------------
" ノートのマージ（\l → m）と取り消し（:GnosisMergeUndo）
"   \l で 1 つ選んで m を押すと、どちらへまとめるかを聞く:
"     o … 開いているノートへ、選んだノートをマージする（選んだノートは消える）
"     s … 選んだノートへ、開いているノートをマージする（開いているノートは消える）
"   本文は相手の本文の最後に入り、関係（Context・BranchGroup・Related・親）と、ほかのノートからのリンクも
"   相手へ移る。実体は python/merge_notes.py。変える前に控えを取るので :GnosisMergeUndo で元に戻せる。
" ---------------------------------------------------------------------------

let s:script_path = fnamemodify(expand('<sfile>:p:h:h:h') . '/python/merge_notes.py', ':p')
let s:sync_path = fnamemodify(expand('<sfile>:p:h:h:h') . '/python/note_format_v2.py', ':p')

function! s:root() abort
  let l:r = get(g:, 'gnosis_root', '')
  return empty(l:r) ? '' : substitute(fnamemodify(l:r, ':p'), '[\\/]\+$', '', '')
endfunction

function! s:run(args) abort
  let l:cmd = gnosis#python_cmd() . ' ' . shellescape(s:script_path) . ' ' . join(map(copy(a:args), 'shellescape(v:val)'), ' ')
  let l:out = gnosis#sh#system(l:cmd)
  try
    return json_decode(trim(split(l:out, "\n")[-1]))
  catch
    return {'ok': 0, 'code': 'error', 'message': trim(l:out)}
  endtry
endfunction

function! s:sync(root) abort
  call gnosis#sh#system(gnosis#python_cmd() . ' ' . shellescape(s:sync_path) . ' update ' . shellescape(a:root))
endfunction

" 1 文字を読む（g:gnosis_test_keys があればそこから。試験用）
function! s:key() abort
  if exists('g:gnosis_test_keys') && !empty(g:gnosis_test_keys)
    return remove(g:gnosis_test_keys, 0)
  endif
  return getcharstr()
endfunction

function! s:warn(msg) abort
  echohl WarningMsg | echo 'Gnosis: ' . a:msg | echohl NONE
endfunction

function! s:title(path) abort
  return gnosis#note_title(a:path)
endfunction

" 開いているノートを読み直す（未保存の変更があるバッファは触らない）。消えたノートのバッファは閉じる
function! s:refresh(paths, gone) abort
  for l:p in a:paths
    let l:nr = bufnr(l:p)
    if l:nr < 0 || !bufloaded(l:nr) || getbufvar(l:nr, '&modified')
      continue
    endif
    if l:nr == bufnr('%')
      let l:view = winsaveview()
      silent! edit!
      call winrestview(l:view)
    else
      silent! execute 'checktime ' . l:nr
    endif
  endfor
  let l:nr = bufnr(a:gone)
  if !empty(a:gone) && l:nr > 0 && l:nr != bufnr('%') && !filereadable(a:gone)
    silent! execute 'bwipeout! ' . l:nr
  endif
endfunction

" \l で選んだ a:link（Markdown リンク 1 本）と、開いているノートをマージする。戻り値はマージしたか。
function! gnosis#merge#pick(link) abort
  let l:root = s:root()
  let l:cur = expand('%:p')
  let l:m = matchlist(a:link, '\v\[%(\\.|[^\]\\])*\]\(([^)]*)\)')
  let l:other = empty(l:m) ? '' : fnamemodify(gnosis#resolve_link(substitute(l:m[1], '#.*$', '', ''), expand('%:p:h')), ':p')
  if empty(l:root) || empty(l:other) || !filereadable(l:other) || !filereadable(l:cur)
    call s:warn(gnosis#i18n#tr('マージするノートが見つかりません'))
    return 0
  endif
  if l:other ==# l:cur
    call s:warn(gnosis#i18n#tr('同じノートはマージできません'))
    return 0
  endif
  let l:a = s:title(l:cur)
  let l:b = s:title(l:other)
  echo printf(gnosis#i18n#tr('o=開いている「%s」へ「%s」をマージ / s=選んだ「%s」へ「%s」をマージ  (Esc)'), l:a, l:b, l:b, l:a)
  let l:ch = s:key()
  redraw
  if l:ch ==# 'o'
    let [l:src, l:dst] = [l:other, l:cur]
  elseif l:ch ==# 's'
    let [l:src, l:dst] = [l:cur, l:other]
  else
    echo 'Gnosis: ' . gnosis#i18n#tr('マージしませんでした')
    return 0
  endif
  " ディスクの内容でまとめるので、開いているノートの未保存の変更を先に保存する
  if &modified && &buftype ==# ''
    silent! update
  endif
  for l:p in [l:src, l:dst]
    let l:nr = bufnr(l:p)
    if l:nr > 0 && getbufvar(l:nr, '&modified')
      call s:warn(gnosis#i18n#tr('未保存の変更があるノートがあります。先に保存してください（何も変更していません）'))
      return 0
    endif
  endfor
  let l:r = s:run(['merge', l:root, l:src, l:dst])
  if !get(l:r, 'ok', 0)
    call s:warn(gnosis#i18n#tr('マージできませんでした: ') . get(l:r, 'message', ''))
    return 0
  endif
  if l:src ==# l:cur
    " 開いていたノートは消えたので、まとめた先を開く
    call gnosis#push_history()
    silent execute 'edit ' . fnameescape(l:dst)
  endif
  call s:refresh([l:dst] + get(l:r, 'changed', []), l:src)
  echo printf(gnosis#i18n#tr('Gnosis: 「%s」を「%s」へマージしました（取り消しは :GnosisMergeUndo）'), get(l:r, 'src_title', ''), get(l:r, 'dst_title', ''))
  return 1
endfunction

" :GnosisMergeUndo … 直前のマージを取り消す（マージのあとに変わったノートがあれば、それも元に戻ってよいか聞く）
function! gnosis#merge#undo() abort
  let l:root = s:root()
  if empty(l:root)
    return
  endif
  if &modified && &buftype ==# ''
    silent! update
  endif
  let l:last = s:run(['last', l:root])
  if !get(l:last, 'ok', 0)
    echo 'Gnosis: ' . gnosis#i18n#tr('取り消せるマージはありません')
    return
  endif
  echo printf(gnosis#i18n#tr('「%s」→「%s」のマージを取り消しますか？ (y/n)'), get(l:last, 'src_title', ''), get(l:last, 'dst_title', ''))
  if s:key() !=# 'y'
    redraw | echo 'Gnosis: ' . gnosis#i18n#tr('取り消しをやめました')
    return
  endif
  redraw
  let l:r = s:run(['undo', l:root])
  if !get(l:r, 'ok', 0) && get(l:r, 'code', '') ==# 'changed'
    echo printf(gnosis#i18n#tr('マージのあとに変わったノートがあります（%s）。その変更も消えますが、元に戻しますか？ (y/n)'), join(map(copy(get(l:r, 'files', [])), 'fnamemodify(v:val, ":t")'), ', '))
    if s:key() !=# 'y'
      redraw | echo 'Gnosis: ' . gnosis#i18n#tr('取り消しをやめました')
      return
    endif
    redraw
    let l:r = s:run(['undo', l:root, '--force'])
  endif
  if !get(l:r, 'ok', 0)
    call s:warn(gnosis#i18n#tr('取り消せませんでした: ') . get(l:r, 'message', ''))
    return
  endif
  call s:sync(l:root)
  let l:paths = map(copy(get(l:r, 'restored', [])), 'l:root . "/" . v:val')
  call s:refresh(l:paths, '')
  echo printf(gnosis#i18n#tr('Gnosis: マージを取り消しました（「%s」を戻しました）'), get(l:r, 'src_title', ''))
endfunction
