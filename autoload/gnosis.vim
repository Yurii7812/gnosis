" =============================================================================
" autoload/Gnosis.vim
" Gnosis - Vimwiki非依存 Markdown PKM プラグイン (autoload)
" =============================================================================
"
" 目次（編集時は目的の見出しを検索して、その区間だけ読む。全体を読まない）:
"   Internal helpers / Title cache / Current file helpers / Section helpers
"   Realtime reciprocal link sync / Link navigation / <Space> ナビゲータ / キー
"   リンクへのラベルジャンプ / History (Back key) / Note template
"   v2: 関係付きリンク追加 / Update link titles / UpdateMD・UpdateAll
"   Auto-sync (BufWritePost) / rename_link_text / rename_title / create_note
"   :NC / :NF・:NA / ビジュアル選択の新ノート / :NQ / :CA / :BC / :YN / gp helper
"   :AT2 / \at / SortYomi / :RP / Markdown table helpers / テーブル行・列の追加・削除
"   CopyStack Mode / Image gallery
" -----------------------------------------------------------------------------

" ---------------------------------------------------------------------------
" Internal helpers
" ---------------------------------------------------------------------------

let s:link_pat = '\v\[%(\\.|[^\]\\])+\]\([^)]*\)'

" コードの中（``` で囲んだブロック・`インラインコード`）はリンクとして扱わない。
" 各行が囲みコードブロックの中（囲みの行も含む）か。
function! s:fence_flags(lines) abort
  let l:out = []
  let l:mark = ''
  for l:ln in a:lines
    let l:m = matchlist(l:ln, '^\s\{0,3}\(`\{3,}\|\~\{3,}\)')
    if l:mark ==# ''
      if !empty(l:m)
        let l:mark = l:m[1][0]
        call add(l:out, 1)
      else
        call add(l:out, 0)
      endif
    else
      call add(l:out, 1)
      if !empty(l:m) && l:m[1][0] ==# l:mark && trim(l:ln) =~# '^' . (l:mark ==# '`' ? '`' : '\~') . '\+$'
        let l:mark = ''
      endif
    endif
  endfor
  return l:out
endfunction

" バッファ全体のコードブロック判定（changedtick ごとにキャッシュ）
let s:fence_cache = {'tick': -1, 'buf': -1, 'flags': []}
function! s:buf_fence_flags() abort
  if s:fence_cache.tick != b:changedtick || s:fence_cache.buf != bufnr('%')
    let s:fence_cache = {'tick': b:changedtick, 'buf': bufnr('%'), 'flags': s:fence_flags(getline(1, '$'))}
  endif
  return s:fence_cache.flags
endfunction

" 行 a:line の 0 始まりの桁 a:col0 が `インラインコード` の中か
function! s:in_inline_code(line, col0) abort
  if stridx(a:line, '`') < 0 | return 0 | endif
  let l:start = 0
  while 1
    let l:m = matchstrpos(a:line, '\(`\+\)\%(\%(\1\)\@!.\)\{-1,}\1', l:start)
    if l:m[1] < 0 | break | endif
    if a:col0 >= l:m[1] && a:col0 < l:m[2] | return 1 | endif
    let l:start = l:m[2]
  endwhile
  return 0
endfunction

" 現在のバッファの lnum 行・0 始まりの col0 桁がコードの中か
function! s:buf_in_code(lnum, col0) abort
  let l:f = s:buf_fence_flags()
  if get(l:f, a:lnum - 1, 0) | return 1 | endif
  return s:in_inline_code(getline(a:lnum), a:col0)
endfunction
let s:fixed_link_text_marker = 'pkm:fixed-text'

function! s:sep() abort
  return has('win32') ? '\' : '/'
endfunction

" 保存済みのパス文字列を展開する。expand() と違い glob のワイルドカード
" （[ ] { * ?）を解釈しないよう、先頭の ~ だけを $HOME に置き換える。
function! s:expand_path(p) abort
  return substitute(a:p, '^\~\ze\%(/\|$\)', escape($HOME, '\&'), '')
endfunction

function! s:python_cmd() abort
  return gnosis#python_cmd()
endfunction

" Python の起動コマンド（g:gnosis_python_cmd で指定できる）。
" Windows は py ランチャー（py -3）を優先する（python3 はストアへの案内だけのことがある）。
function! gnosis#python_cmd() abort
  if !empty(get(g:, 'gnosis_python_cmd', ''))
    return g:gnosis_python_cmd
  endif
  if has('win32')
    return executable('py') ? 'py -3' : 'python'
  endif
  return executable('python3') ? 'python3' : 'python'
endfunction

function! gnosis#has_python() abort
  return executable(split(gnosis#python_cmd())[0])
endfunction

" 外部コマンド文字列を job で動かすときの引数（Windows は 'shell'、それ以外は /bin/sh）
function! gnosis#shell_job(cmd) abort
  if has('win32')
    return [&shell, &shellcmdflag, a:cmd]
  endif
  return ['/bin/sh', '-c', a:cmd]
endfunction

" 同期・並べ替えの外部プロセスを低優先度で走らせる（CPU/ディスクを独占して
" デスクトップのカーソルや入力が止まるのを防ぐ）。nice/ionice が無ければ何もしない。
function! s:low_priority_prefix() abort
  if has('win32')
    return ''
  endif
  let l:p = ''
  if executable('nice')
    let l:p .= 'nice -n 19 '
  endif
  if executable('ionice')
    let l:p .= 'ionice -c3 '
  endif
  return l:p
endfunction

function! s:is_markdown_file(path) abort
  return tolower(fnamemodify(a:path, ':e')) ==# 'md'
endfunction

function! s:is_markdown_target(target) abort
  return tolower(fnamemodify(a:target, ':e')) ==# 'md'
endfunction

function! s:run_sync(args_list) abort
  if !filereadable(g:gnosis_python)
    echoerr 'Gnosis: Python script not found: ' . g:gnosis_python
    return ''
  endif
  let l:cmd = s:low_priority_prefix() . s:python_cmd()
  for a in a:args_list
    let l:cmd .= ' ' . shellescape(a)
  endfor
  return system(l:cmd)
endfunction

" ---------------------------------------------------------------------------
" Title cache (session-level)
" ---------------------------------------------------------------------------

let s:title_cache = {}
let s:filename_resolve_cache = {}

function! gnosis#clear_title_cache() abort
  let s:title_cache = {}
  let s:filename_resolve_cache = {}
endfunction

function! s:get_title(filepath) abort
  let l:fp = fnamemodify(a:filepath, ':p')
  if !s:is_markdown_file(l:fp)
    return ''
  endif
  if has_key(s:title_cache, l:fp)
    return s:title_cache[l:fp]
  endif
  if !filereadable(l:fp)
    return ''
  endif
  let l:lines = readfile(l:fp, '', 30)
  let l:in_yaml = 0
  for l:line in l:lines
    if l:line =~# '^---\s*$'
      if l:in_yaml | break | endif
      let l:in_yaml = 1
      continue
    endif
    if l:in_yaml && l:line =~? '^title:\s*'
      let l:title = trim(matchstr(l:line, ':\s*\zs.*'))
      let l:title = substitute(l:title, '^[\"'']\|[\"'']$', '', 'g')
      let s:title_cache[l:fp] = l:title
      return l:title
    endif
    if !l:in_yaml && l:line =~# '^#\+\s\+'
      let l:title = trim(substitute(l:line, '^#\+\s\+', '', ''))
      let s:title_cache[l:fp] = l:title
      return l:title
    endif
  endfor
  let l:stem = fnamemodify(l:fp, ':t:r')
  let s:title_cache[l:fp] = l:stem
  return l:stem
endfunction

" ---------------------------------------------------------------------------
" Current file helpers
" ---------------------------------------------------------------------------

function! s:get_yaml_title(filepath) abort
  let l:fp = fnamemodify(a:filepath, ':p')
  if !s:is_markdown_file(l:fp) || !filereadable(l:fp)
    return ''
  endif
  let l:lines = readfile(l:fp, '', 30)
  let l:in_yaml = 0
  for l:line in l:lines
    if l:line =~# '^---\s*$'
      if l:in_yaml | break | endif
      let l:in_yaml = 1
      continue
    endif
    if l:in_yaml && l:line =~? '^title:\s*'
      let l:title = trim(matchstr(l:line, ':\s*\zs.*'))
      return substitute(l:title, '^[\"'']\|[\"'']$', '', 'g')
    endif
  endfor
  return ''
endfunction

function! gnosis#current_file() abort
  return expand('%:p')
endfunction

function! gnosis#current_title() abort
  let l:lines = getline(1, min([30, line('$')]))
  let l:in_yaml = 0
  for l:line in l:lines
    if l:line =~# '^---\s*$'
      if l:in_yaml | break | endif
      let l:in_yaml = 1
      continue
    endif
    if l:in_yaml && l:line =~? '^title:\s*'
      let l:t = trim(matchstr(l:line, ':\s*\zs.*'))
      return substitute(l:t, '^[\"'']\|[\"'']$', '', 'g')
    endif
    if !l:in_yaml && l:line =~# '^#\+\s\+'
      return trim(substitute(l:line, '^#\+\s\+', '', ''))
    endif
  endfor
  return expand('%:t:r')
endfunction

function! s:outline_collect() abort
  let l:items = []
  let l:max_lnum = line('$')
  let lnum = 1
  let l:in_fence = 0
  while lnum <= l:max_lnum
    let l:line = getline(lnum)
    if l:line =~# '^\s*```'
      let l:in_fence = !l:in_fence
    elseif !l:in_fence && l:line =~# '^\s*#\+\s\+'
      let l:indent = matchstr(l:line, '^\s*')
      let l:head = matchstr(l:line, '#\+')
      let l:title = substitute(l:line, '^\s*#\+\s\+', '', '')
      let l:title = substitute(l:title, '^\s\+', '', '')
      let l:title = substitute(l:title, '\s\+$', '', '')

      call add(l:items, {
            \ 'src_lnum': lnum,
            \ 'orig': l:line,
            \ 'indent': l:indent,
            \ 'level': strlen(l:head),
            \ 'title': l:title,
            \ })
    endif
    let lnum += 1
  endwhile

  return l:items
endfunction

" ---------------------------------------------------------------------------
" 見出しアンカー（#スラッグ）: GitHub / VS Code 互換
"   [表示名](note.md#スラッグ) の # 以降を扱う。スラッグは GitHub
"   （github-slugger）の近似: 小文字化 → 記号除去（ASCII 句読点と日本語の約物。
"   `-` `_` は残す）→ 空白を `-` に。日本語の文字はそのまま残る。
"   重複見出しは GitHub と同じ `-1` `-2`（s:slugger_unique）。
" ---------------------------------------------------------------------------

function! s:gh_slug(text) abort
  " 見出し内のリンクは表示テキストだけでスラッグ化する（GitHub と同じ。URL は含めない）
  let l:s = tolower(trim(substitute(a:text, '\[\(\%(\\.\|[^\]\\]\)*\)\]([^)]*)', '\1', 'g')))
  " ASCII の句読点・記号（英数と `-` `_` は残す）
  let l:s = substitute(l:s, '[!-,.\/:-@\[-\^`{-~]', '', 'g')
  " 日本語の約物（読点・句点・括弧・中黒など）
  let l:s = substitute(l:s, '[、。，．・：；？！゛゜ヽヾゝゞ「」『』【】〔〕（）［］｛｝〈〉《》…〜～—―‐]', '', 'g')
  let l:s = substitute(l:s, '\s', '-', 'g')
  return l:s
endfunction

" github-slugger と同じ重複処理（foo, foo-1, foo-2 …）。seen は呼び出し側で保持。
function! s:slugger_unique(seen, base) abort
  let l:result = a:base
  while has_key(a:seen, l:result)
    let a:seen[a:base] = get(a:seen, a:base, 0) + 1
    let l:result = a:base . '-' . a:seen[a:base]
  endwhile
  let a:seen[l:result] = 0
  return l:result
endfunction

function! s:link_base(target) abort
  return matchstr(a:target, '^[^#]*')
endfunction

function! s:link_fragment(target) abort
  return matchstr(a:target, '#\zs.*')
endfunction

" ノートの見出しを {text, slug, level, lnum} で返す（アンカー選択用）。
" タイトルと同じ H1・システム見出し（Parent/Related/BackLink 等）・
" コードフェンス内は一覧に出さない。ただしスラッグの重複番号は GitHub と
" 同じになるよう、一覧に出さない見出しも含めてファイル順で数える。
function! s:file_heading_items(path, ...) abort
  " a:1 … ファイルではなくこの行リストを読む（未保存のバッファ用）
  let l:src = a:0 > 0 ? a:1 : (filereadable(a:path) ? readfile(a:path) : [])
  if empty(l:src)
    return []
  endif
  let l:title = s:get_yaml_title(a:path)
  if empty(l:title)
    let l:title = fnamemodify(a:path, ':t:r')
  endif
  let l:items = []
  let l:seen = {}
  let l:in_fence = 0
  let l:lnum = 0
  " body … 見出しの直下から**次の見出し（レベル問わず）の手前**までの本文を1行に
  " 潰したもの。検索で「見出しを優先しつつ、その下の文章にもヒットさせる」ために使う。
  let l:cur = {}
  for l:line in l:src
    let l:lnum += 1
    if l:line =~# '^\s*```'
      let l:in_fence = !l:in_fence
      continue
    endif
    if l:in_fence || l:line !~# '^\s*#\+\s\+'
      if !empty(l:cur) && strchars(l:cur.body) < 400 && trim(l:line) !=# ''
        let l:cur.body .= (empty(l:cur.body) ? '' : ' ') . trim(l:line)
      endif
      continue
    endif
    let l:cur = {}
    let l:level = strlen(matchstr(l:line, '^#\+'))
    let l:text = trim(substitute(l:line, '^\s*#\+\s\+', '', ''))
    if empty(l:text)
      continue
    endif
    let l:slug = s:slugger_unique(l:seen, s:gh_slug(l:text))
    if l:level == 1 && l:text ==# l:title
      continue
    endif
    if s:is_known_section_header_text(l:text)
      continue
    endif
    let l:cur = {'text': l:text, 'slug': l:slug, 'level': l:level, 'lnum': l:lnum, 'body': ''}
    call add(l:items, l:cur)
  endfor
  return l:items
endfunction

let s:note_root = expand('<sfile>:p:h:h')

" 見出しピッカー（zo / zn→t 共通）。左は見出しだけ。検索は python ヘルパーが
" 見出しを優先しつつ見出しの下の本文にも当て、右は検索語を強調して出す。
" a:none が真なら先頭に「（見出しなし）」を足す（zo の解除用）。
function! s:outline_fzf(items, path, sink, none) abort
  let l:tsv = tempname()
  let l:rows = a:none ? [gnosis#i18n#tr('（見出しなし）') . "\t\t\t\t"] : []
  for l:it in a:items
    call add(l:rows, repeat('#', l:it.level) . ' ' . l:it.text . "\t" . l:it.slug
          \ . "\t" . a:path . "\t" . l:it.lnum . "\t" . get(l:it, 'body', ''))
  endfor
  call writefile(l:rows, l:tsv)
  let l:py = shellescape(s:note_root . '/python/outline_pick.py')
  let l:filter = gnosis#python_cmd() . ' ' . l:py . ' filter ' . shellescape(l:tsv) . ' {q}'
  call fzf#run(fzf#wrap({
        \ 'source': systemlist(gnosis#python_cmd() . ' ' . l:py . ' filter ' . shellescape(l:tsv) . ' ""'),
        \ 'sink': a:sink,
        \ 'options': '--delimiter="\t" --with-nth=1 --no-multi --disabled --ansi'
        \   . ' --bind ' . shellescape('change:reload:' . l:filter . ' || true')
        \   . ' --prompt=' . shellescape(gnosis#i18n#tr('見出し> '))
        \   . ' --preview ' . shellescape(gnosis#python_cmd() . ' ' . l:py . ' preview {3} {4} {q}')
        \   . ' --preview-window=right:50%',
        \ }))
endfunction

" fragment（スラッグ or 生見出し or HTML アンカー）の行へジャンプ。
" 見つかれば 1、無ければ 0（カーソル位置は元へ戻す）。
function! s:jump_to_fragment(frag) abort
  if empty(a:frag)
    return 1
  endif
  let l:save = winsaveview()
  let l:target = tolower(a:frag)
  let l:seen = {}
  let l:found = 0
  call cursor(1, 1)
  let l:lnum = search('^\s*#\+\s\+', 'cW')
  while l:lnum > 0
    let l:in_fence = s:line_in_fence(l:lnum)
    call cursor(l:lnum, 1)
    if !l:in_fence
      let l:text = trim(substitute(getline(l:lnum), '^\s*#\+\s\+', '', ''))
      if s:slugger_unique(l:seen, s:gh_slug(l:text)) ==# l:target
        let l:found = l:lnum
        break
      endif
    endif
    let l:lnum = search('^\s*#\+\s\+', 'W')
  endwhile
  " 生の見出しテキスト一致（手書きの #見出し 用）
  if l:found <= 0
    call cursor(1, 1)
    let l:found = search('\c^#\+\s\+\V' . escape(a:frag, '\') . '\m\s*$', 'cW')
  endif
  " HTML アンカー（expand の <a id="note-N"> など）
  if l:found <= 0
    call cursor(1, 1)
    let l:found = search('<\a\+[^>]*id="\V' . escape(a:frag, '\') . '\m"', 'cW')
  endif
  if l:found > 0
    call cursor(l:found, 1)
    normal! zv
    return 1
  endif
  call winrestview(l:save)
  return 0
endfunction

function! s:outline_editor_lines(items) abort
  let l:lines = []
  call add(l:lines, gnosis#i18n#tr('# OutlineEdit: 見出しを編集して :write で反映'))
  call add(l:lines, gnosis#i18n#tr('# <- / -> : 見出しレベル変更（# の数を減増）'))
  call add(l:lines, gnosis#i18n#tr('# Visual選択して <- / -> : 選択範囲を一括変更'))
  call add(l:lines, gnosis#i18n#tr('# q / ZZ / :OutlineApply で反映（Q は保存せず閉じる）'))
  call add(l:lines, '')

  for l:item in a:items
    call add(l:lines, repeat('#', l:item.level) . ' ' . l:item.title)
  endfor
  return l:lines
endfunction

function! s:outline_shift_range(first, last, delta) abort
  let l:base = get(b:, 'gnosis_outline_base', 6)
  let l:last_edit = l:base + len(get(b:, 'gnosis_outline_items', [])) - 1
  let l:start = max([a:first, l:base])
  let l:end = min([a:last, l:last_edit])
  if l:start > l:end
    return
  endif

  for lnum in range(l:start, l:end)
    let l:line = getline(lnum)
    if l:line !~# '^\s*#\+\s\+'
      continue
    endif
    let l:level = strlen(matchstr(l:line, '#\+')) + a:delta
    let l:level = min([6, max([1, l:level])])
    let l:title = trim(substitute(l:line, '^\s*#\+\s\+', '', ''))
    call setline(lnum, repeat('#', l:level) . ' ' . l:title)
  endfor
endfunction

function! gnosis#outline_shift_current(delta) abort
  call s:outline_shift_range(line('.'), line('.'), a:delta)
endfunction

function! gnosis#outline_shift_visual(delta) range abort
  call s:outline_shift_range(a:firstline, a:lastline, a:delta)
endfunction

function! gnosis#outline_editor_apply() abort
  if !get(b:, 'gnosis_outline_editor', 0)
    return
  endif
  let l:src_buf = get(b:, 'gnosis_outline_src_bufnr', -1)
  let l:items = get(b:, 'gnosis_outline_items', [])
  let l:base = get(b:, 'gnosis_outline_base', 6)
  if l:src_buf < 0 || empty(l:items)
    echoerr 'OutlineEdit: invalid editor state'
    return
  endif

  " 元ノートが開いてから変わっていないか確認（行番号ずれで別行を壊さない）
  for l:src in l:items
    if get(getbufline(l:src_buf, l:src.src_lnum), 0, '') !=# l:src.orig
      echoerr gnosis#i18n#tr('OutlineEdit: 元ノートが変わったため反映を中止しました（もう一度 :OutlineEdit してください）')
      return
    endif
  endfor

  let l:new_lines = []
  for l:i in range(0, len(l:items) - 1)
    let l:src = l:items[l:i]
    let l:line = trim(getline(l:base + l:i))
    if l:line =~# '^#\+\s\+'
      let l:new_level = min([6, strlen(matchstr(l:line, '^#\+'))])
      let l:new_title = trim(substitute(l:line, '^#\+\s\+', '', ''))
    else
      let l:new_level = max([1, get(l:src, 'level', 1)])
      let l:new_title = empty(l:line) ? get(l:src, 'title', '') : l:line
    endif
    call add(l:new_lines, [l:src.src_lnum, get(l:src, 'indent', '') . repeat('#', l:new_level) . ' ' . l:new_title])
  endfor
  for [l:lnum, l:text] in l:new_lines
    call setbufline(l:src_buf, l:lnum, l:text)
  endfor

  setlocal nomodified
  echom gnosis#i18n#tr('OutlineEdit: 反映しました')
endfunction

function! gnosis#outline_edit() abort
  if !s:is_markdown_file(expand('%:p'))
    echoerr gnosis#i18n#tr('Gnosis: OutlineEdit は Markdown ファイルでのみ利用できます')
    return
  endif

  let l:items = s:outline_collect()

  if empty(l:items)
    echom gnosis#i18n#tr('Gnosis: 見出しが見つかりませんでした')
    return
  endif

  let l:origin_win = win_getid()
  vertical botright new
  execute 'file ' . fnameescape('[SimpleOutlineEdit]')

  call setline(1, s:outline_editor_lines(l:items))

  let b:gnosis_outline_editor = 1
  let b:gnosis_outline_src_bufnr = winbufnr(l:origin_win)
  let b:gnosis_outline_items = deepcopy(l:items)
  let b:gnosis_outline_base = 6

  setlocal buftype=acwrite
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal filetype=markdown
  setlocal nonumber
  setlocal norelativenumber
  setlocal foldcolumn=0
  setlocal signcolumn=no
  setlocal nowrap
  setlocal modifiable

  augroup gnosis_outline_editor
    autocmd! * <buffer>
    autocmd BufWriteCmd <buffer> call gnosis#outline_editor_apply()
  augroup END
  command! -buffer OutlineApply call gnosis#outline_editor_apply()
  nnoremap <silent><buffer> q  <Cmd>call gnosis#outline_editor_apply()<CR><Cmd>bd!<CR>
  nnoremap <silent><buffer> Q  <Cmd>bd!<CR>
  nnoremap <silent><buffer> ZZ <Cmd>call gnosis#outline_editor_apply()<CR><Cmd>bd!<CR>

  nnoremap <silent><buffer> <Left>  <Cmd>call gnosis#outline_shift_current(-1)<CR>
  nnoremap <silent><buffer> <Right> <Cmd>call gnosis#outline_shift_current(1)<CR>
  xnoremap <silent><buffer> <Left>  :<C-u>call gnosis#outline_shift_visual(-1)<CR>
  xnoremap <silent><buffer> <Right> :<C-u>call gnosis#outline_shift_visual(1)<CR>

  call cursor(b:gnosis_outline_base, 1)
endfunction


function! s:state_dir() abort
  " vault（PKM ルート）の .state/ を優先する。
  " vault を暗号化する場合、ノートタイトル等を含む
  " 状態（hub / recent / locks）もいっしょに暗号化されるように置く場所を
  " vault 内へ統一する。未設定時のみ従来の stdpath に落ちる。
  if !empty(get(g:, 'gnosis_state_in_vault', 1))
    let l:root = ''
    if exists('g:gnosis_root') && !empty(trim(g:gnosis_root))
      let l:root = trim(g:gnosis_root)
    else
      " 障害時に古い場所へ戻せるよう既存の root.txt も尊重する
      let l:legacy = (exists('*stdpath') ? stdpath('data') : expand('~/.vim')) . s:sep() . 'simple_yurii_note'
      let l:rootfile = l:legacy . s:sep() . 'root.txt'
      if filereadable(l:rootfile)
        let l:lines = readfile(l:rootfile)
        if !empty(l:lines) && !empty(trim(l:lines[0]))
          let l:root = trim(l:lines[0])
        endif
      endif
    endif
    if !empty(l:root)
      let l:root = fnamemodify(s:expand_path(l:root), ':p')
      let l:dir = l:root . s:sep() . '.state'
      " ロック中の vault（gocryptfs マウント前）に .state を作らない。
      " gocryptfs は空でないマウントポイントを拒否するため、作成すると
      " 正しいパスワードでもマウントに失敗する。書き込みは各所のロック
      " ガードで止まるので、ここでは場所だけ返す。
      if gnosis#vault_locked_flag() == 1
        return l:dir
      endif
      if !isdirectory(l:dir)
        try
          call mkdir(l:dir, 'p')
        catch
          return s:state_dir_legacy()
        endtry
      endif
      return l:dir
    endif
  endif
  return s:state_dir_legacy()
endfunction

function! s:state_dir_legacy() abort
  if get(g:, 'gnosis_managed', 0)
    return gnosis#home#path('state')
  endif
  if exists('*stdpath')
    return stdpath('data') . s:sep() . 'simple_yurii_note'
  endif
  return expand('~/.vim/simple_yurii_note')
endfunction

function! gnosis#state_dir() abort
  return s:state_dir()
endfunction

" 旧 state_dir（~/.vim/simple_yurii_note など）の状態を vault 内 .state/ へ1回だけ引っ越す。
" 引っ越すのは vault の中身由来のデータ（hubs / hubs.json / recent.json / locks）だけ。
" root.txt は vault を探すためのブートストラップなので残す（vault の場所は暗号対象外）。
function! gnosis#migrate_state_into_vault() abort
  if empty(get(g:, 'gnosis_state_in_vault', 1))
    return
  endif
  " vault がロック中なら vault への書き込み(移行)をしない（mount後に自動で走る前提）
  if gnosis#vault_locked_flag() == 1
    return
  endif
  let l:legacy = s:state_dir_legacy()
  let l:newdir = s:state_dir()
  " 失敗時などで新旧が同じなら何もしない
  if l:newdir ==# l:legacy || !isdirectory(l:legacy)
    return
  endif
  let l:stamp = l:newdir . s:sep() . '.migrated_from_legacy'
  if filereadable(l:stamp)
    return
  endif
  " 1つでも移動に失敗したら stamp を書かない（次回起動で再試行する）
  let l:failed = 0
  for l:name in ['hubs', 'hubs.json', 'recent.json', 'locks']
    let l:src = l:legacy . s:sep() . l:name
    if !isdirectory(l:src) && !filereadable(l:src)
      continue
    endif
    let l:dst = l:newdir . s:sep() . l:name
    if isdirectory(l:src)
      if !isdirectory(l:dst)
        call mkdir(l:dst, 'p')
      endif
      for l:entry in split(glob(l:src . '/*', 1), "\n")
        let l:base = fnamemodify(l:entry, ':t')
        if !filereadable(l:dst . s:sep() . l:base)
          if rename(l:entry, l:dst . s:sep() . l:base) != 0
            let l:failed = 1
          endif
        endif
      endfor
    elseif !filereadable(l:dst)
      if rename(l:src, l:dst) != 0
        let l:failed = 1
      endif
    endif
  endfor
  " 全移動後に空になった legacy のディレクトリを掃除（root.txt は無視）
  for l:name in ['hubs', 'hubs.json', 'recent.json', 'locks']
    let l:src = l:legacy . s:sep() . l:name
    if !isdirectory(l:src)
      continue
    endif
    if empty(glob(l:src . s:sep() . '*', 1))
      try
        call delete(l:src, 'd')
      catch
      endtry
    endif
  endfor
  if l:failed
    return
  endif
  try
    call s:syn_writefile([l:legacy], l:stamp)
  catch
  endtry
endfunction

function! s:root_state_file() abort
  " root.txt は vault を探すためのブートストラップなので、
  " vault 外（旧 state dir）に置いたままにする
  return s:state_dir_legacy() . s:sep() . 'root.txt'
endfunction

function! s:load_persisted_root() abort
  " Gnosis の vault 登録簿（Gnosis ホームの vaults.json）の「最後に選んだ vault」。
  " 登録簿が無い最初の 1 回は、旧 root.txt を取り込む（gnosis#vault#load）。
  let l:vault = gnosis#vault#last()
  if !empty(l:vault)
    return fnamemodify(gnosis#vault#note_root(l:vault), ':p')
  endif
  " 旧 simple-yurii-note の vimrc で起動したときだけ、従来の root.txt も見る
  if get(g:, 'gnosis_managed', 0)
    return ''
  endif
  let l:file = s:root_state_file()
  if !filereadable(l:file)
    return ''
  endif
  let l:lines = readfile(l:file)
  if empty(l:lines)
    return ''
  endif
  let l:root = trim(l:lines[0])
  if empty(l:root)
    return ''
  endif
  return fnamemodify(s:expand_path(l:root), ':p')
endfunction

function! s:save_persisted_root(root) abort
  if empty(a:root)
    return
  endif
  " vault 登録簿へ（登録して「最後に選んだ vault」にする）
  try
    let l:vault = gnosis#vault#of_root(a:root)
    if empty(gnosis#vault#find(l:vault)) || !gnosis#vault#same(gnosis#vault#last(), l:vault)
      call gnosis#vault#select(l:vault)
    endif
  catch
  endtry
  " Gnosis のランチャーで起動したときは、ふだんの Vim の領域（~/.vim）に書かない。
  " 旧 vimrc（~/.vimrc-simple-yurii-note）で起動したときは、その vimrc が root.txt を
  " 読むので、従来どおり書いておく。
  if get(g:, 'gnosis_managed', 0)
    return
  endif
  let l:file = s:root_state_file()
  let l:file_dir = fnamemodify(l:file, ':h')
  if !isdirectory(l:file_dir)
    call mkdir(l:file_dir, 'p')
  endif
  call s:syn_writefile([fnamemodify(a:root, ':p')], l:file)
endfunction

" 「プロジェクトフォルダ A を選んだら A/note を vault 本体にする」解決。
" A/note がディレクトリとして存在すれば、必ず note 側を root にする
" （Index の有無は見ない。暗号化 vault はロック中に Index が見えないため、
"   見ると毎回「Create index.md?」が出てしまう）。
function! s:resolve_note_root(dir) abort
  if empty(a:dir)
    return a:dir
  endif
  let l:d = substitute(fnamemodify(s:expand_path(a:dir), ':p'), s:sep() . '\+$', '', '')
  " 二重解決を避ける（すでに note 自体なら何もしない）
  if fnamemodify(l:d, ':t') ==# 'note'
    return a:dir
  endif
  if isdirectory(l:d . s:sep() . 'note')
    return fnamemodify(l:d . s:sep() . 'note', ':p')
  endif
  return a:dir
endfunction

function! s:get_pkm_root() abort
  let l:root = ''
  if exists('g:gnosis_root')
    let l:root = trim(get(g:, 'gnosis_root', ''))
  endif
  if empty(l:root)
    let l:root = s:load_persisted_root()
    if !empty(l:root)
      let g:gnosis_root = l:root
    endif
  endif
  if empty(l:root)
    return ''
  endif
  let l:root = fnamemodify(s:expand_path(l:root), ':p')
  " A を覚えていても A/note があれば note 側へ寄せる（毎回のIndex作成確認を防ぐ）
  let l:resolved = s:resolve_note_root(l:root)
  if l:resolved !=# l:root
    let l:root = fnamemodify(l:resolved, ':p')
    let g:gnosis_root = l:root
  endif
  " rm ゴミ箱ガード（bash）に vault を知らせる
  " getter から頻繁に呼ばれるので、値が変わったときだけ環境変数を更新する
  if !has('win32') && get(s:, 'vault_env', '') !=# l:root
    let $GNOSIS_VAULT = l:root
    let s:vault_env = l:root
  endif
  return l:root
endfunction

function! s:index_path(root) abort
  " root が既に末尾スラッシュ付き（':p'）なので二重スラッシュを作らない。
  " 「root//index.md」のまま edit すると BufReadPre の <afile>:p が
  " 「/index.md」に化け、noswapfile の自動コマンドが効かなくなる。
  let l:root = fnamemodify(a:root, ':p')
  return l:root . (l:root =~# s:sep() . '$' ? '' : s:sep()) . 'index.md'
endfunction

function! s:is_root_note_path(path) abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || empty(a:path)
    return 0
  endif
  let l:path = fnamemodify(a:path, ':p')
  let l:root = fnamemodify(l:root, ':p')
  return s:is_markdown_file(l:path)
        \ && filereadable(l:path)
        \ && stridx(l:path, l:root) == 0
        \ && index(split(l:path, s:sep()), '.undo') < 0
endfunction

" 自動保存などから使う公開版: PKM ルート配下の .md か
function! gnosis#is_vault_note(path) abort
  return s:is_root_note_path(a:path)
endfunction

" PKM ルート配下の .md か（存在しなくてもよい。noswapfile / ロック判定用）
function! gnosis#is_vault_path(path) abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || empty(a:path)
    return 0
  endif
  let l:path = fnamemodify(a:path, ':p')
  let l:root = fnamemodify(l:root, ':p')
  return s:is_markdown_file(l:path)
        \ && stridx(l:path, l:root) == 0
        \ && index(split(l:path, s:sep()), '.undo') < 0
endfunction

" 自動保存の対象か（vault ルート配下の .md / .csv。同期が走るのは .md だけ）
function! gnosis#is_autosave_target(path) abort
  let l:root = s:get_pkm_root()
  if empty(a:path) || !filereadable(a:path)
    return 0
  endif
  if a:path !~? '\.\(md\|csv\)$'
    return 0
  endif
  if gnosis#vault_locked_flag() == 1
    return 0
  endif
  let l:path = fnamemodify(a:path, ':p')
  " ハブ（state dir の hubs/*.md）は root 外だが自動保存対象。
  let l:hubdir = fnamemodify(s:state_dir() . '/hubs/', ':p')
  if stridx(l:path, fnamemodify(l:hubdir, ':p')) == 0
    return 1
  endif
  if empty(l:root)
    return 0
  endif
  let l:root = fnamemodify(l:root, ':p')
  return stridx(l:path, l:root) == 0
        \ && index(split(l:path, s:sep()), '.undo') < 0
endfunction

" ---------------------------------------------------------------------------
" ロックファイル: アプリ（Electron / ブラウザ）が「Vim がこのノートを開いて
" いる」ことを検知するための PID 入りロック。
"   vault のノートは swap を作らない（noswapfile）代わりに、state dir の
"   locks/<sha256(abs path) 16桁>.lock を見る。クラッシュ時の残骸は PID が
"   生きているかで判定し、死んでいれば掃除する。
" ---------------------------------------------------------------------------

function! s:lock_dir() abort
  let l:dir = s:state_dir() . s:sep() . 'locks'
  " ロック中に mkdir すると gocryptfs の mountpoint に平文の .state/locks が
  " できてしまう（マウントも失敗する）。作成はアンロック中だけ。
  if !isdirectory(l:dir) && gnosis#vault_locked_flag() != 1
    call mkdir(l:dir, 'p')
  endif
  return l:dir
endfunction

function! s:lock_path(path) abort
  return s:lock_dir() . s:sep() . strpart(sha256(fnamemodify(a:path, ':p')), 0, 16) . '.lock'
endfunction

function! s:pid_alive(pid) abort
  if a:pid <= 0
    return 0
  endif
  " Linux は /proc で見る。system('kill -0 …') は一瞬端末を cooked モードへ
  " 戻すため、Vim 起動直後に走ると端末応答（DA2/OSC 10,11/CPR）が画面へ生
  " エコーされる（ロックの掃除は VimEnter で必ず走る）。/proc が無ければ従来通り。
  if isdirectory('/proc')
    return isdirectory('/proc/' . a:pid)
  endif
  call system('kill -0 ' . a:pid . ' 2>/dev/null')
  return v:shell_error == 0
endfunction

function! gnosis#lock_add(path) abort
  if empty(a:path) || !gnosis#is_vault_path(a:path)
    return
  endif
  if gnosis#vault_locked_flag() == 1
    return
  endif
  " 同じバッファで既に自分が書いていれば書き直さない（BufEnter のたびの
  " 書き込みを避ける。実測 15ms/回）。PID とパスは変わらないので内容は同じ。
  let l:key = fnamemodify(a:path, ':p') . '#' . getpid()
  if get(b:, 'gnosis_lock_self', '') ==# l:key
    return
  endif
  call s:syn_writefile([
        \ 'pid=' . getpid(),
        \ 'path=' . fnamemodify(a:path, ':p'),
        \ 'time=' . localtime(),
        \ ], s:lock_path(a:path))
  let b:gnosis_lock_self = l:key
endfunction

function! gnosis#lock_remove(path) abort
  if empty(a:path)
    return
  endif
  call delete(s:lock_path(a:path))
endfunction

" 死んだ PID のロックと、旧バージョンが vault 直下に残した swap を掃除する。
function! gnosis#cleanup_stale_locks() abort
  if gnosis#vault_locked_flag() == 1
    return
  endif
  let l:dir = s:state_dir() . s:sep() . 'locks'
  if isdirectory(l:dir)
    for l:f in glob(l:dir . s:sep() . '*.lock', 0, 1)
      let l:pid = 0
      for l:ln in readfile(l:f)
        let l:m = matchlist(l:ln, '^pid=\(\d\+\)$')
        if !empty(l:m)
          let l:pid = str2nr(l:m[1])
        endif
      endfor
      if !s:pid_alive(l:pid)
        call delete(l:f)
      endif
    endfor
  endif
  " vault 直下の swap 残骸（死んだ PID のもの）。noswapfile なので以後は増えない。
  let l:root = s:get_pkm_root()
  if empty(l:root)
    return
  endif
  for l:pat in ['*.swp', '.*.swp', '*.swo', '.*.swo']
    for l:f in glob(l:root . s:sep() . l:pat, 0, 1)
      let l:info = swapinfo(l:f)
      if empty(l:info) || !s:pid_alive(get(l:info, 'pid', 0))
        call delete(l:f)
      endif
    endfor
  endfor
endfunction

function! s:pkm_format() abort
  return get(g:, 'gnosis_format', 'v2')
endfunction

" 索引テンプレート。a:with_guide が真のときだけ操作ガイドへのリンクを 1 本
" 本文（## Parent の前）に置く。本文のリンクは sync が再生成しないので、
" 自分で消せば復活せず、ディレクトリ移動で Index を作り直しても付かない。
" 付けるのはガイドを新規作成する初回のみ。
function! s:index_template(...) abort
  " index.md は全ノートの最上位の容器なので、v2 では最初から
  " attribute: グループ を付ける（無いと sync が index を容器と認識できず、
  " index に足したリンクが自動で グループ: ラベルにならない）。
  let l:with_guide = a:0 ? a:1 : 0
  let l:v2 = s:pkm_format() ==# 'v2'
  let l:head = [
        \ '---',
        \ 'time: ' . gnosis#timestamp_yaml(),
        \ 'title: Index',
        \ ] + (l:v2 ? ['attribute: group'] : []) + [
        \ '---',
        \ '',
        \ '# Index',
        \ ]
  if l:v2
    " インデックスには Parent/Child 等の見出しを置かない。
    " 本文の裸リンクが子になり、そのリンク先の Parent に Index が入る。
    let l:out = l:head
    if l:with_guide
      let l:out += [s:guide_link()]
    endif
    return l:out
  endif
  return l:head
endfunction

" 操作ガイド。本文は guide/ja.md・guide/en.md（両言語で同じキーを同じ行に載せる。
" test/check_guide.py が照合する）。vault の言語の設定でどちらかを使う。
" ファイル名は新しい vault では gnosis-guide.md。旧 simple-yurii-note の vault で
" simple-yurii-note-guide.md が既にあれば、Index のリンクを壊さないようそれを使い続ける。
let s:guide_dir = expand('<sfile>:p:h:h') . '/guide'
let s:guide_name = 'gnosis-guide.md'
let s:guide_name_legacy = 'simple-yurii-note-guide.md'

function! s:guide_file_name(root) abort
  let l:root = fnamemodify(a:root, ':p')
  if filereadable(l:root . s:sep() . s:guide_name_legacy) && !filereadable(l:root . s:sep() . s:guide_name)
    return s:guide_name_legacy
  endif
  return s:guide_name
endfunction

function! s:guide_title(...) abort
  let l:lang = a:0 ? a:1 : gnosis#i18n#lang()
  return l:lang ==# 'en' ? 'Gnosis Guide' : 'Gnosis 操作ガイド'
endfunction

function! s:guide_link(...) abort
  let l:name = a:0 ? s:guide_file_name(a:1) : s:guide_name
  return '[' . s:guide_title() . '](' . l:name . ')'
endfunction

function! s:guide_template(...) abort
  let l:lang = a:0 ? a:1 : gnosis#i18n#lang()
  let l:src = s:guide_dir . '/' . (l:lang ==# 'en' ? 'en' : 'ja') . '.md'
  let l:body = filereadable(l:src) ? readfile(l:src) : []
  while !empty(l:body) && l:body[-1] ==# ''
    call remove(l:body, -1)
  endwhile
  let l:title = s:guide_title(l:lang)
  return [
        \ '---',
        \ 'time: ' . gnosis#timestamp_yaml(),
        \ 'title: ' . l:title,
        \ '---',
        \ '',
        \ '# ' . l:title,
        \ '',
        \ ] + l:body
endfunction

" 操作ガイドを最新のテンプレートへ更新する。無ければ作る。
" ガイドも vault の普通のノートなので、本文（テンプレートの部分）だけを差し替え、
" 同期が管理する関係の節（### Context / ### Group / ### Related / ### BackLink）と、
" front matter の title 以外の行（time・attribute など）はそのまま引き継ぐ。
" 以前は本文ごと上書きしていたため、起動のたびに Index やグループへの所属
" （### Group）が消え、別のグループへ移していた場合は、次の同期で相手側の
" リンクまで「消された」と扱われるおそれがあった。
" 内容が変わったときだけ書き換える（毎回の無駄な差分を避ける）。
let s:guide_relation_marks = ['### Context', '### Parent', '### Group', '### Related', '### BackLink']

" 関係の節（最初の見張り行から最後まで）。コードブロックの中の行は見張りとみなさない。
function! s:guide_relation_tail(lines) abort
  let l:fence = ''
  let l:in_fm = get(a:lines, 0, '') ==# '---'
  for l:i in range(len(a:lines))
    let l:ln = a:lines[l:i]
    if l:in_fm
      if l:i > 0 && l:ln =~# '^---\s*$'
        let l:in_fm = 0
      endif
      continue
    endif
    let l:m = matchstr(l:ln, '^\s\{0,3}\zs\(`\{3,}\|\~\{3,}\)')
    if !empty(l:m)
      if empty(l:fence)
        let l:fence = l:m[0]
      elseif l:m[0] ==# l:fence
        let l:fence = ''
      endif
      continue
    endif
    if empty(l:fence) && index(s:guide_relation_marks, trim(l:ln)) >= 0
      return a:lines[l:i :]
    endif
  endfor
  return []
endfunction

" 古いガイドの front matter を引き継いだ、新しいガイドの行
function! s:guide_merge(old, new) abort
  let l:out = copy(a:new)
  if get(a:old, 0, '') ==# '---'
    let l:end = index(a:old, '---', 1)
    if l:end > 0
      let l:fm = copy(a:old[0 : l:end])
      let l:title = get(filter(copy(a:new[1 : index(a:new, '---', 1) - 1]), 'v:val =~# "^title:"'), 0, '')
      call map(l:fm, 'v:val =~# "^title:" ? l:title : v:val')
      if empty(filter(copy(l:fm), 'v:val =~# "^title:"'))
        call insert(l:fm, l:title, len(l:fm) - 1)
      endif
      let l:out = l:fm + a:new[index(a:new, '---', 1) + 1 :]
    endif
  endif
  return l:out + s:guide_relation_tail(a:old)
endfunction

function! s:refresh_guide(root) abort
  let l:guide = fnamemodify(a:root, ':p') . s:guide_file_name(a:root)
  let l:new = s:guide_template()
  let l:old_title = ''
  if filereadable(l:guide)
    let l:old = readfile(l:guide)
    let l:new = s:guide_merge(l:old, l:new)
    if l:old ==# l:new
      return
    endif
    let l:old_title = trim(substitute(get(filter(copy(l:old), 'v:val =~# "^title:"'), 0, ''), '^title:', '', ''))
  endif
  call s:syn_writefile(l:new, l:guide)
  " 題が変わった（言語の切り替え・旧名からの更新）ら、ガイドへのリンクの表示名も追従させる
  let l:new_title = s:guide_title()
  if !empty(l:old_title) && l:old_title !=# l:new_title
    silent! call s:run_retitle_links_for_title_change(l:guide, l:old_title, l:new_title)
  endif
endfunction

" 操作ガイドが開いていれば、ディスクの最新内容へ静かに読み直す。
" 未保存の編集があるとき・特殊バッファのときは触らない。
function! s:reload_guide_if_open(root) abort
  let l:guide = fnamemodify(a:root, ':p') . s:guide_file_name(a:root)
  let l:buf = bufnr(l:guide)
  if l:buf <= 0 || !bufloaded(l:buf)
    return
  endif
  if getbufvar(l:buf, '&modified') || getbufvar(l:buf, '&buftype') !=# ''
    return
  endif
  silent! execute 'checktime ' . l:buf
endfunction

" 公開: 操作ガイドを最新にする（VimEnter 用）。
" 起動のたびに vault のガイドを最新テンプレートと比較し、変わっていれば書き換える
" （プラグイン更新に自動追従）。Index がありガイドが無ければ作る。開いていれば読み直す。
function! gnosis#refresh_guide() abort
  " ロック中の vault には書けない（mount後に自動で走らせる前提）
  if gnosis#vault_locked_flag() == 1
    return
  endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || !isdirectory(l:root)
    return
  endif
  " ガイドが無く、Index も無いなら vault 未作成 → 何もしない
  if !filereadable(fnamemodify(l:root, ':p') . s:guide_file_name(l:root))
        \ && !filereadable(s:index_path(l:root))
    return
  endif
  call s:refresh_guide(l:root)
  call s:reload_guide_if_open(l:root)
endfunction

" 公開: 操作ガイドを作り直す（無ければ作る。:GnosisGuide 用）。
function! gnosis#write_guide() abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || !isdirectory(l:root)
    echo gnosis#i18n#tr('Gnosis: PKM root 未設定')
    return
  endif
  call s:refresh_guide(l:root)
  call s:reload_guide_if_open(l:root)
  echo 'Gnosis: ' . gnosis#i18n#tr('操作ガイドを更新: ') . s:guide_file_name(l:root)
endfunction

" index.md と操作ガイドをまとめて作る（ガイドは常に最新へ）。
" ガイドへのリンクは、ガイドを新規に作る初回だけ Index に置く。既にガイドが
" あるとき（ディレクトリ移動で Index を作り直すときなど）はリンクしない。
function! s:write_index_and_guide(root) abort
  let l:index = s:index_path(a:root)
  let l:guide = fnamemodify(a:root, ':p') . s:guide_file_name(a:root)
  let l:first_guide = !filereadable(l:guide)
  call s:refresh_guide(a:root)
  call s:syn_writefile(s:index_template(l:first_guide), l:index)
  call s:mark_index_created()
  " 新しく作ったガイドは Index の本文からリンクされる。すぐ同期して、ガイドにも
  " 所属（### Group の Index）を書く（次に何かを保存するまで所属が無い状態にしない）
  if l:first_guide && s:pkm_format() ==# 'v2' && filereadable(get(g:, 'gnosis_python', ''))
    silent! call s:run_sync([g:gnosis_python, 'update', a:root])
  endif
endfunction

function! s:setup_persistent_undo_for_root(root) abort
  if !get(g:, 'gnosis_persistent_undo', 1)
    return
  endif
  if empty(a:root)
    return
  endif
  " ロック中は .undo を作らない。gocryptfs が空でないマウントポイントを拒否する。
  if gnosis#vault_locked_flag() == 1
    set noundofile
    return
  endif
  let l:root_abs = fnamemodify(a:root, ':p')
  let l:root_abs = substitute(l:root_abs, s:sep() . '\+$', '', '')
  let l:undo_dir = l:root_abs . s:sep() . '.undo'
  if !isdirectory(l:undo_dir)
    try
      call mkdir(l:undo_dir, 'p')
    catch /^Vim\%((\a\+)\)\=:E739/
      let l:fallback = expand('~/.vim/undo')
      if !isdirectory(l:fallback)
        call mkdir(l:fallback, 'p')
      endif
      let l:undo_dir = l:fallback
      echohl WarningMsg
      echom 'Gnosis: persistent undo dir could not be created under root; fallback to ~/.vim/undo'
      echohl None
    endtry
  endif
  execute 'set undodir=' . fnameescape(l:undo_dir)
  set undofile
  set undolevels=10000
  set undoreload=100000
endfunction

function! gnosis#init_persistent_undo_if_ready() abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || !isdirectory(l:root)
    return
  endif
  if !filereadable(s:index_path(l:root))
    return
  endif
  call s:setup_persistent_undo_for_root(l:root)
endfunction

let s:startup_root_recovery_active = 0
let s:index_created_recently = 0

function! s:mark_index_created() abort
  let s:index_created_recently = 1
endfunction

function! s:consume_index_created_flag() abort
  let l:created = get(s:, 'index_created_recently', 0)
  let s:index_created_recently = 0
  return l:created
endfunction

function! s:timer_edit_file_cb(...) abort
  " timer_start() の callback 引数順は Vim 実装/呼び出し方で差が出ることがあるため、
  " 文字列の引数を path として拾う。
  let l:path = ''
  if a:0 >= 1 && type(a:1) == v:t_string
    let l:path = a:1
  elseif a:0 >= 2 && type(a:2) == v:t_string
    let l:path = a:2
  endif
  if empty(l:path)
    return
  endif
  execute 'edit ' . fnameescape(l:path)

endfunction

function! s:timer_redraw_cb(timer) abort
  redraw!
endfunction

function! s:timer_hub_edit_cb(...) abort
  let l:path = ''
  if a:0 >= 1 && type(a:1) == v:t_string
    let l:path = a:1
  elseif a:0 >= 2 && type(a:2) == v:t_string
    let l:path = a:2
  endif
  if empty(l:path)
    return
  endif
  call gnosis#save_current_note()
  silent! execute 'hide edit ' . fnameescape(l:path)
  setlocal bufhidden=hide
  setlocal noundofile
  redraw!
endfunction

function! s:open_index_with_delay(index_path) abort
  call gnosis#push_history()
  call timer_start(0, function('s:timer_edit_file_cb', [a:index_path]))
  call timer_start(50, function('s:timer_redraw_cb'))
endfunction

function! s:startup_recover_missing_root() abort
  let l:new_root = s:prompt_index_root()
  if empty(l:new_root)
    return ''
  endif

  let g:gnosis_root = l:new_root
  call s:save_persisted_root(l:new_root)

  let l:index = s:index_path(l:new_root)
  if !filereadable(l:index)
    " 確認はしない（暗号化 vault がロック中だと Index が無いように見えるため）
    if !isdirectory(l:new_root)
      call mkdir(l:new_root, 'p')
    endif
    call s:setup_persistent_undo_for_root(l:new_root)
    call s:write_index_and_guide(l:new_root)
    call gnosis#clear_title_cache()
    echom 'Created: ' . l:index
  endif

  if filereadable(l:index)
    execute 'cd ' . fnameescape(l:new_root)
    if s:consume_index_created_flag()
      call s:open_index_with_delay(l:index)
    else
      call gnosis#push_history()
      silent execute 'edit ' . fnameescape(l:index)
    endif
  endif
  return l:new_root
endfunction

" 起動の続き（起動画面で Enter を押したあと、または起動画面を出さないとき）。
" 以前は VimEnter の自動コマンドがばらばらに行っていた処理を、この順で行う:
"   vault の設定を反映 → 暗号化 vault のマウント → 検索ハイライトを消す →
"   古いロックの掃除 → 旧状態の vault 内への移行 → root を決めて Index を開く →
"   操作ガイドを最新に → 描き直し
function! gnosis#startup_sequence() abort
  try
    let l:root = s:get_pkm_root()
    if !empty(l:root) && empty(get(g:, 'gnosis_active_vault', ''))
      call gnosis#settings#activate(gnosis#vault#of_root(l:root))
    elseif empty(l:root)
      call gnosis#settings#apply(gnosis#settings#current())
    endif
  catch
    call gnosis#autosync_log('settings: ' . v:exception)
  endtry
  call gnosis#maybe_mount_interactive()
  call gnosis#clear_search_highlight()
  call gnosis#cleanup_stale_locks()
  call gnosis#migrate_state_into_vault()
  call gnosis#startup_restore_root()
  call gnosis#refresh_guide()
  " Index を開く（ファイルを指定して起動したときは、そのファイルのまま）
  if get(g:, 'gnosis_open_index_on_startup', 1) && argc() == 0 && has('timers')
    call timer_start(0, {-> execute('GnosisIndex')})
  endif
  if has('timers')
    call timer_start(300, {-> execute('redraw!')})
  endif
endfunction

" 新しい vault の中身（Index と操作ガイド）を作る（gnosis#vault#create から）
function! gnosis#create_vault_files(path) abort
  let l:root = gnosis#vault#note_root(a:path)
  if !isdirectory(l:root)
    call mkdir(l:root, 'p')
  endif
  if !filereadable(s:index_path(l:root))
    call s:write_index_and_guide(l:root)
    call gnosis#clear_title_cache()
  endif
endfunction

function! gnosis#startup_restore_root() abort
  " ロック中に Index 無し判定や作成確認はしない（mount後に通常のフローへ）
  if gnosis#vault_locked_flag() == 1
    return
  endif
  if get(s:, 'startup_root_recovery_active', 0)
    return
  endif
  let s:startup_root_recovery_active = 1
  try
    let l:root = s:get_pkm_root()
    if empty(l:root)
      return
    endif
    if isdirectory(l:root) && filereadable(s:index_path(l:root))
      let g:gnosis_root = l:root
      call s:setup_persistent_undo_for_root(l:root)
      return
    endif

    if !isdirectory(l:root)
      " 前回の vault が見つからない: 元の場所に勝手に作らず、選び直してもらう
      echom 'Gnosis: ' . gnosis#i18n#t('start.missing_choose', l:root)
      let g:gnosis_root = ''
      if !get(g:, 'gnosis_skip_interactive_mount', 0) && empty($GNOSIS_HEADLESS)
        call timer_start(0, {-> gnosis#start#open()})
      endif
      return
    endif

    " 作ったばかりの vault（起動画面・アプリの「新しい vault」）: Index とガイドを黙って作る
    if get(g:, 'gnosis_new_vault', 0) || filereadable(fnamemodify(gnosis#vault#of_root(l:root), ':p') . '.gnosis/settings.json') && empty(glob(fnamemodify(l:root, ':p') . '*.md', 1, 1))
      let g:gnosis_root = l:root
      call s:save_persisted_root(l:root)
      call gnosis#create_vault_files(l:root)
      execute 'cd ' . fnameescape(l:root)
      call gnosis#push_history()
      silent execute 'edit ' . fnameescape(s:index_path(l:root))
      return
    endif
    " root は覚えているが Index が無い → 勝手には作らず、どこに作るか・
    " 作ってよいかを聞く（s:setup_root_and_index が両方を尋ねる）。
    echom 'Remembered index not found: ' . s:index_path(l:root)
    let g:gnosis_root = l:root
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
    call s:setup_root_and_index(1)
    return
  finally
    let s:startup_root_recovery_active = 0
  endtry
endfunction

" ディレクトリ選択 -> Index作成 -> Indexを開く までを一括で行うヘルパー
" a:open_index: 作成後にIndexを開くかどうか (1=開く, 0=開かない)
" 戻り値: 設定したrootのパス、キャンセル時は ''
function! s:setup_root_and_index(open_index) abort
  " Step1: ディレクトリ選択
  let l:prev_root = s:get_pkm_root()
  let l:default = l:prev_root
  if empty(l:default)
    let l:default = getcwd()
  endif
  try
    let l:root = trim(input('Index directory: ', l:default, 'dir'))
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return ''
  endtry
  if empty(l:root)
    echo 'Cancelled'
    return ''
  endif
  let l:root = fnamemodify(s:expand_path(l:root), ':p')

  " ユーザーがプロジェクト A を指定したら A/note を vault 本体にする
  " （A/note があれば必ず。Index の有無は見ない）
  let l:root = fnamemodify(s:resolve_note_root(l:root), ':p')

  if !isdirectory(l:root)
    call mkdir(l:root, 'p')
  endif
  " 旧 root のバッファは新 Index を開く前に閉じる（全経路共通）
  if !empty(l:prev_root) && fnamemodify(l:prev_root, ':p') !=# fnamemodify(l:root, ':p')
    call s:close_vault_buffers(l:prev_root)
  endif
  let g:gnosis_root = l:root
  call s:save_persisted_root(l:root)

  " ロック中の暗号化 vault を選んだら、ここでパスワードを聞いてマウントする
  " （ロック中に .undo/index を作ると mountpoint が非空になりマウントできなくなる）
  if gnosis#vault_locked_flag() == 1
    call gnosis#mount_vault()
    if gnosis#vault_locked_flag() == 1
      echom gnosis#i18n#tr('Gnosis: vault はロック中。:GnosisMount で解除してください')
      return l:root
    endif
  endif

  call s:setup_persistent_undo_for_root(l:root)

  " Step2: Index が無ければ黙って作る（毎回の確認はしない）
  let l:index = s:index_path(l:root)
  if !filereadable(l:index)
    call s:write_index_and_guide(l:root)
    call gnosis#clear_title_cache()
    echom 'Created: ' . l:index
  endif

  " Step3: Indexを開く
  if a:open_index && filereadable(l:index)
    execute 'cd ' . fnameescape(l:root)
    if s:consume_index_created_flag()
      call s:open_index_with_delay(l:index)
    else
      call gnosis#push_history()
      silent execute 'edit ' . fnameescape(l:index)
    endif
  endif

  return l:root
endfunction

function! s:prompt_index_root() abort
  let l:default = s:get_pkm_root()
  if empty(l:default)
    let l:default = getcwd()
  endif
  try
    let l:dir = trim(input('Index directory: ', l:default, 'dir'))
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return ''
  endtry
  if empty(l:dir)
    echo 'Cancelled'
    return ''
  endif
  " A を選んだら A/note を root にする
  return fnamemodify(s:resolve_note_root(fnamemodify(s:expand_path(l:dir), ':p')), ':p')
endfunction

function! gnosis#ensure_root_and_index() abort
  let l:root = s:get_pkm_root()

  " ロック中の vault では Index 判定も作成確認もしない。
  " マウント待ち（inputsecret）中に他の起動タイマーがここへ入り、
  " 「Create index.md?」をパスワード入力の上に重ねてしまうのを防ぐ。
  " マウント成功後に改めて呼ばれる。
  if gnosis#vault_locked_flag() == 1
    return ''
  endif

  if get(s:, 'startup_root_recovery_active', 0)
    if !empty(l:root) && filereadable(s:index_path(l:root))
      return l:root
    endif
    return ''
  endif

  " rootもIndexも正常
  if !empty(l:root) && filereadable(s:index_path(l:root))
    let g:gnosis_root = l:root
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
    return l:root
  endif

  " rootは設定済みだがディレクトリが消えている → 選び直し
  if !empty(l:root) && !isdirectory(l:root)
    return s:setup_root_and_index(1)
  endif

  " rootは設定済みでディレクトリはあるがIndexがない → 黙って作る
  " （ロック中は冒頭のガードで来ない。アンロック後に本当に無いときだけ）
  if !empty(l:root)
    let g:gnosis_root = l:root
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
    let l:index = s:index_path(l:root)
    call s:write_index_and_guide(l:root)
    call gnosis#clear_title_cache()
    echom 'Created: ' . l:index
    return l:root
  endif

  " rootが未設定 → ディレクトリ選択から
  return s:setup_root_and_index(0)
endfunction

" root 切替時に前 vault のバッファを閉じる（暗号 vault の平文をバッファに残さない）。
" 未保存は lock_vault と同じ流儀でフラッシュしてから bdelete!（保存に失敗したら破棄）。
" カレントは対象外（切替後は新 Index のはず）。
function! s:close_vault_buffers(root) abort
  let l:rootp = fnamemodify(a:root, ':p')
  let l:cur = bufnr('%')
  for l:b in range(1, bufnr('$'))
    if !buflisted(l:b) || l:b == l:cur
      continue
    endif
    if stridx(fnamemodify(bufname(l:b), ':p'), l:rootp) == 0 && getbufvar(l:b, '&modified')
      execute 'silent! buffer ' . l:b
      silent! update
    endif
  endfor
  if bufnr('%') != l:cur
    execute 'silent! buffer ' . l:cur
  endif
  let l:kept = 0
  for l:b in range(1, bufnr('$'))
    if !buflisted(l:b) || l:b == l:cur
      continue
    endif
    if stridx(fnamemodify(bufname(l:b), ':p'), l:rootp) == 0
      " 保存できなかった変更は捨てない（閉じずに残して警告）
      if getbufvar(l:b, '&modified')
        let l:kept += 1
        continue
      endif
      execute 'silent! bdelete ' . l:b
    endif
  endfor
  if l:kept > 0
    echohl WarningMsg
    echom gnosis#i18n#tr('Gnosis: 未保存のバッファが ') . l:kept . gnosis#i18n#tr(' 件残っています（保存してから切替えてください）')
    echohl NONE
  endif
endfunction

function! gnosis#choose_index_root() abort
  let l:current_root = s:get_pkm_root()
  let l:new_root = s:setup_root_and_index(1)
  if empty(l:new_root)
    return ''
  endif
  if !empty(l:current_root) && fnamemodify(l:current_root, ':p') !=# fnamemodify(l:new_root, ':p')
    " 前 vault が暗号化・マウント中ならロックする（VimLeave と同じ流儀）。
    " バッファは setup_root_and_index 内で閉じ済み。
    " lock_vault は現在 root を見るので一時的に戻して呼ぶ。
    let g:gnosis_root = l:current_root
    if gnosis#vault_mounted() == 1
      call gnosis#lock_vault()
      redraw
    endif
    let g:gnosis_root = l:new_root
    call gnosis#settings#activate(gnosis#vault#of_root(l:new_root))
    redraw
    echom 'Switched PKM root to: ' . l:new_root
  else
    echom 'PKM root set to: ' . l:new_root
  endif
  return l:new_root
endfunction

" 使用中に vault を切り替える（起動画面の vault 一覧・:GnosisVaults から）。
" 保存先・検索範囲・同期対象（すべて g:gnosis_root を見る）と、vault の設定（言語・テーマ）を
" まとめて切り替える。前の vault の未保存バッファは保存してから閉じ、暗号化 vault はロックする。
function! gnosis#switch_vault(path) abort
  let l:new_root = fnamemodify(gnosis#vault#note_root(a:path), ':p')
  let l:prev = s:get_pkm_root()
  if !empty(l:prev) && fnamemodify(l:prev, ':p') !=# l:new_root
    call s:close_vault_buffers(l:prev)
    if gnosis#vault_mounted() == 1
      call gnosis#lock_vault()
    endif
  endif
  let g:gnosis_root = l:new_root
  call s:save_persisted_root(l:new_root)
  call gnosis#clear_title_cache()
  call gnosis#settings#activate(gnosis#vault#of_root(l:new_root))
  if gnosis#vault_locked_flag() == 1
    call gnosis#maybe_mount_interactive()
    if gnosis#vault_locked_flag() == 1
      return
    endif
  endif
  call s:setup_persistent_undo_for_root(l:new_root)
  let l:index = s:index_path(l:new_root)
  if !filereadable(l:index)
    call s:write_index_and_guide(l:new_root)
  endif
  execute 'cd ' . fnameescape(l:new_root)
  call gnosis#push_history()
  silent execute 'edit ' . fnameescape(l:index)
  call gnosis#refresh_guide()
  echom 'Gnosis: ' . gnosis#i18n#tr('vault を切り替えました: ') . l:new_root
endfunction

function! gnosis#check_missing_prefix_in_current_dir() abort
  return 1
endfunction

function! gnosis#check_missing_prefix_in_current_dir_once() abort
  return
endfunction

" ---------------------------------------------------------------------------
" Section helpers (buffer-level)
" ---------------------------------------------------------------------------

function! s:bare_section_name(text) abort
  let l:s = trim(a:text)
  let l:s = substitute(l:s, '^#\+\s*', '', '')
  let l:s = substitute(l:s, ':\s*$', '', '')
  return tolower(l:s)
endfunction

function! s:section_aliases(name) abort
  let l:target = tolower(a:name)
  if l:target ==# 'parent' || l:target ==# 'up' || l:target ==# 'context'
    return ['context', 'parent', 'up']
  endif
  if l:target ==# 'group'
    return ['group']
  endif
  if l:target ==# 'child' || l:target ==# 'down' || l:target ==# 'branch'
    return ['child', 'down', 'branch']
  endif
  if l:target ==# 'back' || l:target ==# 'backlink'
    return ['back', 'backlink']
  endif
  return [l:target]
endfunction

function! s:canonical_section_title(name) abort
  let l:target = tolower(a:name)
  if l:target ==# 'parent' || l:target ==# 'up'
    return 'Parent:'
  endif
  if l:target ==# 'child' || l:target ==# 'down' || l:target ==# 'branch'
    return 'Child:'
  endif
  if l:target ==# 'back' || l:target ==# 'backlink'
    return 'BackLink:'
  endif
  return toupper(strpart(a:name, 0, 1)) . strpart(a:name, 1) . ':'
endfunction

function! s:is_section_header_text(text, name) abort
  let l:sec = s:bare_section_name(a:text)
  return index(s:section_aliases(a:name), l:sec) >= 0
endfunction

function! s:is_known_section_header_text(text) abort
  let l:sec = s:bare_section_name(a:text)
  return index(['context', 'group', 'parent', 'up', 'related', 'child', 'down', 'branch', 'back', 'backlink'], l:sec) >= 0
endfunction

function! s:find_section_index_in_lines(lines, name) abort
  let l:found = -1
  let l:in_fence = 0
  for l:i in range(0, len(a:lines) - 1)
    let l:s = trim(a:lines[l:i])
    if l:s =~# '^```'
      let l:in_fence = !l:in_fence
    endif
    if !l:in_fence && s:is_section_header_text(l:s, a:name)
      let l:found = l:i
    endif
  endfor
  return l:found
endfunction

" `is_section_header_text` 相当（bare 名が aliases のどれか）を search() で
" 引くためのパターン。`#` の個数・`:` の有無は問わない。
function! s:section_search_pat(name) abort
  let l:words = s:section_aliases(a:name)
  if empty(l:words) | return '' | endif
  return '\c^\s*#*\s*\%(' . join(l:words, '\|') . '\):\?\s*$'
endfunction

" a:lnum がコードフェンス（`^````）の内側か。フェンス行を C 実装の search() で
" 数えるだけ（Vimscript の全行ループをやめる）。
function! s:line_in_fence(lnum) abort
  let l:start = 1
  let l:in_fence = 0
  while 1
    call cursor(l:start, 1)
    let l:f = search('^\s*```', 'cW', a:lnum)
    if l:f <= 0
      break
    endif
    let l:in_fence = !l:in_fence
    let l:start = l:f + 1
  endwhile
  return l:in_fence
endfunction

" Return line number (1-based) of section header, or 0
" 旧実装は全行を Vimscript ループで trim 比較しており、1 万行の index.md では
" リンクを開くたび（in_up_section / in_back_section）に数百 ms かかっていた。
" 後方 search() で「最後に一致した行」を探し、フェンス内なら手前を再探索する。
function! s:find_section_line(name) abort
  let l:pat = s:section_search_pat(a:name)
  if empty(l:pat) | return 0 | endif
  let l:save = winsaveview()
  try
    let l:lnum = line('$')
    while l:lnum > 0
      call cursor(l:lnum, 1)
      let l:found = search(l:pat, 'bcW')
      if l:found <= 0
        return 0
      endif
      if !s:line_in_fence(l:found)
        return l:found
      endif
      let l:lnum = l:found - 1
    endwhile
  finally
    call winrestview(l:save)
  endtry
  return 0
endfunction

" Ensure the buffer has a Child: section, placed after Parent: and before BackLink:.
" Return insertion end line for outgoing links in Child:.
function! s:down_end_line() abort
  let l:down = s:find_section_line('down')
  if l:down > 0
    let l:back_after_down = 0
    for l:i in range(l:down + 1, line('$'))
      if s:is_section_header_text(getline(l:i), 'back')
        let l:back_after_down = l:i
        break
      endif
    endfor
    return l:back_after_down > 0 ? l:back_after_down - 1 : line('$')
  endif

  return 0
endfunction

" Return line number where appending inserts at top of Child:.
function! s:down_top_insert_line() abort
  let l:down = s:find_section_line('down')
  if l:down > 0
    return l:down
  endif

  return 0
endfunction

function! s:is_current_index_buffer() abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || empty(expand('%:p'))
    return 0
  endif
  return fnamemodify(expand('%:p'), ':p') ==# fnamemodify(s:index_path(l:root), ':p')
endfunction

function! s:structural_link_append_line() abort
  let l:down = s:down_end_line()
  if l:down > 0
    return l:down
  endif
  if s:is_current_index_buffer()
    return line('$')
  endif
  return 0
endfunction

function! s:structural_link_prepend_line() abort
  let l:down = s:down_top_insert_line()
  if l:down > 0
    return l:down
  endif
  if s:is_current_index_buffer()
    return line('$')
  endif
  return 0
endfunction

" Return insertion end line for Parent: section (just before next section header / EOF).
function! s:up_end_line() abort
  let l:up = s:find_section_line('up')
  if l:up <= 0
    return 0
  endif
  for l:i in range(l:up + 1, line('$'))
    if s:is_known_section_header_text(getline(l:i))
      return l:i - 1
    endif
  endfor
  return line('$')
endfunction

function! s:section_end_line(name) abort
  let l:sec = s:find_section_line(a:name)
  if l:sec <= 0
    return 0
  endif
  let l:end = l:sec
  for l:i in range(l:sec + 1, line('$'))
    if s:is_known_section_header_text(getline(l:i))
      return l:i - 1
    endif
    let l:end = l:i
  endfor
  return l:end
endfunction

function! s:append_link_to_buffer_section(name, link) abort
  " Context は空なら見出しごと無い。足すときに作る（index.md は節を持たないので作らない）
  if a:name ==# 'up' && s:find_section_line('up') <= 0 && !s:ensure_context_in_buffer()
    return 0
  endif
  let l:sec = s:find_section_line(a:name)
  if l:sec <= 0
    return 0
  endif

  let l:end = s:section_end_line(a:name)
  if l:end > l:sec
    let l:new_target = s:extract_target(a:link)
    let l:new_fp = empty(l:new_target) ? '' : fnamemodify(gnosis#resolve_link(l:new_target, expand('%:p:h')), ':p')
    for l:line in getline(l:sec + 1, l:end)
      if l:line ==# a:link
        return 0
      endif
      let l:old_target = s:extract_target(l:line)
      if !empty(l:new_fp) && !empty(l:old_target)
        let l:old_fp = fnamemodify(gnosis#resolve_link(l:old_target, expand('%:p:h')), ':p')
        if l:old_fp ==# l:new_fp
          return 0
        endif
      endif
    endfor
  endif

  if a:name ==# 'up'
    let l:plan = s:parent_insert_plan(getline(1, '$'), l:sec - 1, a:link, expand('%:p:h'))
    call append(l:plan.at, l:plan.lines)
    return 1
  endif
  call append(l:end, a:link)
  return 1
endfunction

" ### Related を無ければ ### Context と ### BackLink の間に作る。見出し行番号を返す（無理なら 0）。
" index.md など見張りの無いノートでは作らない（関連はノート間の機能）。
function! s:ensure_related_section_in_buffer() abort
  let l:rel = s:find_section_line('related')
  if l:rel > 0
    return l:rel
  endif
  " 並びは Context → Group → Related → BackLink。BackLink の直前に作る。
  let l:ins = 0
  let l:back = s:find_section_line('back')
  if l:back > 1
    let l:ins = l:back - 1
  endif
  if l:ins <= 0
    let l:ins = s:up_end_line()
  endif
  if l:ins <= 0
    " 関係の節がまだ何も無い: 本文の終わり（最初の節の手前。無ければ末尾）に作る
    if s:no_sections_buffer()
      return 0
    endif
    let l:fs = s:first_section_line()
    let l:ins = l:fs > 0 ? l:fs - 1 : line('$')
  endif
  call append(l:ins, s:v2_related_mark)
  return l:ins + 1
endfunction

" 今のバッファの ### Related にリンクを 1 本足す。Related 内に同じリンク先が
" あれば足さない（本文に同じリンクがあっても Related には足せる）。追加で 1。
function! s:append_related_to_buffer(link) abort
  if s:ensure_related_section_in_buffer() <= 0
    return 0
  endif
  return s:append_link_to_buffer_section('related', a:link)
endfunction

function! s:append_structural_link_to_buffer(link) abort
  let l:down = s:find_section_line('down')
  if l:down > 0
    return s:append_link_to_buffer_section('down', a:link)
  endif

  if !s:is_current_index_buffer()
    return 0
  endif

  let l:new_target = s:extract_target(a:link)
  let l:new_fp = empty(l:new_target) ? '' : fnamemodify(gnosis#resolve_link(l:new_target, expand('%:p:h')), ':p')
  for l:i in range(1, line('$'))
    let l:old_target = s:extract_target(getline(l:i))
    if getline(l:i) ==# a:link
      return 0
    endif
    if !empty(l:new_fp) && !empty(l:old_target)
      let l:old_fp = fnamemodify(gnosis#resolve_link(l:old_target, expand('%:p:h')), ':p')
      if l:old_fp ==# l:new_fp
        return 0
      endif
    endif
  endfor
  call append(line('$'), a:link)
  return 1
endfunction

function! s:section_end_index_in_lines(lines, start_idx) abort
  let l:end = len(a:lines)
  if a:start_idx + 1 >= len(a:lines)
    return l:end
  endif
  for l:i in range(a:start_idx + 1, len(a:lines) - 1)
    if s:is_known_section_header_text(get(a:lines, l:i, ''))
      let l:end = l:i
      break
    endif
  endfor
  return l:end
endfunction

function! s:ensure_section_in_lines(lines, name) abort
  let l:lines = copy(a:lines)
  let l:idx = s:find_section_index_in_lines(l:lines, a:name)
  return {'lines': l:lines, 'idx': l:idx}
endfunction

" リンク行の target が グループ（attribute: group）のノートか。a:base_dir はリンクを解決する基準。
function! s:parent_line_is_group(line, base_dir) abort
  let l:tgt = s:extract_target(a:line)
  if empty(l:tgt) | return 0 | endif
  return s:v2_path_attr(gnosis#resolve_link(l:tgt, a:base_dir)) ==# 'group'
endfunction

" ### Context に a:link を入れる位置と行。並びは「グループ（先頭ブロック）→ 1 行あけ → 普通のノート」。
" 戻り値 {at, lines}: at は 0 始まりで、この index の直前に lines を入れる。
function! s:parent_insert_plan(lines, sec_idx, link, base_dir) abort
  let l:end = s:section_end_index_in_lines(a:lines, a:sec_idx)
  let l:top = a:sec_idx + 1
  " 先頭から続くグループのリンクの直後の位置
  let l:gend = l:top
  while l:gend < l:end && s:parent_line_is_group(a:lines[l:gend], a:base_dir)
    let l:gend += 1
  endwhile

  if s:parent_line_is_group(a:link, a:base_dir)
    let l:ins = [a:link]
    if l:gend < l:end && trim(a:lines[l:gend]) !=# ''
      call add(l:ins, '')
    endif
    return {'at': l:gend, 'lines': l:ins}
  endif

  " 普通のノート: 末尾（末尾の空行の手前）へ。直前がグループだけなら 1 行あける
  let l:last = l:end - 1
  while l:last >= l:top && trim(a:lines[l:last]) ==# ''
    let l:last -= 1
  endwhile
  let l:ins = [a:link]
  if l:last >= l:top && l:last < l:gend
    call insert(l:ins, '', 0)
  endif
  return {'at': l:last + 1, 'lines': l:ins}
endfunction

function! s:add_link_to_lines_section(lines, name, link, ...) abort
  " Context は空なら見出しごと無い。足すときに作る（a:2 が index.md なら作らない）
  let l:in_lines = a:lines
  if a:name ==# 'up' && s:find_section_index_in_lines(l:in_lines, 'up') < 0
        \ && !(a:0 > 1 && fnamemodify(a:2, ':t') ==# 'index.md')
    let l:in_lines = s:ensure_context_in_lines(l:in_lines)
  endif
  let l:ensured = s:ensure_section_in_lines(l:in_lines, a:name)
  let l:lines = l:ensured.lines
  let l:idx = l:ensured.idx
  if l:idx < 0
    return {'lines': l:lines, 'added': 0}
  endif
  let l:end = s:section_end_index_in_lines(l:lines, l:idx)
  if index(l:lines[l:idx + 1 : l:end - 1], a:link) >= 0
    return {'lines': l:lines, 'added': 0}
  endif
  if a:name ==# 'up'
    let l:plan = s:parent_insert_plan(l:lines, l:idx, a:link, a:0 > 0 ? a:1 : '')
    call extend(l:lines, l:plan.lines, l:plan.at)
    return {'lines': l:lines, 'added': 1}
  endif
  call insert(l:lines, a:link, l:end)
  return {'lines': l:lines, 'added': 1}
endfunction


" ---------------------------------------------------------------------------
" Realtime reciprocal Parent/Child link sync (lightweight)
" ---------------------------------------------------------------------------

let s:realtime_sync_busy = 0

function! s:section_link_targets_from_lines(lines, name, base_dir) abort
  if a:name ==# 'up'
    return s:section_link_targets_from_lines_one(a:lines, 'up', a:base_dir)
          \ + s:section_link_targets_from_lines_one(a:lines, 'group', a:base_dir)
  endif
  return s:section_link_targets_from_lines_one(a:lines, a:name, a:base_dir)
endfunction

function! s:section_link_targets_from_lines_one(lines, name, base_dir) abort
  let l:idx = s:find_section_index_in_lines(a:lines, a:name)
  if l:idx < 0
    return []
  endif
  let l:end = s:section_end_index_in_lines(a:lines, l:idx)
  let l:targets = []
  let l:seen = {}
  let l:in_fence = 0
  for l:line in a:lines[l:idx + 1 : l:end - 1]
    let l:stripped = trim(l:line)
    if l:stripped =~# '^```'
      let l:in_fence = !l:in_fence
      continue
    endif
    if l:in_fence || l:stripped =~# '^_\{3,}\s*$'
      continue
    endif
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, '\v\[%(\\.|[^\]\\])+\]\(([^)]*)\)', l:start)
      if empty(l:m) || l:m[1] < 0
        break
      endif
      let l:raw = l:m[0]
      let l:target = s:extract_target(l:raw)
      if !empty(l:target)
        let l:fp = gnosis#resolve_link(l:target, a:base_dir)
        if filereadable(l:fp) && s:is_markdown_file(l:fp)
          let l:fp = fnamemodify(l:fp, ':p')
          if !has_key(l:seen, l:fp)
            let l:seen[l:fp] = 1
            call add(l:targets, l:fp)
          endif
        endif
      endif
      let l:start = l:m[2]
    endwhile
  endfor
  return l:targets
endfunction

function! s:body_link_targets_from_lines(lines, base_dir) abort
  let l:targets = []
  let l:seen = {}
  let l:in_yaml = 0
  let l:in_fence = 0
  for l:i in range(0, len(a:lines) - 1)
    let l:line = a:lines[l:i]
    let l:stripped = trim(l:line)
    if l:i == 0 && l:stripped ==# '---'
      let l:in_yaml = 1
      continue
    endif
    if l:in_yaml
      if l:stripped ==# '---'
        let l:in_yaml = 0
      endif
      continue
    endif
    if l:stripped =~# '^```'
      let l:in_fence = !l:in_fence
      continue
    endif
    if l:in_fence
      continue
    endif
    if l:stripped =~# '^_\{3,}\s*$'
      break
    endif
    if s:is_known_section_header_text(l:stripped)
      break
    endif

    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, '\v\[%(\\.|[^\]\\])+\]\(([^)]*)\)', l:start)
      if empty(l:m) || l:m[1] < 0
        break
      endif
      let l:target = s:extract_target(l:m[0])
      if !empty(l:target)
        let l:fp = gnosis#resolve_link(l:target, a:base_dir)
        if filereadable(l:fp) && s:is_markdown_file(l:fp)
          let l:fp = fnamemodify(l:fp, ':p')
          if !has_key(l:seen, l:fp)
            let l:seen[l:fp] = 1
            call add(l:targets, l:fp)
          endif
        endif
      endif
      let l:start = l:m[2]
    endwhile
  endfor
  return l:targets
endfunction

function! s:current_reciprocal_snapshot(...) abort
  let l:include_back = a:0 > 0 ? a:1 : get(g:, 'gnosis_realtime_backlink_sync', 0)
  let l:file = expand('%:p')
  if empty(l:file)
    return {'up': [], 'down': [], 'back': []}
  endif
  let l:lines = getline(1, '$')
  let l:base = fnamemodify(l:file, ':h')
  return {
        \ 'up': s:section_link_targets_from_lines(l:lines, 'up', l:base),
        \ 'down': s:section_link_targets_from_lines(l:lines, 'down', l:base),
        \ 'back': l:include_back ? s:body_link_targets_from_lines(l:lines, l:base) : [],
        \ }
endfunction

function! gnosis#realtime_sync_snapshot() abort
  if !s:is_markdown_file(expand('%:p'))
    return
  endif
  if line('$') > get(g:, 'gnosis_realtime_link_sync_max_lines', 2000)
    let b:gnosis_realtime_snapshot = {'up': [], 'down': [], 'back': []}
    return
  endif
  let b:gnosis_realtime_snapshot = s:current_reciprocal_snapshot()
endfunction

function! s:list_diff(new, old) abort
  let l:old = {}
  for l:item in a:old
    let l:old[l:item] = 1
  endfor
  let l:diff = []
  for l:item in a:new
    if !has_key(l:old, l:item)
      call add(l:diff, l:item)
    endif
  endfor
  return l:diff
endfunction

function! s:note_lines_for_path(path) abort
  let l:buf = bufnr(a:path)
  if l:buf > 0 && bufloaded(l:buf)
    return getbufline(l:buf, 1, '$')
  endif
  return filereadable(a:path) ? readfile(a:path) : []
endfunction

function! s:write_note_lines_for_path(path, lines) abort
  let l:buf = bufnr(a:path)
  if l:buf > 0 && bufloaded(l:buf)
    call setbufline(l:buf, 1, a:lines)
    let l:old_last = getbufinfo(l:buf)[0].linecount
    if l:old_last > len(a:lines)
      call deletebufline(l:buf, len(a:lines) + 1, l:old_last)
    endif
  else
    call s:syn_writefile(a:lines, a:path)
  endif
endfunction

function! s:remove_link_to_path_from_lines_section(lines, name, target_path, base_dir) abort
  let l:idx = s:find_section_index_in_lines(a:lines, a:name)
  if l:idx < 0
    return {'lines': copy(a:lines), 'removed': 0}
  endif
  let l:lines = copy(a:lines)
  let l:end = s:section_end_index_in_lines(l:lines, l:idx)
  let l:out = []
  let l:removed = 0
  let l:target = fnamemodify(a:target_path, ':p')
  let l:in_fence = 0
  for l:line in l:lines[l:idx + 1 : l:end - 1]
    let l:stripped = trim(l:line)
    if l:stripped =~# '^```'
      let l:in_fence = !l:in_fence
      call add(l:out, l:line)
      continue
    endif
    if l:in_fence
      call add(l:out, l:line)
      continue
    endif
    let l:new_line = ''
    let l:last = 0
    let l:start = 0
    let l:line_removed = 0
    while 1
      let l:m = matchstrpos(l:line, '\v\[%(\\.|[^\]\\])+\]\(([^)]*)\)', l:start)
      if empty(l:m) || l:m[1] < 0
        break
      endif
      let l:raw = l:m[0]
      let l:target_text = s:extract_target(l:raw)
      let l:resolved = empty(l:target_text) ? '' : gnosis#resolve_link(l:target_text, a:base_dir)
      let l:new_line .= strpart(l:line, l:last, l:m[1] - l:last)
      if !empty(l:resolved) && fnamemodify(l:resolved, ':p') ==# l:target
        let l:removed = 1
        let l:line_removed = 1
      else
        let l:new_line .= l:raw
      endif
      let l:last = l:m[2]
      let l:start = l:m[2]
    endwhile
    let l:new_line .= strpart(l:line, l:last)
    if l:line_removed && empty(trim(l:new_line))
      continue
    endif
    call add(l:out, l:line_removed ? substitute(l:new_line, '\s\+$', '', '') : l:line)
  endfor
  if !l:removed
    return {'lines': l:lines, 'removed': 0}
  endif
  return {'lines': l:lines[: l:idx] + l:out + l:lines[l:end :], 'removed': 1}
endfunction

function! s:add_reciprocal_link(target_path, section_name, current_file, current_title) abort
  if !filereadable(a:target_path)
    return 0
  endif
  let l:lines = s:note_lines_for_path(a:target_path)
  let l:link = s:make_link_from_dir(a:current_file, a:current_title, fnamemodify(a:target_path, ':h'))
  let l:result = s:add_link_to_lines_section(l:lines, a:section_name, l:link, fnamemodify(a:target_path, ':h'))
  if l:result.added
    call s:write_note_lines_for_path(a:target_path, l:result.lines)
    return 1
  endif
  return 0
endfunction

function! s:remove_reciprocal_link(target_path, section_name, current_file) abort
  if !filereadable(a:target_path)
    return 0
  endif
  let l:lines = s:note_lines_for_path(a:target_path)
  let l:result = s:remove_link_to_path_from_lines_section(
        \ l:lines, a:section_name, a:current_file, fnamemodify(a:target_path, ':h'))
  if l:result.removed
    call s:write_note_lines_for_path(a:target_path, l:result.lines)
    return 1
  endif
  return 0
endfunction

function! s:realtime_sync_apply() abort
  if s:realtime_sync_busy || !get(g:, 'gnosis_realtime_link_sync', 1)
    return
  endif
  if !s:is_markdown_file(expand('%:p')) || &buftype !=# ''
    return
  endif
  let l:file = expand('%:p')
  let l:root = s:get_pkm_root()
  " 正規表現ではなく前方一致で判定（root の . や [ などをメタ文字扱いしない）
  if empty(l:root) || empty(l:file) || stridx(l:file, l:root) != 0
    return
  endif

  let l:old = get(b:, 'gnosis_realtime_snapshot', {'up': [], 'down': []})
  if line('$') > get(g:, 'gnosis_realtime_link_sync_max_lines', 2000)
    return
  endif
  let l:new = s:current_reciprocal_snapshot()
  let l:title = gnosis#current_title()
  let l:changed = 0
  let l:back_changed = get(g:, 'gnosis_realtime_backlink_sync', 0)
        \ && (!empty(s:list_diff(l:new.back, get(l:old, 'back', [])))
        \ || !empty(s:list_diff(get(l:old, 'back', []), l:new.back)))

  let s:realtime_sync_busy = 1
  try
    for l:target in s:list_diff(l:new.down, get(l:old, 'down', []))
      let l:changed += s:add_reciprocal_link(l:target, 'up', l:file, l:title)
    endfor
    for l:target in s:list_diff(get(l:old, 'down', []), l:new.down)
      let l:changed += s:remove_reciprocal_link(l:target, 'up', l:file)
    endfor
    for l:target in s:list_diff(l:new.up, get(l:old, 'up', []))
      let l:changed += s:add_reciprocal_link(l:target, 'down', l:file, l:title)
    endfor
    for l:target in s:list_diff(get(l:old, 'up', []), l:new.up)
      let l:changed += s:remove_reciprocal_link(l:target, 'down', l:file)
    endfor
    if l:back_changed
      if &modified
        silent noautocmd update
      endif
      call s:run_update_one_for_sync(l:file)
    endif
  finally
    let s:realtime_sync_busy = 0
  endtry

  let b:gnosis_realtime_snapshot = s:current_reciprocal_snapshot()
  if l:changed
    checktime
  endif
endfunction

" 発火時に別バッファへ移っていたら何もしない（別ノートのリンクを書き込まないため）
function! s:realtime_sync_timer(bnr, timer) abort
  if bufnr('%') != a:bnr
    return
  endif
  call s:realtime_sync_apply()
endfunction

function! gnosis#realtime_sync_on_text_changed() abort
  if !get(g:, 'gnosis_realtime_link_sync', 1)
    return
  endif
  if exists('b:gnosis_realtime_timer')
    call timer_stop(b:gnosis_realtime_timer)
  endif
  if has('timers')
    let b:gnosis_realtime_timer = timer_start(get(g:, 'gnosis_realtime_link_sync_delay', 800), function('s:realtime_sync_timer', [bufnr('%')]))
  else
    call s:realtime_sync_apply()
  endif
endfunction

" Backward compatible name

" Return last line of 'back' section (before ___ or EOF), or 0
function! s:in_back_section(lnum) abort
  let l:back = s:find_section_line('back')
  if l:back <= 0
    return 0
  endif
  return a:lnum >= l:back + 1
endfunction

function! s:in_up_section(lnum) abort
  " 上側は Context と Group の 2 つの節（どちらも空なら見出しごと無い）
  for l:name in ['up', 'group']
    let l:sec = s:find_section_line(l:name)
    if l:sec <= 0
      continue
    endif
    if a:lnum >= l:sec + 1 && a:lnum <= s:section_end_line(l:name)
      return 1
    endif
  endfor
  return 0
endfunction

function! s:find_reciprocal_link_pos(target_path, source_name) abort
  if !filereadable(a:target_path)
    return [0, 0]
  endif
  " 呼び出し元は対象ファイルを開いた直後なので、現在のバッファを C 実装の
  " search() で走査する。旧実装は readfile + 全行 Vimscript ループで、
  " 1 万行の index.md へ Parent リンクで戻ると 800ms 超かかっていた。
  " `\i`（open_index）経由だと root 末尾の `/` でバッファ名が `.../vault//index.md`
  " になることがあるため、simplify() で `/` の重複を正規化して比較する。
  let l:cur = simplify(fnamemodify(expand('%:p'), ':p'))
  if !empty(l:cur)
        \ && l:cur ==# simplify(fnamemodify(a:target_path, ':p'))
    let l:save = winsaveview()
    try
      let l:hi = line('$')
      let l:back_pat = s:section_search_pat('back')
      if !empty(l:back_pat)
        call cursor(1, 1)
        let l:back = search(l:back_pat, 'cW')
        if l:back > 0
          let l:hi = l:back - 1
        endif
      endif
      " ファイル名の実文字列で候補行だけを search() で拾い、その行のリンクを
      " 従来と同じ判定（target の末尾 == source_name）で確認する。
      let l:name_pat = escape(a:source_name, "\\.*$^~[]")
      let l:lnum = 1
      while l:lnum > 0 && l:lnum <= l:hi
        call cursor(l:lnum, 1)
        let l:hit = search(l:name_pat, 'cW', l:hi)
        if l:hit <= 0
          break
        endif
        let l:line = getline(l:hit)
        let l:start = 0
        while 1
          let l:m = matchstrpos(l:line, s:link_pat, l:start)
          if len(l:m) < 3 || l:m[1] < 0
            break
          endif
          let l:parts = matchlist(l:m[0], '\v\[(%(\\.|[^\]\\])+)\]\(([^)]*)\)')
          if fnamemodify(get(l:parts, 2, ''), ':t') ==# a:source_name
            return [l:hit, l:m[1] + 1]
          endif
          let l:start = l:m[2]
        endwhile
        let l:lnum = l:hit + 1
      endwhile
    finally
      call winrestview(l:save)
    endtry
    return [0, 0]
  endif
  " 対象が現在のバッファでない場合のフォールバック（従来の readfile 走査）
  let l:lines = readfile(a:target_path)
  let l:back_line = len(l:lines) + 1
  for l:i in range(0, len(l:lines) - 1)
    if s:is_section_header_text(l:lines[l:i], 'back')
      let l:back_line = l:i + 1
      break
    endif
  endfor

  for l:lnum in range(1, l:back_line - 1)
    let l:line = get(l:lines, l:lnum - 1, '')
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, s:link_pat, l:start)
      if len(l:m) < 3 || l:m[1] < 0
        break
      endif
      let l:parts = matchlist(l:m[0], '\v\[(%(\\.|[^\]\\])+)\]\(([^)]*)\)')
      let l:target = fnamemodify(get(l:parts, 2, ''), ':t')
      if l:target ==# a:source_name
        return [l:lnum, l:m[1] + 1]
      endif
      let l:start = l:m[2]
    endwhile
  endfor
  return [0, 0]
endfunction


" ---------------------------------------------------------------------------
" Link navigation
" ---------------------------------------------------------------------------

function! gnosis#jump_link(forward) abort
  let l:flags = a:forward ? 'W' : 'bW'
  if !search(s:link_pat, l:flags)
    echo 'No more links'
    return
  endif
  " search() のマッチ先頭 ([) にそのまま止める
endfunction

" 現在位置の次の文字の先頭バイト位置（マルチバイト対応）。
function! s:byte_next(line, col) abort
  return a:col + strlen(matchstr(strpart(a:line, a:col - 1), '^.'))
endfunction

" :GnosisLinkSource … リンクの元の Markdown を見せる／隠す（このバッファだけ）。
" ふだんは表示名だけを見せ、URL（ファイル名）を直接直したいときに切り替える。
function! gnosis#toggle_link_source() abort
  if &l:conceallevel == 0
    let l:on = get(b:, 'gnosis_link_source_saved', [2, 'nvi'])
    let &l:conceallevel = l:on[0]
    let &l:concealcursor = l:on[1]
    unlet! b:gnosis_link_source_saved
    echo 'Gnosis: ' . gnosis#i18n#t('link.source_hidden')
  else
    let b:gnosis_link_source_saved = [&l:conceallevel, &l:concealcursor]
    setlocal conceallevel=0 concealcursor=
    echo 'Gnosis: ' . gnosis#i18n#t('link.source_shown')
  endif
endfunction

" ←/→ と h/l 用の左右移動（カウント対応）。conceal で隠れた範囲（[ と ](url)）の上には Vim は
" カーソルを表示できず（:h concealcursor "cursor position is not always where
" it's displayed"）、素の l/h では表示カーソルが止まって「動けない」ように
" 見える。隠れた範囲はまとめて飛び越え、表示されている文字（リンクなら
" 表示名）の上だけを動く。conceallevel=0（conceal 無効・巨大ファイル等）
" では素の l/h と同じ。
"
" 隠れた文字の上のカーソルは、その隠れ範囲の直後の可視文字の位置に描かれる。
" そのため隠れた文字から右へ1文字ぶん動かしても画面は動かない（Tab でリンクに
" 乗った直後の ←/→ が「1回無反応」に見える原因）。隠れた文字から右へは、
" 画面で1つ動いて見えるよう可視文字を1つ先まで進める。
function! gnosis#move_visible(dir, ...) abort
  for l:i in range(a:0 > 0 ? max([a:1, 1]) : 1)
    let l:before = [line('.'), col('.')]
    call s:move_visible_once(a:dir)
    if [line('.'), col('.')] ==# l:before
      break
    endif
  endfor
endfunction

function! s:move_visible_once(dir) abort
  if &l:conceallevel == 0
    execute 'normal! ' . (a:dir > 0 ? 'l' : 'h')
    return
  endif
  let l:lnum = line('.')
  let l:last = col([l:lnum, '$']) - 1
  if l:last < 1
    return
  endif
  let l:col = col('.')
  let l:on_concealed = synconcealed(l:lnum, l:col)[0]
  if a:dir > 0
    " 次の「文字」の先頭へ（col + 1 だと日本語などマルチバイト文字の途中を
    " 指し、直後の隠れた [ を見逃して [ の上に止まる＝余計に1回押す羽目になる）
    let l:col = s:byte_next(getline(l:lnum), l:col)
    if l:col > l:last || !synconcealed(l:lnum, l:col)[0]
      if !l:on_concealed
        execute 'normal! l'
        return
      endif
    else
      while l:col <= l:last && synconcealed(l:lnum, l:col)[0]
        let l:col += 1
      endwhile
    endif
    if l:on_concealed && l:col <= l:last
      let l:col = s:byte_next(getline(l:lnum), l:col)
      while l:col <= l:last && synconcealed(l:lnum, l:col)[0]
        let l:col += 1
      endwhile
    endif
  else
    let l:col -= 1
    if l:col < 1 || !synconcealed(l:lnum, l:col)[0]
      execute 'normal! h'
      return
    endif
    while l:col >= 1 && synconcealed(l:lnum, l:col)[0]
      let l:col -= 1
    endwhile
  endif
  if l:col >= 1 && l:col <= l:last
    call cursor(l:lnum, l:col)
  endif
endfunction


function! s:jump_to_line(lnum) abort
  call cursor(a:lnum, 1)
  normal! zv
endfunction

function! gnosis#jump_section_header(name) abort
  let l:sec = s:find_section_line(a:name)
  if l:sec <= 0
    echo '# ' . a:name . ' section not found'
    return
  endif

  call s:jump_to_line(l:sec)
endfunction

function! s:section_link_positions(name) abort
  " 上側は Context と Group の 2 つの節に分かれた（Group はグループへのリンク）
  if a:name ==# 'up'
    return s:section_link_positions_one('up') + s:section_link_positions_one('group')
  endif
  return s:section_link_positions_one(a:name)
endfunction

function! s:section_link_positions_one(name) abort
  let l:sec = s:find_section_line(a:name)
  if l:sec <= 0
    return []
  endif

  let l:end = s:section_end_line(a:name)
  if l:end <= l:sec
    return []
  endif

  let l:positions = []
  for l:lnum in range(l:sec + 1, l:end)
    let l:line = getline(l:lnum)
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, s:link_pat, l:start)
      if len(l:m) < 3 || l:m[1] < 0
        break
      endif
      if !s:buf_in_code(l:lnum, l:m[1])
        call add(l:positions, {'lnum': l:lnum, 'col': l:m[1] + 1})
      endif
      let l:start = l:m[2]
    endwhile
  endfor
  return l:positions
endfunction

function! gnosis#jump_up() abort
  let l:up = s:find_section_line('up')
  if l:up <= 0
    let l:up = s:find_section_line('group')
  endif
  if l:up <= 0
    echo 'Context: section not found'
    return
  endif

  let l:links = s:section_link_positions('up')
  if len(l:links) == 1
    call cursor(l:links[0].lnum, l:links[0].col)
    normal! zv
    call gnosis#open_link_under_cursor()
    return
  endif
  if len(l:links) >= 2
    call cursor(l:links[0].lnum, l:links[0].col)
    normal! zv
    return
  endif

  call s:jump_to_line(l:up)
endfunction

" 行 a:lnum が画面で使う行数（折り返し・閉じた折りたたみを考慮した概算）。
function! s:screen_rows(lnum) abort
  if !&wrap || foldclosed(a:lnum) != -1
    return 1
  endif
  let l:w = max([1, winwidth(0) - getwininfo(win_getid())[0].textoff])
  return max([1, (strdisplaywidth(getline(a:lnum)) + l:w - 1) / l:w])
endfunction

" a:lnum の行を画面の中央に置くときの、窓の先頭行。ただし最終行が窓の下端より
" 上へ上がる（＝ファイルの末尾より下の空白が出る）ほど下へは送らない。
" 下に十分な行があれば中央、無ければ「最終行が窓の下端」になる先頭行を返す。
" カーソルは動かさない（末尾まで動かして戻す、はしない）。
function! s:view_top_centered(lnum) abort
  let l:h = winheight(0)
  " 中央に置くために a:lnum の上へ空ける画面の行数
  let l:above = max([0, (l:h - s:screen_rows(a:lnum)) / 2])
  let l:top = a:lnum
  let l:used = 0
  while l:top > 1
    let l:prev = l:top - 1
    let l:f = foldclosed(l:prev)
    if l:f != -1 | let l:prev = l:f | endif
    let l:r = s:screen_rows(l:prev)
    if l:used + l:r > l:above | break | endif
    let l:used += l:r
    let l:top = l:prev
  endwhile
  " 最終行が窓の下端に来る先頭行（これより下へはスクロールしない）
  let l:max_top = line('$')
  let l:used = 0
  let l:ln = line('$')
  while l:ln >= 1
    let l:f = foldclosed(l:ln)
    let l:start = l:f != -1 ? l:f : l:ln
    let l:r = s:screen_rows(l:start)
    if l:used + l:r > l:h | break | endif
    let l:used += l:r
    let l:max_top = l:start
    let l:ln = l:start - 1
  endwhile
  return min([l:top, l:max_top])
endfunction

" \k 用: Parent セクションへカーソルを移すだけで、リンク先は開かない
" （:JumpParent は従来どおり、リンクが1つならそのノートを開く）。
function! gnosis#jump_up_cursor() abort
  let l:up = s:find_section_line('up')
  if l:up <= 0
    let l:up = s:find_section_line('group')
  endif
  if l:up <= 0
    echo 'Context: section not found'
    return
  endif
  " 「### Context」の見出しの行へ移る（リンクの上ではなく、見出しに置く）。
  " 見出しは、下に十分な行があれば画面の中央、無ければファイルの末尾が窓の下端に
  " 来るところまでで止める（末尾より下の空白は出さない）。
  call s:jump_to_line(l:up)
  let l:view = winsaveview()
  let l:view.topline = s:view_top_centered(l:up)
  let l:view.topfill = 0
  call winrestview(l:view)
endfunction

function! gnosis#jump_down_top() abort
  let l:down = s:find_section_line('down')
  if l:down <= 0
    echo 'Child: section not found'
    return
  endif

  let l:end = s:section_end_line('down')
  call s:jump_to_line(l:end > l:down ? l:down + 1 : l:down)
endfunction

function! gnosis#jump_down_bottom() abort
  let l:up_links = s:section_link_positions('up')
  if len(l:up_links) >= 2
    call cursor(l:up_links[0].lnum, l:up_links[0].col)
    normal! zv
    return
  endif

  let l:down = s:find_section_line('down')
  if l:down <= 0
    echo 'Child: section not found'
    return
  endif

  let l:end = s:section_end_line('down')
  call s:jump_to_line(l:end > l:down ? l:end : l:down)
endfunction

function! gnosis#jump_last_link_before_up() abort
  " 本文の終わり = 最初の関係の節。節がまだ無いノートは本文全体
  let l:up = s:first_section_line()
  if l:up <= 0
    let l:up = line('$') + 1
  endif

  let l:last_lnum = 0
  let l:last_col = 0
  for l:lnum in range(1, l:up - 1)
    let l:line = getline(l:lnum)
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, s:link_pat, l:start)
      if len(l:m) < 3 || l:m[1] < 0
        break
      endif
      let l:last_lnum = l:lnum
      let l:last_col = l:m[1] + 1
      let l:start = l:m[2]
    endwhile
  endfor

  if l:last_lnum <= 0
    let l:up_end = s:up_end_line()
    if l:up_end > l:up
      for l:lnum in range(l:up + 1, l:up_end)
        let l:line = getline(l:lnum)
        let l:m = matchstrpos(l:line, s:link_pat, 0)
        if len(l:m) >= 3 && l:m[1] >= 0
          let l:last_lnum = l:lnum
          let l:last_col = l:m[1] + 1
          break
        endif
      endfor
    endif
  endif

  if l:last_lnum <= 0
    echo 'No links before Context or in Context'
    return
  endif

  call cursor(l:last_lnum, l:last_col)
  normal! zv
endfunction

" --- v2: 文中リンク / 関係リンクの位置一覧 --------------------------------
" 旧実装は 1 行ずつ getline + matchstrpos の Vimscript ループで、1 万行で
" 数百 ms かかっていた。searchpos()（C 実装）で行範囲を走査する。
function! s:link_positions_in_range(lo, hi) abort
  return s:link_positions_in_range_limited(a:lo, a:hi, 0)
endfunction

" a:max > 0 なら a:max 本見つけた時点で打ち切る（0 は無制限）。
function! s:link_positions_in_range_limited(lo, hi, max) abort
  let l:pos = []
  if a:max == 0
    let l:unlimited = 1
  else
    let l:unlimited = 0
  endif
  let l:hi = min([a:hi, line('$')])
  if a:lo > l:hi || (!l:unlimited && a:max <= 0) | return l:pos | endif
  let l:save = winsaveview()
  try
    call cursor(a:lo, 1)
    let l:m = searchpos(s:link_pat, 'cW', l:hi)
    while l:m[0] > 0 && l:m[0] <= l:hi
      if !s:buf_in_code(l:m[0], l:m[1] - 1)
        call add(l:pos, {'lnum': l:m[0], 'col': l:m[1]})
        if !l:unlimited && len(l:pos) >= a:max | break | endif
      endif
      let l:m = searchpos(s:link_pat, 'W', l:hi)
    endwhile
  finally
    call winrestview(l:save)
  endtry
  return l:pos
endfunction

" 本文（こっちにとって の見張りより前）のリンク。v2 ノート以外は空。
function! s:v2_body_link_positions() abort
  let [l:up_m, l:dn_m] = s:v2_boundaries()
  if l:up_m <= 0
    " 見出しが無いノート（index 等）は全行を本文扱い
    return s:link_positions_in_range(1, line('$'))
  endif
  return s:link_positions_in_range(1, l:up_m - 1)
endfunction

" parent/child（こっちにとって + そっちにとって）のリンク。
" v2 なら見張りコメント基準、v1 なら旧セクション基準。
function! s:v2_relation_link_positions() abort
  let [l:up_m, l:dn_m] = s:v2_boundaries()
  if l:up_m > 0
    return s:link_positions_in_range(l:up_m + 1, line('$'))
  endif
  return s:section_link_positions('up') + s:section_link_positions('down')
endfunction

function! s:pos_after(a, b) abort
  return a:a[0] > a:b[0] || (a:a[0] == a:b[0] && a:a[1] > a:b[1])
endfunction

" <Space> … parent/child（文中は対象外）のリンクを順に巡回。端で折り返す。
function! gnosis#jump_relation_link(forward) abort
  let l:pos = s:v2_relation_link_positions()
  if empty(l:pos)
    " ノートじゃない／関係リンクなし → 通常の <Space>/<BS> 相当
    execute 'normal! ' . (a:forward ? 'l' : 'h')
    return
  endif
  let l:cur = [line('.'), col('.')]
  let l:dest = []
  if a:forward
    for l:p in l:pos
      if s:pos_after([l:p.lnum, l:p.col], l:cur)
        let l:dest = l:p | break
      endif
    endfor
    if empty(l:dest) | let l:dest = l:pos[0] | endif
  else
    for l:i in range(len(l:pos) - 1, 0, -1)
      if s:pos_after(l:cur, [l:pos[l:i].lnum, l:pos[l:i].col])
        let l:dest = l:pos[l:i] | break
      endif
    endfor
    if empty(l:dest) | let l:dest = l:pos[-1] | endif
  endif
  call cursor(l:dest.lnum, l:dest.col)
  normal! zv
endfunction

" --- 行配列ベースの収集ヘルパ（ウォークモード用。バッファ非依存） -----------

" s:link_positions_in_range() の行配列版（lo/hi は 1-based）
function! s:link_positions_in_lines(lines, lo, hi) abort
  let l:pos = []
  let l:lo = max([a:lo, 1])
  let l:hi = min([a:hi, len(a:lines)])
  if l:lo > l:hi | return l:pos | endif
  let l:fz = s:fence_flags(a:lines)
  for l:lnum in range(l:lo, l:hi)
    let l:line = a:lines[l:lnum - 1]
    if l:fz[l:lnum - 1] | continue | endif
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, s:link_pat, l:start)
      if len(l:m) < 3 || l:m[1] < 0 | break | endif
      if !s:in_inline_code(l:line, l:m[1])
        call add(l:pos, {'lnum': l:lnum, 'col': l:m[1] + 1})
      endif
      let l:start = l:m[2]
    endwhile
  endfor
  return l:pos
endfunction

" s:v2_boundaries() の行配列版（返り値も 1-based 行番号）
function! s:v2_boundaries_in_lines(lines) abort
  let l:up_m = 0 | let l:dn_m = 0
  for l:i in range(0, len(a:lines) - 1)
    let l:s = trim(a:lines[l:i])
    if l:up_m == 0 && index(s:v2_any_marks, l:s) >= 0                        | let l:up_m = l:i + 1 | endif
    if l:s ==# s:v2_down_mark || index(s:v2_down_marks_legacy, l:s) >= 0 | let l:dn_m = l:i + 1 | endif
  endfor
  return l:up_m > 0 ? [l:up_m, l:dn_m] : [0, 0]
endfunction

function! s:section_link_positions_in_lines(lines, name) abort
  if a:name ==# 'up'
    return s:section_link_positions_in_lines_one(a:lines, 'up') + s:section_link_positions_in_lines_one(a:lines, 'group')
  endif
  return s:section_link_positions_in_lines_one(a:lines, a:name)
endfunction

function! s:section_link_positions_in_lines_one(lines, name) abort
  let l:idx = s:find_section_index_in_lines(a:lines, a:name)
  if l:idx < 0 | return [] | endif
  let l:end = s:section_end_index_in_lines(a:lines, l:idx)
  if l:end <= l:idx + 1 | return [] | endif
  return s:link_positions_in_lines(a:lines, l:idx + 2, l:end)
endfunction

" s:v2_relation_link_positions() の行配列版
function! s:v2_relation_link_positions_in_lines(lines) abort
  let [l:up_m, l:dn_m] = s:v2_boundaries_in_lines(a:lines)
  if l:up_m > 0
    return s:link_positions_in_lines(a:lines, l:up_m + 1, len(a:lines))
  endif
  return s:section_link_positions_in_lines(a:lines, 'up')
        \ + s:section_link_positions_in_lines(a:lines, 'down')
endfunction

" parent/child のリンクを『ラベル / 表示名 / こっちにとって・そっちにとって』付きで集める。
"   {lnum, col, side('up'|'down'), label, text, target}
function! s:relation_links_from_lines(lines, base_dir) abort
  let l:pos = s:v2_relation_link_positions_in_lines(a:lines)
  if empty(l:pos) | return [] | endif
  let [l:up_m, l:dn_m] = s:v2_boundaries_in_lines(a:lines)
  let l:down_start = l:dn_m > 0 ? l:dn_m
        \ : (s:find_section_index_in_lines(a:lines, 'down') + 1)
  let l:out = []
  for l:p in l:pos
    " ラベル: その行 or 上方向で最初に見つかる『語:』行（リンク行は飛ばす）
    let l:label = ''
    for l:ln in range(l:p.lnum, max([l:p.lnum - 20, 1]), -1)
      let l:t = get(a:lines, l:ln - 1, '')
      if l:t =~# '^\s*\[' | continue | endif
      let l:h = matchstr(l:t, '^\s*\zs[^[:space:]:][^:]\{-}\ze\s*:')
      if !empty(l:h) | let l:label = trim(l:h) | break | endif
    endfor
    let l:raw = matchstr(get(a:lines, l:p.lnum - 1, ''), s:link_pat, l:p.col - 1)
    let l:parts = matchlist(l:raw, '\v\[(%(\\.|[^\]\\])*)\]\(([^)]*)\)')
    call add(l:out, {
          \ 'lnum': l:p.lnum, 'col': l:p.col,
          \ 'side': (l:down_start > 0 && l:p.lnum > l:down_start) ? 'down' : 'up',
          \ 'label': l:label,
          \ 'text': get(l:parts, 1, ''), 'target': get(l:parts, 2, '')})
  endfor
  return l:out
endfunction

" 本文（こっちにとって 見張りより前）のリンクを、直近の見出しを label にして集める。
"   {lnum, col, side('body'), label, text, target}
function! s:body_links_from_lines(lines, base_dir) abort
  let [l:up_m, l:dn_m] = s:v2_boundaries_in_lines(a:lines)
  " 見出しが無いノート（index 等）は全行を本文扱い
  let l:hi = l:up_m > 0 ? l:up_m - 1 : len(a:lines)
  let l:pos = s:link_positions_in_lines(a:lines, 1, l:hi)
  if empty(l:pos) | return [] | endif
  let l:out = []
  for l:p in l:pos
    let l:label = ''
    for l:ln in range(l:p.lnum, max([l:p.lnum - 40, 1]), -1)
      let l:t = get(a:lines, l:ln - 1, '')
      let l:hd = matchstr(l:t, '^#\+\s\+\zs.\+')
      if !empty(l:hd) | let l:label = trim(l:hd) | break | endif
    endfor
    let l:raw = matchstr(get(a:lines, l:p.lnum - 1, ''), s:link_pat, l:p.col - 1)
    let l:parts = matchlist(l:raw, '\v\[(%(\\.|[^\]\\])*)\]\(([^)]*)\)')
    call add(l:out, {
          \ 'lnum': l:p.lnum, 'col': l:p.col, 'side': 'body',
          \ 'label': l:label,
          \ 'text': get(l:parts, 1, ''), 'target': get(l:parts, 2, '')})
  endfor
  return l:out
endfunction

" 文中 / こっちにとって / そっちにとって の3グループにまとめる
function! s:space_collect(lines, base_dir) abort
  let l:rel = s:relation_links_from_lines(a:lines, a:base_dir)
  return {
        \ 'body': s:body_links_from_lines(a:lines, a:base_dir),
        \ 'up':   filter(copy(l:rel), 'v:val.side ==# "up"'),
        \ 'down': filter(copy(l:rel), 'v:val.side ==# "down"'),
        \ }
endfunction

" グループを区切り行付きの平坦な一覧にする（区切りは {sep:1, title:...}）
" ---------------------------------------------------------------------------
" <Space> ナビゲータ
"   スコープ  local（今のノートのリンク） / global（全ノート検索）
"   サブモード input（打つ=絞り込み） / select（プレーンキーでナビ）
" キーは両スコープ共通。ラベルキーは常に「選択」だけ。
" ---------------------------------------------------------------------------

let s:rlp_win = -1
let s:rlp_pvwin = -1
let s:rlp_items = []          " 表示中の行（区切り込み）
let s:rlp_sel = 0
let s:rlp_top = 0
let s:rlp_rows = 14
let s:rlp_geo = {}
let s:rlp_scope = 'local'     " 'local' | 'global'
let s:rlp_input = 0           " 1 = 打つとクエリ / 0 = 打つとコマンド
let s:rlp_query = ''
let s:rlp_terms = []
let s:rlp_path = ''           " アンカー = いま一覧を出しているノート
let s:rlp_base = ''
let s:rlp_groups = {}         " local: s:space_collect の結果
let s:rlp_stack = []          " [{path,base,sel,top,scope,query,mode}]
let s:rlp_crumbs = []
let s:rlp_origin = {}         " {bufnr,pos,path}
let s:rlp_cands = []          " [{p,t,b}] 全ノート索引
let s:rlp_rowmap = {}         " ラベル文字 -> s:rlp_items のインデックス
let s:rlp_marks = {}          " path -> 1（popup を閉じても残す）
let s:rlp_want_cursor_init = 0
" コマンド文字（j k l h g G f b i c p y a m n d q）を避けたラベル
let s:rlp_labels = '1234567890esrtuvwxzo'

function! s:rlp_labels_str() abort
  return get(g:, 'gnosis_space_labels', s:rlp_labels)
endfunction

" --- 行の基本操作 -----------------------------------------------------------

function! s:rlp_is_sel(i) abort
  return a:i >= 0 && a:i < len(s:rlp_items) && !get(s:rlp_items[a:i], 'sep', 0)
endfunction

function! s:rlp_first_sel() abort
  for l:i in range(len(s:rlp_items))
    if !get(s:rlp_items[l:i], 'sep', 0) | return l:i | endif
  endfor
  return -1
endfunction

function! s:rlp_last_sel() abort
  for l:i in range(len(s:rlp_items) - 1, 0, -1)
    if !get(s:rlp_items[l:i], 'sep', 0) | return l:i | endif
  endfor
  return -1
endfunction

function! s:rlp_step_sel(dir) abort
  let l:i = s:rlp_sel + a:dir
  while l:i >= 0 && l:i < len(s:rlp_items)
    if !get(s:rlp_items[l:i], 'sep', 0)
      let s:rlp_sel = l:i | return
    endif
    let l:i += a:dir
  endwhile
endfunction

function! s:rlp_sel_item() abort
  return s:rlp_is_sel(s:rlp_sel) ? s:rlp_items[s:rlp_sel] : {}
endfunction

" 行 -> 実ファイルパス（link 行はアンカー基準で解決、それ以外は path をそのまま）
function! s:rlp_row_path(it) abort
  if empty(a:it) | return '' | endif
  if get(a:it, 'kind', '') ==# 'link'
    return s:resolve_link_for_navigation(a:it.target, s:rlp_base)
  endif
  return get(a:it, 'path', '')
endfunction

" 末尾を残して頭を削る（パンくず用。今どこに居るかは末尾が大事）
function! s:rlp_trunc_tail(s, w) abort
  if a:w <= 1 | return a:s | endif
  if strdisplaywidth(a:s) <= a:w | return a:s | endif
  let l:s = a:s
  while strchars(l:s) > 1 && strdisplaywidth(l:s) > a:w - 1
    let l:s = strcharpart(l:s, 1)
  endwhile
  return '…' . l:s
endfunction

" 頭を残して末尾を削る（ノート名・ラベル用。頭が読めないと何のノートか分からない）
function! s:rlp_trunc_head(s, w) abort
  if a:w <= 1 | return a:s | endif
  if strdisplaywidth(a:s) <= a:w | return a:s | endif
  let l:s = a:s
  while strchars(l:s) > 1 && strdisplaywidth(l:s) > a:w - 1
    let l:s = strcharpart(l:s, 0, strchars(l:s) - 1)
  endwhile
  return l:s . '…'
endfunction

function! s:rlp_crumb_line(w) abort
  let l:c = copy(s:rlp_crumbs)
  if empty(l:c) | return '·' | endif
  call map(l:c, {_, v -> strchars(v) > 16 ? strcharpart(v, 0, 15) . '…' : v})
  let l:s = len(l:c) <= 2 ? join(l:c, ' › ') : l:c[0] . ' › … › ' . l:c[-1]
  return s:rlp_trunc_tail(l:s, a:w)
endfunction

" --- 候補の組み立て ---------------------------------------------------------

function! s:rlp_set_terms() abort
  let s:rlp_terms = map(
        \ filter(split(substitute(s:rlp_query, '　', ' ', 'g'), ' '), 'v:val !=# ""'),
        \ 'tolower(v:val)')
endfunction

function! s:rlp_match(hay) abort
  if empty(s:rlp_terms) | return 1 | endif
  let l:h = tolower(a:hay)
  for l:t in s:rlp_terms
    if stridx(l:h, l:t) < 0 | return 0 | endif
  endfor
  return 1
endfunction

" リンク先ノートの全文（小文字・空白を潰した1行）。検索のたびに読まないよう
" パスごとにキャッシュする。.md 以外・読めないものは空。
let s:rlp_body_cache = {}
let s:rlp_origin_names_cache = 0
function! s:rlp_link_body(it) abort
  let l:p = s:resolve_link_for_navigation(a:it.target, s:rlp_base)
  if !has_key(s:rlp_body_cache, l:p)
    let s:rlp_body_cache[l:p] = (s:is_markdown_file(l:p) && filereadable(l:p))
          \ ? tolower(substitute(join(readfile(l:p), ' '), '\s\+', ' ', 'g')) : ''
  endif
  return s:rlp_body_cache[l:p]
endfunction

function! s:rlp_body_match(it) abort
  if empty(s:rlp_terms) | return 0 | endif
  let l:b = s:rlp_link_body(a:it)
  if empty(l:b) | return 0 | endif
  for l:t in s:rlp_terms
    if stridx(l:b, l:t) < 0 | return 0 | endif
  endfor
  return 1
endfunction

function! s:rlp_build_local() abort
  let l:items = []
  if !empty(s:rlp_path) && filereadable(s:rlp_path)
    call add(l:items, {'kind': 'anchor', 'path': s:rlp_path, 'label': '',
          \ 'text': s:get_title(s:rlp_path)})
  endif
  for [l:key, l:title] in [['body', gnosis#i18n#tr('文中')], ['up', gnosis#i18n#tr('こっちにとって')], ['down', gnosis#i18n#tr('そっちにとって')]]
    let l:g = get(s:rlp_groups, l:key, [])
    " リンクの表示名に当たるものを先に、表示名には当たらずリンク先の全文だけに
    " 当たるものをその後ろに並べる（それぞれ元の並びを保つ）。
    let l:hit = filter(copy(l:g), 's:rlp_match(v:val.label . " " . v:val.text)')
    if !empty(s:rlp_terms)
      let l:hit += filter(copy(l:g),
            \ '!s:rlp_match(v:val.label . " " . v:val.text) && s:rlp_body_match(v:val)')
    endif
    if empty(l:hit) | continue | endif
    call add(l:items, {'sep': 1, 'title': l:title})
    for l:x in l:hit
      let l:y = copy(l:x)
      let l:y.kind = 'link'
      call add(l:items, l:y)
    endfor
  endfor
  return l:items
endfunction

function! s:rlp_build_global() abort
  " 一覧に出す名前は、最初に開いたページにそのノートへのリンクがあればその表示名、
  " 無ければタイトル。タイトルに当たるものを先に、本文だけに当たるものをその後ろに
  " 並べる（検索はタイトルと表示名の両方に当てる）。それぞれ索引の並び（最近訪問した順）。
  let l:names = s:rlp_origin_names()
  let l:items = []
  let l:rest = []
  for l:c in s:rlp_cands
    let l:name = get(l:names, fnamemodify(l:c.p, ':p'), '')
    let l:row = {'kind': 'note', 'path': l:c.p, 'text': empty(l:name) ? l:c.t : l:name, 'label': ''}
    if s:rlp_match(l:c.t . ' ' . l:name)
      call add(l:items, l:row)
    elseif s:rlp_match(l:c.t . ' ' . l:name . ' ' . l:c.b)
      call add(l:rest, l:row)
    endif
  endfor
  return l:items + l:rest
endfunction

function! s:rlp_refresh() abort
  call s:rlp_set_terms()
  let s:rlp_items = (s:rlp_scope ==# 'global')
        \ ? s:rlp_build_global() : s:rlp_build_local()
  if !s:rlp_is_sel(s:rlp_sel)
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
  endif
endfunction

function! s:rlp_build_index() abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || !isdirectory(l:root) | let l:root = getcwd() | endif
  let l:idx = get(g:, 'gnosis_search_index', '')
  let s:rlp_cands = []
  if !empty(l:idx) && filereadable(l:idx) && gnosis#has_python()
    for l:ln in systemlist(gnosis#python_cmd() . ' ' . shellescape(l:idx) . ' ' . shellescape(l:root))
      let l:f = split(l:ln, "\t", 1)
      if len(l:f) >= 2
        call add(s:rlp_cands, {'p': l:f[0], 't': l:f[1], 'b': get(l:f, 2, '')})
      endif
    endfor
  endif
  if empty(s:rlp_cands)
    " フォールバック: *.md を舐めてタイトルだけ（本文検索は効かない）
    for l:p in split(globpath(l:root, '**/*.md', 0), "\n")
      if l:p =~# '[\\/]\.undo[\\/]' | continue | endif
      call add(s:rlp_cands, {'p': l:p, 't': s:get_title(l:p), 'b': ''})
    endfor
  endif
  " 最近訪問した順に固定する。無クエリでも絞り込み後でも並びが安定し、
  " 「決める時間」が減る（NAVIGATION.md 根本4）。
  let l:recent = gnosis#recent_map()
  call map(s:rlp_cands, {_, c -> extend(c,
        \ {'r': get(l:recent, fnamemodify(c.p, ':p'), 0)})})
  call sort(s:rlp_cands, {a, b -> b.r == a.r ? (a.t < b.t ? -1 : 1) : b.r - a.r})
endfunction

" --- ジオメトリ -------------------------------------------------------------

function! s:rlp_geometry() abort
  if get(g:, 'gnosis_space_fullscreen', 1)
    " popup 1 個の画面占有 = 宣言幅/高 + border(2) + padding(横2/縦0)
    let l:chrome_w = 4
    let l:chrome_h = 2
    let l:outer = 1
    let l:gap = 1
    let l:top = 1 + l:outer
    let l:h = max([&lines - l:chrome_h - 2 * l:outer, 8])
    let l:lw = get(g:, 'gnosis_space_list_width', 0)
    if l:lw <= 0
      let l:lw = max([36, min([float2nr(&columns * 0.38), 58])])
    endif
    let l:list_col = 1 + l:outer
    let l:pv_col = l:list_col + l:lw + l:chrome_w + l:gap
    let l:pvw = max([&columns - l:pv_col - l:chrome_w - l:outer + 1, 20])
    return {
          \ 'list_line': l:top, 'list_col': l:list_col, 'list_w': l:lw, 'h': l:h,
          \ 'pv_line': l:top, 'pv_col': l:pv_col, 'pv_w': l:pvw,
          \ 'rows': max([l:h - 6, 3]),
          \ }
  endif
  let l:rows = min([max([len(s:rlp_items), 1]), 10])
  let l:h = l:rows + 5
  let l:w = min([float2nr(&columns * 0.40), 56])
  let l:pv = min([float2nr(&columns * 0.46), 90])
  let l:col = max([(&columns - (l:w + 3 + l:pv)) / 2, 2])
  let l:line = max([(&lines - l:h) / 2, 1])
  return {
        \ 'list_line': l:line, 'list_col': l:col, 'list_w': l:w, 'h': l:h,
        \ 'pv_line': l:line, 'pv_col': l:col + l:w + 3, 'pv_w': l:pv,
        \ 'rows': l:rows,
        \ }
endfunction

" --- 読み込み / 移動 --------------------------------------------------------

function! s:rlp_load(path, base, ...) abort
  let l:keep_sel = a:0 > 0 ? a:1 : -1
  let l:keep_top = a:0 > 1 ? a:2 : 0
  let s:rlp_path = a:path
  let s:rlp_base = a:base
  let s:rlp_scope = 'local'
  if a:path ==# get(s:rlp_origin, 'path', '') && get(s:rlp_origin, 'bufnr', -1) > 0
    let l:lines = getbufline(s:rlp_origin.bufnr, 1, '$')
  else
    let l:lines = filereadable(a:path) ? readfile(a:path) : []
  endif
  let s:rlp_groups = s:space_collect(l:lines, a:base)
  call s:rlp_refresh()

  if s:rlp_want_cursor_init
    let s:rlp_want_cursor_init = 0
    let l:cur = s:rlp_origin.pos[1:2]
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
    for l:i in range(len(s:rlp_items))
      let l:it = s:rlp_items[l:i]
      if get(l:it, 'kind', '') !=# 'link' | continue | endif
      if s:pos_after([l:it.lnum, l:it.col], l:cur)
        let s:rlp_sel = l:i | break
      endif
    endfor
    let s:rlp_top = 0
  elseif l:keep_sel >= 0 && s:rlp_is_sel(l:keep_sel)
    let s:rlp_sel = l:keep_sel
    let s:rlp_top = l:keep_top
  else
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
    let s:rlp_top = 0
  endif
  call s:rlp_render()
endfunction

" 選択行のノートへ『潜る』（ポップアップは開いたまま local ビューを積む）
function! s:rlp_dive(idx) abort
  if !s:rlp_is_sel(a:idx) | return | endif
  let l:it = s:rlp_items[a:idx]
  if get(l:it, 'kind', '') ==# 'anchor'
    " アンカー（自分自身）には潜れない。選ぶだけ ＝ ⏎ で開ける状態にする
    let s:rlp_sel = a:idx
    call s:rlp_render()
    return
  endif
  let l:p = s:rlp_row_path(l:it)
  if empty(l:p) || (!filereadable(l:p) && !isdirectory(l:p)) | return | endif
  if isdirectory(l:p) || !s:is_markdown_file(l:p)
    call popup_close(s:rlp_win, {'open': a:idx})
    return
  endif
  call add(s:rlp_stack, {'path': s:rlp_path, 'base': s:rlp_base,
        \ 'sel': s:rlp_sel, 'top': s:rlp_top,
        \ 'scope': s:rlp_scope, 'query': s:rlp_query, 'input': s:rlp_input})
  call add(s:rlp_crumbs, fnamemodify(l:p, ':t:r'))
  let s:rlp_query = ''
  let s:rlp_input = 0
  call s:rlp_load(l:p, fnamemodify(l:p, ':h'))
endfunction

function! s:rlp_back() abort
  if empty(s:rlp_stack)
    call popup_close(s:rlp_win, {'cancel': 1})
    return
  endif
  let l:prev = remove(s:rlp_stack, -1)
  if !empty(s:rlp_crumbs) | call remove(s:rlp_crumbs, -1) | endif
  let s:rlp_query = get(l:prev, 'query', '')
  let s:rlp_input = get(l:prev, 'input', 0)
  if get(l:prev, 'scope', 'local') ==# 'global'
    let s:rlp_scope = 'global'
    call s:rlp_refresh()
    let s:rlp_sel = l:prev.sel
    let s:rlp_top = l:prev.top
    if !s:rlp_is_sel(s:rlp_sel)
      let s:rlp_sel = max([s:rlp_first_sel(), 0])
    endif
    call s:rlp_render()
    return
  endif
  call s:rlp_load(l:prev.path, l:prev.base, l:prev.sel, l:prev.top)
endfunction

" --- マーク -----------------------------------------------------------------

function! s:rlp_toggle_mark() abort
  let l:p = s:rlp_row_path(s:rlp_sel_item())
  if empty(l:p) | return | endif
  if has_key(s:rlp_marks, l:p)
    unlet s:rlp_marks[l:p]
  else
    let s:rlp_marks[l:p] = 1
  endif
endfunction

" 適用対象: マークがあればマーク全部、無ければ選択行
function! s:rlp_targets() abort
  if !empty(s:rlp_marks) | return sort(keys(s:rlp_marks)) | endif
  let l:p = s:rlp_row_path(s:rlp_sel_item())
  return empty(l:p) ? [] : [l:p]
endfunction

" --- 描画 -------------------------------------------------------------------

function! s:rlp_render() abort
  if s:rlp_win < 0 | return | endif
  let l:w = max([get(s:rlp_geo, 'list_w', 46) - 2, 10])
  let l:total = len(s:rlp_items)
  if s:rlp_sel < s:rlp_top | let s:rlp_top = s:rlp_sel | endif
  if s:rlp_sel >= s:rlp_top + s:rlp_rows | let s:rlp_top = s:rlp_sel - s:rlp_rows + 1 | endif
  if s:rlp_top < 0 | let s:rlp_top = 0 | endif

  let l:lw = 0
  for l:it in s:rlp_items
    if get(l:it, 'sep', 0) | continue | endif
    let l:lw = max([l:lw, strdisplaywidth(get(l:it, 'label', ''))])
  endfor
  let l:lw = min([l:lw, 14])

  " 上部 = パンくず / 検索バー / 区切り。打つ場所と見る場所を近づける。
  let l:nsel = 0
  for l:it in s:rlp_items
    if !get(l:it, 'sep', 0) | let l:nsel += 1 | endif
  endfor
  let l:nmark = len(s:rlp_marks)
  let l:pos = printf(' %d/%d%s',
        \ l:nsel ? index(filter(range(len(s:rlp_items)),
        \   '!get(s:rlp_items[v:val], "sep", 0)'), s:rlp_sel) + 1 : 0,
        \ l:nsel, l:nmark > 0 ? ' *' . l:nmark : '')
  if s:rlp_typing()
    " 打っているツールだけ検索バーを出す。カーソル ▏ が見えている＝打てる合図。
    let l:qtext = (s:rlp_scope ==# 'global' ? gnosis#i18n#tr('検索 ') : gnosis#i18n#tr('絞込 ')) . s:rlp_query . '▏'
    let l:right = l:pos
  elseif s:rlp_scope ==# 'global'
    " グローバルのコマンド状態。i で打てることと、効いているクエリを見せる
    let l:qtext = gnosis#i18n#tr('全ノート') . (empty(s:rlp_query) ? '' : ' ' . s:rlp_query)
    let l:qtext = s:rlp_trunc_head(l:qtext, l:w - 14)
    let l:right = l:pos
  else
    " ローカルは打たないので、バーではなく居場所だけ出す
    let l:qtext = '◎ ' . s:rlp_trunc_head(s:get_title(s:rlp_path), l:w - 14)
    let l:right = l:pos
  endif
  let l:bar = s:rlp_trunc_tail(l:qtext,
        \ max([l:w - strdisplaywidth(l:right), 4]))
  let l:bar .= repeat(' ',
        \ max([l:w - strdisplaywidth(l:bar) - strdisplaywidth(l:right), 0])) . l:right

  let l:lines = [s:rlp_crumb_line(l:w), l:bar, repeat('─', l:w)]
  let l:labels = s:rlp_labels_str()
  let l:ln = 0
  let s:rlp_rowmap = {}
  let l:end = min([s:rlp_top + s:rlp_rows, l:total])
  for l:i in range(s:rlp_top, l:end - 1)
    let l:it = s:rlp_items[l:i]
    if get(l:it, 'sep', 0)
      let l:t = '── ' . l:it.title . ' '
      call add(l:lines, l:t . repeat('─', max([l:w - strdisplaywidth(l:t), 0])))
      continue
    endif
    let l:lbl = ' '
    if l:ln < strchars(l:labels)
      let l:lbl = strcharpart(l:labels, l:ln, 1)
      let s:rlp_rowmap[l:lbl] = l:i
      let l:ln += 1
    endif
    let l:cur = (l:i == s:rlp_sel) ? '▶' : ' '
    let l:mk = has_key(s:rlp_marks, s:rlp_row_path(l:it)) ? '*' : ' '
    let l:kind = get(l:it, 'kind', '')
    if l:kind ==# 'anchor'
      call add(l:lines, l:cur . l:lbl . l:mk . '◎ '
            \ . s:rlp_trunc_head(l:it.text, l:w - 5))
    elseif l:kind ==# 'note'
      call add(l:lines, l:cur . l:lbl . l:mk . '  '
            \ . s:rlp_trunc_head(l:it.text, l:w - 5))
    else
      let l:arw = (l:it.side ==# 'up') ? '→' : (l:it.side ==# 'down' ? '←' : '¶')
      let l:pad = repeat(' ', max([l:lw - strdisplaywidth(l:it.label), 0]))
      let l:pre = printf('%s%s%s%s %s%s  ',
            \ l:cur, l:lbl, l:mk, l:arw, l:it.label, l:pad)
      call add(l:lines, l:pre
            \ . s:rlp_trunc_head(l:it.text, max([l:w - strdisplaywidth(l:pre), 4])))
    endif
  endfor

  let l:below = max([0, l:total - l:end])
  call add(l:lines, l:below > 0
        \ ? '─── ↓' . l:below . ' ' . repeat('─', max([l:w - 6 - len(string(l:below)), 0]))
        \ : repeat('─', l:w))
  if s:rlp_input
    call add(l:lines, gnosis#i18n#tr('打つ 絞る  ↑↓ 選択  → 潜る  ⏎ 入力終了  ⌫ 消す  ⎋ 消して終了'))
  else
    call add(l:lines, s:rlp_scope ==# 'global'
          \ ? gnosis#i18n#tr('字 移動  ⏎ 開く  l 潜る  ⌫ 戻る  fb プレ  cp 子親  ym  i 打つ  ⇥ 切替')
          \ : gnosis#i18n#tr('字 潜る  jk 選択  ⏎ 開く  ⌫ 戻る  ␣ ここ  fb プレ  cp 子親  ym  i 打つ  ⇥ 切替'))
  endif
  call popup_settext(s:rlp_win, l:lines)
  call popup_setoptions(s:rlp_win,
        \ {'title': s:rlp_scope ==# 'global' ? gnosis#i18n#tr(' 全ノート ') : gnosis#i18n#tr(' ローカル ')})
  call s:rlp_preview()
endfunction

" 最初に開いたページのリンク先（絶対パス）→ そのページでの表示名。左の一覧に
" 出す名前に使う。popup を開いている間だけ使うので、ナビゲータ起動時に
" s:rlp_origin_names_cache をリセットする。
function! s:rlp_origin_names() abort
  if s:rlp_origin_names_cache isnot 0
    return s:rlp_origin_names_cache
  endif
  let l:m = {}
  if get(s:rlp_origin, 'bufnr', -1) <= 0 || empty(get(s:rlp_origin, 'path', ''))
    let s:rlp_origin_names_cache = l:m
    return l:m
  endif
  let l:base = fnamemodify(s:rlp_origin.path, ':h')
  let l:g = s:space_collect(getbufline(s:rlp_origin.bufnr, 1, '$'), l:base)
  for l:key in ['body', 'up', 'down']
    for l:x in get(l:g, l:key, [])
      let l:p = fnamemodify(s:resolve_link_for_navigation(l:x.target, l:base), ':p')
      if !has_key(l:m, l:p) && !empty(l:x.text)
        let l:m[l:p] = l:x.text
      endif
    endfor
  endfor
  let s:rlp_origin_names_cache = l:m
  return l:m
endfunction

function! s:rlp_preview() abort
  if s:rlp_pvwin < 0 | return | endif
  let l:it = s:rlp_sel_item()
  if empty(l:it)
    call popup_settext(s:rlp_pvwin, [gnosis#i18n#tr('(該当なし)')])
    return
  endif
  let l:path = s:rlp_row_path(l:it)
  if empty(l:path) || (!filereadable(l:path) && !isdirectory(l:path))
    call popup_settext(s:rlp_pvwin,
          \ [gnosis#i18n#tr('(開けない: ') . get(l:it, 'target', get(l:it, 'path', '')) . ')'])
    return
  endif
  if isdirectory(l:path)
    call popup_settext(s:rlp_pvwin, [gnosis#i18n#tr('(ディレクトリ)'), l:path])
    return
  endif
  let l:body = readfile(l:path, '', get(g:, 'gnosis_space_preview_lines', 400))
  if !empty(l:body) && l:body[0] =~# '^---\s*$'
    let l:e = 1
    while l:e < len(l:body) && l:body[l:e] !~# '^\%(---\|\.\.\.\)\s*$'
      let l:e += 1
    endwhile
    let l:body = l:body[l:e + 1 :]
  endif
  while !empty(l:body) && l:body[0] =~# '^\s*$'
    call remove(l:body, 0)
  endwhile
  let l:head = s:get_title(l:path) . '   ' . fnamemodify(l:path, ':t')
  let l:rule = repeat('─', max([get(s:rlp_geo, 'pv_w', 46) - 2, 10]))

  " 検索語を強調し、最初のヒット行が見えるところまでスクロールする。
  " ヒットが見えないと「なぜこれが出てきたのか」が分からず判断できない。
  if empty(s:rlp_terms)
    call popup_settext(s:rlp_pvwin, [l:head, l:rule] + l:body)
    call popup_setoptions(s:rlp_pvwin, {'firstline': 1})
    return
  endif
  call s:rlp_ensure_hl()
  let l:lines = [{'text': l:head}, {'text': l:rule}]
  let l:first = 0
  let l:n = 2
  for l:b in l:body
    let l:n += 1
    let l:props = s:rlp_hit_props(l:b)
    if empty(l:props)
      call add(l:lines, {'text': l:b})
    else
      if l:first == 0 | let l:first = l:n | endif
      call add(l:lines, {'text': l:b, 'props': l:props})
    endif
  endfor
  call popup_settext(s:rlp_pvwin, l:lines)
  " ヒット行の少し上から見せる（文脈が要るので 2 行手前）
  call popup_setoptions(s:rlp_pvwin,
        \ {'firstline': l:first > 0 ? max([l:first - 2, 1]) : 1})
endfunction

" プレビュー内のヒット強調用。reverse なので配色を問わず必ず見える。
function! s:rlp_ensure_hl() abort
  highlight default SimpleNavMatch term=reverse cterm=reverse gui=reverse
  if empty(prop_type_get('gnosisNavMatch'))
    call prop_type_add('gnosisNavMatch',
          \ {'highlight': 'SimpleNavMatch', 'combine': v:true})
  endif
endfunction

" 1 行の中の検索語一致に付ける text-property のリスト
function! s:rlp_hit_props(text) abort
  let l:props = []
  if empty(a:text) | return l:props | endif
  let l:hay = tolower(a:text)
  for l:t in s:rlp_terms
    if empty(l:t) | continue | endif
    let l:len = strlen(l:t)
    let l:start = 0
    while 1
      let l:i = stridx(l:hay, l:t, l:start)
      if l:i < 0 | break | endif
      call add(l:props, {'col': l:i + 1, 'length': l:len, 'type': 'gnosisNavMatch'})
      let l:start = l:i + l:len
    endwhile
  endfor
  return l:props
endfunction

" --- キー -------------------------------------------------------------------

" 打鍵がクエリに行くか（＝グローバル、またはローカルの一時絞り込み中）
" 打鍵がクエリに行く状態か
function! s:rlp_typing() abort
  return s:rlp_input
endfunction

" c/p/y/m の共通処理。記号からも英字からも呼ばれる。
function! s:rlp_op(op) abort
  if a:op ==# 'child'
    call popup_close(s:rlp_win, {'link': 1, 'below': 1, 'targets': s:rlp_targets()})
  elseif a:op ==# 'parent'
    call popup_close(s:rlp_win, {'link': 1, 'below': 0, 'targets': s:rlp_targets()})
  elseif a:op ==# 'yank'
    call popup_close(s:rlp_win, {'yank': s:rlp_targets()})
  elseif a:op ==# 'mark'
    call s:rlp_toggle_mark()
    call s:rlp_render()
  endif
endfunction

" =============================================================================
" キー
"
"   状態は 1 つだけ: 打つ（入力） / 打たない（コマンド）。
"     ⏎ で入力を終える → コマンド
"     i で入力に戻る（/ はクエリを消して入力）
"   コマンド状態のキーは **ローカルでもグローバルでも完全に同じ**。
"   スコープ（ローカル / グローバル）は候補が何かの違いでしかない。
" =============================================================================
function! s:rlp_key(winid, key) abort
  " --- 状態に関係なく同じ意味（特殊キー・矢印・⇥） ---
  if a:key ==# "\<Tab>"
    call s:rlp_switch_scope()
    return 1
  elseif a:key ==# "\<Down>"
    call s:rlp_step_sel(1)  | call s:rlp_render() | return 1
  elseif a:key ==# "\<Up>"
    call s:rlp_step_sel(-1) | call s:rlp_render() | return 1
  elseif a:key ==# "\<Right>"
    call s:rlp_dive(s:rlp_sel) | return 1
  elseif a:key ==# "\<Left>"
    call s:rlp_back() | return 1
  elseif a:key ==# "\<PageDown>"
    if s:rlp_pvwin >= 0 | call win_execute(s:rlp_pvwin, "normal! \<C-f>") | endif
    return 1
  elseif a:key ==# "\<PageUp>"
    if s:rlp_pvwin >= 0 | call win_execute(s:rlp_pvwin, "normal! \<C-b>") | endif
    return 1
  endif

  " ===== 入力状態: 打つとクエリ =====
  if s:rlp_input
    if a:key ==# "\<CR>"
      " 入力終了 → コマンド状態（ここからラベル1タップで潜れる）
      let s:rlp_input = 0
    elseif a:key ==# "\<Esc>" || a:key ==# "\<C-c>"
      " クエリを捨てて入力終了。空で押したら閉じる
      if empty(s:rlp_query)
        call popup_close(s:rlp_win, {'cancel': 1})
        return 1
      endif
      let s:rlp_query = ''
      let s:rlp_input = 0
      call s:rlp_refresh()
      let s:rlp_sel = max([s:rlp_first_sel(), 0])
    elseif a:key ==# "\<BS>" || a:key ==# "\<C-h>"
      if empty(s:rlp_query)
        call s:rlp_back()
        return 1
      endif
      let s:rlp_query = strcharpart(s:rlp_query, 0,
            \ max([strchars(s:rlp_query) - 1, 0]))
      call s:rlp_refresh()
      let s:rlp_sel = max([s:rlp_first_sel(), 0])
    elseif a:key =~# '^.$' && a:key !~# '^[[:cntrl:]]$'
      let s:rlp_query .= a:key
      call s:rlp_refresh()
      let s:rlp_sel = max([s:rlp_first_sel(), 0])
      let s:rlp_top = 0
    endif
    call s:rlp_render()
    return 1
  endif

  " ===== コマンド状態: 打たない。ローカル / グローバルで同じキー =====
  " 記号は入力中はクエリ文字として打てるので、コマンドとして効くのはここだけ。
  if a:key ==# '+'
    call s:rlp_op('child')  | return 1
  elseif a:key ==# '-'
    call s:rlp_op('parent') | return 1
  elseif a:key ==# '*'
    call s:rlp_op('mark')   | return 1
  elseif a:key ==# '='
    call s:rlp_op('yank')   | return 1
  elseif a:key ==# "\<Esc>" || a:key ==# "\<C-c>"
    call popup_close(s:rlp_win, {'cancel': 1})
    return 1
  elseif a:key ==# "\<CR>"
    call popup_close(s:rlp_win, {'open': s:rlp_sel})
    return 1
  elseif a:key ==# "\<BS>" || a:key ==# "\<C-h>" || a:key ==# 'h' || a:key ==# 'q'
    call s:rlp_back()
    return 1
  elseif a:key ==# ' '
    call popup_close(s:rlp_win, {'open_anchor': 1})
    return 1
  elseif a:key ==# 'l'
    call s:rlp_dive(s:rlp_sel)
    return 1
  elseif a:key ==# 'i'
    " クエリを残したまま入力へ戻る
    let s:rlp_input = 1
  elseif a:key ==# '/'
    " クエリを消して入力へ
    let s:rlp_input = 1
    let s:rlp_query = ''
    call s:rlp_refresh()
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
  elseif a:key ==# 'j'
    call s:rlp_step_sel(1)
  elseif a:key ==# 'k'
    call s:rlp_step_sel(-1)
  elseif a:key ==# 'g'
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
  elseif a:key ==# 'G'
    let s:rlp_sel = max([s:rlp_last_sel(), 0])
  elseif a:key ==# 'f'
    if s:rlp_pvwin >= 0 | call win_execute(s:rlp_pvwin, "normal! \<C-f>") | endif
    return 1
  elseif a:key ==# 'b'
    if s:rlp_pvwin >= 0 | call win_execute(s:rlp_pvwin, "normal! \<C-b>") | endif
    return 1
  elseif a:key ==# 'c'
    call s:rlp_op('child')  | return 1
  elseif a:key ==# 'p'
    call s:rlp_op('parent') | return 1
  elseif a:key ==# 'y'
    call s:rlp_op('yank')   | return 1
  elseif a:key ==# 'm'
    call s:rlp_op('mark')   | return 1
  elseif a:key ==# 'M'
    let s:rlp_marks = {}
  elseif a:key ==# 'a'
    call s:rlp_dive(s:rlp_sel)
    return 1
  elseif has_key(s:rlp_rowmap, a:key)
    if s:rlp_scope ==# 'global'
      " 検索結果ではラベルは「移動だけ」。7 番を見たいのに ↓ を 7 回は野暮なので
      " 1 打で飛び、プレビューで中身を見てから ⏎ 開く / l 潜る を選ぶ。
      let s:rlp_sel = s:rlp_rowmap[a:key]
    else
      " ローカルは相手が既に分かっているので1タップでそのまま潜る。
      " 潜ってもアンカー行 ◎ とプレビューに出続け ⌫ で即戻れる（＝非破壊）。
      call s:rlp_dive(s:rlp_rowmap[a:key])
      return 1
    endif
  else
    return 1
  endif
  call s:rlp_render()
  return 1
endfunction

" ⇥ … スコープを切り替える（候補が何かだけが変わる）
"   ローカル → グローバル（全ノートを空クエリ・入力状態で）
"   グローバル → ローカル（選択中のノートへ潜る＝そこが新しいアンカー）
function! s:rlp_switch_scope() abort
  if s:rlp_scope ==# 'local'
    if empty(s:rlp_cands) | call s:rlp_build_index() | endif
    let s:rlp_scope = 'global'
    let s:rlp_input = 1
    let s:rlp_query = ''
    let s:rlp_sel = 0
    let s:rlp_top = 0
    call s:rlp_refresh()
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
    call s:rlp_render()
    return
  endif
  if s:rlp_is_sel(s:rlp_sel)
    call s:rlp_dive(s:rlp_sel)
    return
  endif
  let s:rlp_scope = 'local'
  let s:rlp_input = 0
  let s:rlp_query = ''
  call s:rlp_refresh()
  let s:rlp_sel = max([s:rlp_first_sel(), 0])
  call s:rlp_render()
endfunction

" --- 確定後の処理 -----------------------------------------------------------

" アンカーノートへ関係付きリンクを足す。アンカーが別バッファなら一時的に切り替える。
function! s:rlp_link_apply(targets, below, ...) abort
  let l:anchor = s:rlp_path
  if empty(l:anchor) || !filereadable(l:anchor)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: アンカーが不正') | echohl NONE
    return
  endif
  if empty(a:targets)
    echo gnosis#i18n#tr('Gnosis: 対象なし')
    return
  endif
  let l:rel = (a:0 > 0 && a:1 !=# '') ? a:1 : s:v2_pick_relation()
  if empty(l:rel) | echo gnosis#i18n#tr('Gnosis: キャンセル') | return | endif
  let l:side = s:v2_relation_side(l:rel)
  let l:below = l:side >= 0 ? l:side : a:below

  let l:cur_buf = bufnr('%')
  let l:view = winsaveview()
  let l:same = fnamemodify(expand('%:p'), ':p') ==# fnamemodify(l:anchor, ':p')
  if !l:same
    execute 'silent keepalt hide edit ' . fnameescape(l:anchor)
  endif

  let l:dir = expand('%:p:h')
  let l:n = 0
  let l:save_ai = &autoindent | let l:save_si = &smartindent
  setlocal noautoindent nosmartindent
  for l:t in a:targets
    if fnamemodify(l:t, ':p') ==# fnamemodify(l:anchor, ':p') | continue | endif
    let l:title = s:get_title(l:t)
    if s:v2_insert_link(l:rel, s:make_link_from_dir(l:t, l:title, l:dir), l:below)
      let l:n += 1
    endif
  endfor
  let &autoindent = l:save_ai | let &smartindent = l:save_si
  if l:n > 0 | silent! write | endif

  if !l:same
    execute 'silent keepalt hide buffer ' . l:cur_buf
    call winrestview(l:view)
  endif
  let s:rlp_marks = {}
  echo printf(gnosis#i18n#tr('Gnosis: %s %s %s += %d 件'),
        \ fnamemodify(l:anchor, ':t'), l:rel, l:below ? gnosis#i18n#tr('↓そっちにとって') : gnosis#i18n#tr('↑こっちにとって'), l:n)
endfunction

function! s:rlp_open_path(path, ...) abort
  let l:it = a:0 > 0 ? a:1 : {}
  if empty(a:path) || (!filereadable(a:path) && !isdirectory(a:path))
    echo gnosis#i18n#tr('Gnosis: 開けない: ') . a:path
    return
  endif
  call gnosis#push_history()
  silent! execute 'hide edit ' . fnameescape(a:path)
  let l:frag = (!empty(l:it) && get(l:it, 'kind', '') ==# 'link')
        \ ? s:link_fragment(get(l:it, 'target', '')) : ''
  if !empty(l:frag)
    " 見出しアンカー付きリンク → その見出し行へ
    if !s:jump_to_fragment(l:frag)
      echohl WarningMsg | echo gnosis#i18n#tr('見出しが見つかりません: ') . l:frag | echohl None
    endif
  elseif !empty(l:it) && get(l:it, 'kind', '') ==# 'link'
        \ && (l:it.side ==# 'up' || l:it.side ==# 'down')
    let l:rp = s:find_reciprocal_link_pos(a:path, fnamemodify(s:rlp_path, ':t'))
    if get(l:rp, 0, 0) > 0
      call cursor(l:rp[0], l:rp[1])
      normal! zv
    endif
  endif
endfunction

function! s:rlp_done(winid, result) abort
  let s:rlp_win = -1
  if s:rlp_pvwin >= 0
    call popup_close(s:rlp_pvwin)
    let s:rlp_pvwin = -1
  endif
  if type(a:result) != v:t_dict | return | endif

  " y … リンク記法でヤンク
  if has_key(a:result, 'yank')
    let l:links = []
    for l:t in a:result.yank
      call add(l:links, s:make_link_from_dir(l:t, s:get_title(l:t), expand('%:p:h')))
    endfor
    if empty(l:links) | echo gnosis#i18n#tr('Gnosis: 対象なし') | return | endif
    let l:txt = join(l:links, "\n")
    let @" = l:txt
    call gnosis#clipboard_copy(l:txt)
    let s:rlp_marks = {}
    echo gnosis#i18n#tr('Gnosis: ヤンク ') . len(l:links) . gnosis#i18n#tr(' 件')
    return
  endif

  " c / p … アンカーへ関係付きリンクを追加
  if has_key(a:result, 'link')
    call s:rlp_link_apply(get(a:result, 'targets', []), get(a:result, 'below', 1))
    return
  endif

  " ␣ … アンカーノート自体を開く
  if has_key(a:result, 'open_anchor')
    if empty(s:rlp_path) || s:rlp_path ==# get(s:rlp_origin, 'path', '') | return | endif
    call s:rlp_open_path(s:rlp_path)
    return
  endif

  " ⏎ … 選択行を開く
  if !has_key(a:result, 'open') | return | endif
  let l:idx = a:result.open
  let l:it = s:rlp_is_sel(l:idx) ? s:rlp_items[l:idx] : {}
  if empty(l:it)
    if s:rlp_path !=# get(s:rlp_origin, 'path', '')
      call s:rlp_open_path(s:rlp_path)
    endif
    return
  endif
  if get(l:it, 'kind', '') ==# 'anchor'
    if s:rlp_path ==# get(s:rlp_origin, 'path', '') | return | endif
    call s:rlp_open_path(s:rlp_path)
    return
  endif
  call s:rlp_open_path(s:rlp_row_path(l:it), l:it)
endfunction

" --- 入口 -------------------------------------------------------------------

" <Space> … 文中 / こっちにとって / そっちにとって ＋ 全ノート検索のナビゲータ。
"   jk/ラベル 選択  l 潜る  h 戻る  ⏎ 開く  ␣ アンカーを開く  fb プレビュー
"   c/p 子/親に追加  y ヤンク  m マーク  a アンカー移動  i 絞込  ⇥ local⇄global
function! gnosis#relation_link_popup() abort
  call gnosis#note_navigator('local')
endfunction

" gs … 同じナビゲータを global スコープ（全ノート検索）で開く
function! gnosis#note_search() abort
  call gnosis#note_navigator('global')
endfunction

" a:scope … 'local'（今のノートのリンク） / 'global'（全ノート検索）
function! gnosis#note_navigator(scope) abort
  let l:origin_path = expand('%:p')
  let l:is_note = !empty(l:origin_path) && s:is_markdown_file(l:origin_path)
  let l:groups0 = l:is_note
        \ ? s:space_collect(getline(1, '$'), expand('%:p:h')) : {}
  if a:scope ==# 'local'
    if empty(get(l:groups0, 'body', [])) && empty(get(l:groups0, 'up', []))
          \ && empty(get(l:groups0, 'down', []))
      call gnosis#jump_relation_link(1)
      return
    endif
  endif

  let s:rlp_origin = {'bufnr': bufnr('%'), 'pos': getpos('.'), 'path': l:origin_path}
  let s:rlp_stack = []
  let s:rlp_body_cache = {}
  let s:rlp_origin_names_cache = 0
  let s:rlp_crumbs = [fnamemodify(l:origin_path, ':t:r')]
  let s:rlp_scope = 'local'
  let s:rlp_input = 0
  let s:rlp_query = ''
  let s:rlp_terms = []
  let s:rlp_cands = []
  let s:rlp_path = l:origin_path
  let s:rlp_base = expand('%:p:h')
  let s:rlp_groups = l:groups0
  let s:rlp_want_cursor_init = 1
  call s:rlp_refresh()

  let l:geo = s:rlp_geometry()
  let s:rlp_geo = l:geo
  let s:rlp_rows = l:geo.rows

  let s:rlp_win = popup_create([], {
        \ 'title': gnosis#i18n#tr(' ローカル '),
        \ 'line': l:geo.list_line, 'col': l:geo.list_col,
        \ 'minwidth': l:geo.list_w, 'maxwidth': l:geo.list_w,
        \ 'minheight': l:geo.h, 'maxheight': l:geo.h,
        \ 'zindex': 300,
        \ 'border': [], 'borderchars': ['─','│','─','│','╭','╮','╯','╰'],
        \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1],
        \ 'mapping': 0,
        \ 'filter': function('s:rlp_key'), 'callback': function('s:rlp_done'),
        \ })
  let s:rlp_pvwin = popup_create([], {
        \ 'title': gnosis#i18n#tr(' プレビュー '),
        \ 'line': l:geo.pv_line, 'col': l:geo.pv_col,
        \ 'minwidth': l:geo.pv_w, 'maxwidth': l:geo.pv_w,
        \ 'minheight': l:geo.h, 'maxheight': l:geo.h,
        \ 'zindex': 299,
        \ 'border': [], 'borderchars': ['─','│','─','│','╭','╮','╯','╰'],
        \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1],
        \ })
  call s:rlp_load(l:origin_path, expand('%:p:h'))
  if a:scope ==# 'global'
    " gs 相当。索引を読んで、打てる状態（入力）から始める
    if empty(s:rlp_cands) | call s:rlp_build_index() | endif
    let s:rlp_scope = 'global'
    let s:rlp_input = 1
    let s:rlp_query = ''
    let s:rlp_sel = 0
    let s:rlp_top = 0
    call s:rlp_refresh()
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
    call s:rlp_render()
  endif
endfunction

" ---------------------------------------------------------------------------
" リンクへのラベルジャンプ（ドキュメント順の通し番号、40 個で一周）
"   1-9,0    … その番号のリンクを直接開く（生の数字キー、0は10番目）
"   g1..g0   … 11〜20番目、z1..z0 … 21〜30番目、t1..t0 … 31〜40番目（2打、1→0順）
"   頭文字は「1打で完結しない」g・z・t だけ。p1/b1 等は paste・単語移動を壊すので廃止。
" 番号はファイル先頭のリンクを 1 として**ドキュメント順に連続**で振る。41 個目の
" リンクからはまた `1` に回り込む（ラベルは 40 個で一周）。だから巨大な index を
" スクロールすると、番号が 1-0 → g ゾーン → z ゾーン → t ゾーン → 1-0 … と進む。
" 同じラベルが複数あるときは、押すと**今の画面に見えている側**（画面先頭から下方向で
" 最初のもの。無ければ画面より上の最寄り）を開く。
" 実際に見えている番号・ラベルがリンクの手前に仮想テキストで表示されるので、
" 数えなくても押すキーが分かる（g:gnosis_link_hints=0 で無効化）。
" g/z は単発では完結しない生キー（次の1打を待つ）なので、数字を後ろに続けても
" 新たな干渉や体感速度の悪化は発生しない。2文字目が数字なので既存の
" z-コマンド（zn/zk/zp 等）・g-コマンド（gs/gc 等）との重複もない。
" ---------------------------------------------------------------------------

let s:hint_prop_type = 'gnosisLinkHint'
let s:hint_label_letters = 'gzt'

" 通し番号(1始まり)からラベル文字列を作る。1-9,0 はそのまま（0は10番目）、
" 以降は g+数字 → z+数字 → t+数字（g1 … g0, z1 … z0, t1 … t0、1→0順で 10個ずつ）。
" それ以上は空文字。生の 0 キーは vim 標準の「行頭へ移動」を上書きするが、
" 該当リンクが無ければ digit_key() 側で通常の 0 に素通しされる。
function! s:hint_label(idx) abort
  if a:idx <= 9 | return string(a:idx) | endif
  if a:idx == 10 | return '0' | endif
  let l:n = a:idx - 11
  let l:letter_i = l:n / 10
  let l:pos_in_group = l:n % 10
  let l:digit = (l:pos_in_group == 9) ? 0 : l:pos_in_group + 1
  if l:letter_i >= strlen(s:hint_label_letters) | return '' | endif
  return s:hint_label_letters[l:letter_i] . l:digit
endfunction

" 現在バッファの候補位置（ドキュメント順：本文 → Parent/Child。ラベルは 40 個で
" 一周するので、回り込みを正しくするには全リンクが要る。上限なし＝全件）。
" digit_key / ラベル表示の両方がこの並びを使う。
function! s:hint_positions() abort
  let l:max = 0
  let [l:up_m, l:dn_m] = s:v2_boundaries()
  if l:up_m > 0
    let l:pos = s:link_positions_in_range_limited(1, l:up_m - 1, l:max)
    if l:max == 0 || len(l:pos) < l:max
      let l:pos += s:link_positions_in_range_limited(
            \ l:up_m + 1, line('$'), l:max == 0 ? 0 : l:max - len(l:pos))
    endif
    return l:pos
  endif
  return s:link_positions_in_range_limited(1, line('$'), l:max)
endfunction

" ラベル→位置の対応表を作る。番号はドキュメント順で 40 個周期で回り込む
" （41 個目のリンクはまた `1`）。同じラベルが複数回出るときは位置のリストを持つ。
function! s:hint_build_map() abort
  let l:pos = s:hint_positions()
  let l:n = 10 + 10 * strlen(s:hint_label_letters)
  let l:map = {}
  for l:i in range(len(l:pos))
    let l:label = s:hint_label((l:i % l:n) + 1)
    if has_key(l:map, l:label)
      call add(l:map[l:label], l:pos[l:i])
    else
      let l:map[l:label] = [l:pos[l:i]]
    endif
  endfor
  return l:map
endfunction

" 同じラベルを持つリンクが複数あるとき、開く側を決める。
" 画面先頭（w0）以降で最初のもの。画面の下に無ければ画面より上の最寄り。
function! s:hint_pick(cands) abort
  let l:top = line('w0')
  for l:p in a:cands
    if l:p.lnum >= l:top | return l:p | endif
  endfor
  return a:cands[-1]
endfunction
function! s:hint_ensure_prop_type() abort
  if !has('textprop') | return 0 | endif
  " 黄色（Special）だと見づらいので、落ち着いた青地に白の太字にする
  highlight default GnosisLinkHint term=bold,reverse cterm=bold ctermfg=231 ctermbg=67 gui=bold guifg=#ffffff guibg=#5f87af
  if empty(prop_type_get(s:hint_prop_type))
    call prop_type_add(s:hint_prop_type, {'highlight': 'GnosisLinkHint'})
  endif
  return 1
endfunction

" ラベル位置へ移動してそのままリンクを開く（Enter を省く）。
function! s:hint_go(pos) abort
  normal! m'
  call cursor(a:pos.lnum, a:pos.col)
  normal! zv
  call gnosis#open_link_under_cursor()
endfunction

" 使わなくなった2文字ラベルの一時マッピングを外し、新しく必要な分を張る。
" 対象は10番目以降の文字+数字ラベルのみ（例: z3, c7）。頭文字は
" z/t/c/b/m/p/y に限定しており、このプラグインの既存2打コマンド
" （zc, ta, cu, bu, mp, pe, yn 等）と完全一致することはない
" （2文字目が数字 vs 既存は文字なので重複しない）。
function! s:hint_sync_full_maps(labels) abort
  let l:have = get(b:, 'gnosis_hint_full_labels', [])
  for l:label in l:have
    if index(a:labels, l:label) < 0
      silent! execute 'nunmap <buffer> ' . l:label
    endif
  endfor
  for l:label in a:labels
    if index(l:have, l:label) < 0
      execute printf('nnoremap <silent><buffer> %s <Cmd>call gnosis#hint_goto(%s)<CR>', l:label, string(l:label))
    endif
  endfor
  let b:gnosis_hint_full_labels = a:labels
endfunction

" リンク手前に、ラベル（1-9 / 文字+数字）を画面先頭起点で仮想テキスト表示する。
function! gnosis#refresh_link_hints() abort
  if !get(g:, 'gnosis_link_hints', 1) || !has('textprop') | return | endif
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki' | return | endif
  if get(b:, 'gnosis_hint_built_tick', -1) ==# b:changedtick
    return
  endif
  if !s:hint_ensure_prop_type() | return | endif
  call prop_remove({'type': s:hint_prop_type, 'all': v:true})
  let b:gnosis_hint_map = s:hint_build_map()
  let b:gnosis_hint_built_tick = b:changedtick
  if empty(b:gnosis_hint_map)
    call s:hint_sync_full_maps([])
    return
  endif
  let l:full_labels = []
  " 1〜0（1文字）と g1 等（2文字）が混ざるときは、1文字側に半角スペースを足して
  " リンク本文の開始位置を揃える（ラベルは最大2文字なので幅は最大2）。
  let l:width = 1
  for l:label in keys(b:gnosis_hint_map)
    let l:width = max([l:width, strdisplaywidth(l:label)])
  endfor
  for [l:label, l:cands] in items(b:gnosis_hint_map)
    " 表示はラベルごとに 1 回。同じラベルの複数位置は全部に出す（押したときに
    " 画面に見えている側が開くので、複数表示があっても矛盾しない）。
    for l:pos in l:cands
      let l:text = l:label . repeat(' ', l:width - strdisplaywidth(l:label))
      call prop_add(l:pos.lnum, l:pos.col, {'type': s:hint_prop_type, 'text': l:text})
    endfor
    if strchars(l:label) > 1 | call add(l:full_labels, l:label) | endif
  endfor
  call s:hint_sync_full_maps(l:full_labels)
endfunction

" 数字キー（生の 1-9,0）… ドキュメント順の通し番号（40 周期で回り込み）のうち、
" 今の画面に見えている側のリンクを直接開く。該当が無ければ通常のカウント/
" 行頭移動として送る。
" 起動直後など、まだラベルを計算していないバッファでは初回だけ計算し直す。
" （計算前は候補ゼロ＝素のカウント扱いになり、1打目が「効かない」ように
"  見えるのを防ぐ。ラベル更新は debounce されるが数字ジャンプは常に最新を見る。）
function! gnosis#digit_key(idx, key) abort
  if !has_key(b:, 'gnosis_hint_map')
    call gnosis#refresh_link_hints()
  endif
  let l:label = a:idx == 10 ? '0' : printf('%d', a:idx)
  let l:cands = get(get(b:, 'gnosis_hint_map', {}), l:label, [])
  if !empty(l:cands)
    call s:hint_go(s:hint_pick(l:cands))
    return
  endif
  call feedkeys((v:count > 0 ? v:count : '') . a:key, 'n')
endfunction

" 文字+数字（g1 等、11番目以降のラベル）… 対応する位置を開く。
function! gnosis#hint_goto(label) abort
  let l:cands = get(get(b:, 'gnosis_hint_map', {}), a:label, [])
  if !empty(l:cands)
    call s:hint_go(s:hint_pick(l:cands))
  endif
endfunction

function! gnosis#get_link_under_cursor() abort
  let l:line   = getline('.')
  let l:cursor = col('.') - 1
  let l:start  = 0
  while 1
    let l:m = matchstrpos(l:line, s:link_pat, l:start)
    if len(l:m) < 3 || l:m[1] < 0
      return {}
    endif
    if s:buf_in_code(line('.'), l:m[1])
      let l:start = l:m[2]
      continue
    endif
    if l:cursor >= l:m[1] && l:cursor < l:m[2]
      let l:parts = matchlist(l:m[0], '\v\[(%(\\.|[^\]\\])+)\]\(([^)]*)\)')
      return {
            \ 'raw':      l:m[0],
            \ 'text':     get(l:parts, 1, ''),
            \ 'target':   get(l:parts, 2, ''),
            \ 'startcol': l:m[1] + 1,
            \ 'endcol':   l:m[2]
            \ }
    endif
    " カーソルがリンクより後ろかチェック
    " [xxx](yyy) の形式で、リンク終端の直後にいる場合
    if l:cursor >= l:m[2]
      let l:after = strpart(l:line, l:m[2])
      " 直後がスペース2つ以上 + テキスト の形式
      if l:after =~# '^\s\{2,}\S'
        " 次のリンクが始まる前の範囲内にカーソルがあるか確認
        let l:next = matchstrpos(l:line, s:link_pat, l:m[2])
        let l:title_end = (len(l:next) >= 3 && l:next[1] >= 0) ? l:next[1] : len(l:line)
        if l:cursor < l:title_end
          let l:parts = matchlist(l:m[0], '\v\[(%(\\.|[^\]\\])+)\]\(([^)]*)\)')
          return {
                \ 'raw':      l:m[0],
                \ 'text':     get(l:parts, 1, ''),
                \ 'target':   get(l:parts, 2, ''),
                \ 'startcol': l:m[1] + 1,
                \ 'endcol':   l:title_end
                \ }
        endif
      endif
    endif
    let l:start = l:m[2]
  endwhile
endfunction

function! s:is_absolute_path(path) abort
  let l:path = trim(a:path)
  return l:path =~# '^/' || l:path =~# '^\\' || l:path =~# '^\a\+:' || l:path =~# '^\~[\\/]'
endfunction

function! s:expand_user_path(path) abort
  let l:path = trim(a:path)
  if l:path =~# '^\~[\\/]'
    return fnamemodify(s:expand_path(l:path), ':p')
  endif
  return l:path
endfunction

function! s:path_has_directory(target) abort
  return a:target =~# '[\\/]'
endfunction

function! s:markdown_relative_target(relpath) abort
  let l:rel = substitute(a:relpath, '\\', '/', 'g')
  if empty(l:rel)
    return l:rel
  endif
  " Links to files in child directories should be explicit Markdown relative
  " links from the current note directory, e.g. ./2026-03-26/260616161959.md.
  if l:rel !~# '^\.\.\?/' && l:rel =~# '/'
    return './' . l:rel
  endif
  return l:rel
endfunction

function! s:relpath_from_dir(path, base) abort
  let l:path = fnamemodify(a:path, ':p')
  let l:base = fnamemodify(a:base, ':p')
  let l:path_dir = fnamemodify(l:path, ':h:p')
  let l:path_dir_cmp = substitute(l:path_dir, '[\\/]\+$', '', '')
  let l:base_cmp = substitute(l:base, '[\\/]\+$', '', '')

  " Same-directory links must stay as plain filenames.  In particular, notes
  " created from index.md should get [Index](index.md), never [Index](/index.md).
  if l:path_dir_cmp ==# l:base_cmp
    return fnamemodify(l:path, ':t')
  endif

  let l:path_norm = substitute(l:path, '\\', '/', 'g')
  let l:base_norm = substitute(l:base, '\\', '/', 'g')
  let l:path_parts = split(l:path_norm, '/')
  let l:base_parts = split(l:base_norm, '/')

  while !empty(l:path_parts) && !empty(l:base_parts) && l:path_parts[0] ==# l:base_parts[0]
    call remove(l:path_parts, 0)
    call remove(l:base_parts, 0)
  endwhile

  let l:rel_parts = repeat(['..'], len(l:base_parts)) + l:path_parts
  if empty(l:rel_parts)
    return fnamemodify(l:path, ':t')
  endif
  let l:rel = join(l:rel_parts, '/')
  return empty(l:rel) ? fnamemodify(l:path, ':t') : s:markdown_relative_target(l:rel)
endfunction

function! s:ancestor_dirs_until_root(base) abort
  let l:dirs = []
  let l:root = s:get_pkm_root()
  let l:root = empty(l:root) ? '' : fnamemodify(l:root, ':p')
  let l:dir = fnamemodify(a:base, ':p')

  while !empty(l:dir)
    call add(l:dirs, l:dir)
    if !empty(l:root) && l:dir ==# l:root
      break
    endif
    let l:parent = fnamemodify(l:dir, ':h:p')
    if l:parent ==# l:dir
      break
    endif
    let l:dir = l:parent
  endwhile
  return l:dirs
endfunction

function! s:find_unique_file_near_current_tree(base, name) abort
  let l:root = s:get_pkm_root()
  let l:search_base = !empty(l:root) ? fnamemodify(l:root, ':p') : fnamemodify(a:base, ':p')
  let l:cache_key = fnamemodify(a:base, ':p') . '|' . l:search_base . '|' . a:name
  if has_key(s:filename_resolve_cache, l:cache_key)
    let l:cached = s:filename_resolve_cache[l:cache_key]
    return empty(l:cached) || filereadable(l:cached) ? l:cached : ''
  endif

  let l:files = []
  let l:seen = {}

  for l:dir in s:ancestor_dirs_until_root(a:base)
    let l:candidate = fnamemodify(l:dir . '/' . a:name, ':p')
    if filereadable(l:candidate) && !has_key(l:seen, l:candidate)
      let l:seen[l:candidate] = 1
      call add(l:files, l:candidate)
    endif
  endfor
  if len(l:files) == 1
    let s:filename_resolve_cache[l:cache_key] = l:files[0]
    return l:files[0]
  elseif len(l:files) > 1
    let s:filename_resolve_cache[l:cache_key] = ''
    return ''
  endif

  " 名前の [ ] * ? { } \ を glob の記号として解釈させない（[b-a] などは E944 で止まるため）
  let l:pat = '**/' . escape(a:name, '[]*?{}\')
  let l:found = []
  try
    let l:found = globpath(l:search_base, l:pat, 0, 1)
  catch
    let l:found = []
  endtry
  for l:m in l:found
    let l:path = fnamemodify(l:m, ':p')
    if has_key(l:seen, l:path)
      continue
    endif
    let l:seen[l:path] = 1
    if filereadable(l:path) && index(split(l:path, '[\\/]'), '.undo') < 0 && fnamemodify(l:path, ':t') ==# a:name
      call add(l:files, l:path)
    endif
  endfor

  let l:resolved = len(l:files) == 1 ? l:files[0] : ''
  let s:filename_resolve_cache[l:cache_key] = l:resolved
  return l:resolved
endfunction

function! s:resolve_existing_link_target(target, ...) abort
  let l:base = a:0 ? a:1 : expand('%:p:h')
  let l:target = s:expand_user_path(a:target)
  if empty(l:target) || l:target =~# '\v^\w+://'
    return ''
  endif
  " アンカー（#見出し）はファイル解決には使わない
  let l:target = matchstr(l:target, '^[^#]*')
  if empty(l:target)
    return ''
  endif
  if s:is_absolute_path(l:target)
    let l:absolute = fnamemodify(l:target, ':p')
    return filereadable(l:absolute) ? l:absolute : ''
  endif

  let l:direct = fnamemodify(l:base . '/' . l:target, ':p')
  if filereadable(l:direct)
    return l:direct
  endif

  if !s:path_has_directory(l:target)
    return s:find_unique_file_near_current_tree(l:base, l:target)
  endif

  " Directory-bearing links copied from another note are often relative to
  " the PKM root/current working directory (for example ./N_root.md or
  " folder/N_child.md).  If they do not exist relative to the destination
  " note, resolve them from the root so link insertion can rebase them to
  " ../... for notes inside subdirectories.
  let l:root = s:get_pkm_root()
  if !empty(l:root)
    let l:root_candidate = fnamemodify(l:root . '/' . l:target, ':p')
    if filereadable(l:root_candidate)
      return l:root_candidate
    endif
  endif

  let l:cwd_candidate = fnamemodify(getcwd() . '/' . l:target, ':p')
  if filereadable(l:cwd_candidate)
    return l:cwd_candidate
  endif

  return ''
endfunction

function! s:display_target_from_current_dir(target) abort
  let l:base = expand('%:p:h')
  let l:path = s:resolve_existing_link_target(a:target, l:base)
  if !empty(l:path)
    return s:relpath_from_dir(l:path, l:base)
  endif
  return substitute(s:expand_user_path(a:target), '\\', '/', 'g')
endfunction

function! gnosis#resolve_link(target, ...) abort
  let l:base = a:0 ? a:1 : expand('%:p:h')
  let l:existing = s:resolve_existing_link_target(a:target, l:base)
  if !empty(l:existing)
    return l:existing
  endif
  let l:target = s:expand_user_path(a:target)
  " アンカー（#見出し）はファイル解決には使わない
  let l:target = matchstr(l:target, '^[^#]*')
  if s:is_absolute_path(l:target)
    return fnamemodify(l:target, ':p')
  endif
  return fnamemodify(l:base . '/' . l:target, ':p')
endfunction

function! s:resolve_link_for_navigation(target, ...) abort
  let l:base = a:0 ? a:1 : expand('%:p:h')
  let l:target = s:expand_user_path(a:target)
  if empty(l:target) || l:target =~# '\v^\w+://'
    return ''
  endif
  " アンカー（#見出し）はファイル解決には使わない
  let l:target = matchstr(l:target, '^[^#]*')
  if empty(l:target)
    return ''
  endif
  if s:is_absolute_path(l:target)
    return fnamemodify(l:target, ':p')
  endif

  let l:direct = fnamemodify(l:base . '/' . l:target, ':p')
  if filereadable(l:direct) || isdirectory(l:direct)
    return l:direct
  endif

  if s:path_has_directory(l:target)
    let l:root = s:get_pkm_root()
    if !empty(l:root)
      let l:root_candidate = fnamemodify(l:root . '/' . l:target, ':p')
      if filereadable(l:root_candidate) || isdirectory(l:root_candidate)
        return l:root_candidate
      endif
    endif

    let l:cwd_candidate = fnamemodify(getcwd() . '/' . l:target, ':p')
    if filereadable(l:cwd_candidate) || isdirectory(l:cwd_candidate)
      return l:cwd_candidate
    endif
  elseif get(g:, 'gnosis_global_bare_link_navigation', 0)
    let l:global = s:find_unique_file_near_current_tree(l:base, l:target)
    if !empty(l:global)
      return l:global
    endif
  endif

  return l:direct
endfunction

" クリップボードを読む。Wayland では Vim の +clipboard が XWayland 側を見てしまい、
" PC（Wayland）でコピーした内容とずれることが多い（古い内容を返す）。そこで
" **外部コマンドを先に**試し（wl-paste 等＝PC の本物のクリップボード）、取れなければ
" Vim の + / * / 無名レジスタへ落とす。外部を先に見ることで、遅い + レジスタ読みも回避。
function! s:clipboard_text() abort
  let l:ext = s:clipboard_text_external()
  if !empty(l:ext)
    return l:ext
  endif
  for l:reg in ['+', '*']
    let l:cb = trim(getreg(l:reg))
    if !empty(l:cb)
      return l:cb
    endif
  endfor
  " 無名レジスタは空だと E353 になるので getreg で読む
  return trim(getreg('"'))
endfunction

" 外部コマンド経由でクリップボードを読む（Wayland → KDE → X11 の順）。
" 一度成功したコマンドをセッション中キャッシュし、次回はそれだけを試す（\p を速く）。
function! s:clipboard_text_external() abort
  if exists('s:clip_cmd')
    let l:out = s:run_clip_cmd(s:clip_cmd)
    if !empty(l:out)
      return l:out
    endif
  endif
  if has('win32') || has('win32unix')
    return has('clipboard') ? getreg('+') : ''
  endif
  let l:cmds = [
        \ ['pbpaste'],
        \ ['wl-paste', '--no-newline'],
        \ ['wl-paste', '--primary', '--no-newline'],
        \ ['qdbus6', 'org.kde.klipper', '/klipper', 'getClipboard'],
        \ ['qclip', '-o'],
        \ ['xclip', '-selection', 'clipboard', '-o'],
        \ ['xsel', '-b'],
        \ ]
  for l:cmd in l:cmds
    if !executable(l:cmd[0])
      continue
    endif
    let l:out = s:run_clip_cmd(l:cmd)
    if !empty(l:out)
      let s:clip_cmd = l:cmd
      return l:out
    endif
  endfor
  return ''
endfunction

function! s:run_clip_cmd(cmd) abort
  try
    return trim(system('timeout 1 ' . join(map(copy(a:cmd), 'shellescape(v:val)'), ' ')))
  catch
    return ''
  endtry
endfunction

" システムクリップボードへ書き込む。Wayland では wl-copy（ネイティブ）へ非同期で
" 流し、Vim の +/* レジスタ（XWayland 側）は使わない。大きなヤンクを XWayland の
" クリップボードブリッジに通すと KWin / Klipper ごと固まることがあるため。
" wl-copy が使えない環境だけ + レジスタへフォールバックする（@" は呼び側で設定）。
function! gnosis#clipboard_copy(text) abort
  if !has('nvim') && !empty($WAYLAND_DISPLAY) && executable('wl-copy')
        \ && has('job') && has('channel')
    try
      let s:clip_job = job_start(['wl-copy'], {
            \ 'in_io': 'pipe', 'out_io': 'null', 'err_io': 'null',
            \ 'stoponexit': '',
            \ })
      call ch_sendraw(s:clip_job, a:text)
      call ch_close(s:clip_job)
    catch
    endtry
    return
  endif
  if (has('mac') || has('macunix')) && executable('pbcopy') && has('job')
    try
      let s:clip_job = job_start(['pbcopy'], {'in_io': 'pipe', 'out_io': 'null', 'err_io': 'null', 'stoponexit': ''})
      call ch_sendraw(s:clip_job, a:text)
      call ch_close(s:clip_job)
      return
    catch
    endtry
  endif
  if has('clipboard')
    let @+ = a:text
  endif
endfunction

" システムクリップボードを読む（wl-paste 優先）。挿入モードの <C-v> などで使う。
function! gnosis#clipboard_paste() abort
  return s:clipboard_text()
endfunction

function! s:extract_markdown_link(raw) abort
  let l:raw = trim(a:raw)
  if empty(l:raw)
    return {'text': '', 'target': ''}
  endif
  let l:m = matchlist(l:raw, '^\[\([^]]*\)\](\([^)]\+\))')
  if !empty(l:m)
    return {'text': l:m[1], 'target': trim(l:m[2])}
  endif
  return {'text': '', 'target': ''}
endfunction

" file:///path や file://localhost/path のような file URI をローカルパスへ直す。
" Dolphin などでファイルをコピーすると text/uri-list の file:// URI が
" クリップボードに載るため、そのままだとリンク先として解決できない。
" file:// 以外（http 等）やホスト付き URI はそのまま返す。
function! s:percent_decode(text) abort
  " 連続する %XX 列をバイト列として一括で解釈する（UTF-8 のマルチバイトを文字化けさせない）
  return substitute(a:text, '\%(%\x\x\)\+', '\=s:decode_pct_run(submatch(0))', 'g')
endfunction

function! s:decode_pct_run(run) abort
  let l:esc = substitute(substitute(a:run, '%', '', 'g'), '\x\x', '\\x&', 'g')
  return eval('"' . l:esc . '"')
endfunction

function! s:file_uri_to_path(target) abort
  let l:m = matchlist(a:target, '^file://\([^/]*\)\(/.*\)$')
  if empty(l:m)
    return a:target
  endif
  if !empty(l:m[1]) && l:m[1] !=# 'localhost'
    return a:target
  endif
  return s:percent_decode(l:m[2])
endfunction

function! s:extract_target(raw) abort
  let l:raw = trim(a:raw)
  if empty(l:raw)
    return ''
  endif
  let l:link = s:extract_markdown_link(l:raw)
  if !empty(l:link.target)
    return s:file_uri_to_path(l:link.target)
  endif
  return s:file_uri_to_path(l:raw)
endfunction

function! s:extract_targets_from_clipboard(text) abort
  let l:targets = []
  let l:seen = {}

  if empty(trim(a:text))
    return l:targets
  endif

  " まず Markdown リンクを全文から全部拾う
  let l:start = 0
  while 1
    let l:m = matchstrpos(a:text, '\v\[%(\\.|[^\]\\])+\]\(([^)]*)\)', l:start)
    if empty(l:m) || l:m[1] < 0
      break
    endif
    let l:raw = get(l:m, 0, '')
    let l:target = s:extract_target(l:raw)
    if !empty(l:target) && !has_key(l:seen, l:target)
      let l:seen[l:target] = 1
      call add(l:targets, l:target)
    endif
    let l:start = l:m[2]
  endwhile

  " Markdown リンクが無ければ、各行をそのままターゲットとして扱う
  if empty(l:targets)
    for l:raw in split(a:text, "\n")
      let l:target = s:extract_target(l:raw)
      if !empty(l:target) && !has_key(l:seen, l:target)
        let l:seen[l:target] = 1
        call add(l:targets, l:target)
      endif
    endfor
  endif

  return l:targets
endfunction

function! s:is_filename_target(target) abort
  let l:t = trim(a:target)
  if empty(l:t)
    return 0
  endif
  if s:is_url_target(l:t)
    return 0
  endif
  return l:t =~# '\v(^|[\\/])[^\\/]+\.[A-Za-z0-9_-]+$'
endfunction

function! s:is_url_target(target) abort
  return trim(a:target) =~# '\v^\w+://'
endfunction

function! s:existing_title_for_target(target) abort
  let l:path = gnosis#resolve_link(a:target)
  if filereadable(l:path) && s:is_markdown_target(a:target)
    return s:get_title(l:path)
  endif
  return ''
endfunction

function! s:link_from_target(target) abort
  let l:target = s:file_uri_to_path(trim(a:target))
  if empty(l:target)
    return ''
  endif
  let l:display_target = s:display_target_from_current_dir(l:target)
  let l:name = fnamemodify(l:display_target, ':t')
  " md は YAML/H1 タイトルをリンク文字列にする。非md は拡張子つきのファイル名（.html など）
  let l:title = s:existing_title_for_target(l:display_target)
  if s:is_markdown_target(l:display_target)
    let l:text = empty(l:title) ? fnamemodify(l:name, ':r') : l:title
  else
    let l:text = l:name
  endif
  return '[' . l:text . '](' . l:display_target . ')'
endfunction

function! s:link_from_clipboard_raw(raw) abort
  let l:link = s:extract_markdown_link(a:raw)
  if !empty(l:link.target)
    let l:display_target = s:display_target_from_current_dir(s:file_uri_to_path(l:link.target))
    return '[' . l:link.text . '](' . l:display_target . ')'
  endif
  return s:link_from_target(a:raw)
endfunction

function! s:retitle_markdown_links_in_line(line, base_dir) abort
  let l:line = a:line
  let l:new_line = ''
  let l:last = 0
  let l:start = 0
  let l:changed = 0
  while 1
    let l:m = matchstrpos(l:line, '\v\[%(\\.|[^\]\\])*\]\(([^)]*)\)', l:start)
    if empty(l:m) || l:m[1] < 0
      break
    endif
    let l:raw = l:m[0]
    let l:parts = matchlist(l:raw, '\v\[(%(\\.|[^\]\\])*)\]\(([^)]*)\)')
    let l:target = get(l:parts, 2, '')
    let l:new_link = l:raw
    if !empty(l:target) && s:is_markdown_target(l:target)
      let l:path = gnosis#resolve_link(l:target, a:base_dir)
      let l:title = s:get_yaml_title(l:path)
      if !empty(l:title)
        let l:new_link = '[' . l:title . '](' . l:target . ')'
        if l:new_link !=# l:raw
          let l:changed = 1
        endif
      endif
    endif
    let l:new_line .= strpart(l:line, l:last, l:m[1] - l:last) . l:new_link
    let l:last = l:m[2]
    let l:start = l:m[2]
  endwhile
  let l:new_line .= strpart(l:line, l:last)
  return {'line': l:changed ? l:new_line : a:line, 'changed': l:changed}
endfunction

function! gnosis#rename_down_links_to_yaml_title(line1, line2, range) range abort
  let l:base = expand('%:p:h')
  if a:range > 0
    let l:start = a:line1
    let l:end = a:line2
  else
    let l:down = s:find_section_line('down')
    if l:down <= 0
      echo 'Error: child section not found'
      return
    endif
    let l:start = l:down + 1
    let l:end = s:down_end_line()
  endif

  if l:start > l:end
    echo 'No links to update'
    return
  endif

  let l:changed = 0
  let l:in_fence = 0
  for l:lnum in range(l:start, l:end)
    let l:line = getline(l:lnum)
    if trim(l:line) =~# '^```'
      let l:in_fence = !l:in_fence
      continue
    endif
    if l:in_fence
      continue
    endif
    let l:result = s:retitle_markdown_links_in_line(l:line, l:base)
    if l:result.changed
      call setline(l:lnum, l:result.line)
      let l:changed += 1
    endif
  endfor

  if l:changed
    silent write
  endif
  echo 'YAML title link text updated ' . l:changed . ' line(s)'
endfunction

function! s:link_already_present_in_branch(link) abort
  let l:down = s:find_section_line('down')
  if l:down <= 0
    let l:down = s:find_section_line('branch')
  endif
  if l:down <= 0
    return 0
  endif
  let l:end = s:down_end_line()
  for l:i in range(l:down + 1, l:end)
    if getline(l:i) ==# a:link
      return 1
    endif
  endfor
  return 0
endfunction

" ---------------------------------------------------------------------------
" History (Back key)
" ---------------------------------------------------------------------------

" --- 履歴 / 直前ノート / ハブ / 最近訪問 --------------------------------------

function! s:hist_state_file(name) abort
  return s:state_dir() . s:sep() . a:name
endfunction

function! s:load_json_state(name, default) abort
  let l:f = s:hist_state_file(a:name)
  if !filereadable(l:f) | return a:default | endif
  try
    return json_decode(join(readfile(l:f), ''))
  catch
    return a:default
  endtry
endfunction

function! s:save_json_state(name, value) abort
  let l:dir = s:state_dir()
  if !isdirectory(l:dir) | call mkdir(l:dir, 'p') | endif
  try
    call s:syn_writefile([json_encode(a:value)], s:hist_state_file(a:name))
  catch
  endtry
endfunction

" 最近訪問（path -> epoch）。global スコープの無クエリ時の並び順に使う。
function! gnosis#recent_map() abort
  if !exists('g:gnosis_recent')
    let g:gnosis_recent = s:load_json_state('recent.json', {})
  endif
  return g:gnosis_recent
endfunction

function! s:recent_touch(path) abort
  if empty(a:path) || !s:is_markdown_file(a:path) | return | endif
  let l:m = gnosis#recent_map()
  let l:m[fnamemodify(a:path, ':p')] = localtime()
  " 上限を超えたら古いものから捨てる
  let l:cap = get(g:, 'gnosis_recent_max', 500)
  if len(l:m) > l:cap
    let l:pairs = sort(items(l:m), {a, b -> a[1] - b[1]})
    for l:i in range(len(l:pairs) - l:cap)
      call remove(l:m, l:pairs[l:i][0])
    endfor
  endif
  let g:gnosis_recent = l:m
  call s:save_json_state('recent.json', l:m)
endfunction

" ハブ（'1'..'9' -> path）は Index（PKM ルート）ごとに保存する。
"   hubs.json の形: { <root>: { "1": path, ... }, ... }
"   - Index を切り替えたら別のハブ表になる（\H / \1..\9 / \0 が Index ごと）。
"   - 旧形式（フラットな { "1": path }）は、初回に現在のルート配下へ移行する。
function! s:hub_root_key() abort
  let l:root = s:get_pkm_root()
  if empty(l:root)
    let l:root = expand('%:p:h')
  endif
  return fnamemodify(l:root, ':p')
endfunction

function! s:hub_is_nested(d) abort
  for [l:k, l:v] in items(a:d)
    if type(l:v) == v:t_dict
      return 1
    endif
  endfor
  return 0
endfunction

function! s:hub_store() abort
  if !exists('g:gnosis_hubs_store')
    let l:data = s:load_json_state('hubs.json', {})
    " 旧形式（値がパス文字列）は現在のルートのハブとして引き継ぐ
    if !empty(l:data) && !s:hub_is_nested(l:data)
      let l:old = l:data
      let l:data = {}
      let l:key = s:hub_root_key()
      if !empty(l:key)
        let l:data[l:key] = l:old
      endif
    endif
    let g:gnosis_hubs_store = l:data
  endif
  return g:gnosis_hubs_store
endfunction

function! gnosis#hub_map() abort
  let l:store = s:hub_store()
  let l:key = s:hub_root_key()
  if !has_key(l:store, l:key)
    let l:store[l:key] = {}
  endif
  return l:store[l:key]
endfunction

" 引数が数値でも文字列でも '1'..'9' の文字列に揃える（string() は引用符を付ける）
function! s:hub_key(v) abort
  return type(a:v) == v:t_number ? printf('%d', a:v) : trim(a:v)
endfunction

" ハブは「リンクを並べた編集可能な Markdown ファイル」で持つ（root ごと）。
"   \H       … 今のノートをリンク 1 行として末尾に足す
"   \h / \0  … ハブ画面を開く（普通のリンクなので 1-9/0 でそのまま移動できる）
"   \1..\9   … ファイルの N 番目のリンクへ直行
" 旧 hubs.json があれば初回にこのファイルへ移行する（json はそのまま残す）。
function! s:hub_dir() abort
  return s:state_dir() . s:sep() . 'hubs'
endfunction

function! s:hub_file() abort
  let l:dir = s:hub_dir()
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  return l:dir . s:sep() . sha256(s:hub_root_key())[0:15] . '.md'
endfunction

function! s:hub_migrate() abort
  let l:file = s:hub_file()
  if filereadable(l:file)
    return l:file
  endif
  let l:lines = []
  let l:m = gnosis#hub_map()
  for l:n in map(range(1, 9), 'string(v:val)')
    let l:p = get(l:m, l:n, '')
    if !empty(l:p) && filereadable(l:p)
      call add(l:lines, '[' . s:get_title(l:p) . '](' . fnamemodify(l:p, ':p') . ')')
    endif
  endfor
  call s:syn_writefile(l:lines, l:file)
  return l:file
endfunction

" ハブファイルのリンクを上から順に解決して返す（\1..\9 の並び）。
function! s:hub_link_paths() abort
  let l:file = s:hub_migrate()
  let l:out = []
  for l:ln in readfile(l:file)
    let l:m = matchlist(l:ln, '\v\[(%(\\.|[^\]\\])*)\]\(([^)]+)\)')
    if !empty(l:m)
      call add(l:out, gnosis#resolve_link(l:m[2]))
    endif
  endfor
  return l:out
endfunction

" \h / \0 … ハブ画面（編集可能な Markdown）を開く。
" 起動直後の最初の \h が表示されない不具合のため、:edit は open_index と同じ
" timer 経路で行う（map 内の silent! edit + redraw では再描画が保留される）。
function! gnosis#hub_open() abort
  let l:file = s:hub_migrate()
  call gnosis#push_history()
  call timer_start(0, function('s:timer_hub_edit_cb', [l:file]))
  call timer_start(50, function('s:timer_redraw_cb'))
endfunction

function! gnosis#hub_set(...) abort
  let l:file = expand('%:p')
  if empty(l:file) || !s:is_markdown_file(l:file)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: ノート上で実行して') | echohl NONE | return
  endif
  let l:hub = s:hub_migrate()
  let l:link = '[' . gnosis#current_title() . '](' . fnamemodify(l:file, ':p') . ')'
  let l:lines = readfile(l:hub)
  if index(l:lines, l:link) >= 0
    echo gnosis#i18n#tr('Gnosis: ハブ登録済み')
    return
  endif
  call add(l:lines, l:link)
  call s:syn_writefile(l:lines, l:hub)
  echo printf(gnosis#i18n#tr('Gnosis: ハブに追加（%d 件）'), len(l:lines))
endfunction

function! gnosis#hub_jump(n) abort
  let l:paths = s:hub_link_paths()
  let l:idx = s:hub_key(a:n) - 1
  let l:p = get(l:paths, l:idx, '')
  if empty(l:p) || !filereadable(l:p)
    echo printf(gnosis#i18n#tr('Gnosis: ハブ %s は未登録（\H で登録）'), a:n)
    return
  endif
  if fnamemodify(expand('%:p'), ':p') ==# fnamemodify(l:p, ':p') | return | endif
  call gnosis#push_history()
  silent! execute 'hide edit ' . fnameescape(l:p)
endfunction

" \0 … \h と同じ（ハブ画面を開く）。名前は互換のため残す。
function! gnosis#hub_list() abort
  call gnosis#hub_open()
endfunction

" ---------------------------------------------------------------------------
" ゴミ箱（trash）
"   削除は <root>/.trash/ へ「移動」するソフト削除。.trash はドット始まりなので
"   検索（note_search.py）も同期（note_format_v2.py）も一覧に出さない。
"   ファイル名はアプリと同じ <日時>_<名前>（衝突時は <日時>_<n>_<名前>）。
"   \tr / :GnosisTrashList … ゴミ箱を fzf で覗く（プレビュー付き）→ ⏎=開く / ^r=復元 / ^e=空
"   \tD / :GnosisTrash      … 今のノートをゴミ箱へ
"   \tE / :GnosisTrashEmpty … ゴミ箱を全部空にする（完全削除・確認あり）
" ---------------------------------------------------------------------------
function! s:trash_dir() abort
  let l:root = s:get_pkm_root()
  if empty(l:root)
    let l:root = expand('%:p:h')
  endif
  return fnamemodify(l:root, ':p') . '.trash'
endfunction

" ゴミ箱の .md を新しい順に返す。
function! s:trash_entries() abort
  let l:dir = s:trash_dir()
  if !isdirectory(l:dir)
    return []
  endif
  let l:files = globpath(l:dir, '*.md', 0, 1)
  return sort(l:files, {a, b -> getftime(b) - getftime(a)})
endfunction

function! s:trash_dest(dir, base) abort
  " アプリ (fsapi.cjs / vault.js) と同じ 14 桁の <日時>_<名前>（衝突時は <日時>_<n>_<名前>）
  let l:ts = strftime('%Y%m%d%H%M%S')
  let l:dest = a:dir . s:sep() . l:ts . '_' . a:base
  let l:i = 1
  while filereadable(l:dest)
    let l:dest = a:dir . s:sep() . l:ts . '_' . l:i . '_' . a:base
    let l:i += 1
  endwhile
  return l:dest
endfunction

" 今のノートをゴミ箱へ移す（ソフト削除）。
function! gnosis#trash_current() abort
  let l:file = expand('%:p')
  if empty(l:file) || !filereadable(l:file) || !s:is_markdown_file(l:file)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: ノートを開いて実行して') | echohl NONE | return
  endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || !s:is_root_note_path(l:file)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: PKM のノートではありません') | echohl NONE | return
  endif
  if fnamemodify(l:file, ':t') ==# 'index.md'
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: Index はゴミ箱へ移せません') | echohl NONE | return
  endif
  let l:dir = s:trash_dir()
  if !isdirectory(l:dir) | call mkdir(l:dir, 'p') | endif
  let l:dest = s:trash_dest(l:dir, fnamemodify(l:file, ':t'))
  " 未保存の編集もゴミ箱に入るように、rename の前に書き出す
  call gnosis#save_current_note()
  call rename(l:file, l:dest)
  " 消えたノートへのリンク行を掃除するため全体を同期（バッファを閉じる前に）
  if !empty(l:root) | call s:run_sync([g:gnosis_python, 'update', l:root]) | endif
  " 元ファイルが消えたので、このバッファは閉じる（履歴を残して戻れるように）
  call gnosis#push_history()
  execute 'bwipeout! ' . bufnr('%')
  echo gnosis#i18n#tr('ゴミ箱へ移動: ') . fnamemodify(l:dest, ':t')
endfunction

" ゴミ箱のファイルを vault 直下へ戻す。戻した絶対パスを返す（失敗時は空）。
" フォルゲゼッテル/トピックノート（title と同名の画像を参照するノート）を戻す
" ときは同名のスキャン画像も一緒に戻す（2026-10-09）。
function! s:trash_restore(path) abort
  let l:root = s:get_pkm_root()
  if empty(l:root) | return '' | endif
  let l:name = fnamemodify(a:path, ':t')
  " <日時>_ / <日時>_<n>_ の接頭辞を外す
  let l:orig = substitute(l:name, '^\d\+_\(\d\+_\)\?', '', '')
  if empty(l:orig) | let l:orig = l:name | endif
  let l:dest = fnamemodify(l:root, ':p') . l:orig
  if filereadable(l:dest)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 復元先が既に存在します: ') . l:orig | echohl NONE
    return ''
  endif
  " 対応する画像がゴミ箱にあれば一緒に戻す
  call rename(a:path, l:dest)
  call s:restore_trash_image(a:path, l:root, l:orig)
  if !empty(l:root) | call s:run_sync([g:gnosis_python, 'update', l:root]) | endif
  return l:dest
endfunction

" ゴミ箱内の、復元するノート（元名 a:orig）と同名 stem の画像パスを返す（無ければ ''）
" ゴミ箱画像名は sync 側の退避名: `YYYYMMDD-HHMMSS(-n)_<元名>`
function! s:find_trash_image(trash_dir, orig) abort
  let l:stem = fnamemodify(a:orig, ':t:r')
  for l:cand in split(glob(fnamemodify(a:trash_dir, ':p') . '*'), "\n")
    let l:cname = fnamemodify(l:cand, ':t')
    if l:cname =~# '\.\%(jpg\|jpeg\|png\|tif\|tiff\|bmp\|webp\|avif\|gif\)$'
          \ && substitute(l:cname, '^\d\{8}-\d\{6}\%(-\d\+\)\?_', '', '') =~# '^' . escape(l:stem, '\\.*$^~[]') . '\.'
      return l:cand
    endif
  endfor
  return ''
endfunction

" ゴミ箱にある画像を vault へ戻す（同名が既にあれば触らない）
function! s:restore_trash_image(trash_path, root, orig) abort
  let l:trash_dir = fnamemodify(a:trash_path, ':h')
  let l:img = s:find_trash_image(l:trash_dir, a:orig)
  if empty(l:img) | return | endif
  let l:iname = fnamemodify(l:img, ':t')
  let l:iorig = substitute(l:iname, '^\d\{8}-\d\{6}\%(-\d\+\)\?_', '', '')
  let l:idel = fnamemodify(l:root, ':p') . l:iorig
  if !empty(l:iorig) && !filereadable(l:idel)
    call rename(l:img, l:idel)
  endif
endfunction

" ゴミ箱の fzf 確定処理。先頭は押したキー（--expect）、次が選択行（パス）。
"   ⏎（キー空）… 選択したゴミ箱ノートを開くだけ（復元しない）
"   ^r         … 選択したノートを vault 直下へ復元して開く
"   ^e         … ゴミ箱を全部空にする（確認あり）
function! s:trash_sink(lines) abort
  if len(a:lines) < 2 | return | endif
  let l:key = a:lines[0]
  let l:parts = split(a:lines[1], "\t", 1)
  let l:path = get(l:parts, 0, '')
  if empty(l:path) || !filereadable(l:path) | return | endif
  if l:key ==# 'ctrl-e'
    call gnosis#trash_empty()
    return
  endif
  if l:key ==# 'ctrl-r'
    let l:restored = s:trash_restore(l:path)
    if empty(l:restored) | return | endif
    call gnosis#push_history()
    silent! execute 'edit ' . fnameescape(l:restored)
    echo gnosis#i18n#tr('復元しました: ') . fnamemodify(l:restored, ':t')
    return
  endif
  " ⏎（または他のキー）… 中身を開くだけ。復元は ^r。
  call gnosis#push_history()
  silent! execute 'edit ' . fnameescape(l:path)
endfunction

" \tr … ゴミ箱の中身を fzf で覗く（⏎=開く / ^r=復元 / ^e=空にする）。
" fzf が無ければ quickfix。
function! gnosis#trash_list() abort
  let l:entries = s:trash_entries()
  if empty(l:entries)
    echo gnosis#i18n#tr('Gnosis: ゴミ箱は空です')
    return
  endif
  if !exists('*fzf#run')
    call setqflist(map(copy(l:entries),
          \ {_, p -> {'filename': p, 'text': fnamemodify(p, ':t')}}))
    copen
    return
  endif
  let l:source = map(copy(l:entries), {_, p -> p . "\t" . fnamemodify(p, ':t')})
  call fzf#run(fzf#wrap({
        \ 'source': l:source,
        \ 'sink*': function('s:trash_sink'),
        \ 'options': '--delimiter="\t" --with-nth=2 --accept-nth=1'
        \   . ' --expect=ctrl-r,ctrl-e'
        \   . ' --prompt=' . shellescape(gnosis#i18n#tr('ゴミ箱(⏎=開く ^r=復元 ^e=空)> '))
        \   . ' --preview "sed -n ''1,200p'' -- {1}"'
        \   . ' --preview-window=right:50%',
        \ }))
endfunction

" \tE / :GnosisTrashEmpty … ゴミ箱を全部空にする（完全削除・確認あり）。
function! gnosis#trash_empty() abort
  let l:dir = s:trash_dir()
  if !isdirectory(l:dir)
    echo gnosis#i18n#tr('Gnosis: ゴミ箱は空です')
    return
  endif
  let l:names = filter(readdir(l:dir), {_, n -> n !=# '.' && n !=# '..'})
  if empty(l:names)
    call delete(l:dir, 'd')
    echo gnosis#i18n#tr('Gnosis: ゴミ箱は空です')
    return
  endif
  let l:n = len(l:names)
  if confirm(printf(gnosis#i18n#tr('ゴミ箱の %d 件を完全に削除しますか？（元に戻せません）'), l:n),
        \ "&Yes\n&No", 2) != 1
    echo gnosis#i18n#tr('キャンセルしました')
    return
  endif
  for l:name in l:names
    call delete(l:dir . s:sep() . l:name)
  endfor
  call delete(l:dir, 'd')
  echo printf(gnosis#i18n#tr('ゴミ箱を空にしました（%d 件）'), l:n)
endfunction

" :!rm % などの後始末。今のノートのファイルが消えていたらバッファを閉じて同期する
" （rm ガードで .trash へ入っていれば \tr で戻せる）。
function! gnosis#after_shell_rm() abort
  let l:file = expand('%:p')
  if empty(l:file) || filereadable(l:file)
    return
  endif
  if !gnosis#is_vault_path(l:file)
    return
  endif
  let l:root = s:get_pkm_root()
  if !empty(l:root)
    call s:run_sync([g:gnosis_python, 'update', l:root])
  endif
  let l:buf = bufnr('%')
  call gnosis#push_history()
  if l:buf > 0 && bufexists(l:buf)
    silent! execute 'bwipeout! ' . l:buf
  endif
  echo gnosis#i18n#tr('ファイルが無くなったので閉じました（ゴミ箱なら \tr で復元）')
endfunction

function! gnosis#push_history() abort
  let l:file = gnosis#current_file()
  if empty(l:file) | return | endif
  call add(g:gnosis_history, {'file': l:file, 'pos': getpos('.')})
  if len(g:gnosis_history) > g:gnosis_history_max
    call remove(g:gnosis_history, 0)
  endif
  " 新しい移動が起きたら「進む」履歴は無効になる（ブラウザと同じ）
  let g:gnosis_forward = []
  " 直前ノート（⌥ トグル用）
  let g:gnosis_alt = l:file
  call s:recent_touch(l:file)
endfunction

" 直前に居たノートとの1キー往復。押すたび A→B→A→B。
function! gnosis#toggle_alternate() abort
  let l:cur = expand('%:p')
  let l:alt = get(g:, 'gnosis_alt', '')
  if empty(l:alt) && !empty(get(g:, 'gnosis_history', []))
    let l:alt = g:gnosis_history[-1].file
  endif
  if empty(l:alt) || !filereadable(l:alt)
    echo gnosis#i18n#tr('Gnosis: 直前のノートがない')
    return
  endif
  if fnamemodify(l:alt, ':p') ==# fnamemodify(l:cur, ':p')
    echo gnosis#i18n#tr('Gnosis: 直前のノートが自分自身')
    return
  endif
  call add(g:gnosis_history, {'file': l:cur, 'pos': getpos('.')})
  if len(g:gnosis_history) > g:gnosis_history_max
    call remove(g:gnosis_history, 0)
  endif
  let g:gnosis_forward = []
  let g:gnosis_alt = l:cur
  silent! execute 'hide edit ' . fnameescape(l:alt)
  call s:recent_touch(l:alt)
endfunction

" 履歴を前に進む（⌫ の対）。戻るが可逆になる。
function! gnosis#go_forward() abort
  if !exists('g:gnosis_forward') || empty(g:gnosis_forward)
    echo gnosis#i18n#tr('Gnosis: これ以上進めない')
    return
  endif
  let l:item = remove(g:gnosis_forward, -1)
  if get(g:, 'gnosis_sync_before_link_navigation', 0)
    call s:write_current_and_sync_now()
  elseif get(g:, 'gnosis_save_before_link_navigation', 0) && &modified && &buftype ==# '' && &modifiable
    silent update
  endif
  let l:cur = expand('%:p')
  if !empty(l:cur)
    call add(g:gnosis_history, {'file': l:cur, 'pos': getpos('.')})
    let g:gnosis_alt = l:cur
  endif
  silent! execute 'hide edit ' . fnameescape(l:item.file)
  call setpos('.', l:item.pos)
  call s:snap_cursor_to_link()
  call s:recent_touch(l:item.file)
endfunction

function! gnosis#open_link_under_cursor() abort
  let l:link = gnosis#get_link_under_cursor()
  if empty(l:link) || empty(l:link.target)
    echo 'No link under cursor'
    return
  endif
  let l:frag = s:link_fragment(l:link.target)
  let l:base = s:link_base(l:link.target)
  if empty(l:base)
    " 同一ファイル内アンカー（#見出し / expand の #note-N）
    if !empty(l:frag)
      call gnosis#push_history()
      if !s:jump_to_fragment(l:frag)
        echohl WarningMsg | echo gnosis#i18n#tr('見出しが見つかりません: ') . l:frag | echohl None
      endif
    endif
    return
  endif
  let l:path = s:resolve_link_for_navigation(l:base)
  if !filereadable(l:path) && !isdirectory(l:path)
    echo 'Link target not found: ' . l:path
    return
  endif
  let l:source_name = expand('%:t')
  let l:from_back = s:in_back_section(line('.'))
  let l:from_up = s:in_up_section(line('.'))
  if get(g:, 'gnosis_sync_before_link_navigation', 0)
    call s:write_current_and_sync_now()
  elseif get(g:, 'gnosis_save_before_link_navigation', 0) && &modified && &buftype ==# '' && &modifiable
    silent update
  endif
  call gnosis#push_history()
  silent! execute 'hide edit ' . fnameescape(l:path)
  if !empty(l:frag)
    " 見出しアンカー付きリンク → その見出し行へ
    if !s:jump_to_fragment(l:frag)
      echohl WarningMsg | echo gnosis#i18n#tr('見出しが見つかりません: ') . l:frag | echohl None
    endif
  elseif l:from_back || l:from_up
    let l:pos = s:find_reciprocal_link_pos(l:path, l:source_name)
    if get(l:pos, 0, 0) > 0
      call cursor(l:pos[0], l:pos[1])
    endif
  endif
endfunction


function! gnosis#go_back() abort
  if !exists('g:gnosis_history') || empty(g:gnosis_history)
    echo 'History is empty'
    return
  endif
  let l:item = remove(g:gnosis_history, -1)
  if get(g:, 'gnosis_sync_before_link_navigation', 0)
    call s:write_current_and_sync_now()
  elseif get(g:, 'gnosis_save_before_link_navigation', 0) && &modified && &buftype ==# '' && &modifiable
    silent update
  endif
  " 戻る前に「今いる場所」を進む履歴へ積む（戻りを可逆にする）
  let l:cur = expand('%:p')
  if !empty(l:cur)
    if !exists('g:gnosis_forward') | let g:gnosis_forward = [] | endif
    call add(g:gnosis_forward, {'file': l:cur, 'pos': getpos('.')})
    if len(g:gnosis_forward) > g:gnosis_history_max
      call remove(g:gnosis_forward, 0)
    endif
    let g:gnosis_alt = l:cur
  endif
  silent! execute 'hide edit ' . fnameescape(l:item.file)
  call setpos('.', l:item.pos)
  call s:snap_cursor_to_link()
  call s:recent_touch(l:item.file)
endfunction

" 戻った直後、カーソルがリンク上でなければ一番近いリンクへ寄せる。
" （同期で行がずれてもリンクを見失わないように）
function! s:snap_cursor_to_link() abort
  let l:lnum = line('.')
  " まず現在行にリンクがあればその先頭へ
  let l:m = matchstrpos(getline(l:lnum), s:link_pat)
  if l:m[1] >= 0
    call cursor(l:lnum, l:m[1] + 1)
    return
  endif
  " なければ前後 12 行を近い順に探索
  let l:last = line('$')
  for l:d in range(1, 12)
    for l:cand in [l:lnum + l:d, l:lnum - l:d]
      if l:cand < 1 || l:cand > l:last | continue | endif
      let l:mm = matchstrpos(getline(l:cand), s:link_pat)
      if l:mm[1] >= 0
        call cursor(l:cand, l:mm[1] + 1)
        return
      endif
    endfor
  endfor
endfunction

" ---------------------------------------------------------------------------
" Note template
" ---------------------------------------------------------------------------

function! gnosis#timestamp_filename() abort
  return strftime('%y%m%d%H%M%S')
endfunction

function! gnosis#timestamp_yaml() abort
  return strftime('%Y-%m-%d %H:%M:%S')
endfunction

function! s:k_note_template(title) abort
  if s:pkm_format() ==# 'v2'
    return [
          \ '---',
          \ 'time: ' . gnosis#timestamp_yaml(),
          \ 'title: ' . a:title,
          \ '---',
          \ '',
          \ '# ' . a:title,
          \ '',
          \ '' ]
  endif
  return [
        \ '---',
        \ 'time: ' . gnosis#timestamp_yaml(),
        \ 'filetype: K',
        \ 'title: ' . a:title,
        \ '---',
        \ '',
        \ '# ' . a:title,
        \ '',
        \ s:canonical_section_title('up'),
        \ s:canonical_section_title('down'),
        \ s:canonical_section_title('backlink'),
        \ '[Index](index.md)' ]
endfunction

function! s:k_note_template_with_down(title, down_lines) abort
  let l:content = s:k_note_template(a:title)
  let l:down_lines = s:trim_blank_edges(a:down_lines)
  let l:down_lines = filter(copy(l:down_lines), 'v:val !~# ''^\[Index\](index\.md)$''')
  if !empty(l:down_lines)
    let l:down_idx = s:find_section_index_in_lines(l:content, 'down')
    call extend(l:content, l:down_lines, l:down_idx + 1)
  endif
  return l:content
endfunction

function! s:new_note_insert_line() abort
  let l:ctx = search('^Context:', 'nw')
  if l:ctx > 0
    return min([l:ctx + 1, line('$')])
  endif
  let l:max = min([40, line('$')])
  for lnum in range(1, l:max)
    if getline(lnum) =~# '^#\s\+'
      " H1 の下に空行が複数ある場合は中央の空行に置く（本文入力開始位置）
      if lnum + 2 <= line('$')
            \ && getline(lnum + 1) =~# '^\s*$'
            \ && getline(lnum + 2) =~# '^\s*$'
        return lnum + 2
      endif
      if lnum + 1 <= line('$') && getline(lnum + 1) =~# '^\s*$'
        return lnum + 1
      endif
      return min([lnum + 1, line('$')])
    endif
  endfor
  return min([8, line('$')])
endfunction

function! s:body_top_insert_line() abort
  let l:max = min([120, line('$')])
  for lnum in range(1, l:max)
    if getline(lnum) =~# '^#\s\+'
      if lnum < line('$') && getline(lnum + 1) =~# '^\s*$'
        return lnum + 1
      endif
      return lnum
    endif
  endfor
  return 1
endfunction

" a:1 = v2 で 1 なら `attribute: グループ` を付ける（容器ノート）
function! gnosis#note_template(title, ...) abort
  let l:is_cat = (a:0 > 0 && s:pkm_format() ==# 'v2' && a:1)
  let l:header = [
        \ '---',
        \ 'time: ' . gnosis#timestamp_yaml(),
        \ 'title: ' . a:title,
        \ ]
  if l:is_cat
    call add(l:header, 'attribute: group')
  endif
  call add(l:header, '---')
  if s:pkm_format() ==# 'v2'
    " 普通のノート（zn）は本文の余白を 3 行（最初のカーソルは真ん中）、
    " グループノート（zk）は 1 行だけ空ける（グループは容器で本文を持たないため）。
    let l:gap = l:is_cat ? [''] : ['', '', '']
    return l:header + ['', '# ' . a:title] + l:gap
  endif
  return l:header + [
        \ '',
        \ '# ' . a:title,
        \ '',
        \ '',
        \ '',
        \ s:canonical_section_title('up'),
        \ s:canonical_section_title('down'),
        \ s:canonical_section_title('backlink'),
        \ '[Index](index.md)',
        \ ]
endfunction


" ---------------------------------------------------------------------------
" v2: 関係(relation)付きリンク追加（--- より上の「こっちにとって」側へ 1 行だけ挿入）
" 逆側は書かない。sync が相方ノートの下側に生成する。
" ---------------------------------------------------------------------------

" ピッカーで選べる関係。論点 / 見解 / 前提 は廃止。
" 既存ノートの 論点: / 見解: / 前提: はそのまま残り、sync の並び替えでも壊れない。
" グループ は選ばせない（相手が attribute: グループ なら sync が自動で付ける。
" 手動で選べると向きが固定で壊れる — zw 専用で s:v2_new_attr から直接渡す）。
let s:v2_relations = ['ノート', '補足', '資料', '関連']
" グループ / 小グループ ノードへリンクする時も、既定は変わらず「ノート」。
" （以前は「索引」という言い換えを出していたが、素の「ノート」で統一する）
let s:v2_relations_attr = ['ノート', '補足', '資料', '関連']

" 関係ごとの向きの制約。0 = こっちにとって側のみ / 1 = そっちにとって側のみ / -1 = 制約なし
function! s:v2_relation_side(rel) abort
  if a:rel ==# 'group' | return 0 | endif
  if a:rel ==# '関連'     | return 1 | endif
  return -1
endfunction

" 数字で 1 項目選ぶ共通ピッカー。末尾は「入力」= 自由入力。'' = キャンセル（Esc/q）。
function! s:v2_pick(label, items) abort
  let l:menu = []
  let l:i = 1
  for l:t in a:items
    call add(l:menu, l:i . ' ' . l:t)
    let l:i += 1
  endfor
  call add(l:menu, l:i . gnosis#i18n#tr(' 入力'))
  echo a:label . '  ' . join(l:menu, '   ') . gnosis#i18n#tr('    (Esc / q: キャンセル)')
  let l:c = getchar()
  redraw
  if type(l:c) == v:t_number && (l:c == 27 || l:c == 3)
    return ''
  endif
  let l:ch = type(l:c) == v:t_number ? nr2char(l:c) : l:c
  if l:ch ==? 'q' || l:ch !~# '^[0-9]$'
    return ''
  endif
  let l:n = str2nr(l:ch)
  if l:n >= 1 && l:n <= len(a:items)
    return a:items[l:n - 1]
  endif
  if l:n == len(a:items) + 1
    let l:v = ''
    try
      let l:v = trim(input(a:label . gnosis#i18n#tr('（空でキャンセル）: ')))
    catch /^Vim:Interrupt$/
      let l:v = ''
    endtry
    " input() の後すぐに別の echo/getchar を出すと「ENTERキーを押すか」の
    " 待ちが発生することがあるため、ここで一度画面をクリアしておく。
    redraw
    return l:v
  endif
  return ''
endfunction

" a:1 … 1 なら グループ / 小グループ ノードへリンクする時の変種
" （「ノート」の代わりに「索引」を出す）を使う。省略時は通常の一覧。
function! s:v2_pick_relation(...) abort
  let l:items = (a:0 > 0 && a:1) ? s:v2_relations_attr : s:v2_relations
  let l:r = s:v2_pick('relation', l:items)
  " 旧ピッカーの『なし』互換
  return l:r ==# 'なし' ? 'ノート' : l:r
endfunction

" 自由入力（ピッカーの選択肢に無い言葉）を選ぶ枠を「相手側にも書く」/
" 「相手側には書かない」の 2 つに分けたピッカー。固定の選択肢（ノート/補足/
" 資料/関連 等）を選んだ場合は {rel: ..., write: 1} を返す（write は使われない）。
" 自由入力なら選んだ枠に応じて write が 1/0 になる。キャンセルなら {} を返す。
"   a:1 … 1 なら グループ / 小グループ ノードへリンクする時の変種
"   a:2 … 1 なら「自分側にも書く/書かない」の文言（\ca/\at の逆モード用）。
"          省略時は「相手側」文言
function! s:v2_pick_relation2(...) abort
  let l:items = (a:0 > 0 && a:1) ? s:v2_relations_attr : s:v2_relations
  let l:self  = a:0 > 1 ? a:2 : 0
  let l:side  = l:self ? gnosis#i18n#tr('自分側') : gnosis#i18n#tr('相手側')

  let l:menu = []
  let l:i = 1
  for l:t in l:items
    call add(l:menu, l:i . ' ' . l:t)
    let l:i += 1
  endfor
  let l:write_idx = l:i
  call add(l:menu, l:i . gnosis#i18n#tr(' 入力(') . l:side . gnosis#i18n#tr('にも書く)'))
  let l:i += 1
  let l:nowrite_idx = l:i
  call add(l:menu, l:i . gnosis#i18n#tr(' 入力(') . l:side . gnosis#i18n#tr('には書かない)'))

  echo 'relation  ' . join(l:menu, '   ') . gnosis#i18n#tr('    (Esc / q: キャンセル)')
  let l:c = getchar()
  redraw
  if type(l:c) == v:t_number && (l:c == 27 || l:c == 3)
    return {}
  endif
  let l:ch = type(l:c) == v:t_number ? nr2char(l:c) : l:c
  if l:ch ==? 'q' || l:ch !~# '^[0-9]$'
    return {}
  endif
  let l:n = str2nr(l:ch)
  if l:n >= 1 && l:n <= len(l:items)
    return {'rel': l:items[l:n - 1], 'write': 1}
  endif
  if l:n == l:write_idx || l:n == l:nowrite_idx
    let l:v = ''
    try
      let l:v = trim(input(gnosis#i18n#tr('relation（空でキャンセル）: ')))
    catch /^Vim:Interrupt$/
      let l:v = ''
    endtry
    redraw
    if empty(l:v) | return {} | endif
    return {'rel': l:v, 'write': l:n == l:write_idx ? 1 : 0}
  endif
  return {}
endfunction

" sync がラベルをミラーせず自動生成する対象かどうか。`ノート`/`関連` に加え
" `索引` も対象外（グループ/小グループ 文脈での `ノート` の言い換えに過ぎず、
" 容器自身の側は sync 側の例外処理が実際に選んだ語をそのまま反映するため、
" ここで括弧付きの特別扱いをする必要が無い）。
function! s:v2_is_custom_relation(rel) abort
  return a:rel !=# 'ノート' && a:rel !=# '関連' && a:rel !=# '索引'
endfunction

" ピッカーの選択肢（自由入力ではなく数字で選べる既定の語）かどうか。
" これらは「相手にも書くか」を聞かず、常にもう一方の側へ書く
" （聞くのは自由入力で打った言葉だけ）。
function! s:v2_is_menu_relation(rel) abort
  return index(s:v2_relations, a:rel) >= 0 || index(s:v2_relations_attr, a:rel) >= 0
endfunction

" 「聞かれる側」に (ラベル) をその場で書くかどうかを聞く（自由入力はしない、
" 二択のみ）。a:self が真なら自分側（\ca/\at）、偽なら相手側（ca/at 等）が
" 聞かれる側。「いいえ」なら何も書かず sync の既定『ノート』に任せる。
function! s:v2_ask_write_same_label(rel, ...) abort
  let l:self = a:0 > 0 ? a:1 : 0
  let l:side = l:self ? gnosis#i18n#tr('自分側') : gnosis#i18n#tr('相手側')
  return s:v2_pick(l:side . gnosis#i18n#tr('にも「') . a:rel . gnosis#i18n#tr('」と書く？'), [gnosis#i18n#tr('はい'), gnosis#i18n#tr('いいえ（自動）')]) ==# gnosis#i18n#tr('はい')
endfunction

" 属性ノードは グループ だけ（小グループはグループに統合して廃止）。
" 旧名（カテゴリー / キーワード / 小グループ）はすべて グループ へ読み替える。
" 既存ノートの front matter はそのままでも、機能としては新しい規則で動く。
function! s:v2_normalize_attr(v) abort
  if a:v ==# 'グループ' | return 'group' | endif
  if a:v ==# 'カテゴリー' | return 'group' | endif
  if a:v ==# 'キーワード' | return 'group' | endif
  if a:v ==# '小グループ' | return 'group' | endif
  return a:v
endfunction

" 任意の .md ファイル（現ノートからの相対パス）の front matter attribute 値。無ければ空文字
" （旧名 カテゴリー / キーワード は グループ / 小グループ へ読み替えて返す）
function! s:v2_target_attr(tgt) abort
  return s:v2_path_attr(gnosis#resolve_link(a:tgt))
endfunction

" ファイルの front matter の attribute（正規化済み）。無ければ ''。
function! s:v2_path_attr(path) abort
  if !filereadable(a:path) | return '' | endif
  let l:lines = readfile(a:path, '', 30)
  if empty(l:lines) || l:lines[0] !~# '^---\s*$' | return '' | endif
  for l:i in range(1, len(l:lines) - 1)
    if l:lines[l:i] =~# '^---\s*$' | break | endif
    let l:m = matchlist(l:lines[l:i], '^\s*\%(attribute\|属性\)\s*:\s*\(\S.\{-}\)\s*$')
    if !empty(l:m) | return s:v2_normalize_attr(l:m[1]) | endif
  endfor
  return ''
endfunction

" front matter 終端行と、本文側で末尾寄りの --- 2 本（上側開始 / 下側開始）を返す。
" 2 本無ければ EOF に補って返す。本文中の --- は末尾 2 本にならないので無視される。
let s:v2_up_mark   = '### Context'
let s:v2_group_mark = '### Group'
let s:v2_related_mark = '### Related'
let s:v2_down_mark = '### BackLink'
" 旧見張り（新しい順: `##` なしの Parent/Child -> こっちにとって/そっちにとって
" -> している/されている）。まだ移行していないノートも読めるように残す。
" sync（note_format_v2.py）が保存時に新表記（## Parent / ## Child）へ書き換える。
let s:v2_up_marks_legacy   = ['### Parent', 'Parent', '<!-- こっちにとって -->', '<!-- している -->']
let s:v2_down_marks_legacy = ['Child', '<!-- そっちにとって -->', '<!-- されている -->']

" v2_boundaries_in_lines と同じ判定を、バッファ上では search()（C 実装）で行う。
" 旧: 全行を Vimscript ループで trim 比較しており、1 万行の index.md では
" ヒント更新・数字ジャンプのたびに 200ms 超かかっていた。後方検索 1 回ずつで
" 「最後に一致した行」という同じ意味になる（複数あれば最後が返る）。
let s:v2_up_pat = '\C^\s*\%(### Context\|### Parent\|Parent\|<!-- こっちにとって -->\|<!-- している -->\)\s*$'
let s:v2_down_pat = '\C^\s*\%(### BackLink\|Child\|<!-- そっちにとって -->\|<!-- されている -->\)\s*$'
" 関係の節の見出しのどれか。中身が空の節は見出しごと無い（Context / Group / Related / BackLink は
" あるものだけ書かれる）ので、本文の終わりは「最初に出てくるこれら」で決まる。
let s:v2_any_marks = ['### Context', '### Parent', '### Group', '### Related', '### BackLink',
      \ '<!-- こっちにとって -->', '<!-- している -->', '<!-- そっちにとって -->', '<!-- されている -->']
let s:v2_any_pat = '\C^\s*\%(### Context\|### Parent\|### Group\|### Related\|### BackLink\|<!-- こっちにとって -->\|<!-- している -->\|<!-- そっちにとって -->\|<!-- されている -->\)\s*$'

function! s:v2_first_mark(pat) abort
  let l:save = winsaveview()
  try
    call cursor(1, 1)
    return search(a:pat, 'cW')
  finally
    call winrestview(l:save)
  endtry
endfunction

" 本文の終わり（最初の関係の節の見出し）の行番号（1 始まり）。節が無ければ 0。
function! s:first_section_line() abort
  return s:v2_first_mark(s:v2_any_pat)
endfunction

" 行配列版。0 始まりの index。節が無ければ -1。
function! s:first_section_index_in_lines(lines) abort
  for l:i in range(0, len(a:lines) - 1)
    if index(s:v2_any_marks, trim(a:lines[l:i])) >= 0
      return l:i
    endif
  endfor
  return -1
endfunction

" ### Context が無いときに作る位置（0 始まり）。あるなら -1。
" Group / Related / BackLink のうち最初のものの手前、どれも無ければ末尾。
function! s:context_insert_index(lines) abort
  for l:l in a:lines
    if trim(l:l) ==# s:v2_up_mark || index(s:v2_up_marks_legacy, trim(l:l)) >= 0
      return -1
    endif
  endfor
  let l:fs = s:first_section_index_in_lines(a:lines)
  return l:fs >= 0 ? l:fs : len(a:lines)
endfunction

" 行配列に ### Context を（無ければ）作って返す。
function! s:ensure_context_in_lines(lines) abort
  let l:at = s:context_insert_index(a:lines)
  if l:at < 0 | return a:lines | endif
  let l:lines = copy(a:lines)
  call insert(l:lines, s:v2_up_mark, l:at)
  return l:lines
endfunction

" 行配列に ### BackLink を（無ければ）末尾に作って返す。
function! s:ensure_backlink_in_lines(lines) abort
  for l:l in a:lines
    if trim(l:l) ==# s:v2_down_mark || index(s:v2_down_marks_legacy, trim(l:l)) >= 0
      return a:lines
    endif
  endfor
  return a:lines + [s:v2_down_mark]
endfunction

" index.md のように関係の節を持たないノートか
function! s:no_sections_buffer() abort
  return expand('%:t') ==# 'index.md'
endfunction

" 今のバッファに ### Context を（無ければ）作る。作れた／あったら 1、index.md なら 0。
function! s:ensure_context_in_buffer() abort
  if s:no_sections_buffer() | return 0 | endif
  let l:at = s:context_insert_index(getline(1, '$'))
  if l:at >= 0
    call append(l:at, s:v2_up_mark)
  endif
  return 1
endfunction

" 今のバッファに ### BackLink を（無ければ）末尾に作る。
function! s:ensure_backlink_in_buffer() abort
  if s:no_sections_buffer() | return 0 | endif
  if s:v2_last_mark(s:v2_down_pat) <= 0
    call append(line('$'), s:v2_down_mark)
  endif
  return 1
endfunction

function! s:v2_last_mark(pat) abort
  let l:save = winsaveview()
  try
    call cursor(line('$'), 1)
    return search(a:pat, 'bcW')
  finally
    call winrestview(l:save)
  endtry
endfunction

" Parent / Child の見張り行の行番号を返す。
" 見張りはノート作成時（テンプレート）にだけ入る。無ければ [0, 0] を返し、
" 呼び出し側が処理を中止する（後から見張りを追加することは決してしない）。
function! s:v2_boundaries() abort
  " 内容が同じなら前回の結果を使う。全文後方検索 2 回（1 万行で約 20ms）を
  " ヒント更新のたびに繰り返さないため。b:changedtick で無効化する。
  let l:tick = b:changedtick
  if get(b:, 'gnosis_v2_bounds_tick', -1) ==# l:tick
    return b:gnosis_v2_bounds
  endif
  " up_m = 最初の関係の節の見出し（本文の終わり）、dn_m = BackLink の見出し（無ければ 0）
  let l:up_m = s:v2_first_mark(s:v2_any_pat)
  let l:dn_m = s:v2_last_mark(s:v2_down_pat)
  let l:res = l:up_m > 0 ? [l:up_m, l:dn_m] : [0, 0]
  let b:gnosis_v2_bounds = l:res
  let b:gnosis_v2_bounds_tick = l:tick
  return l:res
endfunction

" a:rel は末尾に `;` を含みうる（例: `きっかけ;` = sync に自動ミラーさせない
" 印。§4）。見出し行を作る時の実際の終端記号と、既存見出しを探す時の
" パターン（`;` 側の有無を問わず一致）をここで統一する。
function! s:v2_rel_header(rel) abort
  return a:rel =~# ';$' ? a:rel : a:rel . ':'
endfunction

function! s:v2_rel_header_pat(rel) abort
  let l:base = substitute(a:rel, ';$', '', '')
  return '^\V' . escape(l:base, '\') . '\m\s*[:;]'
endfunction

" s:v2_insert_link の行配列版（現在のバッファに限らず、任意ファイルの行に
" 対して同じ処理をするために使う）。target_dir は重複チェックの相対パス
" 解決基準（そのファイル自身のディレクトリ）。戻り値: {lines, ok, reason}
function! s:v2_insert_link_in_lines(lines, target_dir, rel, linktext, below) abort
  " 関係の節は空なら見出しごと無いので、書く前に必要な見出し（Context / BackLink）を作る
  let l:lines = s:ensure_context_in_lines(a:lines)
  if a:below
    let l:lines = s:ensure_backlink_in_lines(l:lines)
  endif
  let [l:up_m, l:dn_m] = s:v2_boundaries_in_lines(l:lines)
  if l:up_m == 0
    return {'lines': l:lines, 'ok': 0, 'reason': 'no_marks'}
  endif
  if !a:below && l:dn_m == 0
    let l:dn_m = len(l:lines) + 1
  endif
  let l:n = len(l:lines)
  if a:below
    let l:lo = l:dn_m
    let l:hi = l:n + 1
  else
    let l:lo = l:up_m
    let l:hi = l:dn_m
  endif

  let l:new_tgt = s:extract_target(a:linktext)
  if !empty(l:new_tgt)
    let l:new_fp = fnamemodify(gnosis#resolve_link(l:new_tgt, a:target_dir), ':p')
    for l:i in range(l:lo + 1, min([l:hi - 1, l:n]))
      let l:old = s:extract_target(get(l:lines, l:i - 1, ''))
      if empty(l:old) | continue | endif
      if fnamemodify(gnosis#resolve_link(l:old, a:target_dir), ':p') ==# l:new_fp
        return {'lines': l:lines, 'ok': 0, 'reason': 'dup'}
      endif
    endfor
  endif

  let l:hdr = 0
  for l:i in range(l:lo + 1, l:hi - 1)
    if get(l:lines, l:i - 1, '') =~# s:v2_rel_header_pat(a:rel)
      let l:hdr = l:i | break
    endif
  endfor

  if l:hdr == 0
    " 既定の関係『ノート』は見出しを書かず裸リンクで置く。
    let l:ins = (a:rel ==# 'ノート') ? [a:linktext] : [s:v2_rel_header(a:rel), a:linktext]
    call extend(l:lines, l:ins, l:hi - 1)
    return {'lines': l:lines, 'ok': 1}
  endif

  let l:inline = matchstr(get(l:lines, l:hdr - 1, ''), '[:;]\s*\zs.*$')
  if l:inline =~# '\S'
    let l:lines[l:hdr - 1] = s:v2_rel_header(a:rel)
    call extend(l:lines, [l:inline, a:linktext], l:hdr)
    return {'lines': l:lines, 'ok': 1}
  endif

  let l:end = l:hdr
  for l:i in range(l:hdr + 1, l:hi - 1)
    if get(l:lines, l:i - 1, '') =~# '^\s*\[[^]]*\]([^)]*)'
      let l:end = l:i
    else
      break
    endif
  endfor
  call insert(l:lines, a:linktext, l:end)
  return {'lines': l:lines, 'ok': 1}
endfunction

" ca/bc/cu/at でカスタムラベルを選んだ時、相手ファイルへその場でラベル付き
" バックリンクを直接書き込む。a:below は「自分から見てどちら側に足したか」
" （0=こっちにとって/1=そっちにとって）。相手からは向きが逆になるので
" 書き込みは !a:below 側へ行う。
function! s:v2_write_other_side_label(target_path, label, cur_path, cur_title, below) abort
  if !filereadable(a:target_path) | return 0 | endif
  if fnamemodify(a:target_path, ':t') ==# 'index.md' | return 0 | endif
  let l:lines = readfile(a:target_path)
  let l:target_dir = fnamemodify(a:target_path, ':h')
  let l:linktext = s:make_link_from_dir(a:cur_path, a:cur_title, l:target_dir)
  let l:result = s:v2_insert_link_in_lines(l:lines, l:target_dir, a:label, l:linktext, !a:below)
  if !l:result.ok
    return l:result.reason ==# 'dup' ? 1 : 0
  endif
  call s:syn_writefile(l:result.lines, a:target_path)
  return 1
endfunction

" a:below … 0 = 上側（こっちにとって、見張りの間）、1 = 下側（そっちにとって、最後の見張り以降）
function! s:v2_insert_link(rel, linktext, ...) abort
  let l:below = a:0 > 0 ? a:1 : 0
  " 関係の節は空なら見出しごと無いので、書く前に必要な見出し（Context / BackLink）を作る
  if !s:ensure_context_in_buffer() || (l:below && !s:ensure_backlink_in_buffer())
    echohl WarningMsg
    echo gnosis#i18n#tr('Gnosis: このノートには関係を書けません（index.md など）')
    echohl NONE
    return 0
  endif
  let [l:up_m, l:dn_m] = s:v2_boundaries()
  if l:up_m == 0
    echohl WarningMsg
    echo gnosis#i18n#tr('Gnosis: このノートは v2 形式じゃない（見張りコメントなし）。:V2Migrate で変換して')
    echohl NONE
    return 0
  endif
  if !l:below && l:dn_m == 0
    let l:dn_m = line('$') + 1
  endif
  " 以降は必ず 1 を返す（末尾で return 1）
  if l:below
    let l:lo = l:dn_m
    let l:hi = line('$') + 1
  else
    let l:lo = l:up_m
    let l:hi = l:dn_m
  endif

  " 同じ相手が既にこの区間に居れば二重に足さない（c を2回押しても増えない）
  let l:new_tgt = s:extract_target(a:linktext)
  if !empty(l:new_tgt)
    let l:new_fp = fnamemodify(gnosis#resolve_link(l:new_tgt, expand('%:p:h')), ':p')
    for l:i in range(l:lo + 1, min([l:hi - 1, line('$')]))
      let l:old = s:extract_target(getline(l:i))
      if empty(l:old) | continue | endif
      if fnamemodify(gnosis#resolve_link(l:old, expand('%:p:h')), ':p') ==# l:new_fp
        echo gnosis#i18n#tr('Gnosis: すでに登録済み — ') . l:new_tgt
        return 0
      endif
    endfor
  endif

  " 該当区間の `関係:` / `関係;` ヘッダを探す
  let l:hdr = 0
  for l:i in range(l:lo + 1, l:hi - 1)
    if getline(l:i) =~# s:v2_rel_header_pat(a:rel)
      let l:hdr = l:i | break
    endif
  endfor

  if l:hdr == 0
    " 既定の関係『ノート』は見出しを書かず裸リンクで置く（sync の正規形に
    " 合わせる。`ノート:` を一旦挟まない）。それ以外はブロック形。
    let l:ins = (a:rel ==# 'ノート') ? [a:linktext] : [s:v2_rel_header(a:rel), a:linktext]
    if l:below
      call append(line('$'), l:ins)
    else
      call append(l:hi - 1, l:ins)
    endif
    return 1
  endif

  let l:inline = matchstr(getline(l:hdr), '[:;]\s*\zs.*$')
  if l:inline =~# '\S'
    call setline(l:hdr, s:v2_rel_header(a:rel))
    call append(l:hdr, [l:inline, a:linktext])
    return 1
  endif

  let l:end = l:hdr
  for l:i in range(l:hdr + 1, l:hi - 1)
    if getline(l:i) =~# '^\s*\[[^]]*\]([^)]*)'
      let l:end = l:i
    else
      break
    endif
  endfor
  call append(l:end, a:linktext)
  return 1
endfunction

function! s:v2_title_for(tgt) abort
  let l:root = s:get_pkm_root()
  let l:t = ''
  if !empty(l:root)
    let l:t = s:get_yaml_title(s:join_path(l:root, a:tgt))
  endif
  return l:t !=# '' ? l:t : fnamemodify(a:tgt, ':t:r')
endfunction

" クリップボード / 無名レジスタの `.md` ファイル名 or `[t](x.md)` を関係付きで取り込む。
" 複数行 / 複数リンクにも対応（1 件なら従来どおり質問なしで進む）。
"   a:1 … 取り込む対象（空ならレジスタから。複数行 / 複数リンクも可）
"   a:2 … 関係(relation)（省略時は数字で選択。複数件なら先に「一括 / 個別」を聞く）
"   a:3 … 1 なら --- より下（そっちにとって）へ。既定は上
"   a:4 … 1 なら逆モード（\ca/\at）。今開いているノート側を `(ラベル)` にし、
"          相手側には生のラベルをその場で（質問なしで）書く。通常モード
"          （ca/at）とは括弧が付く側が逆になるだけで、他のロジックは共通。
function! gnosis#v2_add_link(...) abort
  let l:raw = a:0 > 0 && a:1 !=# '' ? a:1 : trim(getreg('+'))
  if l:raw ==# '' | let l:raw = trim(getreg('"')) | endif
  let l:below_default = a:0 > 2 ? a:3 : 0
  let l:reverse = a:0 > 3 ? a:4 : 0

  let l:targets = filter(s:extract_targets_from_clipboard(l:raw), 'v:val =~# ''\.md$''')
  if empty(l:targets)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: .md のファイル名 / リンクが見つからない') | echohl NONE
    return
  endif

  " 対象にグループ / 小グループ属性のファイルが含まれるか（先に判定しておき、
  " 関係ピッカーで「ノート」の代わりに「索引」を出すかどうかに使う）。
  " 現在のノート自身が グループ / 小グループ 属性の場合も同様に「索引」を出す
  " （zc/zp と同じ判定基準。自分が容器なら、相手が普通のノートでも「索引」）。
  let l:attr_targets = {}
  for l:t in l:targets
    if s:v2_target_attr(l:t) !=# '' | let l:attr_targets[l:t] = 1 | endif
  endfor
  let l:self_attr = !empty(s:v2_buf_attr())
  let l:all_attr = l:self_attr || (!empty(l:attr_targets) && len(l:attr_targets) == len(l:targets))

  " 関係: 複数件なら「一括で同じ関係」か「一つずつ選ぶ」かを先に聞く
  let l:rel_fixed = a:0 > 1 && a:2 !=# '' ? a:2 : ''
  let l:batch_rel = l:rel_fixed
  if empty(l:batch_rel)
    if len(l:targets) == 1
      let l:batch_rel = s:v2_pick_relation(l:all_attr)
      if l:batch_rel ==# '' | echo gnosis#i18n#tr('Gnosis: キャンセル') | return | endif
    else
      let l:mode = s:v2_pick(gnosis#i18n#tr('複数件の関係'), [gnosis#i18n#tr('一括で同じ関係'), gnosis#i18n#tr('一つずつ選ぶ')])
      if l:mode ==# '' | echo gnosis#i18n#tr('Gnosis: キャンセル') | return | endif
      if l:mode ==# gnosis#i18n#tr('一括で同じ関係')
        let l:batch_rel = s:v2_pick_relation(l:all_attr)
        if l:batch_rel ==# '' | echo gnosis#i18n#tr('Gnosis: キャンセル') | return | endif
      endif
    endif
  endif

  " 表示名: 対象にグループ / 小グループ属性のファイルが含まれるなら、
  " その表示名の付け方を聞く（複数あれば「一つずつ入力」か「タイトルのまま」を先に選ぶ）。
  " ただし呼び出し側が関係を固定している（za など）ときは表示名を一切聞かず、
  " 相手のタイトルのまま追加する（複数対象でもピッカーを出さない）。
  let l:manual_name = !empty(l:attr_targets) && len(l:attr_targets) == 1
  if !empty(l:rel_fixed)
    let l:manual_name = 0
  elseif !empty(l:attr_targets) && len(l:attr_targets) > 1
    let l:nm = s:v2_pick(gnosis#i18n#tr('属性ノートの表示名'), [gnosis#i18n#tr('一つずつ入力'), gnosis#i18n#tr('タイトルのまま')])
    if l:nm ==# '' | echo gnosis#i18n#tr('Gnosis: キャンセル') | return | endif
    let l:manual_name = (l:nm ==# gnosis#i18n#tr('一つずつ入力'))
  endif

  let l:cur_path  = expand('%:p')
  let l:cur_title = gnosis#current_title()
  if l:cur_title ==# '' | let l:cur_title = fnamemodify(l:cur_path, ':t:r') | endif

  " まず各対象の関係・向き・表示名を決めるだけ決める（挿入はまだしない）。
  " こうしておくと、「相手側にも同じラベルを書くか」を全体で 1 回だけ
  " 聞ける（個々の関係が何であれ、答えは 1 つで済む）。
  let l:entries = []
  for l:tgt in l:targets
    let l:is_attr = has_key(l:attr_targets, l:tgt)
    let l:rel = !empty(l:batch_rel) ? l:batch_rel : s:v2_pick_relation(l:self_attr || l:is_attr)
    if l:rel ==# ''
      echo 'Gnosis: ' . l:tgt . gnosis#i18n#tr(' はキャンセルしてスキップ')
      continue
    endif
    " 関係ごとの向きの制約（グループ=こっちにとって / 関連=対称）
    let l:side = s:v2_relation_side(l:rel)
    let l:below = l:side >= 0 ? l:side : l:below_default

    let l:default_title = s:v2_title_for(l:tgt)
    let l:title = l:default_title
    if l:is_attr && l:manual_name
      let l:input = trim(input('[' . l:tgt . gnosis#i18n#tr('] 表示名: '), l:default_title))
      let l:title = empty(l:input) ? l:default_title : l:input
    endif

    call add(l:entries, {'tgt': l:tgt, 'rel': l:rel, 'below': l:below, 'title': l:title})
  endfor

  " 自由入力（ピッカーの選択肢に無い言葉）が 1 件でもあれば、「聞かれる側」
  " （通常モードなら相手側、逆モード \ca/\at なら自分側）に `(ラベル)` を
  " その場で書くかどうかを全体で 1 回だけ聞く。「いいえ」なら聞かれる側には
  " 何も書かず、次の sync が既定の『ノート』を生成する。ピッカーの選択肢
  " （索引/補足/資料 等）は聞かず、常にもう一方の側へ `(ラベル)` を書く
  " （聞くのは自由入力の言葉だけ）。「もう一方の側」（通常モードなら自分側、
  " 逆モードなら相手側）は常に、質問なしで生のラベルをその場で書く。
  let l:free_rels = {}
  for l:e in l:entries
    if s:v2_is_custom_relation(l:e.rel) && !s:v2_is_menu_relation(l:e.rel)
      let l:free_rels[l:e.rel] = 1
    endif
  endfor
  let l:write_asked = 0
  if len(l:free_rels) == 1
    let l:write_asked = s:v2_ask_write_same_label(keys(l:free_rels)[0], l:reverse)
  elseif len(l:free_rels) > 1
    let l:msg = l:reverse ? gnosis#i18n#tr('自分側にもそれぞれ書く？') : gnosis#i18n#tr('相手側にもそれぞれ書く？')
    let l:write_asked = s:v2_pick(l:msg, [gnosis#i18n#tr('はい'), gnosis#i18n#tr('いいえ（自動）')]) ==# gnosis#i18n#tr('はい')
  endif

  let l:added = 0
  let l:other_written = 0
  for l:e in l:entries
    let l:is_custom = s:v2_is_custom_relation(l:e.rel)
    " ピッカーの選択肢（索引/補足/資料 等）は聞かず常に書く。自由入力の
    " 言葉だけ、上で聞いた結果（l:write_asked）に従う。
    let l:do_write = l:is_custom && (s:v2_is_menu_relation(l:e.rel) || l:write_asked)
    let l:tgt_path = gnosis#resolve_link(l:e.tgt)
    if l:reverse
      " \ca/\at: 相手側は常に（質問なしで）生のラベルをその場で書く。
      " 自分側は聞かれる側: 書くなら (ラベル) をその場で書き、
      " 書かないなら何も書かず sync 任せ（既定の『ノート』になる）。
      " 書かない場合、相手側は `;` 終端で書く（sync の自動ミラー対象外に
      " するため。§4）。
      if l:is_custom
        let l:other_write_rel = l:do_write ? l:e.rel : l:e.rel . ';'
        call s:v2_write_other_side_label(l:tgt_path, l:other_write_rel, l:cur_path, l:cur_title, l:e.below)
        let l:other_written = 1
      endif
      if !l:is_custom || l:do_write
        let l:own_rel = l:is_custom ? '(' . l:e.rel . ')' : l:e.rel
        if s:v2_insert_link(l:own_rel, '[' . l:e.title . '](' . l:e.tgt . ')', l:e.below)
          let l:added += 1
          echo 'Gnosis: ' . l:own_rel . (l:e.below ? ' ↓ ' : ' ') . '+= ' . l:e.title
        endif
      else
        echo 'Gnosis: ' . l:e.rel . (l:e.below ? ' ↓ ' : ' ') . gnosis#i18n#tr('(相手のみ) += ') . l:e.title
      endif
    else
      " ca/at/bc/cu: 自分側は常に生のラベルをその場で書く。相手側は
      " 聞かれる側: 書くなら (ラベル) をその場で書き、書かないなら何も
      " 書かず sync 任せ（既定の『ノート』になる）。書かない場合、自分側は
      " `;` 終端で書く（sync の自動ミラー対象外にするため。§4）。
      let l:own_write_rel = (l:is_custom && !l:do_write) ? l:e.rel . ';' : l:e.rel
      if s:v2_insert_link(l:own_write_rel, '[' . l:e.title . '](' . l:e.tgt . ')', l:e.below)
        let l:added += 1
        echo 'Gnosis: ' . l:own_write_rel . (l:e.below ? ' ↓ ' : ' ') . '+= ' . l:e.title
        if l:do_write
          call s:v2_write_other_side_label(l:tgt_path, '(' . l:e.rel . ')', l:cur_path, l:cur_title, l:e.below)
          let l:other_written = 1
        endif
      endif
    endif
  endfor
  if l:added > 0
    silent! write
  elseif l:other_written
    call s:run_update_one_for(l:cur_path)
  endif
endfunction

" --- ページを開きながら関連ノートを新規作成。
"   a:below … 1 = 現ノートの --- より下（子: 相手が上側に載る）
"             0 = 現ノートの --- より上（親: 相手の下側に載る）
"   a:1     … 関係(relation)（省略時は数字で選択）
" a:below … 0 = 現ノートの こっちにとって 側 / 1 = そっちにとって 側
" a:attr  … 空でなければ新ノートを `attribute: {a:attr}` で作る（グループ / 小グループ 等）
" a:1(可変) … 関係名（省略時は数字ピッカー）
" 現在バッファの attribute 値（グループ / 小グループ 等）。無ければ空文字
" （旧名 カテゴリー / キーワード は グループ / 小グループ へ読み替えて返す）
function! s:v2_buf_attr() abort
  if getline(1) !~# '^---\s*$' | return '' | endif
  for l:i in range(2, min([25, line('$')]))
    if getline(l:i) =~# '^---\s*$' | break | endif
    let l:m = matchlist(getline(l:i), '^\s*\%(attribute\|属性\)\s*:\s*\(\S.\{-}\)\s*$')
    if !empty(l:m) | return s:v2_normalize_attr(l:m[1]) | endif
  endfor
  return ''
endfunction

" zc: 子ノート（リンクは現ノートの そっちにとって 側）
" zc/zp は zn に一本化して廃止。コマンド :NC / :NP からの互換のためだけに残す。
function! gnosis#v2_new_child(...) abort
  call s:v2_new_interactive('')
endfunction

function! gnosis#v2_new_parent(...) abort
  call s:v2_new_interactive('')
endfunction

" zw は廃止して zk（グループノート）に置き換え。互換のため名前だけ残す。
function! gnosis#v2_new_attr() abort
  call s:v2_new_interactive('group')
endfunction

" pe: 現ノートを起点に 親/子/文中/関連 を辿って 1 つの展開ファイルへ集約する。
" シンプル（深さを 1 つだけ指定、親/子/文中/関連を区別せず平等に辿る）と
" 詳細（親・子・文中・関連それぞれ独立の深さ。前回の詳細設定は
" ROOT/.pkm_expand_prefs.json に記録され、次回「保存済み設定を使う」で
" 再利用できる）を選ぶ。出力は ROOT/.trash/T_<timestamp>.md（sync・検索の対象外、
" 編集しても元ノートへは反映されない使い捨てスナップショット）。
function! gnosis#v2_expand() abort
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 名前付きバッファで実行して') | echohl NONE
    return
  endif
  let l:root = s:get_pkm_root()
  if empty(l:root)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: PKM root が未設定') | echohl NONE
    return
  endif
  let l:py = get(g:, 'gnosis_expand_v2_python', '')
  if empty(l:py) || !filereadable(l:py)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: expand_v2.py が見つからない: ') . l:py | echohl NONE
    return
  endif

  let l:mode = s:v2_pick(gnosis#i18n#tr('展開'), [gnosis#i18n#tr('シンプル'), gnosis#i18n#tr('詳細')])
  if l:mode ==# '' | echo gnosis#i18n#tr('Gnosis: キャンセル') | return | endif

  if l:mode ==# gnosis#i18n#tr('シンプル')
    let l:n = input(gnosis#i18n#tr('深さ（数字）: '), '1')
    if l:n !~# '^\d\+$' | echo gnosis#i18n#tr('Gnosis: キャンセル') | return | endif
    let l:args = [s:python_cmd(), l:py, 'simple', l:root, l:cur, l:n]
  else
    let l:st = s:v2_expand_detail_settings(l:root, l:py)
    if empty(l:st) | echo gnosis#i18n#tr('Gnosis: キャンセル') | return | endif
    let l:args = [s:python_cmd(), l:py, 'detailed', l:root, l:cur,
          \ l:st.body, l:st.context, l:st.group, l:st.br, l:st.diary]
  endif

  let l:out = systemlist(join(map(copy(l:args), 'shellescape(v:val)'), ' '))
  if v:shell_error != 0 || empty(l:out)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 展開に失敗: ') . join(l:out, ' ') | echohl NONE
    return
  endif
  let l:result_path = l:out[-1]
  if !filereadable(l:result_path)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 展開ファイルが見つからない: ') . l:result_path | echohl NONE
    return
  endif
  execute 'edit ' . fnameescape(l:result_path)
endfunction

" ---------------------------------------------------------------------------
" \e 詳細モードの探索設定（5 項目）とプリセット
"   {body, context, group, br: 深さの文字列, diary: 't' | 'f'}
"   body    … 文中リンクの深さ（本文のリンクだけを辿る）
"   context … Context の深さ（1 段階目は Context、その先は全種類）
"   group   … Group の深さ（同上）
"   br      … BackLink / Related 共通の深さ（同上）
"   diary   … BackLink の探索に日記（題が YYYY-MM-DD-曜日2文字-…）を含めるか
"   深さ 0 = その探索はしない。前回の設定は自動で記録され、プリセットは明示的に保存したものだけ
"   （vault 直下の .pkm_expand_prefs.json / .pkm_expand_presets.json。ノートには触れない）。
" ---------------------------------------------------------------------------

function! s:v2_expand_parse(line) abort
  let l:p = split(trim(a:line))
  if len(l:p) != 5 | return {} | endif
  return {'body': l:p[0], 'context': l:p[1], 'group': l:p[2], 'br': l:p[3], 'diary': l:p[4]}
endfunction

function! s:v2_expand_fmt(st) abort
  return gnosis#i18n#tr('文中') . a:st.body . ' Context' . a:st.context . ' Group' . a:st.group
        \ . ' BL/Rel' . a:st.br . gnosis#i18n#tr(' 日記') . a:st.diary
endfunction

" 詳細モードの前回設定を取得する。無ければ空 dict
function! s:v2_expand_prefs(root, py) abort
  let l:out = systemlist(join(map([s:python_cmd(), a:py, 'get_prefs', a:root], 'shellescape(v:val)'), ' '))
  if v:shell_error != 0 || empty(l:out)
    return {}
  endif
  return s:v2_expand_parse(l:out[0])
endfunction

" プリセット一覧: [{name, st}]（名前順）
function! s:v2_expand_presets(root, py) abort
  let l:out = systemlist(join(map([s:python_cmd(), a:py, 'presets_list', a:root], 'shellescape(v:val)'), ' '))
  let l:res = []
  if v:shell_error != 0 | return l:res | endif
  for l:ln in l:out
    let l:f = split(l:ln, "\t", 1)
    if len(l:f) != 2 | continue | endif
    let l:st = s:v2_expand_parse(l:f[1])
    if !empty(l:st) | call add(l:res, {'name': l:f[0], 'st': l:st}) | endif
  endfor
  return l:res
endfunction

" 5 項目を 1 つずつ入力する（既定値は a:def）。取り止めなら {}。
function! s:v2_expand_input(def) abort
  let l:st = {}
  for [l:key, l:label] in [['body', gnosis#i18n#tr('文中リンクの深さ')], ['context', gnosis#i18n#tr('Context の深さ')],
        \ ['group', gnosis#i18n#tr('Group の深さ')], ['br', gnosis#i18n#tr('Backlink / Related の深さ')]]
    let l:v = trim(input(l:label . gnosis#i18n#tr(' (0 = 探索しない): '), a:def[l:key]))
    if l:v !~# '^\d\+$' | redraw | return {} | endif
    let l:st[l:key] = l:v
  endfor
  let l:d = trim(input(gnosis#i18n#tr('Backlink の探索に Diary を含めるか (t / f): '), a:def.diary))
  redraw
  if l:d !~# '^[tf]$' | return {} | endif
  let l:st.diary = l:d
  return l:st
endfunction

" プリセットを保存する。同じ名前があれば上書きするか確認する（確認なしには上書きしない）。
function! s:v2_expand_save_preset(root, py, st) abort
  let l:name = trim(input(gnosis#i18n#tr('プリセット名: ')))
  redraw
  if empty(l:name) | echo gnosis#i18n#tr('Gnosis: 保存しない') | return 0 | endif
  let l:base = [s:python_cmd(), a:py, 'preset_save', a:root, l:name,
        \ a:st.body, a:st.context, a:st.group, a:st.br, a:st.diary]
  let l:out = systemlist(join(map(copy(l:base), 'shellescape(v:val)'), ' '))
  if v:shell_error != 0
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: プリセットを保存できません: ') . join(l:out, ' ') | echohl NONE
    return 0
  endif
  if get(l:out, 0, '') ==# 'exists'
    if confirm(gnosis#i18n#tr('プリセット「') . l:name . gnosis#i18n#tr('」は既にあります。上書きしますか？'), "&Yes\n&No", 2) != 1
      echo gnosis#i18n#tr('Gnosis: 上書きしない（保存しない）')
      return 0
    endif
    call systemlist(join(map(l:base + ['overwrite'], 'shellescape(v:val)'), ' '))
  endif
  echo gnosis#i18n#tr('Gnosis: プリセット「') . l:name . gnosis#i18n#tr('」を保存した')
  return 1
endfunction

" 一覧から 1 つ選ぶ（inputlist）。取り止めなら {}。
function! s:v2_expand_choose_preset(label, presets) abort
  let l:lines = [a:label . gnosis#i18n#tr('（番号を入力。0 / 空で取り止め）')]
  let l:i = 1
  for l:p in a:presets
    call add(l:lines, l:i . '. ' . l:p.name . '    [' . s:v2_expand_fmt(l:p.st) . ']')
    let l:i += 1
  endfor
  let l:n = inputlist(l:lines)
  redraw
  if l:n < 1 || l:n > len(a:presets) | return {} | endif
  return a:presets[l:n - 1]
endfunction

" 詳細モードの探索設定を決める。戻り値は設定の dict（取り止めなら {}）。
function! s:v2_expand_detail_settings(root, py) abort
  while 1
    let l:prefs = s:v2_expand_prefs(a:root, a:py)
    let l:presets = s:v2_expand_presets(a:root, a:py)
    let l:items = []
    if !empty(l:prefs) | call add(l:items, gnosis#i18n#tr('前回の設定で展開')) | endif
    call add(l:items, gnosis#i18n#tr('新しく設定する'))
    if !empty(l:presets)
      call add(l:items, gnosis#i18n#tr('プリセットを呼び出す'))
      call add(l:items, gnosis#i18n#tr('プリセットを削除する'))
    endif
    let l:label = gnosis#i18n#tr('詳細設定') . (empty(l:prefs) ? '' : gnosis#i18n#tr('(前回: ') . s:v2_expand_fmt(l:prefs) . ')')
    let l:pm = s:v2_pick(l:label, l:items)
    if l:pm ==# '' | return {} | endif

    if l:pm ==# gnosis#i18n#tr('前回の設定で展開')
      return l:prefs
    elseif l:pm ==# gnosis#i18n#tr('新しく設定する')
      let l:def = empty(l:prefs) ? {'body': '3', 'context': '1', 'group': '1', 'br': '1', 'diary': 't'} : l:prefs
      let l:st = s:v2_expand_input(l:def)
      if empty(l:st) | return {} | endif
      let l:act = s:v2_pick(gnosis#i18n#tr('この設定 [') . s:v2_expand_fmt(l:st) . gnosis#i18n#tr('] を'), [gnosis#i18n#tr('展開する'), gnosis#i18n#tr('名前を付けて保存して展開する')])
      if l:act ==# '' | return {} | endif
      if l:act =~# gnosis#i18n#tr('^名前')
        call s:v2_expand_save_preset(a:root, a:py, l:st)
      endif
      return l:st
    elseif l:pm ==# gnosis#i18n#tr('プリセットを呼び出す')
      let l:p = s:v2_expand_choose_preset(gnosis#i18n#tr('呼び出すプリセット'), l:presets)
      if empty(l:p) | return {} | endif
      return l:p.st
    elseif l:pm ==# gnosis#i18n#tr('プリセットを削除する')
      let l:p = s:v2_expand_choose_preset(gnosis#i18n#tr('削除するプリセット'), l:presets)
      if empty(l:p) | return {} | endif
      if confirm(gnosis#i18n#tr('プリセット「') . l:p.name . gnosis#i18n#tr('」を削除しますか？（ノートは消えません）'), "&Yes\n&No", 2) == 1
        call systemlist(join(map([s:python_cmd(), a:py, 'preset_delete', a:root, l:p.name], 'shellescape(v:val)'), ' '))
        echo gnosis#i18n#tr('Gnosis: プリセット「') . l:p.name . gnosis#i18n#tr('」を削除した')
      endif
      " メニューに戻る
    else
      return {}
    endif
  endwhile
endfunction

" カーソル直下ノート（zh）: 新ノートを作り、そのリンクをカーソル行の直下（本文）に置く。
" 関係セクションには入れない → 相手には バックリンク: として現れる。
function! gnosis#v2_new_here() abort
  if s:pkm_format() !=# 'v2'
    echo gnosis#i18n#tr('Gnosis: v2 専用') | return
  endif
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 名前付きバッファで実行して') | echohl NONE
    return
  endif
  let l:dir = expand('%:p:h')
  let l:ts  = gnosis#timestamp_filename()
  let l:file = s:join_path(l:dir, l:ts . '.md')
  call s:write_new_note(gnosis#note_template(l:ts, 0), l:file)
  let l:save_ai = &autoindent | let l:save_si = &smartindent
  setlocal noautoindent nosmartindent
  call append(line('.'), '[' . l:ts . '](' . l:ts . '.md)')
  let &autoindent = l:save_ai | let &smartindent = l:save_si
  silent noautocmd write
  call s:run_update_one_for(l:cur)
  execute 'edit ' . fnameescape(l:file)
endfunction

" zn: ノート作成。リレーションは書かず、位置だけ h/Enter/o/p で選ぶ。
function! gnosis#v2_new_plain() abort
  call s:v2_new_interactive('')
endfunction

" zk: グループノート作成（attribute: グループ）。位置は zn と同じ h/Enter/o/p。
function! gnosis#v2_new_group() abort
  call s:v2_new_interactive('group')
endfunction

" zk（ビジュアル）… 選択範囲を中身にしたグループノートを作る。
"   選択範囲は新しいグループへのリンクで**置き換える**（リンクをグループへ移す）。
"   グループの ### Context は今のノート。作成後グループを開いて本文末にカーソル。
function! gnosis#v2_new_group_visual() abort range
  if s:pkm_format() !=# 'v2'
    echo gnosis#i18n#tr('Gnosis: v2 専用') | return
  endif
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 名前付きバッファで実行して') | echohl NONE | return
  endif

  " 選択範囲を記録
  let l:is_linewise = (visualmode() ==# 'V')
  let l:sline = line("'<")
  let l:eline = line("'>")
  let l:scol  = col("'<")
  let l:ecol  = col("'>")
  if l:sline <= 0 || l:eline <= 0
    echo 'No visual selection' | return
  endif
  if l:sline > l:eline || (l:sline == l:eline && l:scol > l:ecol)
    let [l:sline, l:eline] = [l:eline, l:sline]
    let [l:scol, l:ecol] = [l:ecol, l:scol]
  endif
  let l:lines = getline(l:sline, l:eline)
  if empty(l:lines)
    echo 'No visual selection' | return
  endif
  if l:is_linewise
    let l:body = copy(l:lines)
  elseif len(l:lines) == 1
    let l:start_char = charidx(l:lines[0], l:scol - 1)
    let l:end_char = charidx(l:lines[0], l:ecol - 1) + 1
    let l:body = [strcharpart(l:lines[0], l:start_char, l:end_char - l:start_char)]
  else
    let l:body = copy(l:lines)
    let l:first_start = charidx(l:body[0], l:scol - 1)
    let l:last_end = charidx(l:body[-1], l:ecol - 1) + 1
    let l:body[0] = strcharpart(l:body[0], l:first_start)
    let l:body[-1] = strcharpart(l:body[-1], 0, l:last_end)
  endif
  while !empty(l:body) && trim(l:body[0]) ==# '' | call remove(l:body, 0) | endwhile
  while !empty(l:body) && trim(l:body[-1]) ==# '' | call remove(l:body, -1) | endwhile
  if empty(l:body)
    echo gnosis#i18n#tr('Gnosis: 選択が空です') | return
  endif

  let l:cur_title = gnosis#current_title()
  let l:dir = expand('%:p:h')
  let l:ts  = gnosis#timestamp_filename()
  let l:file = s:join_path(l:dir, l:ts . '.md')

  " グループ本体: 選択内容を本文に、### Context に今のノート
  let l:content = [
        \ '---',
        \ 'time: ' . gnosis#timestamp_yaml(),
        \ 'title: ' . l:ts,
        \ 'attribute: group',
        \ '---',
        \ '',
        \ '# ' . l:ts,
        \ '',
        \ ] + l:body + [
        \ s:v2_up_mark,
        \ s:make_link_from_dir(l:cur, l:cur_title, l:dir),
        \ ]
  call s:write_new_note(l:content, l:file)

  " 元の選択をグループへのリンクで置き換える
  let l:link = '[' . l:ts . '](' . l:ts . '.md)'
  call s:replace_visual_selection_with_link(l:link, l:is_linewise, l:sline, l:eline, l:scol, l:ecol, l:lines)
  silent noautocmd write
  call s:run_update_one_for(l:cur)

  call gnosis#push_history()
  silent execute 'edit ' . fnameescape(l:file)
  let l:up = search('^' . escape(s:v2_up_mark, '*[]~\.'), 'nw')
  if l:up > 1
    call cursor(l:up - 1, 1)
    call cursor(l:up - 1, col('$'))
  endif
  startinsert
endfunction

" zn / zk の共通本体。
"   a:attr が空なら普通のノート、'グループ' なら容器ノート（attribute: グループ）。
"   作成時にリレーション（ノート: など）は一切書かない。置くのは素のリンク 1 行で、
"   あとから手で グループ / きっかけ: などを書く。`:` / `;` は sync がそのまま扱う。
"   位置キー: h=カーソル直下 / Enter=Child末尾 / o=リンク無し(孤立) / p=Parent末尾。
" simple: 本文の最後（### Context の手前）へ link を、空行 1 つを挟んで置く
function! s:simple_body_append(link) abort
  " 本文の終わり = 最初の関係の節の見出し（Context / Group / Related / BackLink のうち最初のもの）
  let l:up = s:first_section_line()
  if l:up == 0
    call append(line('$'), a:link)
    return
  endif
  " ### Context の直前（本文の最後）にリンクを挿入。
  " 直前が**散文**なら空行 1 つを挟む。直前が**リンク行**なら空行なしで並べる。
  " Enter で連続で置いても空行が累積しない。既存の空行はそのまま。
  let l:prev = l:up - 1
  if l:prev >= 1 && trim(getline(l:prev)) !=# ''
        \ && (trim(getline(l:prev)) !~# '\]\s*(\S\+)\s*$' || s:in_diary_list(l:prev))
    call append(l:prev, ['', a:link])
  else
    call append(l:prev, a:link)
  endif
endfunction

" simple: file の本文末尾（### Context の直前）へ link を 1 行置く。
"   a:is_group が真（zk のグループノート）なら、リンクと ### Context は隣り合う。
"   偽（zn）なら上下に空行 1 つずつ。テンプレートが持つ本文の空行は
"   この並びに置き換わる（空行が累積しない）。
function! s:simple_body_append_to_file(file, link, is_group) abort
  let l:lines = readfile(a:file)
  let l:hdr = s:first_section_index_in_lines(l:lines)
  if l:hdr < 0
    " 関係の節が無い新ノート: 末尾の空行を剥がして、リンクの前後に空行を置く
    while !empty(l:lines) && trim(l:lines[-1]) ==# ''
      call remove(l:lines, -1)
    endwhile
    call extend(l:lines, a:is_group ? ['', a:link] : ['', a:link, ''])
  else
    " 最初の節の見出しの直前まで続く空行の連なりを剥がす。
    let l:top = l:hdr
    while l:top > 0 && trim(l:lines[l:top - 1]) ==# ''
      let l:top -= 1
    endwhile
    if l:top < l:hdr
      call remove(l:lines, l:top, l:hdr - 1)
      let l:hdr = l:top
    endif
    call extend(l:lines, a:is_group ? ['', a:link] : ['', a:link, ''], l:hdr)
  endif
  call s:syn_writefile(l:lines, a:file)
endfunction

" simple: file の ### Context に parent_path へのリンクを 1 本足す
function! s:simple_add_parent(file, parent_path, parent_title) abort
  let l:lines = readfile(a:file)
  let l:link = s:make_link_from_dir(a:parent_path, a:parent_title, fnamemodify(a:file, ':h'))
  " 関係の節は空なら見出しごと無い。重複は Context / Group / Related / BackLink 全体で見る
  for l:ln in l:lines
    if l:ln ==# l:link | return | endif
  endfor
  let l:at = s:context_insert_index(l:lines)
  if l:at >= 0
    " Context が無い: 最初の節の手前（無ければ末尾）に見出しごと作る
    call extend(l:lines, [s:v2_up_mark, l:link], l:at)
  else
    let l:hdr = -1
    for l:i in range(0, len(l:lines) - 1)
      if trim(l:lines[l:i]) ==# s:v2_up_mark || index(s:v2_up_marks_legacy, trim(l:lines[l:i])) >= 0
        let l:hdr = l:i | break
      endif
    endfor
    call insert(l:lines, l:link, l:hdr + 1)
  endif
  call s:syn_writefile(l:lines, a:file)
endfunction

" simple: file の ### Related に other_path へのリンクを 1 本足す（zr の相手側）。
"   見出しが無ければ ### Context と ### BackLink の間に作る。Related 内に同じ
"   リンク先が既にあれば何もしない。追加したら 1 を返す。
function! s:simple_add_related(file, other_path, other_title) abort
  if !filereadable(a:file)
    return 0
  endif
  let l:lines = readfile(a:file)
  let l:dir = fnamemodify(a:file, ':h')
  let l:link = s:make_link_from_dir(a:other_path, a:other_title, l:dir)
  let l:up = -1
  let l:back = -1
  for l:i in range(0, len(l:lines) - 1)
    let l:s = trim(l:lines[l:i])
    if l:s ==# s:v2_up_mark && l:up < 0
      let l:up = l:i
    endif
    if l:s ==# s:v2_down_mark && l:back < 0
      let l:back = l:i
    endif
  endfor
  if fnamemodify(a:file, ':t') ==# 'index.md'
    return 0
  endif
  let l:rel = -1
  for l:i in range(0, (l:back >= 0 ? l:back : len(l:lines)) - 1)
    if trim(l:lines[l:i]) ==# s:v2_related_mark
      let l:rel = l:i
      break
    endif
  endfor
  if l:rel < 0
    " 見出しを作って、その直後にリンクを置く
    let l:ins = l:back >= 0 ? l:back : len(l:lines)
    call insert(l:lines, s:v2_related_mark, l:ins)
    call insert(l:lines, l:link, l:ins + 1)
  else
    " Related セクション末尾（次の ### 見出し or 末尾）へ。重複は解決先で見る。
    let l:end = len(l:lines)
    for l:i in range(l:rel + 1, len(l:lines) - 1)
      if trim(l:lines[l:i]) =~# '^###\s'
        let l:end = l:i
        break
      endif
    endfor
    let l:new_fp = fnamemodify(gnosis#resolve_link(a:other_path, l:dir), ':p')
    for l:i in range(l:rel + 1, l:end - 1)
      let l:tg = s:extract_target(l:lines[l:i])
      if empty(l:tg) || empty(l:new_fp)
        continue
      endif
      let l:fp = fnamemodify(gnosis#resolve_link(l:tg, l:dir), ':p')
      if l:fp ==# l:new_fp
        return 0
      endif
    endfor
    call insert(l:lines, l:link, l:end)
  endif
  call s:syn_writefile(l:lines, a:file)
  return 1
endfunction

" simple: yes/no を聞く（既定 yes）
function! s:ask_yes_no(msg) abort
  " ポップアップは出さず、コマンドラインで y/n を 1 打だけ聞く
  echo a:msg . ' (y/n)'
  let l:c = nr2char(getchar())
  redraw
  return l:c ==? 'y'
endfunction

" zp: クリップボードの .md を今のノートの本文に追加（＝今のノートが相手の親になる）
function! gnosis#add_clipboard() abort
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 名前付きファイルで実行して') | echohl None
    return
  endif
  let l:target = ''
  for l:t in s:extract_targets_from_clipboard(s:clipboard_text())
    if l:t =~? '\.md$'
      let l:target = l:t
      break
    endif
  endfor
  if empty(l:target)
    let l:target = trim(input(gnosis#i18n#tr('追加するノート (.md): '), '', 'file'))
  endif
  if empty(l:target)
    echo gnosis#i18n#tr('キャンセル')
    return
  endif
  let l:tf = gnosis#resolve_link(l:target)
  if !filereadable(l:tf)
    echohl WarningMsg | echo gnosis#i18n#tr('見つかりません: ') . l:tf | echohl None
    return
  endif
  let l:link = s:make_link_from_dir(l:tf, s:v2_title_for(l:target), expand('%:p:h'))
  call s:simple_body_append(l:link)
  silent! write
  call s:write_current_and_sync_now()
  echo gnosis#i18n#tr('Gnosis: 追加 → ') . fnamemodify(l:tf, ':t')
endfunction

" 旧: 今のノートを、相手（カーソル下のリンク or クリップボード）の ### Context に追加
" 公開: カーソル下の .md リンク先の ### Context に、今のノートを 1 本足す。
" 確認プロンプトは出さない（\P）。リンクが無ければ何もしない。
function! gnosis#add_current_as_parent_here() abort
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 名前付きファイルで実行して') | echohl None
    return
  endif
  let l:lk = gnosis#get_link_under_cursor()
  if empty(l:lk) || empty(l:lk.target) || l:lk.target !~? '\.md\(#.*\)\?$'
    echo gnosis#i18n#tr('Gnosis: カーソル下に .md リンクがありません')
    return
  endif
  let l:tgt = gnosis#resolve_link(l:lk.target)
  if !filereadable(l:tgt)
    echohl WarningMsg | echo gnosis#i18n#tr('見つかりません: ') . l:tgt | echohl None
    return
  endif
  call s:simple_add_parent(l:tgt, l:cur, gnosis#current_title())
  call s:write_current_and_sync_now()
  echo gnosis#i18n#tr('Gnosis: Context に追加 → ') . fnamemodify(l:tgt, ':t')
endfunction

function! gnosis#add_to_parent() abort
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 名前付きファイルで実行して') | echohl None
    return
  endif
  let l:cur_title = gnosis#current_title()
  let l:target = ''
  let l:lk = gnosis#get_link_under_cursor()
  if !empty(l:lk) && !empty(l:lk.target) && l:lk.target =~? '\.md\(#.*\)\?$'
    let l:target = l:lk.target
  endif
  if empty(l:target)
    for l:t in s:extract_targets_from_clipboard(s:clipboard_text())
      if l:t =~? '\.md$'
        let l:target = l:t
        break
      endif
    endfor
  endif
  if empty(l:target)
    let l:target = trim(input(gnosis#i18n#tr('Context に追加する相手 (.md): '), '', 'file'))
  endif
  if empty(l:target)
    echo gnosis#i18n#tr('キャンセル')
    return
  endif
  let l:tgt = gnosis#resolve_link(l:target)
  if !filereadable(l:tgt)
    echohl WarningMsg | echo gnosis#i18n#tr('見つかりません: ') . l:tgt | echohl None
    return
  endif
  call s:simple_add_parent(l:tgt, l:cur, l:cur_title)
  call s:write_current_and_sync_now()
  echo gnosis#i18n#tr('Gnosis: Context に追加 → ') . fnamemodify(l:tgt, ':t')
endfunction

function! s:v2_new_interactive(attr) abort
  if s:pkm_format() !=# 'v2'
    echo 'Gnosis: ' . gnosis#i18n#tr('v2 専用') | return
  endif
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo 'Gnosis: ' . gnosis#i18n#tr('名前付きバッファで実行して') | echohl NONE | return
  endif
  if empty(a:attr)
    echo gnosis#i18n#tr('h=カーソル直下 / Enter=本文の最後 / t=見出しの下 / c=Context末尾 / o=リンク無し(孤立)  (Esc/q キャンセル)')
  else
    echo gnosis#i18n#tr('h=カーソル直下 / Enter=本文の最後 / t=見出しの下 / c=Context末尾 / o=リンク無し(孤立) / g=カーソル下のリンクをグループ化  (Esc/q キャンセル)')
  endif
  let l:ch = s:getkey()
  redraw
  if l:ch ==? 'q' || char2nr(l:ch) == 27 || char2nr(l:ch) == 3
    echo 'Gnosis: ' . gnosis#i18n#tr('キャンセル') | return
  endif
  if l:ch ==? 't'
    " 見出しを選んでから作る（選択をキャンセルしたら何も作らない）。選択は非同期なので
    " 続きは s:v2_new_run をコールバックで呼ぶ。
    call s:outline_pick_here(function('s:v2_new_run_t', [a:attr]))
    return
  endif
  if l:ch ==# 'g' && !empty(a:attr)
    " zk → g: カーソル下のリンク 1 本を、新しいグループの中へ移す
    call s:group_link_under_cursor()
    return
  endif
  if l:ch ==? 'c'
    " c: 今のノートの Context に新ノートを入れる。新ノート側に今のノートへのリンクを
    " どう入れるか（Enter / t / o。グループなら表示名も）を、作る前に聞く。
    call s:ask_back_link('', [], !empty(a:attr), gnosis#current_title(),
          \ function('s:v2_new_run_c', [a:attr]))
    return
  endif
  " 位置キー以外（旧 p を含む）では何も作らない
  if l:ch !~? '^[ho]$' && l:ch !=# "\<CR>" && l:ch !=# "\<NL>"
    echo 'Gnosis: ' . gnosis#i18n#tr('キャンセル（h / Enter / t / c / o のどれか）') | return
  endif
  call s:v2_new_run(a:attr, l:ch, 0)
endfunction

" zk → g: カーソル下のリンク 1 本を、新しいグループの中へ移す。
"   新しいグループの本文はそのリンク 1 行、### Context は今のノート（ビジュアルの zk と同じ）。
"   元のリンクの位置は、新しいグループへのリンクに置き換える。同じ行の前後の文章・
"   他のリンクはそのまま。リンク先のノート（ファイル）は動かさない。
"   カーソル下にリンクが無ければ何も変えず、案内だけ出す。
function! s:group_link_under_cursor() abort
  let l:span = s:link_span_under_cursor()
  if empty(l:span)
    echohl WarningMsg
    echo 'Gnosis: ' . gnosis#i18n#tr('カーソル下にリンクがありません（リンクの上で zk → g。アプリでは Alt+クリックでリンクにカーソルを置けます）')
    echohl NONE
    return
  endif
  let l:cur = expand('%:p')
  let l:cur_title = gnosis#current_title()
  let l:dir = expand('%:p:h')
  let l:ts = gnosis#timestamp_filename()
  let l:file = s:join_path(l:dir, l:ts . '.md')
  let l:content = [
        \ '---',
        \ 'time: ' . gnosis#timestamp_yaml(),
        \ 'title: ' . l:ts,
        \ 'attribute: group',
        \ '---',
        \ '',
        \ '# ' . l:ts,
        \ '',
        \ l:span.text,
        \ s:v2_up_mark,
        \ s:make_link_from_dir(l:cur, l:cur_title, l:dir),
        \ ]
  call s:write_new_note(l:content, l:file)
  let l:line = getline(l:span.lnum)
  call setline(l:span.lnum, strpart(l:line, 0, l:span.start) . '[' . l:ts . '](' . l:ts . '.md)' . strpart(l:line, l:span.end))
  silent noautocmd write
  call s:run_update_one_for(l:cur)
  call gnosis#push_history()
  silent execute 'edit ' . fnameescape(l:file)
  call cursor(9, 1)
endfunction

" カーソル下の Markdown リンク（画像・コードの中は除く）の {lnum, start, end, text}（0 始まりのバイト位置）
function! s:link_span_under_cursor() abort
  let l:lnum = line('.')
  let l:line = getline(l:lnum)
  let l:col0 = col('.') - 1
  let l:start = 0
  while 1
    let l:m = matchstrpos(l:line, s:link_pat, l:start)
    if l:m[1] < 0
      return {}
    endif
    let l:is_image = l:m[1] > 0 && l:line[l:m[1] - 1] ==# '!'
    if !l:is_image && l:col0 >= l:m[1] && l:col0 < l:m[2] && !s:buf_in_code(l:lnum, l:m[1])
      return {'lnum': l:lnum, 'start': l:m[1], 'end': l:m[2], 'text': l:m[0]}
    endif
    let l:start = l:m[2]
  endwhile
endfunction

function! s:v2_new_run_c(attr, choice) abort
  call s:v2_new_run(a:attr, 'c', 0, a:choice)
endfunction

function! s:v2_new_run_t(attr, head_lnum) abort
  call s:v2_new_run(a:attr, 't', a:head_lnum)
endfunction

" 見出し行 a:hl の本文の最後に、空行を挟んでリンクを置く。
"   見出し本文
"   (空行)
"   リンク          ← ここ。直前がリンク行なら空行なしで並べる
"   (空行)
"   次の見出し
function! s:insert_link_under_heading(hl, link) abort
  let l:last = line('$')
  let l:end = a:hl + 1
  let l:in_fence = 0
  while l:end <= l:last
    let l:t = getline(l:end)
    if l:t =~# '^\s*```'
      let l:in_fence = !l:in_fence
    elseif !l:in_fence && l:t =~# '^\s*#\+\s\+'
      break
    endif
    let l:end += 1
  endwhile
  " 本文の最後の非空行 e（本文が空なら見出し行そのもの）
  let l:e = l:end - 1
  while l:e > a:hl && trim(getline(l:e)) ==# ''
    let l:e -= 1
  endwhile
  let l:prev_link = l:e > a:hl && trim(getline(l:e)) =~# '\]\s*(\S\+)\s*$'
  " 本文の最後の直後にリンクを置く。後ろにある空行（日記の余白など）はそのまま残す。
  " 空行が無いまま次の見出しが来るときだけ、リンクの後ろに空行を 1 つ足す。
  let l:new = (l:prev_link ? [] : ['']) + [a:link]
  if l:e + 1 <= line('$') && l:e + 1 == l:end
    let l:new += ['']
  endif
  call append(l:e, l:new)
endfunction

" 今のノートの見出しを選ぶ（t モード）。選ばれた見出しの行番号で a:Cb を呼ぶ。
" 検索は見出しを優先しつつ、その下の本文にもヒットする（zo と同じ）。
function! s:outline_pick_here(Cb) abort
  let l:path = expand('%:p')
  let l:items = s:file_heading_items(l:path, getline(1, '$'))
  if empty(l:items)
    echo gnosis#i18n#tr('Gnosis: 見出しがありません')
    return
  endif
  let s:outline_pick_cb = a:Cb
  if !exists('*fzf#run')
    let l:choices = []
    let l:i = 1
    for l:it in l:items
      call add(l:choices, l:i . ': ' . repeat('#', l:it.level) . ' ' . l:it.text)
      let l:i += 1
    endfor
    let l:sel = inputlist(l:choices)
    if l:sel > 0 && l:sel <= len(l:items)
      call s:outline_pick_done(l:items[l:sel - 1].lnum)
    endif
    return
  endif
  call s:outline_fzf(l:items, l:path, function('s:outline_pick_sink'), 0)
endfunction

function! s:outline_pick_sink(line) abort
  call s:outline_pick_done(str2nr(get(split(a:line, "\t", 1), 3, '0')))
endfunction

function! s:outline_pick_done(lnum) abort
  let l:Cb = s:outline_pick_cb
  unlet s:outline_pick_cb
  if a:lnum > 0
    call call(l:Cb, [a:lnum])
  endif
endfunction

" zn / zk の続き。a:ch は位置キー、a:head_lnum は t のときの見出し行。
function! s:v2_new_run(attr, ch, head_lnum, ...) abort
  let l:ch = a:ch
  let l:choice = a:0 ? a:1 : {'mode': 'end', 'lnum': 0, 'name': ''}
  let l:cur = expand('%:p')
  let l:cur_title = gnosis#current_title()
  let l:dir = expand('%:p:h')
  let l:ts  = gnosis#timestamp_filename()
  let l:file = s:join_path(l:dir, l:ts . '.md')

  " 新ノートを先に作る（sync がリンク先を解決できるように）
  " t は見出しの下に直接リンクを置くので、元のノートが日記なら「今日のノート」には重ねない
  let s:diary_skip_from = (l:ch ==? 't') ? l:cur : ''
  try
    call s:write_new_note(gnosis#note_template(l:ts, !empty(a:attr) ? 1 : 0), l:file)
  finally
    let s:diary_skip_from = ''
  endtry

  let l:link = '[' . l:ts . '](' . l:ts . '.md)'
  let l:added = 0
  let l:save_ai = &autoindent | let l:save_si = &smartindent
  setlocal noautoindent nosmartindent
  if l:ch ==? 'h'
    call append(line('.'), l:link)      " カーソル直下（本文）
    let l:added = 1
  elseif l:ch ==? 't'
    call s:insert_link_under_heading(a:head_lnum, l:link)  " 見出しの本文の最後
    let l:added = 1
  elseif l:ch ==? 'c'
    " 今のノートの ### Context 末尾に置く → 今のノートは**新ノートの子**。
    " よって新ノート側は親を持たず、本文リンク（子）で今のノートを指す。
    if s:append_link_to_buffer_section('up', l:link)
      let l:added = 1
    endif
  elseif l:ch ==# "\<CR>" || l:ch ==# "\<NL>"
    call s:simple_body_append(l:link)  " 本文の最後（### Context の手前に空行1つ）
    let l:added = 1
  endif
  " o … リンク無し（孤立）
  if l:added
    call s:ensure_blank_before_up()
  endif
  let &autoindent = l:save_ai | let &smartindent = l:save_si
  silent noautocmd write
  let l:in_body = 0
  let l:hl = 0
  if l:added
    if l:ch ==? 'c'
      " 新ノート側は「もと開いていたノート」を**本文リンク**（子）に置く（o を選んだら置かない）。
      " c は「親（文脈）を作る」操作なので、ここを ### Context にすると循環して読めない。
      if l:choice.mode !=# 'none'
        let l:name = empty(l:choice.name) ? l:cur_title : s:md_link_text(l:choice.name)
        let l:back = s:make_link_from_dir(l:cur, l:name, fnamemodify(l:file, ':h'))
        call s:simple_body_append_to_file(l:file, l:back, !empty(a:attr))
        let l:in_body = 1
      endif
    else
      " h / Enter は今のノートが親。新ノート側は ### Context にだけ入れる。
      " 本文（中央）には入れない。本文はテンプレートのまま（余白 2 行）を残す。潰さない。
      call s:simple_add_parent(l:file, l:cur, l:cur_title)
    endif
    call s:run_update_one_for(l:cur)
  endif
  call gnosis#push_history()
  execute 'edit ' . fnameescape(l:file)
  " 本文入力位置へ。zn は余白 2 行なので 2 行下、zk（グループ）は 1 行下。
  " p は本文リンクを置いた行（リンクの直後に続けて書ける位置）。
  let l:h1 = search('^#\s', 'nw')
  if l:in_body
    let l:hl = search('(' . escape(fnamemodify(l:cur, ':t'), '.*[]~\') . ')$', 'nw')
  endif
  if l:h1 > 0 && l:hl == 0 | let l:hl = l:h1 + (empty(a:attr) ? 2 : 1) | endif
  if l:hl > 0 | call cursor(l:hl, 1) | call cursor(l:hl, col('$')) | endif
  startinsert
endfunction

" ---------------------------------------------------------------------------
" c（今のノート A の Context にリンク先 B を入れる）のあとに、B 側へ A へのリンクを
" どう入れるかを選ぶ（zn / zk / za / \l 共通）。
"   Enter … B の本文の最後（関係の節の手前）
"   t     … B の見出しを選び、その節の最後（次の同じか上の階層の見出しの手前）
"   o     … B には入れない（A の Context への追加はそのまま行う。操作の取り消しではない）
"   Esc   … 操作全体の取り消し（A にも B にも何も書かない）
" B がグループなら、Enter / t のあとに表示名を聞く（空欄から。空 Enter = A のタイトル）。
" 質問はすべて変更の前に行う。答えは a:Cont({mode, lnum, name}) に渡す（取り消しなら呼ばない）。
" 見出しの選択は fzf（非同期）なので、続きはコールバックで行う。
" ---------------------------------------------------------------------------

" 表示名を Markdown のリンクの文字として安全にする（\ [ ] をエスケープ）
function! s:md_link_text(text) abort
  return escape(a:text, '\[]')
endfunction

" 表示名の入力。入力欄は空から始まる。
"   空のまま Enter → a:default_title（リンクが指すノートのタイトル）
"   文字を入れて Enter → その文字
"   Esc → 取り消し（{'ok': 0}）
" g:gnosis_test_display_name があれば入力の代わりに使う（試験用。"\x1b" は Esc）
function! s:ask_display_name(default_title, ...) abort
  let l:prompt = gnosis#i18n#tr('表示名（空 Enter で「%s」・Esc で取り消し）: ', a:default_title)
  if exists('g:gnosis_test_display_name')
    let l:r = remove(g:gnosis_test_display_name, 0)
    let l:r = l:r ==# "\x1b" ? "\x01gnosis-cancel" : l:r
  else
    try
      let l:r = inputdialog(l:prompt, '', "\x01gnosis-cancel")
    catch /^Vim:Interrupt$/
      let l:r = "\x01gnosis-cancel"
    endtry
    redraw
  endif
  if l:r ==# "\x01gnosis-cancel"
    return {'ok': 0}
  endif
  return {'ok': 1, 'name': empty(l:r) ? a:default_title : l:r}
endfunction

" 1 文字を読む（g:gnosis_test_keys があればそこから。試験用）
function! s:getkey() abort
  if exists('g:gnosis_test_keys') && !empty(g:gnosis_test_keys)
    return remove(g:gnosis_test_keys, 0)
  endif
  return nr2char(getchar())
endfunction

" ファイル（または行リスト）の見出しを選ぶ。選ばれた見出しの行番号で a:Cb を呼ぶ。
" g:gnosis_test_heading（見出しの文字）があれば選択の代わりに使う（試験用）。
function! s:outline_pick_lines(path, lines, Cb) abort
  let l:items = s:file_heading_items(a:path, a:lines)
  if empty(l:items)
    return 0
  endif
  if exists('g:gnosis_test_heading')
    for l:it in l:items
      if l:it.text ==# g:gnosis_test_heading
        call call(a:Cb, [l:it.lnum])
        return 1
      endif
    endfor
    return 1
  endif
  let s:outline_pick_cb = a:Cb
  if !exists('*fzf#run')
    let l:choices = [gnosis#i18n#tr('見出しを選んでください（番号）:')]
    let l:i = 1
    for l:it in l:items
      call add(l:choices, l:i . ': ' . repeat('#', l:it.level) . ' ' . l:it.text)
      let l:i += 1
    endfor
    let l:sel = inputlist(l:choices)
    if l:sel > 0 && l:sel <= len(l:items)
      call s:outline_pick_done(l:items[l:sel - 1].lnum)
    endif
    return 1
  endif
  call s:outline_fzf(l:items, a:path, function('s:outline_pick_sink'), 0)
  return 1
endfunction

" B 側への入れ方を聞く。a:target … B のパス（まだ無い新ノートなら ''）、a:lines … B の行、
" a:is_group … B がグループか、a:a_title … A のタイトル（表示名の既定）。
function! s:ask_back_link(target, lines, is_group, a_title, Cont) abort
  echo gnosis#i18n#tr('リンク先に、今のノートへのリンクを: Enter=本文の最後 / t=見出しを選んでその節の最後 / o=入れない  (Esc で取り消し)')
  let l:ch = s:getkey()
  redraw
  let l:n = char2nr(l:ch)
  if l:n == 27 || l:n == 3 || l:ch ==? 'q'
    echo 'Gnosis: ' . gnosis#i18n#tr('取り消しました（何も変更していません）')
    return
  endif
  if l:ch ==? 'o'
    call a:Cont({'mode': 'none', 'lnum': 0, 'name': ''})
    return
  endif
  if l:ch ==? 't'
    let l:Next = function('s:ask_back_link_named', [a:is_group, a:a_title, a:Cont, 't'])
    if !empty(a:lines) && s:outline_pick_lines(a:target, a:lines, l:Next)
      return
    endif
    echo 'Gnosis: ' . gnosis#i18n#tr('リンク先に見出しがないので、本文の最後に入れます')
    call s:ask_back_link_named(a:is_group, a:a_title, a:Cont, 'end', 0)
    return
  endif
  if l:ch ==# "\<CR>" || l:ch ==# "\<NL>"
    call s:ask_back_link_named(a:is_group, a:a_title, a:Cont, 'end', 0)
    return
  endif
  echo 'Gnosis: ' . gnosis#i18n#tr('取り消しました（Enter / t / o のどれか。何も変更していません）')
endfunction

function! s:ask_back_link_named(is_group, a_title, Cont, mode, lnum) abort
  let l:name = ''
  if a:is_group
    let l:r = s:ask_display_name(a:a_title)
    if !l:r.ok
      echo 'Gnosis: ' . gnosis#i18n#tr('取り消しました（何も変更していません）')
      return
    endif
    let l:name = l:r.name
  endif
  call a:Cont({'mode': a:mode, 'lnum': a:lnum, 'name': l:name})
endfunction

" 行リスト a:lines の見出し a:hl（1 始まり）が受け持つ節の終わり（次の同じか上の階層の見出し、
" 関係の節、またはファイルの終わり）の行番号（その見出しの手前の行。1 始まり）
function! s:section_end_in_lines(lines, hl) abort
  let l:level = strlen(matchstr(get(a:lines, a:hl - 1, ''), '^\s*\zs#\+'))
  let l:flags = s:fence_flags(a:lines)
  let l:i = a:hl + 1
  while l:i <= len(a:lines)
    let l:t = a:lines[l:i - 1]
    if !l:flags[l:i - 1]
      if trim(l:t) =~# s:v2_any_pat || trim(l:t) =~# '^###\s\+\%(Context\|Group\|Related\|BackLink\|Parent\)\s*$'
        break
      endif
      let l:m = matchstr(l:t, '^\s*\zs#\+\ze\s\+')
      if !empty(l:m) && strlen(l:m) <= l:level
        break
      endif
    endif
    let l:i += 1
  endwhile
  return l:i - 1
endfunction

" 行リストのリンク挿入（a:mode = 'end' | 't'）。直前が文章なら空行を 1 つ挟み、直前がリンク行なら
" 続けて並べる（zn の Enter・\l の t と同じ並べ方）。挿入後の行リストを返す。
function! s:insert_link_in_lines(lines, link, mode, hl) abort
  let l:lines = copy(a:lines)
  if a:mode ==# 't' && a:hl > 0
    let l:end = s:section_end_in_lines(l:lines, a:hl)
    let l:e = l:end
    while l:e > a:hl && trim(l:lines[l:e - 1]) ==# ''
      let l:e -= 1
    endwhile
    let l:prev_link = l:e > a:hl && trim(l:lines[l:e - 1]) =~# '\]\s*(\S\+)\s*$'
    let l:new = (l:prev_link ? [] : ['']) + [a:link]
    if l:e == l:end && l:end < len(l:lines)
      let l:new += ['']
    endif
    call extend(l:lines, l:new, l:e)
    return l:lines
  endif
  let l:hdr = s:first_section_index_in_lines(l:lines)
  let l:at = l:hdr < 0 ? len(l:lines) : l:hdr
  if l:hdr < 0
    " 関係の節が無い: 末尾の空行の手前（空行はそのまま残す）
    while l:at > 0 && trim(l:lines[l:at - 1]) ==# ''
      let l:at -= 1
    endwhile
  endif
  let l:prev = l:at > 0 ? trim(l:lines[l:at - 1]) : ''
  if l:prev !=# '' && l:prev !~# '\]\s*(\S\+)\s*$' && l:prev !~# '^---\s*$'
    call extend(l:lines, ['', a:link], l:at)
  else
    call insert(l:lines, a:link, l:at)
  endif
  return l:lines
endfunction

" B の本文に A へのリンクが既にあるか（関係の節は見ない）
function! s:body_links_to(lines, b_dir, a_path) abort
  let l:hdr = s:first_section_index_in_lines(a:lines)
  let l:body = l:hdr < 0 ? a:lines : (l:hdr > 0 ? a:lines[: l:hdr - 1] : [])
  let l:want = fnamemodify(a:a_path, ':p')
  for l:t in s:body_link_targets_from_lines(l:body, a:b_dir)
    if fnamemodify(l:t, ':p') ==# l:want
      return 1
    endif
  endfor
  return 0
endfunction

" B（a:target）に A（a:a_path）へのリンクを、選んだ入れ方 a:choice で書く。書いたら 1。
function! s:apply_back_link(target, a_path, a_title, choice) abort
  if a:choice.mode ==# 'none' || !filereadable(a:target)
    return 0
  endif
  let l:nr = bufnr(fnamemodify(a:target, ':p'))
  if l:nr > 0 && bufloaded(l:nr) && getbufvar(l:nr, '&modified')
    echohl WarningMsg | echo 'Gnosis: ' . gnosis#i18n#tr('リンク先に未保存の変更があるため、リンク先には入れませんでした') | echohl NONE
    return 0
  endif
  let l:lines = readfile(a:target)
  let l:bdir = fnamemodify(a:target, ':h')
  if s:body_links_to(l:lines, l:bdir, a:a_path)
    return 0
  endif
  let l:title = empty(a:choice.name) ? a:a_title : a:choice.name
  let l:link = s:make_link_from_dir(a:a_path, s:md_link_text(l:title), l:bdir)
  let l:lines = s:insert_link_in_lines(l:lines, l:link, a:choice.mode, a:choice.lnum)
  call s:syn_writefile(l:lines, a:target)
  if l:nr > 0
    silent! execute 'checktime ' . l:nr
  endif
  return 1
endfunction

" 旧形式（v1 の Parent:/Child: / 旧 `---`）を v2 へ明示変換。
"   :V2Migrate       … PKM ルート全体
"   :V2Migrate %     … 現在のファイルだけ
function! gnosis#v2_migrate(...) abort
  if s:pkm_format() !=# 'v2'
    echo gnosis#i18n#tr('Gnosis: v2 のみ') | return
  endif
  let l:root = s:get_pkm_root()
  if empty(l:root) | echoerr gnosis#i18n#tr('Gnosis: PKM ルート未設定') | return | endif
  let l:args = [s:python_cmd(), g:gnosis_python, 'migrate', l:root]
  if a:0 > 0 && a:1 !=# ''
    call add(l:args, a:1 ==# '%' ? expand('%:p') : a:1)
  endif
  echo system(join(map(copy(l:args), 'shellescape(v:val)'), ' '))
  silent! edit
endfunction


function! s:make_link_from_dir(path, title, base_dir) abort
  let l:path = trim(a:path)
  if s:is_absolute_path(l:path)
    let l:file = s:relpath_from_dir(l:path, a:base_dir)
  else
    let l:file = s:markdown_relative_target(l:path)
  endif
  let l:name = fnamemodify(l:file, ':t')
  let l:text = empty(a:title) ? (s:is_markdown_target(l:name) ? fnamemodify(l:name, ':r') : l:name) : a:title
  return '[' . l:text . '](' . l:file . ')'
endfunction

function! gnosis#make_link(path, title) abort
  return s:make_link_from_dir(a:path, a:title, expand('%:p:h'))
endfunction

function! s:parent_link_lines(parent_path, parent_title, base_dir) abort
  if empty(a:parent_path)
    return []
  endif
  return [s:make_link_from_dir(a:parent_path, a:parent_title, a:base_dir)]
endfunction

function! s:cwd_note_dir() abort
  let l:dir = fnamemodify(getcwd(), ':p')
  let l:trimmed = substitute(l:dir, '[\\/]\+$', '', '')
  return empty(l:trimmed) ? l:dir : l:trimmed
endfunction

function! s:join_path(dir, name) abort
  if a:dir =~# '[\\/]$'
    return a:dir . a:name
  endif
  return a:dir . s:sep() . a:name
endfunction

" ---------------------------------------------------------------------------
" Update link titles in current buffer (Vim-side, lightweight)
" ---------------------------------------------------------------------------

function! gnosis#update_current_buffer() abort
  let l:in_branch = 0
  let l:in_back   = 0
  let l:after_sep = 0
  let l:in_fence  = 0
  let l:modified  = 0

  for l:i in range(1, line('$'))
    let l:line = getline(l:i)
    let l:trimmed = trim(l:line)

    if l:trimmed =~# '^```'
      let l:in_fence = !l:in_fence
    endif

    if !l:in_fence
      if s:is_section_header_text(l:trimmed, 'branch')
        let l:in_branch = 1 | let l:in_back = 0 | let l:after_sep = 0
        continue
      endif
      if s:is_section_header_text(l:trimmed, 'back')
        let l:in_branch = 0 | let l:in_back = 1 | let l:after_sep = 0
        continue
      endif
      if l:trimmed =~# '^_\{3,}\s*$'
        let l:after_sep = 1
        continue
      endif
    endif

    if l:after_sep || l:in_fence
      continue
    endif

    if (l:in_branch || l:in_back) && l:line =~# '\[\%(\\.\|[^\]\\]\)\+\]([^)]\+\.md)'
      let l:lm = matchlist(l:line, '^\(\[\(\%(\\.\|[^\]\\]\)\+\)\](\([^)]\+\))\)\(.*\)$')
      if !empty(l:lm)
        let l:link_text = get(l:lm, 2, '')
        let l:target    = trim(get(l:lm, 3, ''))
        let l:suffix    = get(l:lm, 4, '')

        let l:target_stem = fnamemodify(fnamemodify(l:target, ':t'), ':r')
        if l:link_text !=# l:target_stem
          continue
        endif

        let l:filepath  = expand('%:p:h') . s:sep() . l:target
        if filereadable(l:filepath)
          let l:title = s:get_title(l:filepath)
          if !empty(l:title)
            let l:new_line = '[' . l:title . '](' . l:target . ')' . l:suffix
            if l:new_line !=# l:line
              call setline(l:i, l:new_line)
              let l:modified = 1
            endif
          endif
        endif
      endif
    endif
  endfor

  if l:modified
    echo 'Gnosis: link titles updated'
  endif
endfunction

" 現在バッファに未保存の変更があれば書き出す。
" 「外部アプリで開く前」「ゴミ箱へ移す前」「同期の前」など、保存が要る瞬間に使う。
" 保存したら 1、変更なし・特殊バッファなど対象外なら 0 を返す。
function! gnosis#save_current_note() abort
  if !&modified || &buftype !=# '' || !&modifiable || &readonly
    return 0
  endif
  if empty(expand('%:p'))
    return 0
  endif
  silent! update
  return !&modified
endfunction

" ---------------------------------------------------------------------------
" UpdateMD / UpdateAll
" ---------------------------------------------------------------------------

function! gnosis#update_md(arg) abort
  let l:root = empty(a:arg) ? gnosis#ensure_root_and_index() : fnamemodify(s:expand_path(a:arg), ':p')
  if empty(l:root)
    return
  endif
  if !empty(a:arg)
    let g:gnosis_root = l:root
    if !isdirectory(l:root)
      call mkdir(l:root, 'p')
    endif
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
  endif
  call gnosis#check_missing_prefix_in_current_dir()
  " 同期は disk を正とするので、編集中のノートは先に書き出す
  if gnosis#is_vault_note(expand('%:p'))
    call gnosis#save_current_note()
  endif
  let l:out = s:run_sync([g:gnosis_python, 'update', l:root])
  if v:shell_error
    echoerr substitute(l:out, '\n\+$', '', '')
    return
  endif
  echo substitute(l:out, '\n\+$', '', '')
  call s:reload_current()
endfunction

function! gnosis#update_all(arg) abort
  " ノート同期（Parent/BackLink 等）は保存のたびに autosync が済ませているので、
  " ここでは index.md のよみ順ソートと、紙PKM の再生成だけを行う（どちらも裏で実行）。
  " 全ノートを再同期したいときは :UpdateMD を使う。
  " 日記: 日付で始まる題のノートがその日に 1 つだけなら、その日の日記として登録する。
  call s:diary_adopt_all_safe()
  if !has('job')
    call s:update_all_sync(a:arg)
    return
  endif
  let l:root = empty(a:arg) ? gnosis#ensure_root_and_index() : fnamemodify(s:expand_path(a:arg), ':p')
  if empty(l:root)
    return
  endif
  if !empty(a:arg)
    let g:gnosis_root = l:root
    if !isdirectory(l:root)
      call mkdir(l:root, 'p')
    endif
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
  endif
  if gnosis#is_vault_note(expand('%:p'))
    call gnosis#save_current_note()
  endif
  let l:pkm = s:get_pkm_root()
  let l:paper = s:paper_pkm_script()
  if !empty(l:pkm) && !empty(s:paper_index_path(l:pkm)) && filereadable(l:paper)
    let l:cmd = s:low_priority_prefix() . s:python_cmd() . ' ' . shellescape(l:paper)
          \ . ' regen ' . shellescape(l:pkm)
    call job_start(gnosis#shell_job(l:cmd), {
          \ 'exit_cb': function('s:update_all_done', [l:root]),
          \ 'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
  else
    call s:sort_index_async(l:root, 1)
  endif
  echo gnosis#i18n#tr('Gnosis: UpdateAll（index 並べ替え・紙PKM 再生成）を裏で実行中…')
endfunction

function! s:update_all_done(root, job, status) abort
  call s:reload_current()
  call s:sort_index_async(a:root, 1)
endfunction

" index.md のよみソートを裏で実行する。ソート中に index.md が変わったり、未保存の
" 変更があるときは上書きしない。a:1 が真なら、終わったときに完了メッセージを出す
" （「実行中…」の表示が残り続けないように）。
function! s:sort_index_async(root, ...) abort
  let l:notify = a:0 ? a:1 : 0
  if !has('job')
    call s:sort_index_file(a:root)
    call s:ua_notify(l:notify, gnosis#i18n#tr('Gnosis: UpdateAll 完了'))
    return
  endif
  let l:index = s:index_path(a:root)
  let l:script = s:sort_yomi_script()
  if !filereadable(l:index) || !filereadable(l:script)
    call s:ua_notify(l:notify, gnosis#i18n#tr('Gnosis: UpdateAll 完了（index なし）'))
    return
  endif
  let l:lines = readfile(l:index)
  if empty(l:lines)
    call s:ua_notify(l:notify, gnosis#i18n#tr('Gnosis: UpdateAll 完了（index が空）'))
    return
  endif
  let l:in = tempname()
  let l:out = tempname()
  let l:rep = tempname()
  call writefile(l:lines, l:in)
  let l:cmd = s:low_priority_prefix() . s:python_cmd() . ' ' . shellescape(l:script)
        \ . ' sort --base ' . shellescape(fnamemodify(a:root, ':p'))
        \ . ' --report-file ' . shellescape(l:rep)
        \ . ' < ' . shellescape(l:in) . ' > ' . shellescape(l:out)
  call job_start(gnosis#shell_job(l:cmd), {
        \ 'exit_cb': function('s:sort_index_done', [l:index, l:lines, l:in, l:out, l:rep, l:notify]),
        \ 'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
endfunction

function! s:ua_notify(notify, msg) abort
  if a:notify
    redraw
    echo a:msg
  endif
endfunction

function! s:sort_index_done(index, lines, in, out, rep, notify, job, status) abort
  let l:new = (a:status == 0 && filereadable(a:out)) ? readfile(a:out) : []
  call delete(a:in)
  call delete(a:out)
  call delete(a:rep)
  if a:status != 0 || empty(l:new)
    call s:ua_notify(a:notify, gnosis#i18n#tr('Gnosis: index の並べ替えに失敗しました（pykakasi 未導入?）'))
    return
  endif
  " ソート中に index.md が書き換わっていたら、古い入力の結果で上書きしない
  if !filereadable(a:index) || readfile(a:index) !=# a:lines
    call s:ua_notify(a:notify, gnosis#i18n#tr('Gnosis: UpdateAll 完了（index が更新されたため並べ替えは省略）'))
    return
  endif
  let l:nr = bufnr(a:index)
  if l:nr > 0 && bufloaded(l:nr) && getbufvar(l:nr, '&modified')
    call s:ua_notify(a:notify, gnosis#i18n#tr('Gnosis: UpdateAll 完了（index に未保存の変更があるため並べ替えは省略）'))
    return
  endif
  if len(l:new) != len(a:lines) || l:new ==# a:lines
    call s:ua_notify(a:notify, gnosis#i18n#tr('Gnosis: UpdateAll 完了'))
    return
  endif
  call writefile(l:new, a:index)
  call s:reload_current()
  call s:ua_notify(a:notify, gnosis#i18n#tr('Gnosis: UpdateAll 完了（index を並べ替えました）'))
endfunction

function! s:update_all_sync(arg) abort
  call gnosis#update_md(a:arg)
  " 紙PKM（Index・グループ・Folgezettel-Index・専用ノート）も再生成する
  let l:root = s:get_pkm_root()
  let l:paper = s:paper_pkm_script()
  if !empty(l:root) && !empty(s:paper_index_path(l:root)) && filereadable(l:paper)
    call system(s:low_priority_prefix() . s:python_cmd() . ' ' . shellescape(l:paper) . ' regen ' . shellescape(l:root))
    checktime
  endif
  if !empty(l:root)
    call s:sort_index_file(l:root)
  endif
endfunction

" index.md をよみ順に並べ替える（\S と同じ規則）。ディスク上のファイルを直接書く。
" 開いていて未保存の変更があるときは上書きしない（中止して知らせる）。
function! s:sort_index_file(root) abort
  let l:index = s:index_path(a:root)
  let l:script = s:sort_yomi_script()
  if !filereadable(l:index) || !filereadable(l:script)
    return
  endif
  let l:nr = bufnr(l:index)
  if l:nr > 0 && bufloaded(l:nr) && getbufvar(l:nr, '&modified')
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: index.md に未保存の変更があるため並べ替えを省略しました') | echohl NONE
    return
  endif
  let l:lines = readfile(l:index)
  if empty(l:lines)
    return
  endif
  let l:report = tempname()
  let l:cmd = s:low_priority_prefix() . s:python_cmd() . ' ' . shellescape(l:script) . ' sort --base ' . shellescape(fnamemodify(a:root, ':p'))
        \ . ' --report-file ' . shellescape(l:report)
  let l:out = system(l:cmd, join(l:lines, "\n") . "\n")
  call delete(l:report)
  if v:shell_error != 0
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: index.md のよみソートに失敗しました（pykakasi 未導入?）') | echohl NONE
    return
  endif
  let l:new = split(l:out, "\n", 1)
  if !empty(l:new) && l:new[-1] ==# ''
    call remove(l:new, -1)
  endif
  if len(l:new) != len(l:lines) || l:new ==# l:lines
    return
  endif
  call writefile(l:new, l:index)
  silent! checktime
endfunction

" 現在バッファをディスクから再読み込み（未変更の場合のみ、カーソル位置保持）
function! s:reload_current() abort
  set autoread
  if has('timers')
    " timer 経由で少し遅らせることで、job完了直後でも確実に反映される
    call timer_start(120, function('s:reload_timer_cb'))
  else
    call s:do_reload()
  endif
endfunction

function! s:reload_timer_cb(timer) abort
  call s:do_reload()
endfunction

function! s:do_reload() abort
  " 挿入・置換・操作待ち・コマンドライン中は何もしない（:edit はテキストロックで
  " 失敗し、checktime の自動再読み込みが編集中のバッファを乱すため）。
  " 次の保存・離脱時の autosync が改めて reload を呼ぶ。
  if mode() =~# '^[iR]' || index(['o', 'c'], mode(1)) >= 0
    return
  endif
  " 現在バッファが未保存でなければ、ディスクの内容がバッファと**違うときだけ**再読み込みする。
  " 再読み込み（:edit / autoread）は 'undoreload' のせいで、内容が同じでも undo の 1 段階
  " になる。保存のたびに同期が走るので、毎回それが積まれ、u の最初の 1 回が空振りして
  " カーソルが飛んでいた。同期が何も変えなかったときは触らない。
  let l:cur = expand('%:p')
  if !empty(l:cur) && filereadable(l:cur) && !&modified && &buftype ==# ''
    if s:disk_differs_from_buffer(l:cur)
      call s:reload_by_edit(l:cur)
    endif
  endif
  " 他のバッファの外部変更を検出（現在バッファは上で済ませたか、変わっていない）
  call s:checktime_others()
endfunction

" ディスクのファイルがバッファの内容と違うか。読めない・改行形式が特殊なときは
" 「違う」とみなして従来どおり再読み込みする。
function! s:disk_differs_from_buffer(path) abort
  if &fileformat !=# 'unix' || &bomb || (!empty(&fileencoding) && &fileencoding !~? '^utf-\?8$')
    return 1
  endif
  return readfile(a:path) !=# getline(1, '$')
endfunction

" 現在バッファ以外の外部変更を検出する。現在バッファは内容が同じなら再読み込みしたく
" ない（undo の段階が増える）ので、checktime の対象から外す。
function! s:checktime_others() abort
  let l:cur = bufnr('%')
  for l:b in getbufinfo({'bufloaded': 1})
    if l:b.bufnr != l:cur && empty(getbufvar(l:b.bufnr, '&buftype'))
      silent! execute 'checktime ' . l:b.bufnr
    endif
  endfor
endfunction

function! s:reload_by_edit(path) abort
  let l:pos = getpos('.')
  let l:view = winsaveview()
  " E823（undoファイル不一致）を抑制しつつ再読み込み
  silent! execute 'edit ' . fnameescape(a:path)
  call winrestview(l:view)
  call setpos('.', l:pos)
endfunction

" ---------------------------------------------------------------------------
" Auto-sync: BufWritePost で update_one を非同期実行
"
"   - 保存後に動くので編集を妨げない
"   - job_start が使えれば完全非同期、なければ system() でフォールバック
"   - 完了後 checktime で Vim バッファを更新
" ---------------------------------------------------------------------------

" デバッグログ: /tmp/syn-autosync.on があるときだけ /tmp/syn-autosync.log に追記する。
" 保存時の同期が走らなかった理由を調べるためのもの（普段は何もしない）。
function! gnosis#autosync_log(msg) abort
  if !filereadable('/tmp/syn-autosync.on')
    return
  endif
  call writefile([strftime('%H:%M:%S') . ' ' . a:msg], '/tmp/syn-autosync.log', 'a')
endfunction

" バッファのタイトル（Python の _simple_parse_text と同じ規則: frontmatter の title、
" 無ければファイル名）。タイトル変更前後の比較用。
function! s:fm_title() abort
  let l:lines = getline(1, min([40, line('$')]))
  if !empty(l:lines) && l:lines[0] =~# '^---\s*$'
    for l:ln in l:lines[1:]
      if l:ln =~# '^---\s*$'
        break
      endif
      if l:ln =~# '^title:\s*\S'
        let l:t = trim(matchstr(l:ln, ':\s*\zs.*'))
        return substitute(l:t, '^[\"'']\|[\"'']$', '', 'g')
      endif
    endfor
  endif
  return expand('%:t:r')
endfunction

" 読み込み・保存の時点のタイトルを覚えておく。次の保存でタイトルが変わっていたら、
" この値が「変更前のタイトル」になり、sync へ渡す（状態ファイルは使わない）。
function! gnosis#remember_title() abort
  let b:syn_prev_title = s:fm_title()
endfunction

function! gnosis#autosync_on_save() abort
  call gnosis#autosync_log('autosync_on_save file=' . expand('%:p'))
  if !filereadable(g:gnosis_python)
    call gnosis#autosync_log('  skip: python script not readable: ' . g:gnosis_python)
    return
  endif

  " PKM root 配下のファイルのみ対象
  let l:file = expand('%:p')
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    call gnosis#autosync_log('  skip: root=' . l:root . ' index readable=' . (empty(l:root) ? 0 : filereadable(s:index_path(l:root))))
    return
  endif
  if !s:is_root_note_path(l:file)
    call gnosis#autosync_log('  skip: not a root note path (root=' . l:root . ')')
    return
  endif

  " 紙PKM: Index-write を保存したら Index/グループ/Folgezettel-Index を再生成する。
  " paper_pkm.py regen は SYN 同期まで行うので、update_one の代わりに走らせる。
  if fnamemodify(l:file, ':t') ==# 'Index-write.md'
    let l:paper = s:paper_pkm_script()
    if filereadable(l:paper)
      let l:pcmd = s:python_cmd() . ' ' . shellescape(l:paper)
            \ . ' regen ' . shellescape(l:root)
      if has('job') && has('channel')
        call job_start(gnosis#shell_job(l:pcmd), {
              \ 'exit_cb': function('s:autosync_done'),
              \ 'out_io':  'null',
              \ 'err_io':  'null',
              \ })
      else
        call system(l:pcmd)
        checktime
      endif
      return
    endif
  endif

  let l:py   = s:python_cmd()
  let l:args = [l:py, g:gnosis_python, 'update_one', l:file, l:root]
  " タイトルを変えた保存なら、変更前のタイトルを渡す（表示名が旧タイトルと同じ
  " リンクだけ新タイトルへ追従させるため）
  let l:old_title = get(b:, 'syn_prev_title', '')
  let l:new_title = s:fm_title()
  if !empty(l:old_title) && l:old_title !=# l:new_title
    call add(l:args, l:old_title)
  endif
  let b:syn_prev_title = l:new_title

  " index.md は保存しても勝手に並べ替えない（並べ替えは \ua / \S のときだけ）。

  if has('job') && has('channel')
    " 非同期実行
    let l:cmd = join(map(copy(l:args), 'shellescape(v:val)'), ' ')
    call gnosis#autosync_log('  start job: ' . l:cmd)
    call job_start(gnosis#shell_job(l:cmd), {
          \ 'exit_cb': function('s:autosync_done'),
          \ 'out_io':  'null',
          \ 'err_io':  'null',
          \ })
  else
    " 同期フォールバック
    let l:cmd = join(map(copy(l:args), 'shellescape(v:val)'), ' ')
    let l:out = system(l:cmd)
    if !v:shell_error
      checktime
    endif
  endif
endfunction

function! s:autosync_done(job, status) abort
  " job完了後にバッファを外部変更に合わせる
  call gnosis#autosync_log('  job done status=' . a:status)
  call s:reload_current()
endfunction

" 任意のファイルパスに対して update_one を起動するヘルパー
function! s:update_one_command(target_fp, ...) abort
  let l:force = a:0 > 0 ? a:1 : 0
  if !l:force && !g:gnosis_autosync | return '' | endif
  if !filereadable(g:gnosis_python) | return '' | endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    return ''
  endif
  if !s:is_root_note_path(a:target_fp)
    return ''
  endif
  let l:py = s:python_cmd()
  return l:py . ' ' . shellescape(g:gnosis_python)
        \ . ' update_one ' . shellescape(a:target_fp)
        \ . ' ' . shellescape(l:root)
endfunction

function! s:reparent_down_children_for_sync(new_parent_fp, old_parent_fp) abort
  if !g:gnosis_autosync | return | endif
  if !filereadable(g:gnosis_python) | return | endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    return
  endif
  let l:cmd = s:python_cmd() . ' ' . shellescape(g:gnosis_python)
        \ . ' reparent_down_children ' . shellescape(a:new_parent_fp)
        \ . ' ' . shellescape(a:old_parent_fp)
        \ . ' ' . shellescape(l:root)
  let l:out = system(l:cmd)
  if v:shell_error
    echoerr substitute(l:out, '\n\+$', '', '')
    return
  endif
  checktime
endfunction

function! s:run_update_one_for(target_fp) abort
  let l:cmd = s:update_one_command(a:target_fp)
  if empty(l:cmd) | return | endif
  if has('job') && has('channel')
    call job_start(gnosis#shell_job(l:cmd), {
          \ 'exit_cb': function('s:update_one_done', [a:target_fp]),
          \ 'out_io':  'null',
          \ 'err_io':  'null',
          \ })
  else
    call system(l:cmd)
    checktime
  endif
endfunction

function! s:run_update_one_for_sync(target_fp, ...) abort
  let l:force = a:0 > 0 ? a:1 : 0
  let l:cmd = s:update_one_command(a:target_fp, l:force)
  if empty(l:cmd) | return | endif
  let l:out = system(l:cmd)
  if v:shell_error
    echoerr substitute(l:out, '\n\+$', '', '')
    return
  endif
  checktime
endfunction

function! s:write_current_and_sync_now() abort
  if !&modified | return | endif
  let l:file = expand('%:p')
  if empty(l:file)
    silent write
    return
  endif
  let l:autosync = g:gnosis_autosync
  silent write
  " BufWritePost の autosync が非同期で走るので、ここで同期実行しない
  " （sync は Python で全ノートを走査するため、待つと \p などが固まる）。
  " autosync を切っているときだけ、従来どおり強制的に同期する。
  if !l:autosync
    call s:run_update_one_for_sync(l:file, 1)
  endif
endfunction

function! gnosis#save_before_normal_jump(keys) abort
  if &buftype ==# '' && &modifiable && &modified
    let l:file = expand('%:p')
    if empty(l:file)
      echohl ErrorMsg | echom 'Gnosis: file name is empty; cannot auto-save before jump' | echohl None
      return
    endif
    try
      silent update
    catch
      echohl ErrorMsg | echom 'Gnosis: auto-save before jump failed: ' . v:exception | echohl None
      return
    endtry
    if s:is_markdown_file(l:file)
      call s:run_update_one_for_sync(l:file)
    endif
  endif
  execute 'normal! ' . a:keys
endfunction

function! s:update_one_done(target_fp, job, status) abort
  if expand('%:p') ==# a:target_fp
    call s:reload_current()
  else
    checktime
  endif
endfunction

" タイトル変更時は、旧タイトルと一致するリンク文字列だけ新タイトルへ置換する
function! s:run_retitle_links_for_title_change(target_fp, old_title, new_title) abort
  if a:old_title ==# a:new_title
    return
  endif
  if !filereadable(g:gnosis_python)
    return
  endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    return
  endif

  let l:py  = s:python_cmd()
  let l:cmd = l:py . ' ' . shellescape(g:gnosis_python)
        \    . ' retitle_links ' . shellescape(a:target_fp)
        \    . ' ' . shellescape(l:root)
        \    . ' ' . shellescape(a:old_title)
        \    . ' ' . shellescape(a:new_title)

  if has('job') && has('channel')
    call job_start(gnosis#shell_job(l:cmd), {
          \ 'exit_cb': function('s:title_change_update_done'),
          \ 'out_io':  'null',
          \ 'err_io':  'null',
          \ })
  else
    call system(l:cmd)
    checktime
  endif
endfunction

function! s:title_change_update_done(job, status) abort
  call s:reload_current()
endfunction

" ---------------------------------------------------------------------------
" rename_link_text
" ---------------------------------------------------------------------------

function! gnosis#rename_link_text_with_default(default) abort
  let l:link = gnosis#get_link_under_cursor()
  if empty(l:link) || empty(get(l:link, 'target', ''))
    echo 'No link under cursor'
    return
  endif

  let l:new_text = input('new link text: ', a:default)
  if empty(l:new_text)
    echo 'Cancelled'
    return
  endif

  let l:line = getline('.')
  let l:start = l:link.startcol - 1
  let l:raw_end = l:start + strlen(l:link.raw)
  let l:new_raw = '[' . l:new_text . '](' . l:link.target . ')'
  call setline('.', strpart(l:line, 0, l:start) . l:new_raw . strpart(l:line, l:raw_end))
  call cursor(line('.'), l:start + 2)
endfunction

function! gnosis#rename_link_text(args) abort
  let l:link = gnosis#get_link_under_cursor()
  if empty(l:link) || empty(get(l:link, 'target', ''))
    echo 'No link under cursor'
    return
  endif
  let l:default = a:args ==# '' ? l:link.text : a:args
  call gnosis#rename_link_text_with_default(l:default)
endfunction

" ---------------------------------------------------------------------------
" link_to_outline (zo): カーソル下の .md リンク先ノートの見出しを選んで
"   リンク先に #スラッグ（GitHub 互換）を付ける。先頭の「（見出しなし）」で解除。
"   タイトルと同じ H1・システム見出し（Parent/Related/BackLink）は出さない。
"   BackLink は同期が行を作り直すため fragment が消える → 対象外。
" ---------------------------------------------------------------------------

function! s:link_to_outline_apply(frag) abort
  if !exists('s:link_to_outline_ctx')
    return
  endif
  let l:ctx = s:link_to_outline_ctx
  let s:link_to_outline_ctx = {}
  if empty(l:ctx) || !bufexists(l:ctx.buf)
    return
  endif
  let l:lk = l:ctx.link
  let l:new_target = l:ctx.base
  if !empty(a:frag)
    let l:new_target .= '#' . a:frag
  endif
  let l:new_raw = '[' . l:lk.text . '](' . l:new_target . ')'
  execute 'buffer ' . l:ctx.buf
  call setline(l:ctx.lnum, strpart(getline(l:ctx.lnum), 0, l:lk.startcol - 1)
        \ . l:new_raw . strpart(getline(l:ctx.lnum), l:lk.endcol))
  call cursor(l:ctx.lnum, 1)
  if empty(a:frag)
    echo gnosis#i18n#tr('Gnosis: 見出しアンカーを外しました')
  else
    echo 'Gnosis: → #' . a:frag
  endif
endfunction

function! s:link_to_outline_sink(line) abort
  if a:line ==# gnosis#i18n#tr('（見出しなし）')
    call s:link_to_outline_apply('')
  else
    call s:link_to_outline_apply(get(split(a:line, "\t", 1), 1, ''))
  endif
endfunction

" fzf が無いときは inputlist で選ぶ（同じ apply を使う）。
function! s:link_to_outline_fallback(items) abort
  let l:choices = [gnosis#i18n#tr('0: （見出しなし）')]
  let l:i = 1
  for l:it in a:items
    call add(l:choices, l:i . ': ' . repeat('#', l:it.level) . ' ' . l:it.text)
    let l:i += 1
  endfor
  let l:sel = inputlist(l:choices)
  if l:sel <= 0
    let s:link_to_outline_ctx = {}
    return
  endif
  if l:sel == 1
    call s:link_to_outline_apply('')
  else
    call s:link_to_outline_apply(a:items[l:sel - 2].slug)
  endif
endfunction

function! gnosis#link_to_outline(...) abort
  let l:lk = gnosis#get_link_under_cursor()
  if empty(l:lk) || empty(l:lk.target) || l:lk.target !~? '\.md\(#.*\)\?$'
    echo gnosis#i18n#tr('Gnosis: カーソル下に .md リンクがありません')
    return
  endif
  if s:in_back_section(line('.'))
    echohl WarningMsg
    echo gnosis#i18n#tr('Gnosis: BackLink は同期で作り直されるため見出しリンクにできません')
    echohl None
    return
  endif
  let l:path = s:resolve_link_for_navigation(s:link_base(l:lk.target))
  if !filereadable(l:path)
    echohl WarningMsg | echo gnosis#i18n#tr('見つかりません: ') . l:path | echohl None
    return
  endif
  let s:link_to_outline_ctx = {
        \ 'buf': bufnr('%'),
        \ 'lnum': line('.'),
        \ 'link': l:lk,
        \ 'base': s:link_base(l:lk.target),
        \ }
  if a:0 > 0
    " 非対話版（テスト・自動化用）: 引数のスラッグをそのまま付ける（空で解除）
    call s:link_to_outline_apply(a:1)
    return
  endif
  let l:items = s:file_heading_items(l:path)
  if empty(l:items)
    let s:link_to_outline_ctx = {}
    echo gnosis#i18n#tr('Gnosis: 見出しがありません: ') . fnamemodify(l:path, ':t')
    return
  endif
  if !exists('*fzf#run')
    call s:link_to_outline_fallback(l:items)
    return
  endif
  call s:outline_fzf(l:items, l:path, function('s:link_to_outline_sink'), 1)
endfunction

" ---------------------------------------------------------------------------
" rename_title (:NT)
" ---------------------------------------------------------------------------

function! gnosis#rename_title_with_default(default) abort
  let l:old_title = gnosis#current_title()
  let l:title = input('new title: ', a:default)

  if empty(l:title)
    echo 'Cancelled'
    return
  endif

  let l:lines = getline(1, '$')
  let l:yaml_start = -1
  let l:yaml_end   = -1
  for l:i in range(len(l:lines))
    if l:lines[l:i] ==# '---'
      if l:yaml_start < 0
        let l:yaml_start = l:i
      else
        let l:yaml_end = l:i
        break
      endif
    endif
  endfor

  if l:yaml_start == 0 && l:yaml_end > 0
    let l:done = 0
    for l:i in range(l:yaml_start + 1, l:yaml_end - 1)
      if l:lines[l:i] =~# '^title:\s*'
        let l:lines[l:i] = 'title: ' . l:title
        let l:done = 1
        break
      endif
    endfor
    if !l:done
      call insert(l:lines, 'title: ' . l:title, l:yaml_start + 1)
    endif
  else
    let l:header = ['---', 'time: ' . gnosis#timestamp_yaml(),
          \ 'title: ' . l:title, '---', '']
    let l:lines = l:header + l:lines
  endif

  " H1 も更新
  let l:found_h1 = 0
  for l:i in range(len(l:lines))
    if l:lines[l:i] =~# '^#\s\+'
      let l:lines[l:i] = '# ' . l:title
      let l:found_h1 = 1
      break
    endif
  endfor
  if !l:found_h1
    call add(l:lines, '# ' . l:title)
  endif

  call setline(1, l:lines)
  if len(l:lines) < line('$')
    execute (len(l:lines) + 1) . ',$delete _'
  endif
  write
  call gnosis#clear_title_cache()
  call s:run_retitle_links_for_title_change(expand('%:p'), l:old_title, l:title)
endfunction

function! gnosis#rename_title(args) abort
  let l:default = a:args ==# '' ? gnosis#current_title() : a:args
  call gnosis#rename_title_with_default(l:default)
endfunction

" ---------------------------------------------------------------------------
" create_note (internal)
" ---------------------------------------------------------------------------

function! gnosis#create_note(prefix, title, open_after, insert_mode) abort
  let l:root = gnosis#ensure_root_and_index()
  if empty(l:root)
    return {}
  endif
  let l:dir = expand('%:p:h')
  if empty(l:dir)
    let l:dir = l:root
  endif
  let l:fname = a:prefix . '_' . gnosis#timestamp_filename() . '.md'
  let l:file  = l:dir . s:sep() . l:fname
  if filereadable(l:file)
    echoerr 'File already exists: ' . l:file
    return {}
  endif

  let l:parent_file  = expand('%:p')
  let l:parent_title = gnosis#current_title()

  if a:insert_mode ==# 'branch' && s:structural_link_append_line() <= 0
    echoerr 'Gnosis: Child: section not found'
    return {}
  endif

  let l:tmpl = gnosis#note_template(a:title, a:prefix)
  if filereadable(l:parent_file)
    let l:parent_link = s:make_link_from_dir(l:parent_file, l:parent_title, l:dir)
    let l:up_idx = s:find_section_index_in_lines(l:tmpl, 'up')
    if l:up_idx >= 0
      call insert(l:tmpl, l:parent_link, l:up_idx + 1)
    else
      call insert(l:tmpl, l:parent_link, len(l:tmpl) - 1)
    endif
  endif
  call s:syn_writefile(l:tmpl, l:file)

  let l:link = gnosis#make_link(l:file, a:title)
  let l:save_ai = &autoindent
  let l:save_si = &smartindent
  setlocal noautoindent nosmartindent
  if a:insert_mode ==# 'branch'
    let l:ins = s:structural_link_append_line()
    call append(l:ins, l:link)
    silent write
    call s:run_update_one_for_sync(expand('%:p'))
  elseif a:insert_mode ==# 'cursor'
    call append(line('.'), l:link)
    silent write
    call s:run_update_one_for_sync(expand('%:p'))
  endif
  let &autoindent = l:save_ai
  let &smartindent = l:save_si

  if a:open_after
    call gnosis#push_history()
    execute 'edit ' . fnameescape(l:file)
    let &autoindent = l:save_ai
    let &smartindent = l:save_si

    startinsert
    call cursor(s:new_note_insert_line(), 9)
  endif

  return {'path': l:file, 'link': l:link}
endfunction


" ---------------------------------------------------------------------------
" :NC - New Child (常に C プレフィックス、タイトルのみ入力)
" ---------------------------------------------------------------------------

function! gnosis#new_child(args) abort
  try
    let l:title = input('title: ', a:args)
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return
  endtry
  if empty(l:title)
    let l:title = gnosis#timestamp_filename()
  endif
  call gnosis#create_note('C', l:title, 1, 'branch')
endfunction

" ---------------------------------------------------------------------------
" :NF / :NA - 現在ファイルと同ディレクトリに F_ / A_ ノートを作成し
"             現在ファイルの 本文末尾に追加する
" ---------------------------------------------------------------------------

function! gnosis#new_here_typed(prefix) abort
  try
    let l:title = input('title: ')
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return
  endtry
  if empty(l:title)
    let l:title = gnosis#timestamp_filename()
  endif
  call gnosis#create_note(a:prefix, l:title, 1, 'branch')
endfunction

" ---------------------------------------------------------------------------
" タイトル入力なし、o/b/h選択あり (nf / mm / nk 共通内部実装, Enter=ChildLast)

" ---------------------------------------------------------------------------


function! s:trim_blank_edges(lines) abort
  let l:out = copy(a:lines)
  while !empty(l:out) && trim(l:out[0]) ==# ''
    call remove(l:out, 0)
  endwhile
  while !empty(l:out) && trim(l:out[-1]) ==# ''
    call remove(l:out, -1)
  endwhile
  return l:out
endfunction

function! s:new_note_no_title(prefix) abort
  if s:pkm_format() ==# 'v2'
    call gnosis#v2_new_child()
    return
  endif
  let l:parent_line  = line('.')
  let l:parent_path  = expand('%:p')
  let l:parent_dir   = expand('%:p:h')
  let l:parent_title = gnosis#current_title()
  let l:filetype = toupper(a:prefix)
  let l:is_k = (l:filetype ==# 'K')
  let l:timestamp = gnosis#timestamp_filename()
  let l:title = l:timestamp

  if l:is_k
    try
      let l:title = input('title: ')
    catch /^Vim:Interrupt$/
      echo 'Cancelled'
      return
    endtry
    if empty(l:title)
      let l:title = l:timestamp
    endif
  endif

  echon 'mode: (O)rphan (B)ack (H)=cursor Enter=ChildLast: '

  let l:char = getchar()
  redraw

  " Esc or Ctrl-C でキャンセル
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:mode = nr2char(l:char)

  let l:insert_at_cursor = 0
  let l:insert_at_down_end = 0
  let l:no_parent_link   = 0
  let l:reverse_link     = 0

  if l:mode =~? '^o$'
    let l:no_parent_link = 1
  elseif l:mode =~? '^b$'
    let l:reverse_link = 1
  elseif l:mode =~? '^h$'
    let l:insert_at_cursor = 1
  else
    let l:insert_at_down_end = 1
  endif

  let l:no_prefix_name = (l:filetype ==# 'N')
  let l:fname = l:is_k
        \ ? (l:timestamp . '.md')
        \ : (l:no_prefix_name ? (l:title . '.md') : (a:prefix . '_' . l:title . '.md'))
  let l:dir   = s:cwd_note_dir()
  let l:file  = s:join_path(l:dir, l:fname)
  let l:link  = s:make_link_from_dir(l:file, l:title, l:parent_dir)

  if !l:no_parent_link && !l:reverse_link && !l:insert_at_cursor && s:structural_link_append_line() <= 0
    echoerr 'Gnosis: Child: section not found'
    return
  endif

  if !l:no_parent_link && !l:reverse_link
    let l:save_ai = &autoindent
    let l:save_si = &smartindent
    setlocal noautoindent nosmartindent
    if l:insert_at_cursor
      if !s:link_already_present_in_branch(l:link)
        call append(l:parent_line, l:link)
      endif
    elseif l:insert_at_down_end
      call s:append_structural_link_to_buffer(l:link)
    else
      if a:prefix ==? 'N'
        let l:ins = s:structural_link_prepend_line()
        if !s:link_already_present_in_branch(l:link)
          call append(l:ins, l:link)
        endif
      else
        call s:append_structural_link_to_buffer(l:link)
      endif
    endif
    let &autoindent = l:save_ai
    let &smartindent = l:save_si
    silent noautocmd write
  endif

  let l:parent_link_lines = s:parent_link_lines(l:parent_path, l:parent_title, l:dir)

  if l:reverse_link
    if l:is_k
      let l:content = s:k_note_template(l:title)
      let l:cursor_line = 7
    else
      " b モード: 新ノートの Child に現在ノートへのリンクを入れる
      " # title / (空) / Parent / Child / [親リンク] / Back / [index]
      let l:content = [
            \ '---',
            \ 'time: ' . gnosis#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ '',
            \ '',
            \ s:canonical_section_title('up'),
            \ s:canonical_section_title('down'),
          \ ] + l:parent_link_lines + [
            \ s:canonical_section_title('backlink'),
            \ '[Index](index.md)' ]
    endif
    if !l:is_k
      let l:cursor_line = 8
    endif
  elseif l:is_k
    " nk の h/Enter/o モード: 見出しのみ作成
    let l:content = s:k_note_template(l:title)
    let l:cursor_line = 7
  else
    " mm/nf の h/Enter/o モード: 従来どおり
    let l:content = [
          \ '---',
          \ 'time: ' . gnosis#timestamp_yaml(),
          \ 'title: ' . l:title,
          \ '---',
          \ '',
          \ '# ' . l:title,
          \ '',
          \ '',
          \ '',
          \ s:canonical_section_title('up'),
        \ ] + l:parent_link_lines + [
          \ s:canonical_section_title('down'),
          \ s:canonical_section_title('backlink'),
          \ '[Index](index.md)' ]
    let l:cursor_line = 8
  endif

  call s:write_new_note(l:content, l:file)

  " 通常モード: 新ノート作成前はリンク先が未存在のため、作成後に親の本文リンクを同期する
  " mm/nf/nk の体感速度を優先し、重い update_one は非同期で走らせる。
  if !l:no_parent_link && !l:reverse_link
    call s:run_update_one_for(expand('%:p'))
  endif

  " bモード: 新ノートの Child を元に Parent/BackLink を同期
  if l:reverse_link
    call s:run_update_one_for(l:file)
  endif

  if &modified
    try
      silent noautocmd write
    catch
      echohl ErrorMsg
      echom 'Error: could not save current buffer; new note was created but not opened: ' . l:fname
      echohl None
      return
    endtry
  endif

  call gnosis#push_history()
  execute 'edit ' . fnameescape(l:file)

  startinsert
  call cursor(l:cursor_line, 9)
endfunction

" ---------------------------------------------------------------------------
" ビジュアル選択範囲を新ノートに切り出す (mm / nf / nk のビジュアル版)
"
" 動作:
"   - 選択範囲のテキストを取得して削除（元ファイルから cut）
"   - 新ノートファイルに YAML + # title + 空行 + 切り出しテキスト を書き込む
"   - bモードのときは選択テキストの代わりにリンクだけ残す（本文なし）
"   - 画面（カーソル位置・スクロール）は元のまま動かさない
" ---------------------------------------------------------------------------

function! s:visual_new_note(prefix, mode, ...) abort
  " ビジュアル選択の範囲を取得（'< と '> マーク）
  let l:vstart = line("'<")
  let l:vend   = line("'>")
  if l:vstart <= 0 || l:vend <= 0 || l:vstart > l:vend
    echo 'No visual selection'
    return
  endif

  let l:sel_lines = getline(l:vstart, l:vend)

  let l:parent_path  = expand('%:p')
  let l:parent_dir   = expand('%:p:h')
  let l:parent_title = gnosis#current_title()
  let l:dir          = s:cwd_note_dir()

  let l:timestamp = gnosis#timestamp_filename()
  let l:title = (a:0 >= 1 && !empty(a:1)) ? a:1 : l:timestamp
  let l:filetype = toupper(a:prefix)
  let l:no_prefix_name = (l:filetype ==# 'N')
  let l:fname = (l:filetype ==# 'K')
        \ ? (l:timestamp . '.md')
        \ : (l:no_prefix_name ? (l:title . '.md') : (a:prefix . '_' . l:title . '.md'))
  let l:file  = s:join_path(l:dir, l:fname)
  let l:parent_link_lines = s:parent_link_lines(l:parent_path, l:parent_title, l:dir)
  let l:link_to_new      = s:make_link_from_dir(l:file, l:title, l:parent_dir)

  let l:is_b = (a:mode ==? 'b')
  let l:is_k = (a:prefix ==? 'K')

  " 新ファイルの内容を組み立てる
  if l:is_b
    " bモード: 選択テキストは新ファイルに移す、Back セクションに親リンク
    if l:is_k
      let l:content = s:k_note_template_with_down(l:title, l:sel_lines)
    else
      let l:content = [
            \ '---',
            \ 'time: ' . gnosis#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ '',
            \ '',
            \ s:canonical_section_title('up'),
          \ ] + l:parent_link_lines + [
            \ s:canonical_section_title('down'),
            \ s:canonical_section_title('backlink'),
            \ '[Index](index.md)' ]
    endif
    if !l:is_k
      " 選択テキストを本文（Back の直前）に挿入
      let l:back_idx = s:find_section_index_in_lines(l:content, 'back')
      " Back の前に空行 + 選択テキストを差し込む
      let l:insert_pos = l:back_idx
      call extend(l:content, l:sel_lines, l:insert_pos)
    endif
  else
    " o / Enter モード: 本文に選択テキストを配置
    if l:is_k
      let l:content = s:k_note_template_with_down(l:title, l:sel_lines)
    else
      let l:content = [
            \ '---',
            \ 'time: ' . gnosis#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '' ]
      call extend(l:content, l:sel_lines)
      call add(l:content, '')
      call add(l:content, '')
      call add(l:content, '')
      call add(l:content, s:canonical_section_title('up'))
      call extend(l:content, l:parent_link_lines)
      call add(l:content, s:canonical_section_title('down'))
      call add(l:content, s:canonical_section_title('backlink'))
      call add(l:content, '[Index](index.md)')
    endif
  endif

  call s:write_new_note(l:content, l:file)

  " ---- 元ファイルの選択範囲を置き換える ----
  " スクロール位置・カーソルを保存
  let l:save_view = winsaveview()
  let l:save_pos  = getpos('.')

  let l:save_ai = &autoindent
  let l:save_si = &smartindent
  setlocal noautoindent nosmartindent

  " 選択範囲をリンク1行に置き換える（全モード共通）
  execute l:vstart . ',' . l:vend . 'delete _'
  call append(l:vstart - 1, l:link_to_new)
  " カーソルはリンク行の次行（元の選択終端の次）
  let l:cursor_line = l:vstart + 1

  if l:is_b
    " bモード: 親の Back セクション直後にも逆リンクを追記
    let l:parent_fp = l:parent_path
    if filereadable(l:parent_fp)
      let l:plines = readfile(l:parent_fp)
      let l:back_idx2 = -1
      for l:i in range(0, len(l:plines) - 1)
        if s:is_section_header_text(l:plines[l:i], 'back')
          let l:back_idx2 = l:i
          break
        endif
      endfor
      if index(l:plines, l:link_to_new) < 0
        if l:back_idx2 < 0
          call add(l:plines, '')
          call add(l:plines, s:canonical_section_title('backlink'))
          call add(l:plines, '[Index](index.md)')
          let l:back_idx2 = len(l:plines) - 2
        endif
        call insert(l:plines, l:link_to_new, l:back_idx2 + 1)
        call s:syn_writefile(l:plines, l:parent_fp)
        call s:run_update_one_for(l:parent_fp)
      endif
    endif
  endif

  let &autoindent = l:save_ai
  let &smartindent = l:save_si

  " スクロール位置は保持、カーソルはリンク行の次行へ
  call winrestview(l:save_view)
  let l:cursor_line = min([l:cursor_line, line('$')])
  call cursor(l:cursor_line, 1)

  silent noautocmd write
  call s:reparent_down_children_for_sync(l:file, l:parent_path)
  call s:run_update_one_for(expand('%:p'))
  call s:run_update_one_for(l:file)

  redraw | echon 'Created: ' . l:fname
endfunction

" ビジュアル選択から nf / mm / nk を呼ぶエントリポイント
function! gnosis#visual_new_quick_no_title() abort
  echo 'prefix (a-z): '
  let l:char = getchar()
  redraw
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:ch = nr2char(l:char)
  if l:ch !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  call s:visual_select_mode(toupper(l:ch))
endfunction

function! gnosis#visual_new_prefix_note(prefix) abort
  call s:visual_select_mode(a:prefix)
endfunction

function! s:visual_select_mode(prefix) abort
  let l:title = ''
  if a:prefix ==? 'K'
    try
      let l:title = input('title: ')
    catch /^Vim:Interrupt$/
      echo 'Cancelled'
      return
    endtry
  endif

  echon 'mode: (O)rphan (B)ack (H)=cursor Enter=ChildLast: '

  let l:char = getchar()
  redraw
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:mode = nr2char(l:char)
  if a:prefix ==? 'K'
    call s:visual_new_note(a:prefix, l:mode, l:title)
  else
    call s:visual_new_note(a:prefix, l:mode)
  endif
endfunction

" nf用: prefix入力 → o/b/h選択（Enter=ChildLast）

function! gnosis#new_quick_no_title() abort
  echo 'prefix (a-z): '
  let l:char = getchar()
  redraw
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:ch = nr2char(l:char)
  if l:ch !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  call s:new_note_no_title(toupper(l:ch))
endfunction

" mm / nk用: prefix固定 → o/b/h選択（Enter=ChildLast）

function! gnosis#new_prefix_note(prefix) abort
  call s:new_note_no_title(a:prefix)
endfunction

" ---------------------------------------------------------------------------
" :NQ - Quick new child (旧 QuickNewChildWithMode に忠実)
"   1. プレフィックス1文字入力（即時確定）
"   2. タイトル入力
"   3. モード選択: (O)rphan / (B)ack / (H)=cursor / Enter=ChildLast

" ---------------------------------------------------------------------------

function! gnosis#new_quick(args) abort
  if s:pkm_format() ==# 'v2'
    call gnosis#v2_new_child()
    return
  endif
  let l:parent_bufnr = bufnr('%')
  let l:parent_line = line('.')
  let l:parent_file  = expand('%:t')
  let l:parent_title = gnosis#current_title()

  echo 'prefix (a-z): '
  let l:raw = getchar()
  redraw
  if l:raw == 27 || l:raw == 3
    echo 'Cancelled'
    return
  endif
  let l:char = nr2char(l:raw)
  if l:char !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  let l:prefix = toupper(l:char)

  let l:title = input('title: ', a:args)

  echon "\nmode: (O)rphan (B)ack (H)=cursor Enter=ChildLast: "

  let l:raw2 = getchar()
  redraw
  if l:raw2 == 27 || l:raw2 == 3
    echo 'Cancelled'
    return
  endif
  let l:mode = nr2char(l:raw2)

  let l:insert_at_cursor = 0
  let l:insert_at_down_end = 0
  let l:no_parent_link   = 0
  let l:reverse_link     = 0

  if l:mode =~? '^o$'
    let l:no_parent_link = 1
  elseif l:mode =~? '^b$'
    let l:reverse_link = 1
  elseif l:mode =~? '^h$'
    let l:insert_at_cursor = 1
  else
    let l:insert_at_down_end = 1
  endif

  if empty(l:title)
    let l:title = gnosis#timestamp_filename()
  endif

  let l:fname = l:prefix . '_' . gnosis#timestamp_filename() . '.md'
  let l:dir   = expand('%:p:h')
  let l:file  = l:dir . s:sep() . l:fname
  let l:link = gnosis#make_link(l:fname, l:title)

  if !l:no_parent_link && !l:reverse_link && !l:insert_at_cursor && s:structural_link_append_line() <= 0
    echoerr 'Gnosis: Child: section not found'
    return
  endif

  if !l:no_parent_link && !l:reverse_link
    let l:save_ai = &autoindent
    let l:save_si = &smartindent
    setlocal noautoindent nosmartindent
    if l:insert_at_cursor
      call append(l:parent_line, l:link)
    elseif l:insert_at_down_end
      let l:ins = s:structural_link_append_line()
      call append(l:ins, l:link)
    else
      let l:ins = s:structural_link_append_line()
      call append(l:ins, l:link)
    endif
    let &autoindent = l:save_ai
    let &smartindent = l:save_si
    silent noautocmd write
  endif

  let l:parent_link_lines = s:parent_link_lines(l:parent_file, l:parent_title, l:dir)
  let l:is_k = (l:prefix ==? 'K')

  if l:reverse_link
    if l:is_k
      let l:content = s:k_note_template(l:title)
      let l:cursor_line = 7
    else
      let l:content = [
            \ '---',
            \ 'time: ' . gnosis#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ '',
            \ '',
            \ s:canonical_section_title('up'),
          \ ] + l:parent_link_lines + [
            \ s:canonical_section_title('down'),
            \ s:canonical_section_title('backlink'),
            \ '[Index](index.md)' ]
    endif
    if !l:is_k
      let l:cursor_line = 8
    endif
  elseif l:is_k
    let l:content = s:k_note_template(l:title)
    let l:cursor_line = 7
  else
    let l:content = [
          \ '---',
          \ 'time: ' . gnosis#timestamp_yaml(),
          \ 'title: ' . l:title,
          \ '---',
          \ '',
          \ '# ' . l:title,
          \ '',
          \ '',
          \ '',
          \ s:canonical_section_title('up'),
        \ ] + l:parent_link_lines + [
          \ s:canonical_section_title('down'),
          \ s:canonical_section_title('backlink'),
          \ '[Index](index.md)' ]
    let l:cursor_line = 8
  endif

  call s:write_new_note(l:content, l:file)

  " 通常モード: 新ノート作成前はリンク先が未存在のため、作成後に親の本文リンクを同期する
  " mm/nf/nk の体感速度を優先し、重い update_one は非同期で走らせる。
  if !l:no_parent_link && !l:reverse_link
    call s:run_update_one_for(expand('%:p'))
  endif

  " bモード: 親ファイルの Back セクション直後に新ノートへのリンクを追記してsync
  if l:reverse_link
    " ディスクとバッファの不一致を防ぐため先に保存
    if &modified
      silent noautocmd write
    endif
    let l:new_link = gnosis#make_link(l:fname, l:title)
    let l:parent_fp = l:dir . s:sep() . l:parent_file
    if filereadable(l:parent_fp)
      let l:plines = readfile(l:parent_fp)
      let l:back_idx = -1
      for l:i in range(0, len(l:plines) - 1)
        if s:is_section_header_text(l:plines[l:i], 'back')
          let l:back_idx = l:i
          break
        endif
      endfor
      if index(l:plines, l:new_link) < 0
        if l:back_idx < 0
          call add(l:plines, '')
          call add(l:plines, s:canonical_section_title('backlink'))
          call add(l:plines, '[Index](index.md)')
          let l:back_idx = len(l:plines) - 2
        endif
        call insert(l:plines, l:new_link, l:back_idx + 1)
        call s:syn_writefile(l:plines, l:parent_fp)
        call s:run_update_one_for(l:parent_fp)
      endif
    endif
  endif

  if &modified
    try
      silent noautocmd write
    catch
      echohl ErrorMsg
      echom 'Error: could not save current buffer; new note was created but not opened: ' . l:fname
      echohl None
      return
    endtry
  endif

  call gnosis#push_history()
  execute 'edit ' . fnameescape(l:file)

  startinsert
  call cursor(l:cursor_line, 9)
endfunction


" ---------------------------------------------------------------------------
" :CA - Create Atomic note (本文末尾に追加、新ファイルを開く)
" ---------------------------------------------------------------------------

function! gnosis#create_atomic(args) abort
  let l:prefix = g:gnosis_default_atomic_prefix
  let l:prefix = toupper(input('prefix [' . l:prefix . ']: ', l:prefix))
  if empty(l:prefix) | let l:prefix = g:gnosis_default_atomic_prefix | endif
  let l:title = input('title: ', a:args)
  if empty(l:title) | echo 'Cancelled' | return | endif
  call gnosis#create_note(l:prefix, l:title, 1, 'branch')
endfunction


" ---------------------------------------------------------------------------
" :BC - Add from clipboard before Back
" ---------------------------------------------------------------------------

function! gnosis#add_from_clipboard(...) abort
  if s:pkm_format() ==# 'v2'
    call gnosis#v2_add_link(a:0 > 0 ? a:1 : '')
    return
  endif
  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:insert_at_cursor = 0
  for l:arg in a:000
    if l:arg ==# 'here'
      let l:insert_at_cursor = 1
    endif
  endfor

  let l:links = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    let l:path = gnosis#resolve_link(l:target)
    if !filereadable(l:path)
      echo 'Warning: not found: ' . l:target
      continue
    endif
    let l:link = s:link_from_target(l:target)
    if !empty(l:link)
      call add(l:links, l:link)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  if l:insert_at_cursor
    let l:ins = line('.')
    for l:lk in reverse(copy(l:links))
      call append(l:ins, l:lk)
    endfor
  else
    let l:ins = s:structural_link_append_line()
    if l:ins <= 0
      echo 'Error: child section not found'
      return
    endif
    for l:lk in l:links
      call append(l:ins, l:lk)
      let l:ins += 1
    endfor
  endif
  call s:realtime_sync_apply()
  silent write
  echo 'Added ' . len(l:links) . ' link(s)'
endfunction

" 本文中の連続する空行を 1 行に潰す（テンプレートの余白 2 行を 1 行にする）。
" 見出し行は残す。`### Context` より上だけを対象にする。
function! s:squeeze_body_blanks() abort
  " 空行の連続（2 行以上）を 1 行に潰す。`### Context` より上が対象。
  " テンプレートの余白 2 行を 1 行にして、本文リンクが中央に 1 つだけ見えるようにする。
  let l:up = s:find_section_line('up')
  let l:end = (l:up > 0) ? l:up - 1 : line('$')
  let l:changes = 0
  let l:i = 2
  while l:i <= l:end
    if trim(getline(l:i)) ==# '' && trim(getline(l:i - 1)) ==# ''
      execute l:i . 'delete _'
      let l:end -= 1
      let l:changes += 1
      continue
    endif
    let l:i += 1
  endwhile
  return l:changes
endfunction

" ### Context の直前の行が本文（空行でない）なら、空行を 1 つ足す。
" リンクを本文に置いたときの見た目を「本文 / 空行 / ### Context」に揃える。
function! s:ensure_blank_before_up() abort
  " `### Context` の直前の行が**散文**のときだけ空行を 1 つ足す。
  " リンク行で終わっているときは空行を挟まない（リンク群と `### Context` をくっつけたまま）。
  " 既に空行があれば足さない。
  let l:up = s:first_section_line()
  if l:up <= 1
    return 0
  endif
  let l:prev = trim(getline(l:up - 1))
  if l:prev ==# ''
    return 0
  endif
  if l:prev =~# '\]\s*(\S\+)\s*$'
    return 0
  endif
  call append(l:up - 1, '')
  return 1
endfunction

" リンクを「どこに置くか」を 1 文字で選ばせる（h / Enter / p / r。zn と同じ約束）。
"   h     … カーソル行の直下（本文）
"   Enter … 本文の最後（### Context の直前）
"   p     … 今のノートの ### Context 末尾（相手が親になる）
"   r     … ### Related へ（今のノートと相手の両方に相互追加）
" Esc / q / o は「何も置かない」で終わる。
" za,p: 今のノートの本文の中、### Context の直前にリンクを入れる。文中に同じリンクが既にあれば入れない。
" 入れたら、相手（リンク先）の本文の ### Context の直前にも、今のノートへのリンクを入れる。

" a:links を置き場所キーで今のノートに入れる。a:1 に Funcref（Done）を渡すと t（見出しの下）
" が使える: 見出しの選択は非同期なので、入れ終わったあとの処理は Done を選択後に呼ぶ。
" 戻り値は追加できたか（0/1）。t のときだけ -1（選択待ち。Done は選択後に呼ばれる）。
function! s:insert_links_core(links, ...) abort
  let l:links = a:links
  if empty(l:links)
    return 0
  endif
  let l:inline = !empty(get(s:, 'inline_pos', []))
  echo gnosis#i18n#tr('h=カーソル直下 / Enter=本文の最後 / ')
        \ . (a:0 > 0 ? gnosis#i18n#tr('t=見出しの下 / ') : '')
        \ . (l:inline ? gnosis#i18n#tr('i=カーソル位置 / n=表示名を入力して本文の最後 / ') : '')
        \ . gnosis#i18n#tr('c=Context末尾 / r=Related  (Esc で取り止め)')
  let l:ch = s:getkey()
  redraw
  let l:num = char2nr(l:ch)
  if l:ch ==? 'q' || l:num == 27 || l:num == 3
    echo gnosis#i18n#tr('Gnosis: 何も追加しない')
    return 0
  endif
  if l:ch ==? 't' && a:0 > 0
    call s:outline_pick_here(function('s:insert_links_under_heading', [l:links, a:1]))
    return -1
  endif
  if l:ch ==? 'p'
    echo gnosis#i18n#tr('Gnosis: 位置キー p は c（Context 末尾）に変わりました。何も追加しません')
    return 0
  endif
  if l:ch ==# 'n' && l:inline
    " \l → n: 表示名を入力して、今のノートの本文の最後へ入れる（入力欄は空から。
    " 空 Enter = リンク先ノートのタイトル、Esc = 取り消し）。ノートのタイトルは変えない。
    let l:added = 0
    for l:lk in l:links
      let l:tg = s:extract_target(l:lk)
      let l:fp = gnosis#resolve_link(substitute(l:tg, '#.*$', '', ''))
      let l:title = s:get_title(l:fp)
      if empty(l:title)
        let l:title = get(s:extract_markdown_link(l:lk), 'text', fnamemodify(l:fp, ':t:r'))
      endif
      let l:r = s:ask_display_name(l:title)
      if !l:r.ok
        echo 'Gnosis: ' . gnosis#i18n#tr('取り消しました（何も変更していません）')
        return 0
      endif
      let l:named = '[' . s:md_link_text(l:r.name) . '](' . l:tg . ')'
      if s:insert_link_before_up_note(l:named)
        let l:added += 1
      else
        echo 'Gnosis: ' . gnosis#i18n#tr('このノートには既にそのリンクがあります')
      endif
    endfor
    if l:added
      call s:ensure_blank_before_up()
    endif
    return l:added > 0
  endif
  if l:ch ==? 'i' && l:inline
    " ピッカーを開いたときのカーソル位置に、行の中へそのまま入れる（従来の \l）
    call cursor(s:inline_pos[1], s:inline_pos[2])
    let l:text = join(l:links, ' ')
    let l:cur = getline('.')
    let l:col = col('.') - 1
    call setline('.', strpart(l:cur, 0, l:col) . l:text . strpart(l:cur, l:col))
    call cursor(line('.'), l:col + strlen(l:text) + 1)
    return 1
  endif
  if l:ch ==? 'c'
    " 今のノートの ### Context 末尾に置く（相手が親になる）。zn / zk の c と同じ。
    " そのあと、相手（リンク先）に今のノートへのリンクをどう入れるか（Enter / t / o）を
    " リンクごとに聞いてから、まとめて書く（Esc なら何も書かない）。
    let l:Done = a:0 > 0 ? a:1 : function('s:noop')
    call s:c_mode_chain(l:links, 0, [], {'path': expand('%:p'), 'buf': bufnr('%'),
          \ 'title': gnosis#current_title()}, l:Done)
    return -1
  endif
  if l:ch ==? 'r'
    " ### Related に相互追加: 今のノートの Related に相手、相手ノートの
    " Related に今のノート（対称）。sync は Related を勝手に作らないので、
    " ここで初めてセクションが生まれる。
    let l:cur = expand('%:p')
    if empty(l:cur)
      echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 名前付きファイルで実行して') | echohl None
      return 0
    endif
    let l:cur_title = gnosis#current_title()
    let l:added = 0
    for l:lk in l:links
      let l:tgt = gnosis#resolve_link(s:extract_target(l:lk))
      if empty(l:tgt) || !filereadable(l:tgt)
        echo 'Warning: not found: ' . s:extract_target(l:lk)
        continue
      endif
      if s:append_related_to_buffer(l:lk)
        let l:added += 1
      endif
      call s:simple_add_related(l:tgt, l:cur, l:cur_title)
    endfor
    if l:added == 0
      echo gnosis#i18n#tr('Gnosis: Related は変更なし（既に追加済み）')
    endif
    return l:added > 0
  endif
  if l:ch ==? 'h'
    let l:ins = line('.')
    for l:lk in reverse(copy(l:links))
      if s:buffer_has_link(l:lk)
        continue
      endif
      call append(l:ins, l:lk)
      let l:ins += 1
    endfor
    return 1
  endif
  " 既定（Enter）: 本文の最後 = ### Context の直前
  let l:added = 0
  for l:lk in l:links
    if s:insert_link_before_up_note(l:lk)
      let l:added += 1
    endif
  endfor
  if l:added
    call s:ensure_blank_before_up()
  endif
  return l:added > 0
endfunction

" 見出しが選ばれたあと: その見出しの本文の最後にリンクを入れ、Done を呼ぶ。
function! s:insert_links_under_heading(links, Done, lnum) abort
  for l:lk in a:links
    if !s:buffer_has_link(l:lk)
      call s:insert_link_under_heading(a:lnum, l:lk)
    endif
  endfor
  call a:Done()
endfunction

" a:Done があれば、入れ終わったあと（t のときは見出しを選んだあと）に呼ぶ。
function! s:insert_links_at_position(links, ...) abort
  if a:0 == 0
    return s:insert_links_core(a:links)
  endif
  let l:r = s:insert_links_core(a:links, a:1)
  if l:r != -1
    call a:1()
  endif
  return l:r > 0
endfunction

function! gnosis#paste_clipboard_link_here() abort
  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:links = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    " md ファイルは存在チェックあり、非md（.svc 等）は存在チェックなしでリンク化
    if s:is_markdown_target(l:target)
      let l:path = gnosis#resolve_link(l:target)
      if !filereadable(l:path)
        echo 'Warning: not found: ' . l:target
        continue
      endif
    endif
    let l:link = s:link_from_target(l:target)
    if !empty(l:link)
      call add(l:links, l:link)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  let l:ins = line('.')
  for l:lk in reverse(copy(l:links))
    call append(l:ins, l:lk)
  endfor
  call s:write_current_and_sync_now()
endfunction

function! gnosis#add_clipboard_to_branch() abort
  if s:pkm_format() ==# 'v2'
    call gnosis#v2_add_link()
    return
  endif
  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:links = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    let l:path = gnosis#resolve_link(l:target)
    if !filereadable(l:path)
      echo 'Warning: not found: ' . l:target
      continue
    endif
    let l:link = s:link_from_target(l:target)
    if !empty(l:link)
      call add(l:links, l:link)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  let l:added = 0
  for l:lk in l:links
    if s:append_link_to_buffer_section('up', l:lk)
      let l:added += 1
    endif
  endfor
  call s:realtime_sync_apply()
  silent write
  echo 'Context added ' . l:added . ' link(s)'
endfunction


" 本文中（`### Context` の直前の行）にリンクを足す。simple 形式では
" 「子」は本文リンクなので、BackLink 側ではなくここに入れる。
" 行 a:lnum が、日記の「今日のノート」の節の中のリンク行か（直近の見出しがその節）。
" za / zn の Enter で入れるリンクを、一覧と空行 1 つ空けて区別するために使う。
function! s:in_diary_list(lnum) abort
  if a:lnum < 1 || trim(getline(a:lnum)) !~# '\]\s*(\S\+)\s*$'
    return 0
  endif
  let l:sec = '## ' . get(g:, 'gnosis_diary_section', '今日のノート')
  let l:i = a:lnum - 1
  while l:i >= 1
    if getline(l:i) =~# '^#'
      return trim(getline(l:i)) ==# l:sec
    endif
    let l:i -= 1
  endwhile
  return 0
endfunction

function! s:insert_link_before_up_note(link) abort
  let l:up = s:first_section_line()
  if l:up <= 0
    " 見張りが無いとき（index.md など）は末尾へ
    if s:buffer_has_link(a:link)
      return 0
    endif
    call append(line('$'), a:link)
    return 1
  endif

  if s:buffer_has_link(a:link)
    return 0
  endif

  let l:ins = l:up - 1
  " 本文末尾が散文のときだけ、空行を 1 つ開けてからリンクを置く
  if l:ins >= 1 && trim(getline(l:ins)) !=# ''
        \ && (trim(getline(l:ins)) !~# '\]\s*(\S\+)\s*$' || s:in_diary_list(l:ins))
    call append(l:ins, '')
    let l:ins += 1
  endif
  call append(l:ins, a:link)
  return 1
endfunction

" バッファ内に同じリンク（表示名または解決先一致）が無いか
function! s:buffer_has_link(link) abort
  let l:new_target = s:extract_target(a:link)
  let l:new_fp = empty(l:new_target) ? '' : fnamemodify(gnosis#resolve_link(l:new_target, expand('%:p:h')), ':p')
  for l:line in getline(1, line('$'))
    if l:line ==# a:link
      return 1
    endif
    let l:old_target = s:extract_target(l:line)
    if !empty(l:new_fp) && !empty(l:old_target)
      let l:old_fp = fnamemodify(gnosis#resolve_link(l:old_target, expand('%:p:h')), ':p')
      if l:old_fp ==# l:new_fp
        return 1
      endif
    endif
  endfor
  return 0
endfunction

" za: ca と同じ そっちにとって 側だが、関係は常に既定の「ノート」固定
" （ピッカーも「相手にも書くか」の質問も出さない）。
function! gnosis#add_clipboard_before_up_note(...) abort
  " za: 今のノートに（カーソル下のリンク or クリップボードの）リンクを 1 本足す。
  "     置き場所は h（カーソル直下）/ Enter（本文の最後）。相手側の Parent は書かない。
  let l:links = s:pick_links()
  if empty(l:links)
    echo gnosis#i18n#tr('Gnosis: クリップボードにもヤンクにも、追加できるノートへのリンクがありません')
    return
  endif
  call s:insert_links_at_position(l:links, function('s:links_added_done'))
endfunction

" \l などのピッカーから: 選んだリンク（Markdown リンクの文字列のリスト）を、za と同じ置き場所キー
" （h / Enter / t / c / r と、行の中へ入れる i）で今のノートに入れる。
" a:pos はピッカーを開いたときの getpos('.')（i 用）。
function! gnosis#insert_links_pick(links, pos) abort
  let s:inline_pos = a:pos
  try
    call s:insert_links_at_position(a:links, function('s:links_added_done'))
  finally
    let s:inline_pos = []
  endtry
endfunction

function! s:links_added_done() abort
  call s:realtime_sync_apply()
  silent write
endfunction

" zA: za と同じだが、追加前に「表示名」を 1 つ入力する（既定は za が使う表示名。
"     空 Enter / Esc で中止）。Vim 標準の折りたたみ zA は上書きされる。
"     引数に文字列を渡すと input() を出さずその表示名を使う（テスト・自動化用）。
" zap: カーソル下（またはクリップボード）のリンクを、今のノートの Parent の節の最後へ足す。
"     本文に同じリンクがあっても Parent には足す（Parent に既にあるときだけ足さない）。
"     Parent の節が無ければ、末尾に「### Context」を作って足す。
" 相手ノート（親にしたノート）の本文の、### Context の手前に、このノートへのリンクを足す。
" 相手の本文に既にあれば足さない。相手が開いていて未保存の変更があるときは触らない。
function! s:zap_add_child_link(rel_target) abort
  let l:self = expand('%:p')
  let l:parent_file = fnamemodify(expand('%:p:h') . '/' . a:rel_target, ':p')
  if !filereadable(l:parent_file)
    return
  endif
  let l:nr = bufnr(l:parent_file)
  if l:nr > 0 && bufloaded(l:nr) && getbufvar(l:nr, '&modified')
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 相手のノートに未保存の変更があるため、相手の本文へは足しませんでした') | echohl NONE
    return
  endif
  " このノートのタイトル（相手のリンクの表示名）
  let l:mine = filter(getline(1, 12), 'v:val =~# "^title:"')
  let l:title = empty(l:mine) ? fnamemodify(l:self, ':t:r') : trim(substitute(l:mine[0], '^title:\s*', '', ''))
  let l:link = s:make_link_from_dir(l:self, l:title, fnamemodify(l:parent_file, ':h'))
  let l:relself = matchstr(l:link, '](\zs[^)]*\ze)')
  let l:lines = readfile(l:parent_file)
  let l:p = index(l:lines, '### Context')
  let l:body_end = l:p >= 0 ? l:p : len(l:lines)
  for l:i in range(0, l:body_end - 1)
    if stridx(l:lines[l:i], '](' . l:relself) >= 0
      return
    endif
  endfor
  " ### Context の直前に入れる（既存の空行はそのまま。Parent が無ければ末尾）
  call insert(l:lines, l:link, l:body_end)
  call writefile(l:lines, l:parent_file)
  if l:nr > 0
    silent! execute 'checktime ' . l:nr
  endif
endfunction

function! s:add_parent_with_reverse(link) abort
  " A（今のノート）の Parent の節の末尾に B（リンク先）を入れる。
  " A の本文に B へのリンクが既にあっても入れる（本文で引用しつつ親にもできる。
  " sync は Parent を消さず、BackLink は Parent と本文のどちらにあっても出さない）。
  " 入れたら、B の本文に A が無ければ、B の ### Context の直前に A を入れる（s:zap_add_child_link）。
  let l:target = s:extract_target(a:link)
  if empty(l:target)
    return 0
  endif
  let l:bare = substitute(l:target, '#.*$', '', '')
  if !s:append_link_to_buffer_section('up', a:link)
    echo gnosis#i18n#tr('Gnosis: Context に追加できませんでした（重複 or ### Context 無し）')
    return 0
  endif
  call s:realtime_sync_apply()
  silent write
  call s:zap_add_child_link(l:bare)
  return 1
endfunction

function! s:noop(...) abort
endfunction

" za / \l の c: リンクごとに相手側の入れ方を聞き（非同期の見出し選択を含む）、全部そろったら書く
function! s:c_mode_chain(links, idx, choices, a, Done) abort
  if a:idx >= len(a:links)
    call s:c_mode_apply(a:links, a:choices, a:a, a:Done)
    return
  endif
  let l:lk = a:links[a:idx]
  let l:tgt = gnosis#resolve_link(substitute(s:extract_target(l:lk), '#.*$', '', ''), fnamemodify(a:a.path, ':h'))
  let l:lines = filereadable(l:tgt) ? readfile(l:tgt) : []
  let l:is_group = filereadable(l:tgt) && s:v2_path_attr(l:tgt) ==# 'group'
  call s:ask_back_link(l:tgt, l:lines, l:is_group, a:a.title,
        \ function('s:c_mode_next', [a:links, a:idx, a:choices, a:a, a:Done]))
endfunction

function! s:c_mode_next(links, idx, choices, a, Done, choice) abort
  call s:c_mode_chain(a:links, a:idx + 1, a:choices + [a:choice], a:a, a:Done)
endfunction

function! s:c_mode_apply(links, choices, a, Done) abort
  if bufnr('%') != a:a.buf && bufexists(a:a.buf)
    execute 'silent! buffer ' . a:a.buf
  endif
  let l:added = 0
  for l:i in range(len(a:links))
    let l:lk = a:links[l:i]
    if !s:append_link_to_buffer_section('up', l:lk)
      continue
    endif
    let l:added += 1
    call s:realtime_sync_apply()
    silent write
    let l:tgt = gnosis#resolve_link(substitute(s:extract_target(l:lk), '#.*$', '', ''), fnamemodify(a:a.path, ':h'))
    call s:apply_back_link(l:tgt, a:a.path, a:a.title, a:choices[l:i])
  endfor
  if l:added == 0
    echo 'Gnosis: ' . gnosis#i18n#tr('追加できるリンクがありません（Context に既にある or 取れなかった）')
  endif
  call a:Done()
endfunction

function! gnosis#add_link_to_parent() abort
  " zap / za,p: カーソル下（またはクリップボード）のリンクを、今のノートの Parent の末尾に入れ、
  " 相手（リンク先）の本文に今のノートが無ければ相手の ### Context の直前に入れる。
  let l:links = s:pick_links()
  if empty(l:links)
    echo gnosis#i18n#tr('Gnosis: クリップボードにもヤンクにも、追加できるノートへのリンクがありません')
    return
  endif
  let l:n = 0
  for l:lk in l:links
    if s:add_parent_with_reverse(l:lk)
      let l:n += 1
    endif
  endfor
  if l:n
    echo gnosis#i18n#tr('Gnosis: Context に ') . l:n . gnosis#i18n#tr(' 本追加しました')
  endif
endfunction

function! gnosis#add_clipboard_before_up_note_named(...) abort
  let l:links = s:pick_links()
  if empty(l:links)
    echo gnosis#i18n#tr('Gnosis: クリップボードにもヤンクにも、追加できるノートへのリンクがありません')
    return
  endif
  " 複数あるときは 1 本ずつ表示名を聞く（空 Enter / Esc でどれか 1 本でも中止したら全部中止）
  let l:named = []
  let l:i = 0
  for l:link in l:links
    let l:parts = s:extract_markdown_link(l:link)
    let l:target = get(l:parts, 'target', '')
    let l:default = get(l:parts, 'text', '')
    if empty(l:target)
      echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: リンクの形式が不正です') | echohl NONE
      return
    endif
    if a:0 > 0 && l:i == 0
      let l:name = a:1
    else
      let l:label = len(l:links) > 1 ? gnosis#i18n#tr('表示名 (') . (l:i + 1) . '/' . len(l:links) . '): ' : gnosis#i18n#tr('表示名: ')
      let l:name = input(l:label, l:default)
    endif
    if empty(l:name)
      echo gnosis#i18n#tr('Gnosis: 中止しました')
      return
    endif
    call add(l:named, '[' . l:name . '](' . l:target . ')')
    let l:i += 1
  endfor
  call s:insert_links_at_position(l:named, function('s:named_links_added_done', [len(l:named)]))
endfunction

function! s:named_links_added_done(count) abort
  call s:realtime_sync_apply()
  silent write
  echo gnosis#i18n#tr('Gnosis: 表示名を付けてリンクを ') . a:count . gnosis#i18n#tr(' 本追加')
endfunction

" 現ノートがグループ（attribute: group / index.md）かどうか
function! s:buf_is_group() abort
  if s:is_current_index_buffer()
    return 1
  endif
  return s:v2_buf_attr() ==# 'group'
endfunction

" 追加するリンクを 1 行で取り出す。優先は「カーソル下のリンク」、
" 無ければクリップボード。za / zp 共通。
function! s:pick_one_link() abort
  let l:links = s:pick_links()
  return empty(l:links) ? '' : l:links[0]
endfunction

" za / zA / zp / zap が足すリンクを全部（複数行・複数リンク可）。クリップボードかヤンクしたリンクで、
" カーソル下のリンクではない。取得元を順に見て、最初に「実在するノートを指すリンク」が 1 本でもあった
" 取得元の、実在するリンクを全部返す（同じノートは 1 本にまとめる）。システムのクリップボードが
" リンクでない文字のときでも、ヤンクしたリンク（"/0 レジスタ）を見落とさない。
function! s:pick_links() abort
  let l:texts = [s:clipboard_text_external(), getreg('"'), getreg('0'), getreg('+'), getreg('*')]
  for l:text in l:texts
    if empty(trim(l:text))
      continue
    endif
    let l:found = []
    let l:seen = {}
    " 文中の Markdown リンク [表示名](パス) を全部拾う（行頭でなくてもよい）
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:text, '\v\[%(\\.|[^\]\\])+\]\(([^)]*)\)', l:start)
      if empty(l:m) || l:m[1] < 0
        break
      endif
      let l:start = l:m[2]
      call s:pick_links_add(l:found, l:seen, l:m[0])
    endwhile
    " リンク記法でない行（パスや file:// だけ）
    for l:raw in split(l:text, "\n")
      if l:raw =~# '\[\%(\\.\|[^\]\\]\)\+\]([^)]*)'
        continue
      endif
      call s:pick_links_add(l:found, l:seen, l:raw)
    endfor
    if !empty(l:found)
      return l:found
    endif
  endfor
  return []
endfunction

" a:raw が実在するノートを指していて、まだ入っていなければ l:found に足す
function! s:pick_links_add(found, seen, raw) abort
  let l:target = s:extract_target(a:raw)
  if empty(l:target)
    return
  endif
  let l:path = gnosis#resolve_link(l:target)
  if !filereadable(l:path)
    return
  endif
  let l:key = fnamemodify(l:path, ':p')
  if has_key(a:seen, l:key)
    return
  endif
  let a:seen[l:key] = 1
  call add(a:found, s:link_from_clipboard_raw(a:raw))
endfunction

" \ca: ca と同じ そっちにとって 側だが、括弧が付く側が逆。今開いているノート
" 側を `(ラベル)` にし、相手側にはその場で生のラベルを書く（質問なし）。
function! gnosis#add_clipboard_before_up_reverse() abort
  if s:pkm_format() ==# 'v2'
    call gnosis#v2_add_link('', '', 1, 1)
    return
  endif
  call gnosis#add_clipboard_before_up()
endfunction

" zp: 今のノートにクリップボードのリンクを追加（h/Enter で位置を選ぶ）し、
"     さらに「今のノート」側のリンクを相手ノートの ### Context にも書く。
"     今のノートがグループの場合は本文リンクだけで十分（sync が親側を作る）。
function! gnosis#add_clipboard_as_child_with_parent() abort
  " zp: za と同じことをしたうえで、今開いてるノートを「相手の ### Context」にも書く（複数のリンクも全部）。
  "     今のノートがグループなら本文リンクだけで足りるので親は sync に任せる。
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 名前付きファイルで実行して') | echohl None
    return
  endif
  let l:links = s:pick_links()
  if empty(l:links)
    echo gnosis#i18n#tr('Gnosis: クリップボードにもヤンクにも、追加できるノートへのリンクがありません')
    return
  endif
  call s:insert_links_at_position(l:links)
  if s:buf_is_group()
    call s:realtime_sync_apply()
    silent write
    echo gnosis#i18n#tr('グループ: 本文リンクを追加（親は sync が書く）')
    return
  endif
  let l:done = []
  let l:cur_title = gnosis#current_title()
  for l:link in l:links
    let l:target = gnosis#resolve_link(s:extract_target(l:link))
    if empty(l:target) || !filereadable(l:target)
      continue
    endif
    call s:simple_add_parent(l:target, l:cur, l:cur_title)
    call add(l:done, fnamemodify(l:target, ':t'))
  endfor
  call s:realtime_sync_apply()
  silent write
  if empty(l:done)
    echo gnosis#i18n#tr('リンクのみ追加（相手ノートが見つからず Context には書けません）')
  else
    echo gnosis#i18n#tr('リンク追加 + 親に登録 → ') . join(l:done, ', ')
  endif
endfunction

function! gnosis#add_clipboard_before_up() abort
  if s:pkm_format() ==# 'v2'
    call gnosis#v2_add_link('', '', 1)  " ca: そっちにとって 側へ
    return
  endif
  let l:current_file = expand('%:p')
  let l:current_title = gnosis#current_title()

  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:links = []
  let l:targets = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    let l:path = gnosis#resolve_link(l:target)
    if !filereadable(l:path)
      echo 'Warning: not found: ' . l:target
      continue
    endif
    let l:link = s:link_from_clipboard_raw(l:raw)
    if !empty(l:link)
      call add(l:links, l:link)
      call add(l:targets, l:target)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  let l:down_added = 0
  let l:up_added = 0
  for l:i in range(0, len(l:links) - 1)
    let l:link = l:links[l:i]
    let l:target_path = gnosis#resolve_link(l:targets[l:i])

    if s:append_link_to_buffer_section('down', l:link)
      let l:down_added += 1
    endif

    let l:target_lines = readfile(l:target_path)
    let l:current_link = s:make_link_from_dir(
          \ l:current_file, l:current_title, fnamemodify(l:target_path, ':h'))
    let l:up_result = s:add_link_to_lines_section(l:target_lines, 'up', l:current_link, fnamemodify(l:target_path, ':h'), l:target_path)
    if l:up_result.added
      call s:syn_writefile(l:up_result.lines, l:target_path)
      let l:up_added += 1
    endif
  endfor
  silent write
  echo 'ca: Child added ' . l:down_added . ', reciprocal Context added ' . l:up_added
endfunction

function! gnosis#add_clipboard_to_top() abort
  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:links = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    let l:path = gnosis#resolve_link(l:target)
    if !filereadable(l:path)
      echo 'Warning: not found: ' . l:target
      continue
    endif
    let l:link = s:link_from_target(l:target)
    if !empty(l:link)
      call add(l:links, l:link)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  let l:ins = s:body_top_insert_line()
  for l:lk in l:links
    call append(l:ins, l:lk)
    let l:ins += 1
  endfor
  silent write
endfunction

function! gnosis#linkify_filename_under_cursor() abort
  let l:word = expand('<cfile>')
  if empty(l:word)
    echo 'Error: no filename under cursor'
    return
  endif
  let l:path = gnosis#resolve_link(l:word)
  if !filereadable(l:path)
    echo 'Error: not found: ' . l:word
    return
  endif
  let l:link = s:link_from_target(l:word)
  if empty(l:link)
    echo 'Error: failed to build link'
    return
  endif
  let l:line = getline('.')
  let l:start = col('.')
  let l:idx = match(l:line, '\V' . escape(l:word, '\'))
  if l:idx < 0
    echo 'Error: filename text not found on line'
    return
  endif
  let l:newline = strpart(l:line, 0, l:idx) . l:link . strpart(l:line, l:idx + strlen(l:word))
  call setline('.', l:newline)
endfunction

function! s:replace_visual_selection_with_link(link, is_linewise, sline, eline, scol, ecol, lines) abort
  if a:is_linewise
    call setline(a:sline, a:link)
    if a:eline > a:sline
      execute (a:sline + 1) . ',' . a:eline . 'delete _'
    endif
  elseif len(a:lines) == 1
    let l:line = a:lines[0]
    let l:start_char = charidx(l:line, a:scol - 1)
    let l:end_char = charidx(l:line, a:ecol - 1) + 1
    let l:newline = strcharpart(l:line, 0, l:start_char) . a:link . strcharpart(l:line, l:end_char)
    call setline(a:sline, l:newline)
  else
    let l:first_start_char = charidx(a:lines[0], a:scol - 1)
    let l:last_end_char = charidx(a:lines[-1], a:ecol - 1) + 1
    let l:prefix = strcharpart(a:lines[0], 0, l:first_start_char)
    let l:suffix = strcharpart(a:lines[-1], l:last_end_char)
    call setline(a:sline, l:prefix . a:link . l:suffix)
    if a:eline > a:sline
      execute (a:sline + 1) . ',' . a:eline . 'delete _'
    endif
  endif
endfunction

" 公開: ビジュアル選択を 1 つのリンクで置き換える（fzf 確定後のコールバック用）。
function! gnosis#replace_visual_selection(link, is_linewise, sline, eline, scol, ecol, lines) abort
  call s:replace_visual_selection_with_link(a:link, a:is_linewise, a:sline, a:eline, a:scol, a:ecol, a:lines)
endfunction

function! gnosis#linkify_selection_new_note() abort range

  let l:vmode = visualmode()
  let l:is_linewise = (l:vmode ==# 'V')

  let l:sline = line("'<")
  let l:eline = line("'>")
  let l:scol  = col("'<")
  let l:ecol  = col("'>")

  if l:sline <= 0 || l:eline <= 0
    echo 'No visual selection'
    return
  endif

  if l:sline > l:eline || (l:sline == l:eline && l:scol > l:ecol)
    let [l:sline, l:eline] = [l:eline, l:sline]
    let [l:scol, l:ecol] = [l:ecol, l:scol]
  endif

  let l:lines = getline(l:sline, l:eline)
  if empty(l:lines)
    echo 'No visual selection'
    return
  endif

  if l:is_linewise
    let l:selected = join(l:lines, "\n")
  elseif len(l:lines) == 1
    let l:start_char = charidx(l:lines[0], l:scol - 1)
    let l:end_char = charidx(l:lines[0], l:ecol - 1) + 1
    let l:selected = strcharpart(l:lines[0], l:start_char, l:end_char - l:start_char)
  else
    let l:selected_lines = copy(l:lines)
    let l:first_start_char = charidx(l:selected_lines[0], l:scol - 1)
    let l:last_end_char = charidx(l:selected_lines[-1], l:ecol - 1) + 1
    let l:selected_lines[0] = strcharpart(l:selected_lines[0], l:first_start_char)
    let l:selected_lines[-1] = strcharpart(l:selected_lines[-1], 0, l:last_end_char)
    let l:selected = join(l:selected_lines, "\n")
  endif

  let l:text = trim(substitute(l:selected, '\n\+', ' ', 'g'))
  if empty(l:text)
    echo 'No visual selection'
    return
  endif

  " 既存ファイル名が選択されている場合はそのままリンク化する
  " - 非md: [filename.ext](filename.ext)
  " - md: タイトル(取得できなければ拡張子なしファイル名)をリンク文字列に使う
  if s:is_filename_target(l:text)
    let l:link = s:link_from_target(l:text)
    call s:replace_visual_selection_with_link(l:link, l:is_linewise, l:sline, l:eline, l:scol, l:ecol, l:lines)
    return
  endif

  let l:target = gnosis#timestamp_filename() . '.md'
  let l:new_file = expand('%:p:h') . s:sep() . l:target
  let l:parent_file = expand('%:p')
  let l:parent_title = gnosis#current_title()
  let l:parent_link_lines = s:parent_link_lines(l:parent_file, l:parent_title, expand('%:p:h'))

  if !filereadable(l:new_file)
    " title はタイムスタンプのまま。選択範囲はリンクの表示名だけに使う
    "（タイトルを変えても文中の表示名は変わらない）
    let l:title = fnamemodify(l:target, ':t:r')
    let l:new_content = [
          \ '---',
          \ 'time: ' . gnosis#timestamp_yaml(),
          \ 'title: ' . l:title,
          \ '---',
          \ '',
          \ '# ' . l:title,
          \ '',
          \ '',
          \ '',
          \ ]
    call s:syn_writefile(l:new_content, l:new_file)
    call s:diary_place_safe(l:new_file, l:new_content)
    " Parent は付けない（2026-10-09〜）。元ノートは sync が新ノートの BackLink に
    " 自動で載せる。後に Parent にしたいだけなら \P で足せる。
  endif

  let l:link = '[' . l:text . '](' . l:target . ')'
  call s:replace_visual_selection_with_link(l:link, l:is_linewise, l:sline, l:eline, l:scol, l:ecol, l:lines)
  " y/n を押したらそのまま新しいノートを開く
  if filereadable(l:new_file)
    silent! write
    call gnosis#push_history()
    execute 'edit ' . fnameescape(l:new_file)
    let l:h1 = search('^#\s', 'nw')
    if l:h1 > 0 | call cursor(l:h1 + 2, 1) | endif
  endif
endfunction

" Backward compatibility: :LinkifySelection から呼ばれる既存関数名
function! gnosis#linkify_selection() abort range
  return gnosis#linkify_selection_new_note()
endfunction

function! gnosis#linkify_selection_from_clipboard() abort range
  let l:vmode = visualmode()
  let l:is_linewise = (l:vmode ==# 'V')

  let l:sline = line("'<")
  let l:eline = line("'>")
  let l:scol  = col("'<")
  let l:ecol  = col("'>")


  if l:sline <= 0 || l:eline <= 0
    echo 'No visual selection'
    return
  endif

  if l:sline > l:eline || (l:sline == l:eline && l:scol > l:ecol)
    let [l:sline, l:eline] = [l:eline, l:sline]
    let [l:scol, l:ecol] = [l:ecol, l:scol]
  endif

  let l:lines = getline(l:sline, l:eline)
  if empty(l:lines)
    echo 'No visual selection'
    return
  endif

  if l:is_linewise
    let l:selected = join(l:lines, "\n")
  elseif len(l:lines) == 1
    let l:start_char = charidx(l:lines[0], l:scol - 1)
    let l:end_char = charidx(l:lines[0], l:ecol - 1) + 1
    let l:selected = strcharpart(l:lines[0], l:start_char, l:end_char - l:start_char)
  else
    let l:selected_lines = copy(l:lines)
    let l:first_start_char = charidx(l:selected_lines[0], l:scol - 1)
    let l:last_end_char = charidx(l:selected_lines[-1], l:ecol - 1) + 1
    let l:selected_lines[0] = strcharpart(l:selected_lines[0], l:first_start_char)
    let l:selected_lines[-1] = strcharpart(l:selected_lines[-1], 0, l:last_end_char)
    let l:selected = join(l:selected_lines, "\n")
  endif

  let l:text = trim(substitute(l:selected, '\n\+', ' ', 'g'))
  if empty(l:text)
    echo 'No visual selection'
    return
  endif

  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    return
  endif

  let l:targets = s:extract_targets_from_clipboard(l:clipboard)
  if empty(l:targets)
    return
  endif

  " ファイル名を優先。無ければ URL（http 等）もリンク先に使える。
  let l:target = ''
  for l:item in l:targets
    if s:is_filename_target(l:item)
      let l:target = l:item
      break
    endif
  endfor
  if empty(l:target)
    for l:item in l:targets
      if s:is_url_target(l:item)
        let l:target = l:item
        break
      endif
    endfor
  endif
  if empty(l:target)
    return
  endif

  if s:is_markdown_target(l:target)
    let l:path = gnosis#resolve_link(l:target)
    if !filereadable(l:path)
      return
    endif
  endif

  let l:display_target = s:display_target_from_current_dir(l:target)
  let l:link = '[' . l:text . '](' . l:display_target . ')'
  call s:replace_visual_selection_with_link(l:link, l:is_linewise, l:sline, l:eline, l:scol, l:ecol, l:lines)
  " 親への追加はここでは聞かない（リンク上で \P を押せば足せる）
  call s:write_current_and_sync_now()
endfunction


" ---------------------------------------------------------------------------
" :YN - Yank Note name
" ---------------------------------------------------------------------------
" ---------------------------------------------------------------------------
" :YN - Yank Note name (拡張子なし)
" ---------------------------------------------------------------------------

function! gnosis#yank_name() abort
  let l:name = expand('%:t')
  let @" = l:name
  call gnosis#clipboard_copy(l:name)
  echo 'Yanked: ' . l:name
endfunction

" ---------------------------------------------------------------------------
" gp helper: システムクリップボード優先で、末尾改行を落として行下に追加
" ---------------------------------------------------------------------------

" \v / \V: 外部（Wayland）クリップボードを読んでから通常の貼り付けをする。
"   Vim の + レジスタ（"+p）は XWayland を見て古い内容になることがあるため、
"   s:clipboard_text() で本物のシステムクリップボードを取ってから貼る。
"   a:mode = 'p'（カーソルの後ろ）/ 'P'（前）。a:1 に count を渡すと回数分貼る。
function! gnosis#paste_clipboard(mode, ...) abort
  let l:text = s:clipboard_text()
  if empty(l:text)
    echo gnosis#i18n#tr('Gnosis: クリップボードが空')
    return
  endif
  let @" = l:text
  let l:cnt = a:0 > 0 && a:1 =~# '^\d\+$' && a:1 > 0 ? a:1 : 1
  execute 'normal! ' . l:cnt . a:mode
endfunction

function! gnosis#paste_charwise() abort
  let l:text = s:clipboard_text()
  if empty(l:text)
    let l:text = @"
  endif
  " 末尾の改行を除去してキャラクター単位に変換
  let l:text = substitute(l:text, '\n\+$', '', '')
  let l:lines = split(l:text, "\n", 1)
  call append(line('.'), l:lines)
endfunction

" 速度診断: 実環境で :call gnosis#perf_diag() して数値を確認する。
"   どこが遅いか（外部クリップボード / Vim レジスタ / ヒント / sync コマンド）を
"   ミリ秒で出す。バッファも同期も書き換えない（読み取りのみ）。
function! gnosis#perf_diag() abort
  let l:o = []
  call add(l:o, 'clipboard=' . &clipboard . '  root=' . s:get_pkm_root())
  let l:t = reltime()
  let l:wp = system('timeout 1 wl-paste --no-newline')
  call add(l:o, printf('wl-paste      : %7.1f ms (len=%d)', reltimefloat(reltime(l:t)) * 1000, len(l:wp)))
  let l:t = reltime()
  let l:r = getreg('+')
  call add(l:o, printf('getreg(+) reg : %7.1f ms (len=%d)', reltimefloat(reltime(l:t)) * 1000, len(l:r)))
  let l:t = reltime()
  let l:r = getreg('"')
  call add(l:o, printf('getreg(") reg : %7.1f ms (len=%d)', reltimefloat(reltime(l:t)) * 1000, len(l:r)))
  let l:t = reltime()
  call gnosis#refresh_link_hints()
  call add(l:o, printf('refresh_hints : %7.1f ms', reltimefloat(reltime(l:t)) * 1000))
  let l:cmd = s:update_one_command(expand('%:p'), 1)
  call add(l:o, 'sync cmd      : ' . (empty(l:cmd) ? '(none)' : 'ok'))
  echo join(l:o, "\n")
endfunction

" ---------------------------------------------------------------------------
" :AT2 - Add To clipboard target (逆リンク)
" ---------------------------------------------------------------------------

" \at: at と同じ こっちにとって 側だが、括弧が付く側が逆。今開いているノート
" 側を `(ラベル)` にし、相手側にはその場で生のラベルを書く（質問なし）。
function! gnosis#at_add_reverse() abort
  if s:pkm_format() ==# 'v2'
    call gnosis#v2_add_link('', '', 0, 1)
    return
  endif
  call gnosis#at_add()
endfunction

function! gnosis#at_add() abort
  if s:pkm_format() ==# 'v2'
    call gnosis#v2_add_link('', '', 0)  " at: こっちにとって 側へ（相方は sync）
    return
  endif
  let l:current_file  = expand('%:p')
  let l:current_title = gnosis#current_title()

  let l:cb = s:clipboard_text()
  if empty(l:cb)
    echo 'Error: clipboard empty'
    return
  endif

  let l:targets = s:extract_targets_from_clipboard(l:cb)
  if empty(l:targets)
    echo 'Error: no valid link target in clipboard'
    return
  endif

  let l:down_added = 0
  let l:up_added = 0
  let l:already = 0
  let l:missing = 0

  for l:target in l:targets
    let l:target_fp = gnosis#resolve_link(l:target)
    if !filereadable(l:target_fp)
      let l:missing += 1
      echom 'Warning: not found: ' . l:target
      continue
    endif
    if fnamemodify(l:target_fp, ':t') ==# 'index.md'
      continue
    endif

    let l:target_link = s:link_from_target(l:target)
    if !empty(l:target_link) && s:append_link_to_buffer_section('up', l:target_link)
      let l:up_added += 1
    endif

    let l:lines = readfile(l:target_fp)
    let l:new_link = s:make_link_from_dir(
          \ l:current_file, l:current_title, fnamemodify(l:target_fp, ':h'))
    let l:down_result = s:add_link_to_lines_section(l:lines, 'down', l:new_link)
    if l:down_result.added
      call s:syn_writefile(l:down_result.lines, l:target_fp)
      let l:down_added += 1
    else
      let l:already += 1
    endif
  endfor

  silent write
  echo 'AT: Child added ' . l:down_added . ', Context added ' . l:up_added . ', already ' . l:already . ', missing ' . l:missing
endfunction


" ---------------------------------------------------------------------------
" SortYomi (Child セクション yomi ソート) - Python 経由
" ---------------------------------------------------------------------------

function! gnosis#open_index() abort
  let l:root = gnosis#ensure_root_and_index()
  if empty(l:root)
    return
  endif
  execute 'cd ' . fnameescape(l:root)
  let l:index = s:index_path(l:root)
  if filereadable(l:index)
    if s:consume_index_created_flag()
      call s:open_index_with_delay(l:index)
    else
      call gnosis#push_history()
      execute 'edit ' . fnameescape(l:index)
    endif
  else
    echo 'index.md not found in ' . l:root
  endif
endfunction

" ---------------------------------------------------------------------------
" 紙のPKM（フォルゲゼッテル）
" ---------------------------------------------------------------------------

function! s:paper_pkm_script() abort
  return fnamemodify(g:gnosis_python, ':h') . s:sep() . 'paper_pkm.py'
endfunction

function! s:paper_scan_script() abort
  return fnamemodify(g:gnosis_python, ':h') . s:sep() . 'folgezettel_scan.py'
endfunction

" 紙PKM Index（Index・Index-write・Folgezettel-Index）を作成/再利用して開く。
" 紙PKM索引（Paper-Zettelkasten-Index）のパス。無ければ ''。
" 固定ファイル名 Paper-Zettelkasten-Index.md（title が Paper-Zettelkasten-Index）を優先し、
" 無ければ旧タイムスタンプ名で title が同じ（または旧 paper_index: true つき）ノートを返す。
let s:paper_index_name = 'Paper-Zettelkasten-Index.md'

function! s:is_paper_index_head(lines) abort
  return index(a:lines, 'title: Paper-Zettelkasten-Index') >= 0 || index(a:lines, 'paper_index: true') >= 0
endfunction

function! s:paper_index_path(root) abort
  let l:fixed = a:root . s:sep() . s:paper_index_name
  if filereadable(l:fixed) && s:is_paper_index_head(readfile(l:fixed, '', 8))
    return l:fixed
  endif
  let l:found = []
  for l:f in glob(a:root . s:sep() . '*.md', 0, 1)
    if s:is_paper_index_head(readfile(l:f, '', 8))
      call add(l:found, l:f)
    endif
  endfor
  return empty(l:found) ? '' : sort(l:found)[-1]
endfunction

function! gnosis#paper_index() abort
  let l:root = s:get_pkm_root()
  if empty(l:root)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: PKM root が未設定です') | echohl NONE
    return
  endif
  " 既にある索引は開くだけ（再生成は重いので \ua で行う）
  let l:existing = s:paper_index_path(l:root)
  if !empty(l:existing) && fnamemodify(l:existing, ':t') !=# s:paper_index_name
    " 旧タイムスタンプ名の Index: 固定名へ移行（他のノートからのリンクも書き換える）してから開く
    let l:script0 = s:paper_pkm_script()
    if filereadable(l:script0)
      let l:mig = systemlist(s:python_cmd() . ' ' . shellescape(l:script0) . ' migrate ' . shellescape(l:root))
      if v:shell_error == 0 && !empty(l:mig) && filereadable(l:mig[-1])
        let l:existing = l:mig[-1]
        silent! checktime
      endif
    endif
  endif
  if !empty(l:existing)
    silent execute 'edit ' . fnameescape(l:existing)
    redraw | echo gnosis#i18n#tr('Gnosis: 紙PKM Index を開きました（更新は \ua）')
    return
  endif
  let l:script = s:paper_pkm_script()
  if !filereadable(l:script)
    echohl ErrorMsg | echo gnosis#i18n#tr('Gnosis: paper_pkm.py が見つかりません: ') . l:script | echohl NONE
    return
  endif
  let l:cmd = s:python_cmd() . ' ' . shellescape(l:script) . ' create ' . shellescape(l:root)
  let l:out = system(l:cmd)
  if v:shell_error
    echohl ErrorMsg | echo substitute(l:out, '\n\+$', '', '') | echohl NONE
    return
  endif
  let l:path = substitute(l:out, '\n.*$', '', '')
  if empty(l:path) || !filereadable(l:path)
    echohl ErrorMsg | echo gnosis#i18n#tr('Gnosis: 紙PKM Index を作成できませんでした') | echohl NONE
    return
  endif
  silent execute 'edit ' . fnameescape(l:path)
  redraw | echo gnosis#i18n#tr('Gnosis: 紙PKM Index を開きました（Index-write にキーワードを書く）')
endfunction

" スキャン画像の番号付け GUI を起動する。移動先は今開いているノートのフォルダ。
function! gnosis#paper_scan() abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: PKM root が未設定です') | echohl NONE
    return
  endif
  let l:dest = expand('%:p:h')
  if empty(l:dest)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: ノートを開いてから実行してください') | echohl NONE
    return
  endif
  if stridx(fnamemodify(l:dest, ':p'), fnamemodify(l:root, ':p')) != 0
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 今のノートが vault の外です: ') . l:dest | echohl NONE
    return
  endif
  let l:script = s:paper_scan_script()
  if !filereadable(l:script)
    echohl ErrorMsg | echo gnosis#i18n#tr('Gnosis: folgezettel_scan.py が見つかりません: ') . l:script | echohl NONE
    return
  endif
  " GUI が Index を再生成するので、編集中の内容は先に書き出す。
  if &modified
    silent! update
  endif
  let l:cmd = s:python_cmd() . ' ' . shellescape(l:script)
        \ . ' --root ' . shellescape(l:root)
        \ . ' --dest ' . shellescape(l:dest)
  if has('job') && has('channel')
    call job_start(gnosis#shell_job(l:cmd), {
          \ 'exit_cb': function('s:paper_scan_done'),
          \ 'out_io':  'null',
          \ 'err_io':  'null',
          \ })
  else
    call system(l:cmd)
    checktime
  endif
  echo gnosis#i18n#tr('Gnosis: フォルゲゼッテル番号付けを起動しました（GUI で番号を入力）')
endfunction

function! s:paper_scan_done(job, status) abort
  call s:reload_current()
  if a:status == 0
    echo gnosis#i18n#tr('Gnosis: 番号付けが完了しました（Index を再読み込み）')
  endif
endfunction

" sort_yomi.py の場所（:SortYomi / \S / \zy が使う）
function! s:sort_yomi_script() abort
  return fnamemodify(g:gnosis_python, ':h') . s:sep() . 'sort_yomi.py'
endfunction

" 指定行範囲のリンクだけの行を表示名のよみ順に並べ替える。
" リンクでない行（front matter・見出し・空行・文章など）は位置ごと動かさない。
" `### Context` / `### Related` / `### BackLink` 以降のリンクも動かさない（本文だけ）。
" 未登録の表示名は pykakasi のよみをリンク先の yomi: に書き込む（\S の副作用）。
function! s:sort_lines_by_yomi(first, last) abort
  if expand('%:t') ==# 'Folgezettel-Index.md'
    echohl WarningMsg
    echo gnosis#i18n#tr('Gnosis: Folgezettel-Index は生成物（ID の自然順）なので \S しません')
    echohl NONE
    return
  endif
  let l:script = s:sort_yomi_script()
  if !filereadable(l:script)
    echohl ErrorMsg | echo gnosis#i18n#tr('Gnosis: sort_yomi.py が見つかりません: ') . l:script | echohl NONE
    return
  endif
  let l:lines = getline(a:first, a:last)
  if empty(l:lines)
    return
  endif
  let l:report = tempname()
  let l:cmd = s:python_cmd() . ' ' . shellescape(l:script) . ' sort --base ' . shellescape(expand('%:p:h'))
        \ . (expand('%:t') ==# 'Index-write.md' ? ' --keyword-lines' : '')
        \ . ' --report-file ' . shellescape(l:report)
  " 1 万行の Index では数秒かかる。無反応に見えないよう先に表示する。
  echo printf(gnosis#i18n#tr('Gnosis: %d 行をよみ順に並べ替え中…'), len(l:lines))
  redraw
  let l:out = system(l:cmd, join(l:lines, "\n") . "\n")
  if v:shell_error != 0
    call delete(l:report)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: よみソートに失敗しました（pykakasi 未導入?）') | echohl NONE
    return
  endif
  let l:added = 0
  if filereadable(l:report)
    let l:added = str2nr(get(readfile(l:report), 0, '0'))
    call delete(l:report)
  endif
  let l:new = split(l:out, "\n", 1)
  if !empty(l:new) && l:new[-1] ==# ''
    call remove(l:new, -1)
  endif
  if len(l:new) != len(l:lines)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: よみソートの行数が一致しません') | echohl NONE
    return
  endif
  let l:view = winsaveview()
  call setline(a:first, l:new)
  call winrestview(l:view)
  if l:added
    silent! checktime
    echo printf(gnosis#i18n#tr('Gnosis: %d 行をよみ順に並べ替え（未登録のよみ %d 件を yomi: に追加）'), len(l:new), l:added)
  else
    echo printf(gnosis#i18n#tr('Gnosis: %d 行をよみ順に並べ替えました'), len(l:new))
  endif
endfunction

" \S（ノーマル）/ :SortYomi … バッファ内の本文リンク行をよみ順にソート（主に index.md）。
" ### Context / ### Related / ### BackLink 以降のリンクは動かさない。
function! gnosis#sort_yomi() abort
  if s:sort_group_mode()
    let l:r = s:group_last_block()
    if empty(l:r) || s:count_link_lines(l:r[0], l:r[1]) <= 1
      echo 'Gnosis: ' . gnosis#i18n#tr('並べ替えるリンクがありません（グループの最後のブロックにリンクが 2 本以上あるときだけ並べ替えます）')
      return
    endif
    call s:sort_lines_by_yomi(l:r[0], l:r[1])
    return
  endif
  call s:sort_lines_by_yomi(1, line('$'))
endfunction

" \S をグループの規則（本文の最後のブロックだけ）で行うか。
" Index（index.md）と紙PKM の生成物は、これまでどおりバッファ全体の規則のまま。
function! s:sort_group_mode() abort
  if !s:buf_is_group() || s:is_current_index_buffer()
    return 0
  endif
  return expand('%:t') !~# '^\%(index\|Index-write\|Paper-Zettelkasten-Index\|Folgezettel-Index\)\.md$'
endfunction

" グループの本文の最後の「空行で区切られたブロック」の行範囲 [first, last]（無ければ []）。
"   本文 = front matter の後から、最初の関係の節（### Context など）の手前まで。
"   本文末尾の空行は、ブロックを探すときだけ読み飛ばす（空行そのものは変えない）。
"   最後の非空行から上へたどり、直前の空行の次の行までがブロック。
"   ブロックの先頭がコードブロックの途中なら、コードブロックが終わった次の行から。
function! s:group_last_block() abort
  let l:start = 1
  if getline(1) =~# '^---\s*$'
    let l:i = 2
    while l:i <= line('$') && getline(l:i) !~# '^---\s*$'
      let l:i += 1
    endwhile
    let l:start = l:i + 1
  endif
  let l:sec = s:first_section_line()
  let l:end = l:sec > 0 ? l:sec - 1 : line('$')
  while l:end >= l:start && trim(getline(l:end)) ==# ''
    let l:end -= 1
  endwhile
  if l:end < l:start
    return []
  endif
  let l:first = l:end
  while l:first > l:start && trim(getline(l:first - 1)) !=# ''
    let l:first -= 1
  endwhile
  let l:flags = s:buf_fence_flags()
  if get(l:flags, l:first - 1, 0) && get(l:flags, l:first - 2, 0)
    " ブロックがコードブロックの途中から始まる: 閉じの行の次から
    while l:first <= l:end && get(l:flags, l:first - 1, 0)
      let l:first += 1
    endwhile
  endif
  return l:first <= l:end ? [l:first, l:end] : []
endfunction

" 範囲内の「リンクだけの行」（コードブロックの外）の数
function! s:count_link_lines(first, last) abort
  let l:flags = s:buf_fence_flags()
  let l:n = 0
  for l:lnum in range(a:first, a:last)
    if !get(l:flags, l:lnum - 1, 0) && getline(l:lnum) =~# '^\s*\[\%(\\.\|[^\]\\]\)*\]([^)]\+)\s*$'
      let l:n += 1
    endif
  endfor
  return l:n
endfunction

" \S（ビジュアル）… 選択した行のリンク行をよみ順にソート。
function! gnosis#sort_selection() abort
  let l:first = line("'<")
  let l:last = line("'>")
  if l:first <= 0 || l:last <= 0 || l:first > l:last
    echo gnosis#i18n#tr('Gnosis: 選択範囲がありません')
    return
  endif
  call s:sort_lines_by_yomi(l:first, l:last)
endfunction

" zy … 今開いているノートの表示名（タイトル）のよみを、
"      そのノートの front matter `yomi:` に登録する。
"      空 Enter / Esc で削除。pykakasi の推測を既定値に出す。
"      `yomi:` に表示名が複数あるときは番号で表示名を選んでから編集する。
"      引数に文字列を渡すと input() を出さずそのよみを使う（テスト・自動化用）。
" よみ操作の対象（表示名, ノートパス）を決める。常に今開いているノート。
" 表示名が複数ある場合の選択は s:yomi_choose_name() が行う。
function! s:yomi_target() abort
  let l:note = expand('%:p')
  let l:name = gnosis#current_title()
  if empty(l:name) || empty(l:note) || !filereadable(l:note)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: ノート上で実行して') | echohl NONE
    return ['', '']
  endif
  return [l:name, l:note]
endfunction

" sort_yomi.py を呼ぶ小道具
function! s:yomi_py(script, sub, extra) abort
  return substitute(system(
        \ s:python_cmd() . ' ' . shellescape(a:script) . ' ' . a:sub . ' ' . a:extra),
        \ '\n*$', '', '')
endfunction

function! s:yomi_guess(script, name) abort
  return s:yomi_py(a:script, 'guess', shellescape(a:name))
endfunction

function! s:yomi_get(script, note, name) abort
  return s:yomi_py(a:script, 'get',
        \ '--note ' . shellescape(a:note) . ' --name ' . shellescape(a:name))
endfunction

" 対象ノートの `yomi:` に登録された表示名（登録順）。
function! s:yomi_names(script, note) abort
  if !filereadable(a:script)
    return []
  endif
  let l:out = s:yomi_py(a:script, 'list', '--note ' . shellescape(a:note))
  return filter(split(l:out, "\n"), {_, v -> !empty(v)})
endfunction

" `yomi:` の表示名が複数あるときは番号で選ばせる（1つ以下ならそのまま）。
" 今の表示名が未登録なら候補の末尾に足す。戻り値は選ばれた表示名（中止なら ''）。
function! s:yomi_choose_name(script, note, name) abort
  let l:names = s:yomi_names(a:script, a:note)
  if len(l:names) < 2
    return a:name
  endif
  if !empty(a:name) && index(l:names, a:name) < 0
    call add(l:names, a:name)
  endif
  let l:menu = join(map(copy(l:names), {i, v -> (i + 1) . '=' . v}), '  ')
  let l:choice = inputdialog(gnosis#i18n#tr('表示名を選択 (') . l:menu . '): ',
        \ string(index(l:names, a:name) + 1), "\x01")
  if l:choice ==# "\x01" || empty(trim(l:choice))
    echo gnosis#i18n#tr('Gnosis: 中止')
    return ''
  endif
  let l:num = str2nr(trim(l:choice))
  if l:num < 1 || l:num > len(l:names)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 番号が範囲外です') | echohl NONE
    return ''
  endif
  return l:names[l:num - 1]
endfunction

" よみの入力と保存（表示名は確定済み）。既定値を消して Enter なら削除。
function! s:yomi_input(note, name, default) abort
  let l:reading = inputdialog(gnosis#i18n#tr('よみ(') . a:name . '): ', a:default, "\x01")
  if l:reading ==# "\x01"
    echo gnosis#i18n#tr('Gnosis: 中止')
    return
  endif
  if empty(l:reading) && empty(a:default)
    echo gnosis#i18n#tr('Gnosis: 変更なし')
    return
  endif
  call s:apply_yomi(a:note, a:name, l:reading)
endfunction

" よみを書き込む（空文字で削除）。非対話の低レベル。
function! s:apply_yomi(note, name, reading) abort
  let l:script = s:sort_yomi_script()
  if !filereadable(l:script)
    echohl ErrorMsg | echo gnosis#i18n#tr('Gnosis: sort_yomi.py が見つかりません: ') . l:script | echohl NONE
    return
  endif
  let l:out = s:yomi_py(l:script, 'set',
        \ '--note ' . shellescape(a:note)
        \ . ' --name ' . shellescape(a:name)
        \ . ' --reading ' . shellescape(a:reading))
  call gnosis#clear_title_cache()
  silent! checktime
  echo l:out
endfunction

" zy / zY の非対話版。引数があればそのよみを使う（テスト・自動化用）。
function! gnosis#set_yomi(...) abort
  let [l:name, l:note] = s:yomi_target()
  if empty(l:name)
    return
  endif
  if a:0 > 0
    let l:reading = a:1
  else
    let l:reading = s:yomi_guess(s:sort_yomi_script(), l:name)
  endif
  call s:apply_yomi(l:note, l:name, l:reading)
endfunction

" zy … よみを空欄から変更（zt と同じ流儀）。Esc で中止。
"      既定値を消して Enter なら削除（既定が空のときの空 Enter は変更なし）。
"      `yomi:` に表示名が複数あるときは番号で表示名を選んでから編集する。
function! gnosis#rename_yomi_with_default(default) abort
  let [l:name, l:note] = s:yomi_target()
  if empty(l:name)
    return
  endif
  let l:name = s:yomi_choose_name(s:sort_yomi_script(), l:note, l:name)
  if empty(l:name)
    return
  endif
  call s:yomi_input(l:note, l:name, a:default)
endfunction

" zY … 現在のよみ（未登録なら pykakasi 推測）を残して編集（zT と同じ流儀）。
"      表示名の選択は zy と同じ（`yomi:` に複数あれば番号で選ぶ）。
function! gnosis#rename_yomi(args) abort
  let [l:name, l:note] = s:yomi_target()
  if empty(l:name)
    return
  endif
  let l:name = s:yomi_choose_name(s:sort_yomi_script(), l:note, l:name)
  if empty(l:name)
    return
  endif
  let l:default = a:args
  if empty(l:default)
    let l:default = s:yomi_get(s:sort_yomi_script(), l:note, l:name)
    if empty(l:default)
      let l:default = s:yomi_guess(s:sort_yomi_script(), l:name)
    endif
  endif
  call s:yomi_input(l:note, l:name, l:default)
endfunction

function! s:extract_time_digits(text) abort
  let l:digits = substitute(a:text, '\D', '', 'g')
  if strlen(l:digits) >= 14
    return strpart(l:digits, 0, 14)
  endif
  return ''
endfunction

function! s:link_time_key(line) abort
  let l:m = matchlist(a:line, '\v\[%(\\.|[^\]\\])+\]\(([^)]+)\)')
  let l:target = get(l:m, 1, '')
  if empty(l:target)
    return '00000000000000'
  endif

  let l:path = gnosis#resolve_link(l:target)
  if filereadable(l:path)
    let l:head = readfile(l:path, '', 40)
    let l:in_yaml = 0
    for l:line in l:head
      if l:line =~# '^---\s*$'
        if l:in_yaml
          break
        endif
        let l:in_yaml = 1
        continue
      endif
      if l:in_yaml && l:line =~? '^time:\s*'
        let l:key = s:extract_time_digits(matchstr(l:line, ':\s*\zs.*'))
        if !empty(l:key)
          return l:key
        endif
      endif
    endfor
    let l:mtime = getftime(l:path)
    if l:mtime > 0
      return strftime('%Y%m%d%H%M%S', l:mtime)
    endif
  endif

  let l:stem = fnamemodify(l:target, ':t:r')
  let l:from_name = matchstr(l:stem, '\d\{12,14}')
  if strlen(l:from_name) == 12
    return '20' . l:from_name
  elseif strlen(l:from_name) >= 14
    return strpart(l:from_name, 0, 14)
  endif
  return '00000000000000'
endfunction

function! s:sort_time_compare(a, b) abort
  let l:ka = get(a:a, 'key', '00000000000000')
  let l:kb = get(a:b, 'key', '00000000000000')
  if l:ka ==# l:kb
    return a:a.idx - a:b.idx
  endif
  return l:ka <# l:kb ? -1 : 1
endfunction

function! gnosis#sort_time(...) abort
  let l:descending = a:0 >= 1 ? a:1 : 0
  let l:line1 = a:0 >= 2 ? a:2 : 0
  let l:line2 = a:0 >= 3 ? a:3 : 0
  let l:has_range = a:0 >= 4 ? a:4 : 0

  if l:has_range > 0 && l:line1 > 0 && l:line2 >= l:line1
    let l:start = l:line1
    let l:end = l:line2
    let l:scope = 'selected range'
  else
    let l:down = s:find_section_line('down')
    if l:down <= 0
      echo 'Child section not found'
      return
    endif
    let l:back = s:find_section_line('back')
    let l:start = l:down + 1
    let l:end = l:back > l:down ? l:back - 1 : line('$')
    let l:scope = 'Child links'
  endif

  if l:end < l:start
    echo 'No links to sort'
    return
  endif

  let l:entries = []
  for lnum in range(l:start, l:end)
    let l:line = getline(lnum)
    if l:line =~# s:link_pat
      call add(l:entries, {
            \ 'lnum': lnum,
            \ 'line': l:line,
            \ 'key': s:link_time_key(l:line),
            \ 'idx': len(l:entries),
            \ })
    endif
  endfor

  if len(l:entries) <= 1
    echo 'No links to sort'
    return
  endif

  call sort(l:entries, 's:sort_time_compare')
  if l:descending
    call reverse(l:entries)
  endif

  let l:i = 0
  for lnum in range(l:start, l:end)
    if getline(lnum) =~# s:link_pat
      call setline(lnum, l:entries[l:i].line)
      let l:i += 1
    endif
  endfor

  echo l:scope . ' sorted by time' . (l:descending ? ' (desc)' : ' (asc)')
endfunction

" ---------------------------------------------------------------------------
" :RP - Rename Prefix
"   現在のファイルのプレフィクスを変更し、PKMルート配下の全リンクを更新する
" ---------------------------------------------------------------------------

function! gnosis#rename_prefix() abort
  let l:lines = getline(1, '$')
  let l:cur_type = ''
  let l:yaml_start = -1
  let l:yaml_end = -1
  for l:i in range(0, len(l:lines) - 1)
    if l:lines[l:i] ==# '---'
      if l:yaml_start < 0
        let l:yaml_start = l:i
      else
        let l:yaml_end = l:i
        break
      endif
    endif
  endfor
  if l:yaml_start == 0 && l:yaml_end > 0
    for l:i in range(l:yaml_start + 1, l:yaml_end - 1)
      if l:lines[l:i] =~? '^filetype:\s*'
        let l:cur_type = toupper(trim(substitute(l:lines[l:i], '^filetype:\s*', '', 'i')))
        break
      endif
    endfor
  endif
  if empty(l:cur_type)
    let l:cur_type = 'N'
  endif

  " 新プレフィクスを1文字即時入力
  echon 'filetype [' . l:cur_type . '] → '
  let l:char = nr2char(getchar())
  redraw
  if l:char !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  let l:new_type = toupper(l:char)
  if l:new_type ==# l:cur_type
    echo 'Filetype unchanged'
    return
  endif

  " 未保存の変更があれば保存
  if l:yaml_start == 0 && l:yaml_end > 0
    let l:done = 0
    for l:i in range(l:yaml_start + 1, l:yaml_end - 1)
      if l:lines[l:i] =~? '^filetype:\s*'
        let l:lines[l:i] = 'filetype: ' . l:new_type
        let l:done = 1
        break
      endif
    endfor
    if !l:done
      call insert(l:lines, 'filetype: ' . l:new_type, l:yaml_start + 1)
    endif
  else
    call insert(l:lines, '---', 0)
    call insert(l:lines, 'filetype: ' . l:new_type, 1)
    call insert(l:lines, '---', 2)
  endif
  call setline(1, l:lines)
  if len(l:lines) < line('$')
    execute (len(l:lines) + 1) . ',$delete _'
  endif
  silent write
  echo 'Filetype changed: ' . l:cur_type . ' → ' . l:new_type
endfunction



function! gnosis#expand_s_under_cursor(...) abort
  let l:source_path = expand('%:p')
  if empty(l:source_path) || !filereadable(l:source_path)
    echoerr 'expand_s: current file is not readable'
    return
  endif

  let l:depth_arg = a:0 ? trim(a:1) : ''
  if empty(l:depth_arg)
    let l:depth = get(g:, 'gnosis_expand_default_depth', 1)
  else
    let l:depth = str2nr(l:depth_arg)
  endif
  if l:depth < 0
    echoerr 'expand_s: depth must be >= 0'
    return
  endif

  let l:expand_py = g:gnosis_expand_s_python
  if !filereadable(l:expand_py)
    echoerr 'expand_s.py not found: ' . l:expand_py
    return
  endif

  let l:root = gnosis#ensure_root_and_index()
  if empty(l:root)
    return
  endif

  let l:py  = s:python_cmd()
  let l:cmd = l:py . ' ' . shellescape(l:expand_py)
        \ . ' expand_any ' . shellescape(l:source_path)
        \ . ' ' . shellescape(l:root)
        \ . ' ' . shellescape(string(l:depth))

  let l:out = system(l:cmd)
  if v:shell_error
    echoerr 'expand_s error: ' . substitute(l:out, '\n\+$', '', '')
    return
  endif

  let l:t_path = substitute(l:out, '\n\+$', '', '')
  if !filereadable(l:t_path)
    echoerr 'expand_s: T note not created: ' . l:t_path
    return
  endif

  let l:t_fname = fnamemodify(l:t_path, ':t')
  execute 'edit ' . fnameescape(l:t_path)

  echo 'Expanded: ' . l:t_fname . ' (depth=' . l:depth . ')'
endfunction


" ---------------------------------------------------------------------------
" Markdown table helpers (vimwiki-like)
" ---------------------------------------------------------------------------

function! s:is_table_line(line) abort
  return a:line =~# '\v^\s*\|.*\|\s*$'
endfunction

function! s:is_table_separator(line) abort
  return a:line =~# '\v^\s*\|\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|\s*$'
endfunction

function! s:table_block_range(lnum) abort
  if a:lnum < 1 || a:lnum > line('$') || !s:is_table_line(getline(a:lnum))
    return [0, 0]
  endif
  let l:start = a:lnum
  while l:start > 1 && s:is_table_line(getline(l:start - 1))
    let l:start -= 1
  endwhile
  let l:end = a:lnum
  while l:end < line('$') && s:is_table_line(getline(l:end + 1))
    let l:end += 1
  endwhile
  return [l:start, l:end]
endfunction

function! s:parse_table_line(line) abort
  let l:indent = matchstr(a:line, '^\s*')
  let l:core = substitute(a:line, '^\s*|\s*', '', '')
  let l:core = substitute(l:core, '\s*|\s*$', '', '')
  let l:cells = split(l:core, '|', 1)
  call map(l:cells, 'trim(v:val)')
  if empty(l:cells)
    let l:cells = ['']
  endif
  return {
        \ 'indent': l:indent,
        \ 'cells': l:cells,
        \ 'sep': s:is_table_separator(a:line)
        \ }
endfunction

function! s:table_col_count(start_lnum, end_lnum) abort
  let l:max_cols = 0
  for l:lnum in range(a:start_lnum, a:end_lnum)
    let l:parsed = s:parse_table_line(getline(l:lnum))
    let l:max_cols = max([l:max_cols, len(l:parsed.cells)])
  endfor
  return l:max_cols
endfunction

function! s:table_separator_token(width, align) abort
  let l:w = max([3, a:width])
  if a:align ==# 'right'
    return repeat('-', l:w - 1) . ':'
  elseif a:align ==# 'center'
    return ':' . repeat('-', max([1, l:w - 2])) . ':'
  elseif a:align ==# 'left'
    return ':' . repeat('-', l:w - 1)
  endif
  return repeat('-', l:w)
endfunction

function! s:table_align_block(start_lnum, end_lnum) abort
  let [l:new_lines, l:cols] = s:table_align_lines(getline(a:start_lnum, a:end_lnum))
  if l:cols <= 0
    return 0
  endif
  call setline(a:start_lnum, l:new_lines)
  return l:cols
endfunction

function! s:table_pipe_positions(line) abort
  let l:positions = []
  let l:start = 0
  while 1
    let l:idx = stridx(a:line, '|', l:start)
    if l:idx < 0
      break
    endif
    call add(l:positions, l:idx)
    let l:start = l:idx + 1
  endwhile
  return l:positions
endfunction

function! s:table_cell_index_from_col(line, colnum) abort
  let l:pipes = s:table_pipe_positions(a:line)
  if len(l:pipes) < 2
    return 1
  endif
  let l:cur = max([0, a:colnum - 1])
  for l:i in range(0, len(l:pipes) - 2)
    if l:cur <= l:pipes[l:i + 1]
      return l:i + 1
    endif
  endfor
  return len(l:pipes) - 1
endfunction

function! s:table_cell_startcol(line, cell_index) abort
  let l:pipes = s:table_pipe_positions(a:line)
  if len(l:pipes) < a:cell_index + 1 || a:cell_index < 1
    return 1
  endif
  let l:start0 = l:pipes[a:cell_index - 1] + 2
  if l:start0 > l:pipes[a:cell_index]
    let l:start0 = l:pipes[a:cell_index - 1] + 1
  endif
  return l:start0 + 1
endfunction

function! s:table_blank_row(cols, indent) abort
  return a:indent . '|' . join(repeat(['   '], a:cols), '|') . '|'
endfunction

function! s:table_headers(start_lnum, end_lnum, cols) abort
  let l:headers = []
  if a:start_lnum < a:end_lnum && s:is_table_separator(getline(a:start_lnum + 1))
    let l:parsed = s:parse_table_line(getline(a:start_lnum))
    while len(l:parsed.cells) < a:cols
      call add(l:parsed.cells, '')
    endwhile
    for l:i in range(0, a:cols - 1)
      let l:label = trim(l:parsed.cells[l:i])
      call add(l:headers, empty(l:label) ? ('Col ' . (l:i + 1)) : l:label)
    endfor
    return l:headers
  endif

  for l:i in range(1, a:cols)
    call add(l:headers, 'Col ' . l:i)
  endfor
  return l:headers
endfunction

function! s:table_align_lines(lines) abort
  if empty(a:lines)
    return [[], 0]
  endif

  let l:cols = 0
  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    let l:cols = max([l:cols, len(l:parsed.cells)])
  endfor
  if l:cols <= 0
    return [copy(a:lines), 0]
  endif

  let l:widths = repeat([3], l:cols)
  let l:aligns = repeat(['plain'], l:cols)

  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    while len(l:parsed.cells) < l:cols
      call add(l:parsed.cells, '')
    endwhile

    if l:parsed.sep
      for l:i in range(0, l:cols - 1)
        let l:token = trim(l:parsed.cells[l:i])
        if l:token =~# '^:-\+$'
          let l:aligns[l:i] = 'left'
        elseif l:token =~# '^:-\+:$'
          let l:aligns[l:i] = 'center'
        elseif l:token =~# '^\-\+:$'
          let l:aligns[l:i] = 'right'
        endif
        let l:plain = substitute(l:token, ':', '', 'g')
        let l:widths[l:i] = max([l:widths[l:i], strdisplaywidth(l:plain)])
      endfor
    else
      for l:i in range(0, l:cols - 1)
        let l:widths[l:i] = max([l:widths[l:i], strdisplaywidth(l:parsed.cells[l:i])])
      endfor
    endif
  endfor

  let l:new_lines = []
  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    while len(l:parsed.cells) < l:cols
      call add(l:parsed.cells, '')
    endwhile

    let l:parts = []
    for l:i in range(0, l:cols - 1)
      if l:parsed.sep
        let l:token = s:table_separator_token(l:widths[l:i], l:aligns[l:i])
        call add(l:parts, ' ' . l:token . ' ')
      else
        let l:cell = l:parsed.cells[l:i]
        let l:pad = l:widths[l:i] - strdisplaywidth(l:cell)
        call add(l:parts, ' ' . l:cell . repeat(' ', l:pad) . ' ')
      endif
    endfor
    call add(l:new_lines, l:parsed.indent . '|' . join(l:parts, '|') . '|')
  endfor

  return [l:new_lines, l:cols]
endfunction

function! s:find_prev_table_data_line(start_lnum, first_lnum) abort
  let l:lnum = a:start_lnum
  while l:lnum >= a:first_lnum
    if s:is_table_line(getline(l:lnum)) && !s:is_table_separator(getline(l:lnum))
      return l:lnum
    endif
    let l:lnum -= 1
  endwhile
  return 0
endfunction

function! s:find_next_table_data_line(start_lnum, last_lnum) abort
  let l:lnum = a:start_lnum
  while l:lnum <= a:last_lnum
    if s:is_table_line(getline(l:lnum)) && !s:is_table_separator(getline(l:lnum))
      return l:lnum
    endif
    let l:lnum += 1
  endwhile
  return 0
endfunction

function! gnosis#table_align_current() abort
  let [l:start, l:end] = s:table_block_range(line('.'))
  if l:start == 0
    echo 'Not on a table'
    return
  endif
  call s:table_align_block(l:start, l:end)
endfunction

function! gnosis#table_new(args) abort
  let l:cols = 3
  let l:body_rows = 1
  let l:parts = split(trim(a:args))
  if len(l:parts) >= 1 && l:parts[0] =~# '^\d\+$'
    let l:cols = max([1, str2nr(l:parts[0])])
  endif
  if len(l:parts) >= 2 && l:parts[1] =~# '^\d\+$'
    let l:body_rows = max([1, str2nr(l:parts[1])])
  endif

  let l:indent = matchstr(getline('.'), '^\s*')
  let l:table_lines = [
        \ l:indent . '|' . join(repeat(['   '], l:cols), '|') . '|',
        \ l:indent . '|' . join(repeat([' --- '], l:cols), '|') . '|'
        \ ]
  for l:_ in range(1, l:body_rows)
    call add(l:table_lines, l:indent . '|' . join(repeat(['   '], l:cols), '|') . '|')
  endfor

  let l:start_lnum = line('.')
  if empty(trim(getline('.')))
    " 空行を削除してからテーブルを挿入（setline+リストは以降の行を上書きするためNG）
    call deletebufline('%', l:start_lnum)
    call append(l:start_lnum - 1, l:table_lines)
  else
    call append(l:start_lnum, l:table_lines)
    let l:start_lnum += 1
  endif

  let l:end_lnum = l:start_lnum + len(l:table_lines) - 1
  call s:table_align_block(l:start_lnum, l:end_lnum)
  call cursor(l:start_lnum, s:table_cell_startcol(getline(l:start_lnum), 1))
  startinsert
endfunction


function! s:feedkeys_insert(keys) abort
  call feedkeys("\<C-g>u" . a:keys, 'in')
endfunction

function! gnosis#table_tab_action() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    call s:feedkeys_insert("\<Tab>")
    return
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    call s:feedkeys_insert("\<Tab>")
    return
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:parsed = s:parse_table_line(l:cur_line)
  let l:cols = len(l:parsed.cells)
  if l:cols <= 0
    call s:feedkeys_insert("\<Tab>")
    return
  endif

  if l:cur_cell < l:cols
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell + 1))
    return
  endif

  let l:next_data = s:find_next_table_data_line(l:cur_lnum + 1, l:end)
  if l:next_data > 0
    call cursor(l:next_data, s:table_cell_startcol(getline(l:next_data), 1))
    return
  endif

  let l:insert_after = l:cur_lnum
  if l:insert_after < l:end && s:is_table_separator(getline(l:insert_after + 1))
    let l:insert_after += 1
  endif
  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), 1))
endfunction

function! gnosis#table_stab_action() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    call s:feedkeys_insert("\<C-d>")
    return
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    call s:feedkeys_insert("\<C-d>")
    return
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:parsed = s:parse_table_line(l:cur_line)
  let l:cols = len(l:parsed.cells)
  if l:cols <= 0
    return
  endif

  if l:cur_cell > 1
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell - 1))
    return
  endif

  let l:prev_data = s:find_prev_table_data_line(l:cur_lnum - 1, l:start)
  if l:prev_data > 0
    call cursor(l:prev_data, s:table_cell_startcol(getline(l:prev_data), l:cols))
  endif
endfunction

function! gnosis#table_cr_action() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    call s:feedkeys_insert("\<CR>")
    return
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    call s:feedkeys_insert("\<CR>")
    return
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:parsed = s:parse_table_line(l:cur_line)
  let l:cols = len(l:parsed.cells)
  if l:cols <= 0
    call s:feedkeys_insert("\<CR>")
    return
  endif

  let l:target_cell = min([max([1, l:cur_cell]), l:cols])
  let l:next_data = s:find_next_table_data_line(l:cur_lnum + 1, l:end)
  if l:next_data > 0
    call cursor(l:next_data, s:table_cell_startcol(getline(l:next_data), l:target_cell))
    return
  endif

  let l:insert_after = l:cur_lnum
  if l:cur_lnum < l:end && s:is_table_separator(getline(l:cur_lnum + 1))
    let l:insert_after = l:cur_lnum + 1
  endif

  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), l:target_cell))
endfunction
function! gnosis#table_tab() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return "\<Tab>"
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    return "\<Tab>"
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:cols = s:table_align_block(l:start, l:end)
  if l:cols <= 0
    return "\<Tab>"
  endif

  if l:cur_cell < l:cols
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell + 1))
    return ''
  endif

  let l:next_data = s:find_next_table_data_line(l:cur_lnum + 1, l:end)
  if l:next_data > 0
    call cursor(l:next_data, s:table_cell_startcol(getline(l:next_data), 1))
    return ''
  endif

  let l:insert_after = l:cur_lnum
  if l:insert_after < l:end && s:is_table_separator(getline(l:insert_after + 1))
    let l:insert_after += 1
  endif
  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), 1))
  return ''
endfunction

function! gnosis#table_stab() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return "\<S-Tab>"
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    return "\<S-Tab>"
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:cols = s:table_align_block(l:start, l:end)
  if l:cols <= 0
    return "\<S-Tab>"
  endif

  if l:cur_cell > 1
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell - 1))
    return ''
  endif

  let l:prev_data = s:find_prev_table_data_line(l:cur_lnum - 1, l:start)
  if l:prev_data > 0
    call cursor(l:prev_data, s:table_cell_startcol(getline(l:prev_data), l:cols))
    return ''
  endif
  return ''
endfunction

function! gnosis#table_cr() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return "\<CR>"
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    return "\<CR>"
  endif

  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:cols = s:table_align_block(l:start, l:end)
  if l:cols <= 0
    return "\<CR>"
  endif

  let l:insert_after = l:cur_lnum
  if s:is_table_separator(getline(l:cur_lnum))
    let l:insert_after = l:cur_lnum
  elseif l:cur_lnum < l:end && s:is_table_separator(getline(l:cur_lnum + 1))
    let l:insert_after = l:cur_lnum + 1
  endif

  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), 1))
  return ''
endfunction

function! s:table_row_editor_lines(headers, cells) abort
  let l:lines = [
        \ gnosis#i18n#tr('# TableRowEdit: 各項目の次の行を書き換えて :write で反映'),
        \ gnosis#i18n#tr('# q で閉じる / ZZ で保存して閉じる'),
        \ ''
        \ ]
  for l:i in range(0, len(a:cells) - 1)
    call add(l:lines, '[' . (l:i + 1) . '] ' . a:headers[l:i])
    call add(l:lines, a:cells[l:i])
    call add(l:lines, '')
  endfor
  return l:lines
endfunction

function! gnosis#table_row_edit() abort
  let l:cur_lnum = line('.')
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  if l:start == 0
    echo 'Not on a table'
    return
  endif
  if s:is_table_separator(getline(l:cur_lnum))
    echo 'Separator row cannot be edited here'
    return
  endif

  let l:cols = s:table_align_block(l:start, l:end)
  let l:parsed = s:parse_table_line(getline(l:cur_lnum))
  while len(l:parsed.cells) < l:cols
    call add(l:parsed.cells, '')
  endwhile
  let l:headers = s:table_headers(l:start, l:end, l:cols)

  let l:origin_win = win_getid()
  vertical botright new
  let l:editor_buf = bufnr('%')
  call setline(1, s:table_row_editor_lines(l:headers, l:parsed.cells))

  let b:gnosis_table_editor = 1
  let b:gnosis_table_src_bufnr = bufnr('#') > 0 ? bufnr('#') : bufnr(winbufnr(l:origin_win))
  let b:gnosis_table_src_bufnr = winbufnr(l:origin_win)
  let b:gnosis_table_src_lnum = l:cur_lnum
  " 開いた時点の元行を覚え、保存時に一致するか確認する（途中で行がずれていたら別行を壊さない）
  let b:gnosis_table_orig_line = get(getbufline(b:gnosis_table_src_bufnr, l:cur_lnum), 0, '')
  let b:gnosis_table_src_start = l:start
  let b:gnosis_table_src_end = l:end
  let b:gnosis_table_cols = l:cols
  let b:gnosis_table_headers = copy(l:headers)

  setlocal buftype=acwrite
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal filetype=markdown
  setlocal wrap
  setlocal linebreak
  setlocal breakindent
  setlocal nonumber
  setlocal norelativenumber
  setlocal foldcolumn=0
  setlocal signcolumn=no
  setlocal textwidth=0
  setlocal modifiable

  execute 'autocmd! BufWriteCmd <buffer> call gnosis#table_row_editor_apply()'
  nnoremap <silent><buffer> q  <Cmd>bd!<CR>
  nnoremap <silent><buffer> ZZ <Cmd>write<Bar>bd!<CR>

  call cursor(4, 1)
endfunction

function! gnosis#table_row_editor_apply() abort
  if !exists('b:gnosis_table_editor') || !b:gnosis_table_editor
    return
  endif

  let l:cols = get(b:, 'gnosis_table_cols', 0)
  let l:headers = get(b:, 'gnosis_table_headers', [])
  if l:cols <= 0 || len(l:headers) != l:cols
    echoerr 'TableRowEdit: invalid editor state'
    return
  endif

  let l:new_cells = []
  let l:base = 4
  for l:i in range(0, l:cols - 1)
    let l:value_lnum = l:base + (l:i * 3) + 1
    call add(l:new_cells, trim(getline(l:value_lnum)))
  endfor

  let l:src_buf = b:gnosis_table_src_bufnr
  let l:src_start = b:gnosis_table_src_start
  let l:src_end = b:gnosis_table_src_end
  let l:src_lnum = b:gnosis_table_src_lnum

  if !bufexists(l:src_buf)
    echoerr 'TableRowEdit: source buffer not found'
    return
  endif

  let l:block_lines = getbufline(l:src_buf, l:src_start, l:src_end)
  if empty(l:block_lines)
    echoerr 'TableRowEdit: source table not found'
    return
  endif

  let l:row_idx = l:src_lnum - l:src_start
  if l:row_idx < 0 || l:row_idx >= len(l:block_lines)
    echoerr 'TableRowEdit: source row is out of range'
    return
  endif

  if l:block_lines[l:row_idx] !=# get(b:, 'gnosis_table_orig_line', '')
    echoerr gnosis#i18n#tr('TableRowEdit: 元の行が変わったため保存しません（エディタを開き直してください）')
    return
  endif
  let l:src_parsed = s:parse_table_line(l:block_lines[l:row_idx])
  let l:block_lines[l:row_idx] = l:src_parsed.indent . '| ' . join(l:new_cells, ' | ') . ' |'

  let [l:aligned, l:cols2] = s:table_align_lines(l:block_lines)
  if l:cols2 <= 0
    echoerr 'TableRowEdit: failed to align table'
    return
  endif

  call setbufline(l:src_buf, l:src_start, l:aligned)
  setlocal nomodified
  echo 'Table row updated'
endfunction


function! s:csv_escape_field(field) abort
  let l:field = a:field
  let l:needs_quote = l:field =~# '[",\n]'
  let l:field = substitute(l:field, '"', '""', 'g')
  return l:needs_quote ? '"' . l:field . '"' : l:field
endfunction

function! s:csv_join_fields(fields) abort
  let l:out = []
  for l:field in a:fields
    call add(l:out, s:csv_escape_field(l:field))
  endfor
  return join(l:out, ',')
endfunction

function! s:csv_parse_line(line) abort
  let l:fields = []
  let l:field = ''
  let l:in_quotes = 0
  let l:i = 0
  while l:i < strlen(a:line)
    let l:ch = strpart(a:line, l:i, 1)
    if l:in_quotes
      if l:ch ==# '"'
        if l:i + 1 < strlen(a:line) && strpart(a:line, l:i + 1, 1) ==# '"'
          let l:field .= '"'
          let l:i += 1
        else
          let l:in_quotes = 0
        endif
      else
        let l:field .= l:ch
      endif
    else
      if l:ch ==# ','
        call add(l:fields, l:field)
        let l:field = ''
      elseif l:ch ==# '"'
        let l:in_quotes = 1
      else
        let l:field .= l:ch
      endif
    endif
    let l:i += 1
  endwhile
  call add(l:fields, l:field)
  return l:fields
endfunction

function! s:csv_block_range(lnum) abort
  if a:lnum < 1 || a:lnum > line('$') || empty(trim(getline(a:lnum)))
    return [0, 0]
  endif
  let l:start = a:lnum
  let l:end = a:lnum
  while l:start > 1 && !empty(trim(getline(l:start - 1)))
    let l:start -= 1
  endwhile
  while l:end < line('$') && !empty(trim(getline(l:end + 1)))
    let l:end += 1
  endwhile
  return [l:start, l:end]
endfunction

function! s:table_lines_to_csv(lines) abort
  let l:csv = []
  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    if l:parsed.sep
      continue
    endif
    call add(l:csv, s:csv_join_fields(l:parsed.cells))
  endfor
  return l:csv
endfunction

function! s:csv_lines_to_table(lines, indent) abort
  let l:rows = []
  let l:maxcols = 0
  for l:line in a:lines
    if empty(trim(l:line))
      continue
    endif
    let l:fields = s:csv_parse_line(l:line)
    let l:maxcols = max([l:maxcols, len(l:fields)])
    call add(l:rows, l:fields)
  endfor
  if empty(l:rows)
    return []
  endif
  let l:maxcols = max([1, l:maxcols])
  let l:table = []
  for l:ridx in range(0, len(l:rows) - 1)
    while len(l:rows[l:ridx]) < l:maxcols
      call add(l:rows[l:ridx], '')
    endwhile
    call add(l:table, a:indent . '| ' . join(l:rows[l:ridx], ' | ') . ' |')
    if l:ridx == 0
      call add(l:table, a:indent . '|' . join(repeat([' --- '], l:maxcols), '|') . '|')
    endif
  endfor
  let [l:aligned, l:cols] = s:table_align_lines(l:table)
  return l:aligned
endfunction

function! s:append_current_file_branch_link(link) abort
  let l:ins = s:structural_link_append_line()
  if l:ins <= 0
    return 0
  endif
  let l:save_ai = &l:autoindent
  let l:save_si = &l:smartindent
  setlocal noautoindent nosmartindent
  call append(l:ins, a:link)
  let &l:autoindent = l:save_ai
  let &l:smartindent = l:save_si
  return 1
endfunction

function! s:next_t_csv_path(base_dir, idx_hint) abort
  let l:ts = strftime('%y%m%d%H%M%S')
  let l:idx = a:idx_hint > 0 ? a:idx_hint : 1
  let l:path = a:base_dir . '/T_' . l:ts . '_' . l:idx . '.csv'
  while filereadable(l:path)
    let l:idx += 1
    let l:path = a:base_dir . '/T_' . l:ts . '_' . l:idx . '.csv'
  endwhile
  return l:path
endfunction

function! s:csv_branch_link(csv_path) abort
  let l:name = fnamemodify(a:csv_path, ':t')
  return '[' . l:name . '](' . l:name . ')'
endfunction

function! gnosis#csv_new() abort
  let l:src_name = expand('%:p')
  let l:base_dir = empty(l:src_name) ? getcwd() : fnamemodify(l:src_name, ':p:h')
  let l:csv_path = s:next_t_csv_path(l:base_dir, 1)
  call s:syn_writefile([], l:csv_path)
  call s:append_current_file_branch_link(s:csv_branch_link(l:csv_path))
  silent! write
  execute 'edit ' . fnameescape(l:csv_path)
endfunction

" \tc / :TableToCsv … テーブルを同じページのまま CSV 行へ置き換える。
" （以前は別の .csv ファイルを作って開いていた。CSV バッファで編集したいときは
"  :TCSV / <leader>tc を使う。逆変換は \tt / :CsvToTable。）
function! gnosis#table_to_csv() abort
  return gnosis#table_to_csv_current()
endfunction

function! gnosis#csv_to_table() abort
  return gnosis#csv_to_table_current()
endfunction

function! gnosis#table_to_csv_current() abort
  let [l:start, l:end] = s:table_block_range(line('.'))
  if l:start == 0
    echo 'Not on a table'
    return
  endif
  let l:indent = matchstr(getline(l:start), '^\s*')
  let l:csv = s:table_lines_to_csv(getline(l:start, l:end))
  call map(l:csv, 'l:indent . v:val')
  call setline(l:start, l:csv)
  if l:end > l:start + len(l:csv) - 1
    execute (l:start + len(l:csv)) . ',' . l:end . 'delete _'
  endif
  echo 'Converted table to CSV'
endfunction

function! gnosis#csv_to_table_current() abort
  let [l:start, l:end] = s:csv_block_range(line('.'))
  if l:start == 0
    echo 'Not on CSV lines'
    return
  endif
  let l:indent = matchstr(getline(l:start), '^\s*')
  let l:table = s:csv_lines_to_table(getline(l:start, l:end), l:indent)
  if empty(l:table)
    echo 'CSV block is empty'
    return
  endif
  call setline(l:start, l:table)
  if l:end > l:start + len(l:table) - 1
    execute (l:start + len(l:table)) . ',' . l:end . 'delete _'
  endif
  echo 'Converted CSV to table'
endfunction

function! s:table_csv_temp_path(src_buf, start) abort
  let l:src_name = bufname(a:src_buf)
  let l:base_dir = empty(l:src_name) ? getcwd() : fnamemodify(l:src_name, ':p:h')
  let l:stamp = strftime('%y%m%d%H%M%S')
  return l:base_dir . '/T_' . l:stamp . '_' . a:start . '.csv'
endfunction

function! s:table_csv_apply_to_source(csv_lines, src_buf, src_start, src_end, indent) abort
  if a:src_buf < 0 || a:src_start <= 0 || a:src_end < a:src_start || !bufexists(a:src_buf)
    echoerr 'TableCsvEdit: source buffer not found'
    return 0
  endif

  call bufload(a:src_buf)

  let l:table = s:csv_lines_to_table(a:csv_lines, a:indent)
  if empty(l:table)
    echoerr 'TableCsvEdit: CSV is empty'
    return 0
  endif

  call setbufline(a:src_buf, a:src_start, l:table)
  let l:new_end = a:src_start + len(l:table) - 1
  if a:src_end > l:new_end
    call deletebufline(a:src_buf, l:new_end + 1, a:src_end)
  endif
  call setbufvar(a:src_buf, '&modified', 1)
  return l:new_end
endfunction


function! gnosis#table_csv_editor_cleanup(...) abort
  return
endfunction

function! gnosis#table_csv_edit() abort
  let l:cur_lnum = line('.')
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  if l:start == 0
    echo 'Not on a table'
    return
  endif

  let l:src_buf = bufnr('%')
  let l:src_indent = matchstr(getline(l:start), '^\s*')
  let l:csv_lines = s:table_lines_to_csv(getline(l:start, l:end))
  let l:csv_path = s:table_csv_temp_path(l:src_buf, l:start)
  call s:syn_writefile(l:csv_lines, l:csv_path)

  execute 'edit ' . fnameescape(l:csv_path)

  let b:gnosis_table_csv_editor = 1
  let b:gnosis_table_src_bufnr = l:src_buf
  let b:gnosis_table_src_start = l:start
  let b:gnosis_table_src_end = l:end
  let b:gnosis_table_src_indent = l:src_indent
  let b:gnosis_table_csv_path = l:csv_path

  setlocal filetype=csv
  setlocal nowrap
  setlocal nonumber
  setlocal norelativenumber
  setlocal foldcolumn=0
  setlocal signcolumn=no
  setlocal textwidth=0

  augroup gnosis_table_csv_editor
    autocmd! * <buffer>
  augroup END
  nnoremap <silent><buffer> q  <Cmd>bd!<CR>
  echo 'TableCsvEdit: editing ' . fnamemodify(l:csv_path, ':t') . ' (use :TableCsvApplySaved to apply)'
endfunction

function! gnosis#table_csv_editor_apply(...) abort
  if a:0 >= 1
    let l:buf = a:1
  else
    let l:buf = bufnr('%')
    " カレントバッファがCSVエディタでなければ、全バッファから探す
    if !getbufvar(l:buf, 'gnosis_table_csv_editor', 0)
      let l:buf = -1
      for l:b in range(1, bufnr('$'))
        if bufexists(l:b) && getbufvar(l:b, 'gnosis_table_csv_editor', 0)
          let l:buf = l:b
          break
        endif
      endfor
    endif
  endif
  if l:buf < 0 || !getbufvar(l:buf, 'gnosis_table_csv_editor', 0)
    echoerr 'TableCsvEdit: not a TableCsvEdit CSV buffer'
    return
  endif

  let l:src_buf = getbufvar(l:buf, 'gnosis_table_src_bufnr', -1)
  let l:src_start = getbufvar(l:buf, 'gnosis_table_src_start', 0)
  let l:src_end = getbufvar(l:buf, 'gnosis_table_src_end', 0)
  let l:indent = getbufvar(l:buf, 'gnosis_table_src_indent', '')
  let l:src_win = bufwinid(l:src_buf)

  if bufloaded(l:buf)
    let l:csv_lines = getbufline(l:buf, 1, '$')
  else
    let l:csv_path = getbufvar(l:buf, 'gnosis_table_csv_path', bufname(l:buf))
    if empty(l:csv_path) || !filereadable(l:csv_path)
      echoerr 'TableCsvEdit: CSV file not found'
      return
    endif
    let l:csv_lines = readfile(l:csv_path)
  endif

  let l:new_end = s:table_csv_apply_to_source(l:csv_lines, l:src_buf, l:src_start, l:src_end, l:indent)
  if l:new_end <= 0
    return
  endif

  call setbufvar(l:buf, 'gnosis_table_src_end', l:new_end)

  if l:src_win > 0
    call win_gotoid(l:src_win)
  else
    execute 'keepalt buffer ' . l:src_buf
  endif
  call cursor(l:src_start, 1)

  if bufnr('%') == l:src_buf
    silent! write
  endif

  echo 'CSV changes applied to table'
endfunction

function! gnosis#table_csv_editor_apply_saved(...) abort
  let l:buf = a:0 >= 1 ? a:1 : bufnr('%')
  call gnosis#table_csv_editor_apply(l:buf)
endfunction


" ---------------------------------------------------------------------------
" テーブル行・列の追加・削除
" ---------------------------------------------------------------------------

" カーソル行をテーブルから削除（ヘッダ行・セパレータ行は削除不可）
function! gnosis#table_del_row() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table row'
    return
  endif
  if s:is_table_separator(getline(l:lnum))
    echo 'Cannot delete separator row'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  if l:lnum == l:start
    echo 'Cannot delete header row'
    return
  endif
  let l:data_rows = 0
  for l:i in range(l:start, l:end)
    if !s:is_table_separator(getline(l:i)) && l:i != l:start
      let l:data_rows += 1
    endif
  endfor
  if l:data_rows <= 1
    echo 'Cannot delete the last data row'
    return
  endif
  execute l:lnum . 'delete _'
  call s:table_align_block(l:start, l:end - 1)
endfunction

" カーソル列をテーブルから削除
function! gnosis#table_del_col() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table column'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  let l:cols = s:table_col_count(l:start, l:end)
  if l:cols <= 1
    echo 'Cannot delete the last column'
    return
  endif
  let l:col_idx = s:table_cell_index_from_col(getline(l:lnum), col('.'))
  if l:col_idx < 0 || l:col_idx >= l:cols
    echo 'Cursor is not inside a cell'
    return
  endif
  for l:i in range(l:start, l:end)
    let l:parsed = s:parse_table_line(getline(l:i))
    if len(l:parsed.cells) <= l:col_idx
      continue
    endif
    call remove(l:parsed.cells, l:col_idx)
    if l:parsed.sep
      let l:new_cells = map(copy(l:parsed.cells), '"---"')
      call setline(l:i, l:parsed.indent . '| ' . join(l:new_cells, ' | ') . ' |')
    else
      call setline(l:i, l:parsed.indent . '| ' . join(l:parsed.cells, ' | ') . ' |')
    endif
  endfor
  call s:table_align_block(l:start, l:end)
endfunction

" カーソル行の下に空行を追加
function! gnosis#table_add_row() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table row'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  let l:cols = s:table_col_count(l:start, l:end)
  let l:indent = matchstr(getline(l:start), '^\s*')
  let l:insert_after = l:lnum
  if l:insert_after < l:end && s:is_table_separator(getline(l:insert_after + 1))
    let l:insert_after += 1
  endif
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:insert_after + 1, s:table_cell_startcol(getline(l:insert_after + 1), 1))
endfunction

" カーソル列の右に空列を追加
function! gnosis#table_add_col() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table column'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  let l:cols = s:table_col_count(l:start, l:end)
  let l:col_idx = s:table_cell_index_from_col(getline(l:lnum), col('.'))
  if l:col_idx < 0
    let l:col_idx = l:cols - 1
  endif
  let l:insert_at = l:col_idx + 1
  for l:i in range(l:start, l:end)
    let l:parsed = s:parse_table_line(getline(l:i))
    let l:pos = min([l:insert_at, len(l:parsed.cells)])
    if l:parsed.sep
      call insert(l:parsed.cells, '---', l:pos)
      let l:new_cells = map(copy(l:parsed.cells), '"---"')
      call setline(l:i, l:parsed.indent . '| ' . join(l:new_cells, ' | ') . ' |')
    else
      call insert(l:parsed.cells, '', l:pos)
      call setline(l:i, l:parsed.indent . '| ' . join(l:parsed.cells, ' | ') . ' |')
    endif
  endfor
  call s:table_align_block(l:start, l:end)
endfunction

" ---------------------------------------------------------------------------
" CopyStack Mode  (スタック選択コピー)
" ---------------------------------------------------------------------------
" 使い方:
"   :CopyStack  モード開始 / 2回目でコミット（クリップボードに書いて終了）
"   y           ノーマル: 現在行をスタックに追加
"               ビジュアル: 選択範囲をスタックに追加
" ---------------------------------------------------------------------------

let s:stack_copy_mode  = 0
let s:stack_copy_lines = []
let s:stack_copy_stl_save = ''
let s:stack_copy_wbr_save = ''

function! s:stack_copy_statusline_on() abort
  let s:stack_copy_stl_save = &l:statusline
  if exists('+winbar')
    let s:stack_copy_wbr_save = &l:winbar
  else
    let s:stack_copy_wbr_save = ''
  endif
  setlocal statusline=%#WarningMsg#\ [CopyStack]\ %*%f\ %m%=%l/%L
  if exists('+winbar')
    let &l:winbar = gnosis#i18n#tr('%#WarningMsg# [CopyStack] y:追加  d:切り取り  :CopyStack:確定/終了 %#Normal#')
  endif
endfunction

function! s:stack_copy_statusline_off() abort
  if s:stack_copy_stl_save ==# ''
    setlocal statusline&
  else
    let &l:statusline = s:stack_copy_stl_save
  endif
  if exists('+winbar')
    if s:stack_copy_wbr_save ==# ''
      setlocal winbar&
    else
      let &l:winbar = s:stack_copy_wbr_save
    endif
  endif
  let s:stack_copy_stl_save = ''
  let s:stack_copy_wbr_save = ''
endfunction

function! s:stack_copy_finish(copy_to_clipboard) abort
  if a:copy_to_clipboard && !empty(s:stack_copy_lines)
    let l:text = join(s:stack_copy_lines, "\n")
    let @" = l:text
    call gnosis#clipboard_copy(l:text)
  else
    
  endif
  silent! nunmap <buffer> y
  silent! xunmap <buffer> y
  silent! nunmap <buffer> d
  silent! xunmap <buffer> d
  call s:stack_copy_statusline_off()
  let s:stack_copy_mode  = 0
  let s:stack_copy_lines = []
endfunction

function! gnosis#stack_copy_toggle() abort
  if !s:stack_copy_mode
    let s:stack_copy_mode  = 1
    let s:stack_copy_lines = []
    nnoremap <buffer> <silent> <nowait> y :<C-u>call gnosis#stack_copy_yank_line()<CR>
    xnoremap <buffer> <silent> <nowait> y :<C-u>call gnosis#stack_copy_yank_visual()<CR>
    nnoremap <buffer> <silent> <nowait> d :<C-u>call gnosis#stack_copy_delete_line()<CR>
    xnoremap <buffer> <silent> <nowait> d :<C-u>call gnosis#stack_copy_delete_visual()<CR>
    call s:stack_copy_statusline_on()
    
  else
    call s:stack_copy_finish(!empty(s:stack_copy_lines))
  endif
endfunction

function! gnosis#stack_copy_yank_line() abort
  let l:line = getline('.')
  call add(s:stack_copy_lines, l:line)
  
endfunction

function! gnosis#stack_copy_yank_visual() abort range
  let l:s = line("'<")
  let l:e = line("'>")
  for l:i in range(l:s, l:e)
    call add(s:stack_copy_lines, getline(l:i))
  endfor
  
endfunction

function! gnosis#stack_copy_delete_line() abort
  let l:line = getline('.')
  call add(s:stack_copy_lines, l:line)
  execute 'delete _'
  
endfunction

function! gnosis#stack_copy_delete_visual() abort range
  let l:s = line("'<")
  let l:e = line("'>")
  for l:i in range(l:s, l:e)
    call add(s:stack_copy_lines, getline(l:i))
  endfor
  execute "normal! <Esc>"
  execute "'<,'>delete _"
  
endfunction

function! s:toggle_checkbox_in_line(lnum) abort
  let l:line = getline(a:lnum)
  let l:start = 0
  let l:best = []
  while 1
    let l:m = matchstrpos(l:line, '\[[ xX]\]', l:start)
    if empty(l:m) || l:m[1] < 0
      break
    endif
    if a:lnum == line('.') && col('.') - 1 >= l:m[1] && col('.') - 1 <= l:m[2] - 1
      let l:best = l:m
      break
    endif
    if empty(l:best)
      let l:best = l:m
    endif
    let l:start = l:m[2]
  endwhile
  if empty(l:best)
    return 0
  endif
  let l:mark = strpart(l:best[0], 1, 1)
  let l:new = (l:mark =~# '[xX]') ? '[ ]' : '[x]'
  let l:newline = strpart(l:line, 0, l:best[1]) . l:new . strpart(l:line, l:best[2])
  call setline(a:lnum, l:newline)
  return 1
endfunction

function! gnosis#toggle_checkbox(first, last, has_range) abort range
  if a:has_range
    for l:lnum in range(a:first, a:last)
      call s:toggle_checkbox_in_line(l:lnum)
    endfor
    return
  endif
  if !s:toggle_checkbox_in_line(line('.'))
    echo 'No checkbox ([ ] / [x]) on this line'
  endif
endfunction

" ---------------------------------------------------------------------------
" Image gallery: open current Markdown note as a browser thumbnail grid
" ---------------------------------------------------------------------------

function! s:python_executable() abort
  return gnosis#python_cmd()
endfunction


function! s:line_has_image_link(line) abort
  let l:image_ext = '\%(avif\|bmp\|gif\|jpe\?g\|png\|svg\|webp\)'
  return a:line =~# '!\[\%(\\.\|[^\]\\]\)*\]([^)]\+)'
        \ || a:line =~? '\[\%(\\.\|[^\]\\]\)*\]([^)]*\.' . l:image_ext . '\%([#?][^)]*\)\?)'
        \ || a:line =~? '!?\[\[[^]|]\+\.' . l:image_ext . '\%([#?][^]|]\)*\%(|[^]]*\)\?\]\]'
        \ || (a:line =~? '<img' && a:line =~? 'src\s*=')
endfunction

function! s:buffer_has_image_link() abort
  for l:line in getline(1, '$')
    if s:line_has_image_link(l:line)
      return 1
    endif
  endfor
  return 0
endfunction

function! s:index_root_from_path(path) abort
  let l:path = fnamemodify(expand(a:path), ':p')
  let l:dir = isdirectory(l:path) ? l:path : fnamemodify(l:path, ':h')
  while !empty(l:dir)
    if filereadable(l:dir . s:sep() . 'index.md')
      return l:dir
    endif
    let l:parent = fnamemodify(l:dir, ':h')
    if l:parent ==# l:dir
      break
    endif
    let l:dir = l:parent
  endwhile
  return ''
endfunction

function! s:gallery_root() abort
  let l:root = fnamemodify(expand(get(g:, 'gnosis_root', '')), ':p')
  if !empty(l:root) && isdirectory(l:root)
    return l:root
  endif
  return s:index_root_from_path(expand('%:p'))
endfunction

function! s:run_gallery_command(args, label) abort
  let l:py = get(g:, 'gnosis_gallery_python', '')
  if empty(l:py) || !filereadable(l:py)
    echoerr 'Gnosis: gallery.py not found: ' . l:py
    return
  endif
  let l:port = get(g:, 'gnosis_gallery_port', 8765)
  let l:cmd = [s:python_executable(), l:py] + a:args + ['--port', string(l:port)]

  if exists('*jobstart')
    call jobstart(l:cmd, {'detach': v:true})
    echom 'Gnosis: opening gallery for ' . a:label
    return
  endif
  if exists('*job_start')
    call job_start(l:cmd, {'out_io': 'null', 'err_io': 'null'})
    echom 'Gnosis: opening gallery for ' . a:label
    return
  endif

  let l:result = system(join(map(copy(l:cmd), 'shellescape(v:val)'), ' '))
  if v:shell_error
    echohl ErrorMsg | echom 'Gnosis Gallery failed: ' . l:result | echohl None
  else
    echom 'Gnosis: opening gallery for ' . a:label
  endif
endfunction

function! gnosis#open_folder_gallery(...) abort
  let l:target = a:0 >= 1 && !empty(a:1) ? a:1 : s:gallery_root()
  if empty(l:target)
    let l:target = expand('%:p')
  endif
  if empty(l:target)
    let l:target = getcwd()
  endif
  let l:path = fnamemodify(expand(l:target), ':p')
  let l:dir = isdirectory(l:path) ? l:path : fnamemodify(l:path, ':h')
  if empty(l:dir) || !isdirectory(l:dir)
    echoerr 'Gnosis: folder not found: ' . l:dir
    return
  endif
  call s:run_gallery_command(['--open-folder', l:dir], fnamemodify(l:dir, ':t'))
endfunction

function! gnosis#open_gallery(...) abort
  let l:file = a:0 >= 1 && !empty(a:1) ? a:1 : expand('%:p')
  if empty(l:file)
    echoerr 'Gnosis: Gallery requires a Markdown file'
    return
  endif
  let l:file = fnamemodify(expand(l:file), ':p')
  if !filereadable(l:file)
    echoerr 'Gnosis: file not found: ' . l:file
    return
  endif
  if l:file !~? '\.md$'
    echoerr 'Gnosis: Gallery can only open Markdown files'
    return
  endif
  if get(g:, 'gnosis_auto_save_on_command', 1) && expand('%:p') ==# l:file && &modified
    silent write
  endif
  let l:args = ['--open', l:file]
  let l:root = s:gallery_root()
  if !empty(l:root)
    call extend(l:args, ['--root', l:root])
  endif
  call s:run_gallery_command(l:args, fnamemodify(l:file, ':t'))
endfunction


function! gnosis#open_gallery_smart() abort
  if s:is_markdown_file(expand('%:p')) && s:buffer_has_image_link()
    call gnosis#open_gallery()
  else
    call gnosis#open_folder_gallery()
  endif
endfunction


" ---------------------------------------------------------------------------
" Web app (ブラウザで閲覧・編集)
"   ノート実体と同じフォルダをブラウザ (Brave/Chrome) から直接読み書きする。
"   サーバーは立てない。同期ロジックは JS 移植 (web/src/sync.js)。
"   起動: :GnosisWeb / \A
" ---------------------------------------------------------------------------
function! gnosis#open_web() abort
  " 関数内の <sfile> は信用できない（現在のバッファ名になることがある）。
  " Python スクリプトのパス (…/Gnosis/python/… or legacy/…) から
  " プラグインルートを導出する。
  if !exists('g:gnosis_python') || empty(g:gnosis_python)
    echoerr 'Gnosis: g:gnosis_python is not set'
    return
  endif
  let l:webdir = fnamemodify(g:gnosis_python, ':h:h') . '/web'
  let l:root = s:get_pkm_root()
  " アプリは disk を読むので、編集中のノートは先に書き出す（古い内容で開かない）
  if gnosis#is_vault_note(expand('%:p'))
    call gnosis#save_current_note()
  endif
  " デスクトップアプリ (Electron)。今の vault と、今開いているノートを渡して起動する。
  " Linux / macOS はランチャー（bin/gnosis --app。KDE Wayland 向けの起動オプション付き）、
  " Windows は実体の electron.exe を直接起動する。
  let l:env = {'GNOSIS_HOME': gnosis#home#dir()}
  if !empty($MYVIMRC) && get(g:, 'gnosis_managed', 0)
    let l:env.GNOSIS_VIMRC = $MYVIMRC
  endif
  if !empty(l:root)
    let l:env.GNOSIS_ROOT = fnamemodify(l:root, ':p')
  endif
  if gnosis#is_vault_note(expand('%:p'))
    let l:env.GNOSIS_FILE = expand('%:p')
  endif
  let l:launcher = fnamemodify(l:webdir, ':h') . '/bin/gnosis'
  if has('win32')
    let l:cmd = [l:webdir . '/node_modules/electron/dist/electron.exe', l:webdir]
  else
    let l:cmd = [l:launcher, '--app']
  endif
  if executable(l:cmd[0]) && filereadable(l:webdir . '/electron/main.cjs')
        \ && (has('win32') || executable(l:webdir . '/node_modules/.bin/electron'))
    call job_start(l:cmd, {'out_io': 'null', 'err_io': 'null', 'env': l:env, 'stoponexit': ''})
    echo 'Gnosis app: ' . (empty(l:root) ? '' : fnamemodify(l:root, ':p'))
    return
  endif
  echohl WarningMsg
  echo 'Gnosis: ' . gnosis#i18n#tr('アプリが入っていません（install/install.sh または install\install.ps1 で入れます）')
  echohl NONE
endfunction




function! gnosis#exit_cleanup() abort
  " 履歴（コマンド履歴・タイトル入力履歴・recent）は vault 内 .state/ に
  " 残す方針に変更（消すと不便）。vault が暗号化されると履歴も暗号化される。
  return
endfunction


" ---------------------------------------------------------------------------
" vault の暗号（gocryptfs箱・透過）
"   ・起動時にロック中ならパスワードを聞いてマウント
"   ・終了時は自動でロック（マウント解除）
"   ・:GnosisSetPassword でパスワード変更（マウント中でもOK）
" 暗号実体: <vault>.crypt（vault の隣。中身はみんな暗号化、ファイル名も暗号化）
" ---------------------------------------------------------------------------

" vault(=ノートroot) の末尾スラッシュを整えて返す
function! s:vault_clean() abort
  let l:root = s:get_pkm_root()
  if empty(l:root)
    return ''
  endif
  return substitute(l:root, s:sep() . '\+$', '', '')
endfunction

" dir の中に何かあるか（'.'/'..' は数えない）
function! s:dir_has_content(dir) abort
  if !isdirectory(a:dir)
    return 0
  endif
  if exists('*readdir')
    return !empty(readdir(a:dir))
  endif
  let l:ls = split(glob(a:dir . s:sep() . '*', 1), "\n")
  let l:ls += filter(split(glob(a:dir . s:sep() . '.*', 1), "\n"),
        \ 'fnamemodify(v:val, ":t") !~# ''^\.\{1,2}$''')
  return !empty(l:ls)
endfunction

" 暗号箱の場所（g:gnosis_cipher_dir で上書き可）
" 「A/note を vault、暗号実体は A/.crypt」が正規（兄弟構成＝自己包括なし）。
" 旧配置も探す: A/.note-crypt（A/note 時代の名残）/ <root>.crypt。
" conf がある場所を優先。どれも無ければ新規用に正規の場所を返す。
function! gnosis#cipher_dir() abort
  if !empty(get(g:, 'gnosis_cipher_dir', ''))
    return fnamemodify(expand(g:gnosis_cipher_dir), ':p')
  endif
  let l:root = s:vault_clean()
  if empty(l:root)
    return ''
  endif
  let l:parent = fnamemodify(l:root, ':h') . s:sep()
  if fnamemodify(l:root, ':t') ==# 'note'
    " A/note 型: 正規は A/.crypt
    let l:cand = [
          \ l:parent . '.crypt',
          \ l:parent . '.note-crypt',
          \ l:root . '.crypt',
          \ ]
  else
    " 旧来の root 直置き型: 正規は兄弟の .<name>-crypt（親の .crypt は共用事故になるため後ろ）
    let l:cand = [
          \ l:parent . '.' . fnamemodify(l:root, ':t') . '-crypt',
          \ l:parent . '.crypt',
          \ l:root . '.crypt',
          \ ]
  endif
  for l:c in l:cand
    if filereadable(l:c . s:sep() . 'gocryptfs.conf')
      return l:c
    endif
  endfor
  return l:cand[0]
endfunction

" FUSE マウント状態（1=マウント中 / 0=ロック中）。a:1=vault指定、a:2=1で再取得
function! gnosis#vault_mounted(...) abort
  let l:root = empty(a:000) ? s:vault_clean() : a:1
  if empty(l:root)
    return -1
  endif
  if !exists('s:mounted_cache')
    let s:mounted_cache = {'time': 0, 'val': -1}
  endif
  let l:now = reltimefloat(reltime())
  " キャッシュは vault ごとに持つ（別 vault の値を返すと、切替時にロックが抜ける）
  if !get(a:000, 1, 0) && get(s:mounted_cache, 'root', '') ==# l:root
        \ && s:mounted_cache.val >= 0 && l:now - s:mounted_cache.time < 2
    return s:mounted_cache.val
  endif
  call system('mountpoint -q ' . shellescape(l:root))
  let s:mounted_cache = {'root': l:root, 'time': l:now, 'val': v:shell_error == 0 ? 1 : 0}
  return s:mounted_cache.val
endfunction

function! s:mount_cache_reset() abort
  if exists('s:mounted_cache')
    let s:mounted_cache.val = -1
  endif
endfunction

" mountpoint 直下のゴミ（.state / .undo）を gocryptfs のマウント前に削除する。
" ロック中に vimrc やプラグインの初期化が mountpoint に書いてしまったファイルが
" あると、gocryptfs は空でないマウントポイントを拒否する。
function! s:clear_mountpoint_garbage(root) abort
  if empty(a:root) || !isdirectory(a:root)
    return
  endif
  for l:name in ['.state', '.undo']
    let l:dir = a:root . s:sep() . l:name
    if isdirectory(l:dir)
      call system('rm -rf ' . shellescape(l:dir))
    endif
  endfor
endfunction

" vault の暗号状態を1か所で判定して返す。判定が各所に散ると、ある経路で変数が
" 未定義になる／平文とロックを取り違える（2026-10-08 の E121 の原因）ので、
" mount/lock/set_password はこれを使う。
"   layout     : 'note'（A/note 型）| 'flat'（A 直置き型）
"   cipher     : 暗号箱パス（conf があればそれ、無ければ新規候補）
"   has_cipher : gocryptfs.conf が読めるか
"   mounted    : FUSE マウント中か
"   plain_flat : 直置き型で中身がある（＝平文 vault。旧暗号箱が残っていても暗号扱いしない）
"   encrypted  : :GnosisSetPassword 用。マウント中 or 暗号箱あり（plain_flat を除く）
"   locked     : ロック中（暗号箱あり・未マウント・平文再作成でない）
function! s:vault_status() abort
  let l:root = s:vault_clean()
  let l:st = {'root': l:root, 'layout': '', 'cipher': '', 'has_cipher': 0,
        \ 'mounted': 0, 'plain_flat': 0, 'encrypted': 0, 'locked': 0}
  if empty(l:root)
    return l:st
  endif
  let l:st.layout = fnamemodify(l:root, ':t') ==# 'note' ? 'note' : 'flat'
  let l:st.cipher = gnosis#cipher_dir()
  let l:st.has_cipher = !empty(l:st.cipher) && filereadable(l:st.cipher . s:sep() . 'gocryptfs.conf')
  let l:st.mounted = (gnosis#vault_mounted() == 1)
  let l:st.plain_flat = (l:st.layout ==# 'flat' && s:dir_has_content(l:root))
  let l:st.encrypted = l:st.mounted || (l:st.has_cipher && !l:st.plain_flat)
  let l:st.locked = l:st.has_cipher && !l:st.mounted && !l:st.plain_flat
  return l:st
endfunction

" vault が暗号箱持ちでロック中なら 1（暗号箱なし vault はいつも 0）
function! gnosis#vault_locked_flag() abort
  return s:vault_status().locked
endfunction

" パスワードを含む一時ファイルを消す（shred があれば上書きしてから削除）
function! s:secure_delete(path) abort
  if executable('shred')
    call system('shred -u -n 1 ' . shellescape(a:path) . ' 2>/dev/null')
  endif
  call delete(a:path)
endfunction

" 一時パスワードファイル（0600, すぐ消す）
function! s:temp_passfile(pw) abort
  let l:pf = tempname()
  " 先に 0600 で作ってから書く（writefile の後で chmod すると一瞬だけ他人に読める）
  call system('install -m 600 /dev/null ' . shellescape(l:pf))
  call s:syn_writefile([a:pw], l:pf)
  return l:pf
endfunction

" vault をアンマウントして、実際に切れるまで待つ。切れたら 1、切れなければ 0。
" 終了時に遅延アンマウント（-z）だけを投げると、切れかけのマウントが残って、すぐ開き直したときに
" マウントに失敗する。そこで: 1) 普通のアンマウントを、使用中なら少し待って 10 回までやり直す
" 2) それでも切れなければ最後の手段で遅延アンマウント 3) 実際に切れるまで最大 3 秒待つ。
function! s:unmount_vault(root) abort
  let l:r = shellescape(a:root)
  for l:i in range(10)
    call system('fusermount3 -u ' . l:r . ' 2>&1')
    call s:mount_cache_reset()
    if gnosis#vault_mounted(a:root, 1) != 1
      return 1
    endif
    execute 'sleep 200m'
  endfor
  call system('fusermount3 -u -z ' . l:r . ' 2>&1')
  for l:i in range(15)
    call s:mount_cache_reset()
    if gnosis#vault_mounted(a:root, 1) != 1
      return 1
    endif
    execute 'sleep 200m'
  endfor
  return 0
endfunction

" 前回の切れかけ／壊れたマウント（デーモンが死んで stat が「Transport endpoint is not connected」に
" なるなど）が残っていたら、マウントする前に片付ける。マウントポイントが /proc/mounts にあるのに
" stat できないときだけ動く。普通の状態（ロック中・マウント中）には何もしない。
function! s:release_stale_mount(root) abort
  if empty(a:root) || !filereadable('/proc/mounts')
    return
  endif
  let l:rootp = substitute(fnamemodify(a:root, ':p'), s:sep() . '\+$', '', '')
  let l:listed = !empty(filter(readfile('/proc/mounts'), {_, l -> get(split(l), 1, '') ==# l:rootp}))
  if !l:listed
    return
  endif
  call system('stat ' . shellescape(l:rootp) . ' 2>&1')
  if v:shell_error == 0
    return
  endif
  call system('fusermount3 -u -z ' . shellescape(l:rootp) . ' 2>&1')
  for l:i in range(15)
    call system('stat ' . shellescape(l:rootp) . ' 2>&1')
    if v:shell_error == 0
      break
    endif
    execute 'sleep 200m'
  endfor
  call s:mount_cache_reset()
endfunction

" パスワードを聞いてマウント（成功=1、空入力/3回失敗=0）
" マウント前に mountpoint 内のゴミ（.state / .undo / hacks 等）を掃除する。
" gocryptfs は「空でないマウントポイント」を拒否するため、起動時の vimrc や
" プラグインの初期化がロック中に mountpoint へファイルを作ると、正しいパスワード
" でもマウントに失敗する。
" この Vim 自身がマウントしたか。アプリ（\A）が起動する Vim は、別の Vim が先にマウントした vault を
" 終了時にアンマウントしない（アンマウントすると元の Vim が使えなくなり、次にまたパスワードを聞かれる）。
let s:mounted_by_me = 0

function! s:mount_by_password(cipher, root) abort
  call s:release_stale_mount(a:root)
  call s:clear_mountpoint_garbage(a:root)
  for l:i in range(3)
    let l:pw = inputsecret('vault password: ')
    if empty(l:pw)
      echom gnosis#i18n#tr('Gnosis: マウントせず終了（:GnosisMount で再試行）')
      return 0
    endif
    let l:pf = s:temp_passfile(l:pw)
    " 失敗の理由を見分ける: gocryptfs は「パスワードが違う」とき終了コード 12 を返す。それ以外の失敗
    " （前回の遅延アンマウントがまだ残っている・マウントポイントが使用中 など）は、パスワードの間違いと
    " 区別して、同じパスワードで少し待ってやり直す。
    let l:out = ''
    let l:code = 0
    for l:try in range(4)
      let l:out = system('gocryptfs -passfile=' . shellescape(l:pf) . ' '
            \ . shellescape(a:cipher) . ' ' . shellescape(a:root) . ' 2>&1')
      let l:code = v:shell_error
      call s:mount_cache_reset()
      " 成功してもマウントの反映が少し遅れることがあるので、短く待って確かめる
      for l:w in range(10)
        if gnosis#vault_mounted(escape(a:root, '\\'), 1) == 1
          break
        endif
        execute 'sleep 150m'
        call s:mount_cache_reset()
      endfor
      if gnosis#vault_mounted(escape(a:root, '\\'), 1) == 1 || l:code == 12
        break
      endif
      execute 'sleep 700m'
    endfor
    call s:secure_delete(l:pf)
    call s:mount_cache_reset()
    if gnosis#vault_mounted(escape(a:root, '\\'), 1) == 1
      let s:mounted_by_me = 1
      redraw
      return 1
    endif
    echohl ErrorMsg
    if l:code == 12
      echom gnosis#i18n#tr('Gnosis: パスワードが違う (') . (l:i + 1) . '/3)'
    else
      " パスワードの間違いではない失敗。本当の理由を出す
      let l:why = trim(get(split(l:out, "\n"), -1, ''))
      echom gnosis#i18n#tr('Gnosis: マウントできません（パスワードの間違いではありません・終了コード ') . l:code . '）: ' . l:why
    endif
    echohl NONE
  endfor
  return 0
endfunction

" 起動時: encrypted vault がロック中ならパスワードを聞き、マウントしたらバッファを
" 復号した内容に差し替える。headless/テストは g:gnosis_skip_interactive_mount
function! gnosis#maybe_mount_interactive() abort
  if get(g:, 'gnosis_skip_interactive_mount', 0) || (!empty($GNOSIS_HEADLESS) || !empty($YURII_NOTE_HEADLESS))
    return
  endif
  let l:cipher = gnosis#cipher_dir()
  let l:root = s:vault_clean()
  if empty(l:cipher) || empty(l:root)
    return
  endif
  if !filereadable(l:cipher . s:sep() . 'gocryptfs.conf')
    return
  endif
  call s:release_stale_mount(l:root)
  if !isdirectory(l:root)
    " mountpoint が無いと gocryptfs はマウントできない。yurii-note は
    " 死んだ root.txt が残っているだけかもしれないので、聞かずに止める。
    echom gnosis#i18n#tr('Gnosis: vault ディレクトリが無いのでマウントできません: ') . l:root
    return
  endif
  if gnosis#vault_mounted() == 1
    return
  endif
  redraw
  if s:mount_by_password(l:cipher, l:root) != 1
    return
  endif
  call s:adopt_vault_runtime(l:root)
  call gnosis#reload_vault_buffers()
  " パスワード待ちの間に他経路の起動タイマー（GnosisIndex 等）はロック中として
  " 空振りしている。マウントできたここで Index を開き直す。
  call timer_start(0, {-> execute('GnosisIndex')})
endfunction

" :GnosisMount（手動マウント）
function! gnosis#mount_vault() abort
  let l:cipher = gnosis#cipher_dir()
  let l:root = s:vault_clean()
  if empty(l:cipher) || empty(l:root) || !filereadable(l:cipher . s:sep() . 'gocryptfs.conf')
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 暗号箱(') . l:cipher . gnosis#i18n#tr(')がありません（このvaultは暗号化されていません）')
    echohl NONE
    return
  endif
  if gnosis#vault_mounted() == 1
    echom gnosis#i18n#tr('Gnosis: 既にマウント済み')
    return
  endif
  if s:mount_by_password(l:cipher, l:root) != 1
    return
  endif
  call s:adopt_vault_runtime(l:root)
  call gnosis#reload_vault_buffers()
  echom 'Gnosis: vault unlocked'
endfunction

" vault が cwd のままだと fusermount が "Device or resource busy" で
" 失敗し、終了時にロックされない。アンマウント前に vault の外へ出る。
function! s:cd_out_of_vault(root) abort
  let l:rootp = substitute(fnamemodify(a:root, ':p'), s:sep() . '\+$', '', '')
  if empty(l:rootp)
    return
  endif
  let l:cwd = substitute(fnamemodify(getcwd(), ':p'), s:sep() . '\+$', '', '')
  if l:cwd ==# l:rootp || stridx(l:cwd, l:rootp . s:sep()) == 0
    silent! execute 'cd ' . fnameescape(expand('~'))
  endif
endfunction

" vault をロックする前: 履歴を vault 内へ書き出し、以後の書き先を無効化する。
" アンマウント後に &viminfofile / undodir が vault 内を指したまま平文の
" mountpoint に書かれるのを防ぐ（vault 外に平文の履歴を残さない）。
function! s:release_vault_runtime() abort
  silent! wviminfo
  set viminfofile=
  set noundofile
endfunction

" VimLeavePre: viminfo はこの後（VimLeave の前）に書かれる。ロック中のまま
" 終了する場合、書き先を無効化して mountpoint に平文を作らない保険。
function! gnosis#before_write_viminfo() abort
  if gnosis#vault_locked_flag() == 1
    set viminfofile=
    set noundofile
  endif
endfunction

" :GnosisLock（保存フラッシュしてからアンマウント）
function! gnosis#lock_vault() abort
  let l:root = s:vault_clean()
  if empty(l:root)
    return
  endif
  if gnosis#vault_mounted() != 1
    echom gnosis#i18n#tr('Gnosis: vault は既にロック中です')
    return
  endif
  call gnosis#save_current_note()
  for l:b in range(1, bufnr('$'))
    if !buflisted(l:b) || l:b == bufnr('%')
      continue
    endif
    let l:p = fnamemodify(bufname(l:b), ':p')
    if stridx(l:p, fnamemodify(l:root, ':p')) == 0 && getbufvar(l:b, '&modified')
      execute 'silent! buffer ' . l:b
      silent! update
    endif
  endfor
  call s:release_vault_runtime()
  call s:cd_out_of_vault(l:root)
  " 通常アンマウント（-z は使わない）。busy なら失敗させて「ロック失敗」を正しく出す。
  " lazy unmount だと見かけ上ロックされたまま平文が残るため。
  call system('fusermount3 -u ' . shellescape(l:root))
  call s:mount_cache_reset()
  if v:shell_error != 0 || gnosis#vault_mounted(escape(l:root, '\\'), 1) == 1
    echohl WarningMsg
    echom gnosis#i18n#tr('Gnosis: 他アプリが開いていてロック失敗。閉じてから再度 :GnosisLock')
    echohl NONE
    return
  endif
  echom 'Gnosis: vault locked'
endfunction

" :GnosisBackup [出力先ディレクトリ]
" vault のプロジェクトフォルダ（.crypt・その他全部。note/ の中身は .crypt の複製なので
" 除く。直置き型は .crypt のみ）を 7z にまとめる。vault のパスワードで暗号化（ファイル名も隠す）し、出力は
" <出力先>/<YYYYmmddHHMMSS>-<プロジェクト名>.7z。出力先は引数 →
" g:gnosis_backup_dir → 聞く、の順。
function! gnosis#backup_vault(...) abort
  let l:st = s:vault_status()
  if !l:st.has_cipher
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 暗号箱がないのでバックアップできません（暗号化されていない vault）')
    echohl NONE
    return
  endif
  if !executable('7z') || !executable('gocryptfs')
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 7z と gocryptfs が必要です')
    echohl NONE
    return
  endif
  let l:dest = a:0 && !empty(a:1) ? a:1 : get(g:, 'gnosis_backup_dir', '')
  if empty(l:dest)
    let l:dest = input(gnosis#i18n#tr('バックアップ先ディレクトリ: '), '', 'dir')
  endif
  let l:dest = fnamemodify(expand(l:dest), ':p')
  if empty(l:dest) || l:dest ==# fnamemodify('', ':p') || !isdirectory(l:dest)
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 出力先ディレクトリがありません: ') . l:dest
    echohl NONE
    return
  endif
  let l:pw = inputsecret('vault password: ')
  if empty(l:pw)
    echom gnosis#i18n#tr('Gnosis: バックアップを中止')
    return
  endif
  call gnosis#backup_vault_with(l:pw, l:dest)
endfunction

" backup_vault の本体（パスワード検証→7z）。テストはここを直接呼ぶ。
function! gnosis#backup_vault_with(pw, dest) abort
  let l:pw = a:pw
  let l:dest = a:dest
  let l:st = s:vault_status()
  let l:cipher = fnamemodify(l:st.cipher, ':p:h')
  " 固める対象。A/note 型なら vault のプロジェクトフォルダ A ごと（note/・.crypt・
  " その他のファイル全部）。直置き型は暗号箱だけ。
  let l:target = l:st.layout ==# 'note' ? fnamemodify(l:st.root, ':p:h:h') : l:cipher
  if stridx(l:dest, l:target . s:sep()) == 0 || l:dest ==# l:target . s:sep()
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 出力先を vault の中にはできません')
    echohl NONE
    return
  endif
  let l:proj = fnamemodify(l:target, ':t')
  if l:st.layout !=# 'note'
    let l:proj = fnamemodify(l:st.root, ':t')
  endif
  let l:out = substitute(l:dest, s:sep() . '\+$', '', '') . s:sep()
        \ . strftime('%Y%m%d%H%M%S') . '-' . l:proj . '.7z'
  if filereadable(l:out)
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 既に存在します: ') . l:out
    echohl NONE
    return
  endif
  " vault と違うパスワードで固めると復元できなくなるので、先に gocryptfs で検証する
  let l:pf = s:temp_passfile(l:pw)
  call system('gocryptfs -fsck -passfile ' . shellescape(l:pf) . ' ' . shellescape(l:cipher) . ' 2>&1')
  let l:ok = v:shell_error == 0
  call s:secure_delete(l:pf)
  if !l:ok
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: パスワードが違う（または暗号箱が壊れています）')
    echohl NONE
    return
  endif
  " 7z は標準入力からパスワードを読む（コマンドラインに出さない）。2 回分を一時ファイルへ。
  let l:pf2 = tempname()
  call system('install -m 600 /dev/null ' . shellescape(l:pf2))
  call s:syn_writefile([l:pw, l:pw], l:pf2)
  let l:parent = fnamemodify(l:target, ':h')
  " note/ の中身はマウントして見ている .crypt の複製なので入れない（空の note/ だけ残す。
  " 復元後のマウント先に必要）。直置き型は固めるのが暗号箱だけなので除外なし。
  let l:excl = ''
  if l:st.layout ==# 'note'
    let l:excl = ' ' . shellescape('-x!' . fnamemodify(l:target, ':t') . '/' . fnamemodify(l:st.root, ':t') . '/*')
  endif
  let l:res = system('cd ' . shellescape(l:parent) . ' && 7z a -t7z -mhe=on -mx=1 -snl -p '
        \ . shellescape(l:out) . ' ' . shellescape(fnamemodify(l:target, ':t')) . l:excl . ' < ' . shellescape(l:pf2) . ' 2>&1')
  let l:rc = v:shell_error
  " 終了コード 1 は警告（マウント中の vault がバックアップ中に書き換わって、走査後に
  " 消えたファイルがあった等）。7z は出来ているので失敗扱いにしない。2 以上が失敗。
  let l:warn = l:rc == 1
  if l:rc >= 2 || !filereadable(l:out)
    call s:secure_delete(l:pf2)
    call delete(l:out)
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 7z 失敗: ') . substitute(l:res, '\n\+', ' ', 'g')[-200:]
    echohl NONE
    return
  endif
  " 出来た 7z がパスワードで開けて壊れていないか検査する
  call system('7z t ' . shellescape(l:out) . ' < ' . shellescape(l:pf2) . ' 2>&1')
  let l:tested = v:shell_error == 0
  call s:secure_delete(l:pf2)
  if !l:tested
    call delete(l:out)
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 7z の検査に失敗したので破棄しました')
    echohl NONE
    return
  endif
  if l:warn
    echohl WarningMsg
    echom gnosis#i18n#tr('Gnosis: 警告あり（バックアップ中に変更されたファイルがあった可能性）。保存中でない時にもう一度取ると確実です')
    echohl NONE
  endif
  echom gnosis#i18n#tr('Gnosis: バックアップ完了 → ') . l:out
endfunction

" Vim 終了 = 自動ロック（busy なら静かに諦める）

" 矢印キーなどの端末の制御文字列（ESC O D / ESC [ D など）が、キーとして解釈されず文字のまま
" ノートに入ってしまうことがある（「定^[OD、」のように見える）。入ったらその場で取り除く。
" 本物の ESC 文字（0x1b）を含む行だけが対象で、普通の文章には影響しない。
let s:stray_esc_pat = '\e\%(O[A-DFHPQRS]\|\[[0-9;]*[A-DFHPQRSZ~]\)'

function! gnosis#strip_stray_escape() abort
  if &buftype !=# '' || !&modifiable
    return
  endif
  let l:lnum = line('.')
  let l:line = getline(l:lnum)
  if stridx(l:line, "\x1b") < 0
    return
  endif
  let l:col = col('.')
  let l:new = substitute(l:line, s:stray_esc_pat, '', 'g')
  if l:new ==# l:line
    return
  endif
  " カーソルより手前で取り除いた分だけ、カーソルを戻す
  let l:before = substitute(strpart(l:line, 0, l:col - 1), s:stray_esc_pat, '', 'g')
  call setline(l:lnum, l:new)
  call cursor(l:lnum, strlen(l:before) + 1)
endfunction

function! gnosis#quit_unmount() abort
  if gnosis#vault_mounted() != 1
    return
  endif
  " アプリの Vim は、別の Vim がマウントした vault をそのままにして終わる（閉じるのは元の Vim の仕事）
  if !empty($SYN_GUI_PORT) && !s:mounted_by_me
    return
  endif
  let l:root = s:vault_clean()
  if empty(l:root)
    return
  endif
  call s:cd_out_of_vault(l:root)
  call s:unmount_vault(l:root)
  call s:mount_cache_reset()
endfunction

" :GnosisSetPassword（inputsecret で旧/新/確認。マウント中でもOK）
function! gnosis#set_password() abort
  let l:root = s:vault_clean()
  if empty(l:root)
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: vault(root) が決まっていません')
    echohl NONE
    return
  endif
  " 判定: 暗号化済み（=パスワード変更）か、未暗号化（=init）か。判定は
  " s:vault_status() に一元化（マウント中／A/note 型で conf あり／直置きで中身あり＝平文）。
  let l:st = s:vault_status()
  let l:cipher = l:st.cipher
  let l:encrypted = l:st.encrypted
  " 未暗号化 vault = 今からノート全体を暗号化して始める（init）
  if !l:encrypted
    return gnosis#init_encrypted()
  endif
  let l:old = inputsecret('Current password: ')
  if empty(l:old)
    return
  endif
  let l:new = inputsecret('New password: ')
  if empty(l:new)
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 空のパスワードは使えません。中止')
    echohl NONE
    return
  endif
  if l:new !=# inputsecret(gnosis#i18n#tr('New password (確認): '))
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 新パスワードが一致しません。中止')
    echohl NONE
    return
  endif
  let l:pold = s:temp_passfile(l:old)
  let l:out = system('gocryptfs -passwd -passfile=' . shellescape(l:pold) . ' '
        \ . shellescape(l:cipher) . ' 2>&1', l:new . "\n" . l:new . "\n")
  call s:secure_delete(l:pold)
  if v:shell_error == 0
    redraw
    echom gnosis#i18n#tr('Gnosis: パスワードを変更しました（次回のマウントから有効）')
  else
    let l:msg = trim(substitute(l:out, "\n", ' ', 'g'))[0:100]
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 変更失敗: ') . l:msg
    echohl NONE
  endif
endfunction

" 未暗号化 vault を gocryptfs 化する（ノート全部を暗号箱へ入れ替える）
"   必ず「プロジェクト A/note（mountpoint）↔ A/.crypt（暗号箱）」に正規化する。
"   root が note でない（ノートが直置き）ときは、暗号化と同時に
"   中身を A/note へ寄せてレイアウトを変換する（root も A/note に更新）。
"   mv root → <root-t>-plain-…（退避）→ mkdir → init → mount → cp → 検証 → 退避を消す
" 処理完了後もマウントは継続（そのまま作業できる）。閉じるとロック。
function! gnosis#init_encrypted() abort
  return s:init_encrypted_impl()
endfunction

" stage: mv→init→mount→copy→verify でcatch時に巻き戻る
function! s:init_encrypted_impl() abort
  let l:cur = s:vault_clean()
  if empty(l:cur)
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: vault(root) が決まっていません')
    echohl NONE
    return
  endif
  if gnosis#vault_mounted(escape(l:cur, '\\'), 1) == 1
    echohl WarningMsg
    echom gnosis#i18n#tr('Gnosis: 既にマウント済み（暗号化済み vault）。:GnosisSetPassword はパスワード変更用')
    echohl NONE
    return
  endif
  " vault 本体は常に A/note、暗号箱は A/.crypt（プロジェクトの中。隣には作らない）
  let l:proj = fnamemodify(l:cur, ':t') ==# 'note' ? fnamemodify(l:cur, ':h') : l:cur
  let l:proj = substitute(fnamemodify(l:proj, ':p'), s:sep() . '\+$', '', '')
  let l:root = l:proj . s:sep() . 'note'
  let l:cipher = l:proj . s:sep() . '.crypt'
  let l:converted = (l:root !=# substitute(fnamemodify(l:cur, ':p'), s:sep() . '\+$', '', ''))
  let l:new = inputsecret(gnosis#i18n#tr('vault の新しいパスワード: '))
  if empty(l:new)
    echom gnosis#i18n#tr('Gnosis: 中止（空パスワード）')
    return
  endif
  if l:new !=# inputsecret(gnosis#i18n#tr('もう一度（確認）: '))
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: パスワードが一致しません。中止')
    echohl NONE
    return
  endif
  " バッファの未保存分は、パスが有効な今のうちに書き出しておく
  call gnosis#save_current_note()
  " 退避（mv）で cwd のディレクトリが消えるので、vault の外へ出ておく
  call s:cd_out_of_vault(l:cur)
  let l:plaindir = fnamemodify(l:cur, ':h') . s:sep() . fnamemodify(l:cur, ':t') . '-plain-' . strftime('%Y%m%d%H%M%S')
  let l:n = trim(system('find ' . shellescape(l:cur) . ' -mindepth 1 2>/dev/null | wc -l'))
  " 数えられない（空・失敗）時も確認を飛ばさない
  if l:n !~# '^\d\+$' || str2nr(l:n) > 0
    let l:size = trim(system('du -sh ' . shellescape(l:cur) . ' 2>/dev/null | cut -f1'))
    let l:msg = l:converted
          \ ? printf(gnosis#i18n#tr('%s を暗号化して %s + %s にします：%s 個のファイル(%s)。よければ y: '),
          \          l:cur, l:root, l:cipher, l:n, l:size)
          \ : printf(gnosis#i18n#tr('%s を暗号化します：%s 個のファイル(%s)。よければ y: '), l:cur, l:n, l:size)
    let l:yn = input(l:msg)
    if l:yn !=# 'y'
      echom gnosis#i18n#tr('Gnosis: 中止')
      return
    endif
  endif
  let l:pf = s:temp_passfile(l:new)
  let l:stage = 'none'
  let l:before_err = ''
  try
    if !empty(glob(l:cipher . s:sep() . '*', 1)) || filereadable(l:cipher . s:sep() . 'gocryptfs.conf')
      throw gnosis#i18n#tr('cipher が既に存在・非空: ') . l:cipher
    endif
    let l:stage = 'mv'
    call system('mv ' . shellescape(l:cur) . ' ' . shellescape(l:plaindir))
    if v:shell_error != 0
      throw gnosis#i18n#tr('mv 失敗')
    endif
    let l:stage = 'init'
    call mkdir(fnamemodify(l:cipher, ':h'), 'p')
    call mkdir(l:cipher, 'p')
    let l:out = system('gocryptfs -init -passfile=' . shellescape(l:pf) . ' ' . shellescape(l:cipher) . ' 2>&1')
    if v:shell_error != 0
      throw gnosis#i18n#tr('init 失敗: ') . trim(substitute(l:out, "\n", ' ', 'g'))
    endif
    let l:stage = 'mount'
    call mkdir(l:root, 'p')
    call s:clear_mountpoint_garbage(l:root)
    let l:out = system('gocryptfs -passfile=' . shellescape(l:pf) . ' ' . shellescape(l:cipher)
          \ . ' ' . shellescape(l:root) . ' 2>&1')
    if v:shell_error != 0
      throw gnosis#i18n#tr('mount 失敗: ') . trim(substitute(l:out, "\n", ' ', 'g'))
    endif
    let s:mounted_by_me = 1
    let l:stage = 'copy'
    let l:out = system('cp -a --no-preserve=xattr,context,mode,ownership ' . shellescape(l:plaindir) . '/. ' . shellescape(l:root) . '/ 2>&1')
    if v:shell_error != 0
      throw gnosis#i18n#tr('copy 失敗')
    endif
    let l:stage = 'verify'
    " パイプ（| head）を挟むと終了コードが head のものになり不一致を見逃すので使わない
    let l:out = system('diff -rq --no-dereference ' . shellescape(l:plaindir)
          \ . ' ' . shellescape(l:root) . ' 2>&1')
    if v:shell_error != 0
      throw gnosis#i18n#tr('verify 不一致: ') . trim(substitute(l:out, "\n", ' ', 'g'))[0:300]
    endif
    let l:stage = 'done'
    " verify 済みだが FUSE 越しで silent corruption の可能性はゼロではない。
    " 本当の安全を取るなら plaindir を残してユーザーに rm させることも可（重い）。
    call system('rm -rf ' . shellescape(l:plaindir))
    " FUSE 内に .crypt symlink（../<cipher>）を保存しておく
    " （mount後に作ると暗号ファイルとして格納され、再マウント時も表示される）
    call system('ln -s ' . shellescape('../' . fnamemodify(l:cipher, ':t')) . ' ' . shellescape(l:root . s:sep() . '.crypt'))
  catch
    let l:before_err = v:exception
    " 巻き戻し: mount 中なら外し、root/退避を復元
    call s:init_rollback(l:cur, l:root, l:plaindir, l:cipher, l:stage, l:converted)
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 暗号化失敗(') . l:before_err . gnosis#i18n#tr(')。元の状態に戻しました')
    echohl NONE
    call s:secure_delete(l:pf)
    return
  endtry
  call s:secure_delete(l:pf)
  call s:mount_cache_reset()
  if l:converted
    " root を A/note に更新してバッファも張り替える（旧 A/index.md → A/note/index.md）
    let g:gnosis_root = fnamemodify(l:root, ':p')
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
    call s:adopt_vault_runtime(l:root)
    call gnosis#clear_title_cache()
    call s:remap_vault_buffers_to(l:cur, l:root)
  endif
  call gnosis#reload_vault_buffers(l:root)
  " Index 無しの真空 vault だと起動後に作成確認が出るので、ここで作る
  if !filereadable(s:index_path(l:root))
    try
      call s:write_index_and_guide(l:root)
    catch
    endtry
  endif
  silent! execute 'cd ' . fnameescape(l:root)
  redraw
  echom gnosis#i18n#tr('Gnosis: vault を暗号化しました。閉じるとロックされます（開くときはパスワード）')
endfunction

" :GnosisRemovePassword（暗号化を解除して平文 vault に戻す）
"   暗号化 vault（A/note + A/.crypt）を解除し、ノートをプロジェクト直下 A へ戻す。
"   ロック中ならパスワードを聞いてマウントしてから解除する。
"   手順: 平文を兄弟の一時 <A>-plain-<ts> へ cp → diff 検証 → アンマウント →
"         マウントポイント削除 → 一時平文を A 直下へ cp → 検証 → 暗号箱削除 → 一時削除。
"   途中で失敗しても平文は必ず「暗号箱 or 一時 or A 直下」のどれかに残る（データ消失なし）。
function! gnosis#remove_password() abort
  return s:remove_encryption_impl()
endfunction

function! s:remove_encryption_impl() abort
  let l:st = s:vault_status()
  if empty(l:st.root)
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: vault(root) が決まっていません')
    echohl NONE
    return
  endif
  if !l:st.encrypted
    echohl WarningMsg
    echom gnosis#i18n#tr('Gnosis: この vault は暗号化されていません（解除する必要はありません）')
    echohl NONE
    return
  endif
  " ロック中ならパスワードを聞いてマウントしてから解除する
  if l:st.locked
    call gnosis#mount_vault()
    if gnosis#vault_mounted() != 1
      echohl ErrorMsg
      echom gnosis#i18n#tr('Gnosis: マウントできませんでした。解除を中止')
      echohl NONE
      return
    endif
  endif
  " 正規形（A/note 型）はマウントポイント note を、直置き型は root 自体を平文に戻す
  let l:mount = l:st.root
  let l:cipher = l:st.cipher
  let l:proj = (l:st.layout ==# 'note') ? fnamemodify(l:mount, ':h') : l:mount
  let l:proj = substitute(fnamemodify(l:proj, ':p'), s:sep() . '\+$', '', '')
  if empty(l:cipher) || !filereadable(l:cipher . s:sep() . 'gocryptfs.conf')
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 暗号箱が見つかりません: ') . l:cipher
    echohl NONE
    return
  endif
  let l:n = trim(system('find ' . shellescape(l:mount) . ' -mindepth 1 2>/dev/null | wc -l'))
  let l:size = trim(system('du -sh ' . shellescape(l:mount) . ' 2>/dev/null | cut -f1'))
  let l:msg = (l:st.layout ==# 'note')
        \ ? printf(gnosis#i18n#tr('暗号を解除して %s 直下の平文に戻します：%s 個(%s)。よければ y: '), l:proj, l:n, l:size)
        \ : printf(gnosis#i18n#tr('暗号を解除します（%s のまま平文に戻します）：%s 個(%s)。よければ y: '), l:proj, l:n, l:size)
  if input(l:msg) !=# 'y'
    echom gnosis#i18n#tr('Gnosis: 中止')
    return
  endif
  " バッファの未保存分は、パスが有効な今のうちに書き出しておく
  call gnosis#save_current_note()
  for l:b in range(1, bufnr('$'))
    if !buflisted(l:b) || l:b == bufnr('%')
      continue
    endif
    let l:p = fnamemodify(bufname(l:b), ':p')
    if stridx(l:p, fnamemodify(l:mount, ':p')) == 0 && getbufvar(l:b, '&modified')
      execute 'silent! buffer ' . l:b
      silent! update
    endif
  endfor
  let l:temp = fnamemodify(l:proj, ':h') . s:sep() . fnamemodify(l:proj, ':t')
        \ . '-plain-' . strftime('%Y%m%d%H%M%S')
  let l:stage = 'none'
  try
    if !empty(glob(l:temp . s:sep() . '*', 1)) || isdirectory(l:temp)
      throw gnosis#i18n#tr('一時退避先が既に存在: ') . l:temp
    endif
    let l:stage = 'copy'
    call mkdir(l:temp, 'p')
    let l:out = system('cp -a --no-preserve=xattr,context,mode,ownership '
          \ . shellescape(l:mount) . '/. ' . shellescape(l:temp) . '/ 2>&1')
    if v:shell_error != 0
      throw gnosis#i18n#tr('copy 失敗')
    endif
    " FUSE 内の .crypt symlink（../.crypt）は暗号箱を消すと無効になるので持ち込まない
    call system('find ' . shellescape(l:temp) . ' -maxdepth 1 -name .crypt -type l -delete 2>/dev/null')
    " パイプ（| head）は終了コードを隠すので使わない（不一致を見逃して暗号箱を消す事故になる）
    let l:out = system('diff -rq --no-dereference --exclude=.crypt '
          \ . shellescape(l:mount) . ' ' . shellescape(l:temp) . ' 2>&1')
    if v:shell_error != 0
      throw gnosis#i18n#tr('verify 不一致: ') . trim(substitute(l:out, "\n", ' ', 'g'))[0:300]
    endif
    " アンマウント（cwd がマウント内だと busy になるので vault の外へ出る）
    let l:stage = 'unmount'
    call s:cd_out_of_vault(l:mount)
    call system('fusermount3 -u ' . shellescape(l:mount) . ' 2>&1')
    call s:mount_cache_reset()
    if gnosis#vault_mounted(escape(l:mount, '\\'), 1) == 1
      throw gnosis#i18n#tr('アンマウント失敗（他アプリが開いていませんか）')
    endif
    " マウントポイント（空）を外し、一時平文を A 直下へ複製して検証
    let l:stage = 'restore'
    call system('rm -rf ' . shellescape(l:mount))
    call mkdir(l:proj, 'p')
    let l:out = system('cp -a --no-preserve=xattr,context,mode,ownership '
          \ . shellescape(l:temp) . '/. ' . shellescape(l:proj) . '/ 2>&1')
    if v:shell_error != 0
      throw gnosis#i18n#tr('コピー失敗')
    endif
    " A に元からある非 vault ファイル（Only in <proj>）は無視し、欠落・不一致だけを見る。
    " diff のメッセージが翻訳されると "Only in" が一致しないので LC_ALL=C で英語に固定する。
    let l:out = system('LC_ALL=C diff -rq --no-dereference ' . shellescape(l:temp) . ' '
          \ . shellescape(l:proj) . ' 2>&1 | grep -v ' . shellescape('^Only in ' . l:proj) . ' || true')
    if !empty(trim(l:out))
      throw gnosis#i18n#tr('restore 不一致: ') . trim(substitute(l:out, "\n", ' ', 'g'))
    endif
    " 暗号箱を削除（これで解除完了）
    let l:stage = 'rm-cipher'
    call system('rm -rf ' . shellescape(l:cipher))
    call s:mount_cache_reset()
  catch
    let l:err = v:exception
    " 平文は「暗号箱 or 一時 or A 直下」のどれかに残る。一時退避は不要になったら消す。
    " アンマウント前（copy）は vault 無傷。アンマウント後も暗号箱は残っている。
    call system('rm -rf ' . shellescape(l:temp))
    if l:stage ==# 'restore' || l:stage ==# 'rm-cipher'
      " A 直下へは平文をコピー済み。暗号箱が残っていれば二重だが安全側。
      call s:mount_cache_reset()
    endif
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: 暗号解除に失敗(') . l:err . gnosis#i18n#tr(')。平文データは失われていません')
    echohl NONE
    return
  endtry
  call system('rm -rf ' . shellescape(l:temp))
  " root を A 直下へ更新し、バッファを張り替える（旧 A/note/index.md → A/index.md）
  let g:gnosis_root = fnamemodify(l:proj, ':p')
  call s:save_persisted_root(l:proj)
  call s:setup_persistent_undo_for_root(l:proj)
  call gnosis#clear_title_cache()
  if l:mount !=# l:proj
    call s:remap_vault_buffers_to(l:mount, l:proj)
  endif
  call gnosis#reload_vault_buffers(l:proj)
  silent! execute 'cd ' . fnameescape(l:proj)
  redraw
  echom gnosis#i18n#tr('Gnosis: 暗号を解除しました。') . l:proj . gnosis#i18n#tr(' は平文の vault です')
endfunction

" レイアウト変換後: 旧 root 配下のバッファを新 root 配下の同名ファイルへ張り替える
function! s:remap_vault_buffers_to(oldroot, newroot) abort
  let l:oldp = fnamemodify(a:oldroot, ':p')
  let l:newp = fnamemodify(a:newroot, ':p')
  let l:cur = bufnr('%')
  for l:b in range(1, bufnr('$'))
    if !buflisted(l:b)
      continue
    endif
    let l:p = fnamemodify(bufname(l:b), ':p')
    if empty(l:p) || stridx(l:p, l:oldp) != 0
      continue
    endif
    let l:rel = strpart(l:p, len(l:oldp))
    if empty(l:rel)
      continue
    endif
    let l:np = l:newp . l:rel
    if !filereadable(l:np)
      continue
    endif
    execute 'silent! buffer ' . l:b
    silent! execute 'edit! ' . fnameescape(l:np)
  endfor
  if bufexists(l:cur) && l:cur != bufnr('%')
    execute 'silent! buffer ' . l:cur
  endif
endfunction

" 巻き戻し。a:converted=1 のときは「A を丸ごと退避した」型なので、
" 再作成したプロジェクト A を消してから plaindir を A に戻す
function! s:init_rollback(oldroot, root, plaindir, cipher, stage, converted) abort
  let l:root = fnamemodify(a:root, ':p')
  if index(['mount', 'copy', 'verify'], a:stage) >= 0
    " mount したまま失敗したときは外して root を掃除
    call s:cd_out_of_vault(l:root)
    call system('fusermount3 -u ' . shellescape(l:root) . ' 2>/dev/null')
    call s:mount_cache_reset()
    " マウントが外れていないのに rm -rf すると暗号箱の中身を消すので、外れた時だけ掃除する
    if isdirectory(l:root) && gnosis#vault_mounted(escape(l:root, '\\'), 1) != 1
      call system('rm -rf ' . shellescape(l:root))
    endif
  endif
  if a:converted
    " plaindir がある＝退避（mv）が成功しているときだけ掃除して戻す。
    " mv 自体が失敗しているなら A は無傷なので何もしない。
    if isdirectory(a:plaindir)
      " まだマウントが残っているなら親を消さない（中の暗号箱・マウント先を巻き込むため）
      if gnosis#vault_mounted(escape(l:root, '\\'), 1) == 1
        echohl WarningMsg
        echom gnosis#i18n#tr('Gnosis: 巻き戻し中断（マウントが残っています）。平文は ') . a:plaindir . gnosis#i18n#tr(' にあります')
        echohl NONE
        return
      endif
      call system('rm -rf ' . shellescape(fnamemodify(l:root, ':h')))
      call system('mv ' . shellescape(a:plaindir) . ' ' . shellescape(a:oldroot))
    endif
  else
    if isdirectory(a:plaindir)
      call system('mv ' . shellescape(a:plaindir) . ' ' . shellescape(l:root))
    endif
  endif
  " init以後の失敗は暗号箱も掃除（成功検証までのものなので）
  if a:stage !=# 'none'
    call system('rm -rf ' . shellescape(a:cipher))
  endif
endfunction


" マウント成功後: 履歴(viminfo)と undo を vault 内へ向け直す。
" 起動時はロック中で読めなかった vault 内の履歴を rviminfo で読み直し、
" vault 外に残った平文 viminfo があれば取り込んで消す。
function! s:adopt_vault_runtime(root) abort
  let l:root = substitute(fnamemodify(a:root, ':p'), s:sep() . '\+$', '', '')
  if empty(l:root)
    return
  endif
  let l:state = l:root . s:sep() . '.state'
  if !isdirectory(l:state)
    try
      call mkdir(l:state, 'p')
    catch
    endtry
  endif
  let l:vi = l:state . s:sep() . 'viminfo'
  " 旧・平文の viminfo を vault 内へ取り込んで消す:
  "   ① vault 外の退避先 ~/.vim/simple_yurii_note/viminfo
  "   ② 旧 vimrc が A/note を解決できず作った A/.state/viminfo
  let l:legacy = [s:state_dir_legacy() . s:sep() . 'viminfo']
  if fnamemodify(l:root, ':t') ==# 'note'
    call add(l:legacy, fnamemodify(l:root, ':h') . s:sep() . '.state' . s:sep() . 'viminfo')
  endif
  for l:old in l:legacy
    if filereadable(l:old) && fnamemodify(l:old, ':p') !=# fnamemodify(l:vi, ':p')
      silent! execute 'rviminfo ' . fnameescape(l:old)
      silent! call delete(l:old)
    endif
  endfor
  if &viminfofile !=# l:vi
    execute 'set viminfofile=' . fnameescape(l:vi)
  endif
  " ロック中は読めなかった vault 内の履歴をここで読み込む
  silent! rviminfo
  call gnosis#clear_search_highlight()
  call s:setup_persistent_undo_for_root(l:root)
endfunction

" マウント後にバッファ内容を復号側へ差し替え
function! gnosis#reload_vault_buffers(...) abort
  let l:root = empty(a:000) ? s:vault_clean() : a:1
  if empty(l:root)
    return
  endif
  let l:rootp = fnamemodify(l:root, ':p')
  let l:cur = bufnr('%')
  for l:b in range(1, bufnr('$'))
    if !buflisted(l:b)
      continue
    endif
    let l:p = fnamemodify(bufname(l:b), ':p')
    if !empty(l:p) && stridx(l:p, l:rootp) == 0
      execute 'silent! buffer ' . l:b
      silent! edit!
    endif
  endfor
  if bufexists(l:cur) && l:cur != bufnr('%')
    execute 'silent! buffer ' . l:cur
  endif
endfunction

" ロック中に vault を書こうとしたら全部止める（:w / ノート作成 / sync など全経路）
function! gnosis#guard_vault_write(path) abort
  if gnosis#vault_locked_flag() != 1
    return
  endif
  let l:root = s:vault_clean()
  if empty(l:root)
    return
  endif
  let l:p = fnamemodify(expand(a:path), ':p')
  if stridx(l:p, fnamemodify(l:root, ':p')) == 0
    echohl ErrorMsg
    echom gnosis#i18n#tr('Gnosis: vault はロック中。:GnosisMount でマウントしてから')
    echohl NONE
    throw 'Gnosis: vault locked'
  endif
endfunction

" ロック中に vault のバッファを開いたときのフック（undo 書き込みも封じる）
function! gnosis#vault_locked_buffer_hint() abort
  if gnosis#vault_locked_flag() != 1
    return
  endif
  let l:root = s:vault_clean()
  if empty(l:root) || empty(expand('%:p'))
    return
  endif
  if stridx(fnamemodify(expand('%:p'), ':p'), fnamemodify(l:root, ':p')) == 0
    setlocal noundofile
    setlocal noswapfile
    if !exists('s:vault_locked_shown') || empty(s:vault_locked_shown)
      let s:vault_locked_shown = 1
      echohl WarningMsg
      echom gnosis#i18n#tr('Gnosis: vault はロック中。編集不可（:GnosisMount でマウント）')
      echohl NONE
    endif
  endif
endfunction

" writefile を全部ここに統一（ロック中 vault へ作成する経路も止めるため）
" 新規ノート作成用: 既存ファイルを上書きしない（同秒タイムスタンプ衝突や同名タイトルで
" 既存本文を無言で消すのを防ぐ）
function! s:write_new_note(lines, path) abort
  if filereadable(a:path) || isdirectory(a:path)
    throw gnosis#i18n#tr('Gnosis: 既存のファイルを上書きしません: ') . a:path
  endif
  let l:ret = s:syn_writefile(a:lines, a:path)
  call s:diary_place_safe(a:path, a:lines)
  return l:ret
endfunction

function! s:syn_writefile(lines, path, ...) abort
  call gnosis#guard_vault_write(a:path)
  if a:0 == 0
    return writefile(a:lines, a:path)
  endif
  return writefile(a:lines, a:path, a:1)
endfunction

" ---------------------------------------------------------------------------
" 日記の「今日のノート」
"   ノートを作ると、その日の日記ノート（題が YYYY-MM-DD-曜日2文字- だけ）の本文の
"   `## 今日のノート` の節にリンクを足す。リンクは日記の本文リンクなので、
"   新ノート側は Parent ではなく BackLink に日記が出る（sync の規則どおり）。
"   - グループは載せない。日記自身も載せない。
"   - 題が YYYY-MM-DD-… で始まる日記以外のノート（夢日記など）は、作成時刻に関係なく
"     題の日付の日記に入れる。題が後から付くので、保存時にも見直して移す。
"   - それ以外は作成時刻（g:gnosis_diary_day_start_hour 時区切り）の日付。
"   - 日記が無ければ自動で作る（月グループ YYYY-MM の下）。
"   - 日記の本文にすでに文中リンクがあっても、節の中に無ければ足す。
"   - 日記は .state/diary_days.json に記録するので、題を後から変えても別の日記は作らない。
" ---------------------------------------------------------------------------

let s:diary_weekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU']
" zn→t で作るノートの、リンクを置いた元のノート（日記の「今日のノート」に重ねない判定用）
let s:diary_skip_from = ''

function! s:diary_state_path() abort
  return s:state_dir() . s:sep() . 'diary_days.json'
endfunction

" {'days': {日付: 日記のファイル名}, 'notes': {ノートのファイル名: 入れた日記のファイル名}}
function! s:diary_state_read() abort
  let l:st = {'days': {}, 'notes': {}, 'backfilled': 0, 'no_list': {}}
  let l:p = s:diary_state_path()
  if filereadable(l:p)
    try
      let l:d = json_decode(join(readfile(l:p), "\n"))
      if type(l:d) == v:t_dict
        let l:st.days = get(l:d, 'days', {})
        let l:st.notes = get(l:d, 'notes', {})
        let l:st.backfilled = get(l:d, 'backfilled', 0)
        let l:st.no_list = get(l:d, 'no_list', {})
      endif
    catch
    endtry
  endif
  return l:st
endfunction

function! s:diary_state_write(st) abort
  call s:syn_writefile([json_encode(a:st)], s:diary_state_path())
endfunction

" front matter から title / time / group を取る（lines は先頭付近でよい）
function! s:diary_head(lines) abort
  " paper: 紙の日記（\F の GUI で登録したスキャン。題はデジタル日記と同じ YYYY-MM-DD-曜日2文字 だが、
  " デジタル日記（\d）の機能からは見えないようにする）
  " 紙の日記かどうかは front matter の目印ではなく、本文の画像 `![](paper-diary-…)` で判定する
  " （月・年・一番上のグループは s:diary_scan がリンク先から判定する）。links は本文の .md リンク先。
  let l:r = {'title': '', 'time': '', 'group': 0, 'paper': 0, 'links': []}
  let l:fence = 0
  for l:ln in a:lines
    if l:ln ==# '---'
      let l:fence += 1
      if l:fence >= 2 | continue | endif
      continue
    endif
    if l:fence >= 2
      if l:ln =~# '^!\[\%(\\.\|[^\]\\]\)*\](paper-diary-\d\{8}-\d\+\.\w\+)\s*$'
        let l:r.paper = 1
      endif
      let l:rest = l:ln
      while 1
        let l:m = matchlist(l:rest, '\[\%(\\.\|[^\]\\]\)*\](\([^)#[:space:]]\+\.md\)')
        if empty(l:m) | break | endif
        call add(l:r.links, fnamemodify(l:m[1], ':t'))
        let l:rest = substitute(l:rest, '\[\%(\\.\|[^\]\\]\)*\](\([^)#[:space:]]\+\.md\)', '', '')
      endwhile
      continue
    endif
    if l:fence != 1 | break | endif
    if l:ln =~# '^title:'
      let l:r.title = trim(substitute(l:ln, '^title:\s*', '', ''))
    elseif l:ln =~# '^time:'
      let l:r.time = trim(substitute(l:ln, '^time:\s*', '', ''))
    elseif l:ln =~# '^attribute:\s*group\>'
      let l:r.group = 1
    elseif l:ln =~# '^paper_diary\w*:'
      " 旧い目印（移行前のノート。paper_pkm.py の regen が外す）
      let l:r.paper = 1
    endif
  endfor
  return l:r
endfunction

function! s:diary_is_diary_title(title) abort
  return a:title =~# '^\d\{4}-\d\{2}-\d\{2}-\u\u-\=$'
endfunction

" 日記以外で、題が日付で始まるもの → その日付。違えば ''
function! s:diary_title_date(title) abort
  if s:diary_is_diary_title(a:title)
    return ''
  endif
  return matchstr(a:title, '^\d\{4}-\d\{2}-\d\{2}\ze-')
endfunction

function! s:diary_day_of_time(timestr) abort
  let l:h = get(g:, 'gnosis_diary_day_start_hour', 5)
  let l:ts = (!empty(a:timestr) && exists('*strptime'))
        \ ? strptime('%Y-%m-%d %H:%M:%S', a:timestr) : 0
  if l:ts <= 0
    let l:ts = localtime()
  endif
  return strftime('%Y-%m-%d', l:ts - l:h * 3600)
endfunction

function! s:diary_weekday(date) abort
  let l:ts = strptime('%Y-%m-%d %H:%M:%S', a:date . ' 12:00:00')
  return s:diary_weekdays[str2nr(strftime('%u', l:ts)) - 1]
endfunction

" vault 直下の .md を {file, title, group} で返す
function! s:diary_scan(root) abort
  let l:all = []
  for l:f in glob(fnamemodify(a:root, ':p') . '*.md', 0, 1)
    let l:h = s:diary_head(readfile(l:f, '', 200))
    let l:h.file = fnamemodify(l:f, ':t')
    call add(l:all, l:h)
  endfor
  " 紙の日記のグループ（月・年・一番上の「日記」）は、リンク先が紙の日記ノート（または紙の日記のグループ）
  " のグループ。デジタル日記の同名のグループは別物なので、リンク階層で見分ける（不動点まで繰り返す）
  let l:paper = {}
  for l:h in l:all
    if l:h.paper | let l:paper[l:h.file] = 1 | endif
  endfor
  let l:changed = 1
  while l:changed
    let l:changed = 0
    for l:h in l:all
      if !l:h.group || has_key(l:paper, l:h.file) | continue | endif
      for l:t in l:h.links
        if has_key(l:paper, l:t)
          let l:paper[l:h.file] = 1
          let l:changed = 1
          break
        endif
      endfor
    endfor
  endwhile
  let l:out = []
  for l:h in l:all
    if has_key(l:paper, l:h.file) | continue | endif
    call add(l:out, {'file': l:h.file, 'title': l:h.title, 'group': l:h.group, 'time': l:h.time})
  endfor
  return l:out
endfunction

function! s:diary_find_group(notes, title) abort
  for l:n in a:notes
    if l:n.group && l:n.title ==# a:title
      return l:n.file
    endif
  endfor
  return ''
endfunction

" その日の日記のファイル名（記録 → 題が日付-曜日- だけのもの）。無ければ ''
function! s:diary_find(root, date, st, notes) abort
  let l:rec = get(a:st.days, a:date, '')
  if !empty(l:rec) && filereadable(fnamemodify(a:root, ':p') . l:rec)
    return l:rec
  endif
  for l:n in a:notes
    if s:diary_is_diary_title(l:n.title) && l:n.title[0 : 9] ==# a:date
      let a:st.days[a:date] = l:n.file
      return l:n.file
    endif
  endfor
  return ''
endfunction

function! s:diary_new_filename(root) abort
  let l:i = 0
  while 1
    let l:name = strftime('%y%m%d%H%M%S', localtime() + l:i) . '.md'
    if !filereadable(fnamemodify(a:root, ':p') . l:name)
      return l:name
    endif
    let l:i += 1
  endwhile
endfunction

function! s:diary_link(file, title) abort
  return '[' . a:title . '](' . a:file . ')'
endfunction

" Parent の節に親リンクを 1 本入れた新規ノートの内容
function! s:diary_new_lines(title, is_group, parent_link, ...) abort
  let l:lines = gnosis#note_template(a:title, a:is_group)
  if a:0 > 0
    call map(l:lines, {_, v -> v =~# '^time: ' ? 'time: ' . a:1 : v})
  endif
  if !empty(a:parent_link)
    " テンプレートは関係の節を持たない。親リンクがあるときだけ Context を作る
    let l:p = index(l:lines, s:v2_up_mark)
    if l:p >= 0
      call insert(l:lines, a:parent_link, l:p + 1)
    else
      call extend(l:lines, [s:v2_up_mark, a:parent_link])
    endif
  endif
  return l:lines
endfunction

" a:section が空なら本文の最後（### Context の直前）に足す。あれば `## 節` に足す。
" 重複判定は同じ節の中だけ（文中にあっても節に足す）。
function! s:diary_op_add(link, section, lines) abort
  let l:lines = s:diary_op_add_raw(a:link, a:section, a:lines)
  return empty(a:section) ? l:lines : s:diary_section_blank(l:lines, a:section)
endfunction

" `## 節` の見出しと最初のリンクの間に空行を 1 つ空ける（すでに空行があれば何もしない）。
" 見出しの直後が空行・次の見出し・節の終わりなら触らない。
function! s:diary_section_blank(lines, section) abort
  let l:lines = copy(a:lines)
  let l:p = s:first_section_index_in_lines(l:lines)
  let l:end = l:p >= 0 ? l:p : len(l:lines)
  let l:h = index(l:lines[0 : l:end - 1], '## ' . a:section)
  if l:h >= 0 && l:h + 1 < l:end && trim(l:lines[l:h + 1]) !=# '' && l:lines[l:h + 1] !~# '^#'
    call insert(l:lines, '', l:h + 1)
  endif
  return l:lines
endfunction

function! s:diary_section_blank_op(section, lines) abort
  return s:diary_section_blank(a:lines, a:section)
endfunction

function! s:diary_op_add_raw(link, section, lines) abort
  let l:lines = copy(a:lines)
  let l:tgt = matchstr(a:link, '](\zs[^)]*\ze)')
  let l:p = s:first_section_index_in_lines(l:lines)
  let l:end = l:p >= 0 ? l:p : len(l:lines)
  if empty(a:section)
    for l:i in range(0, l:end - 1)
      if stridx(l:lines[l:i], '](' . l:tgt . ')') >= 0
        return l:lines
      endif
    endfor
    if l:end > 0 && trim(l:lines[l:end - 1]) !=# '' && l:lines[l:end - 1] !~# ')\s*$'
      call insert(l:lines, '', l:end)
      let l:end += 1
    endif
    call insert(l:lines, a:link, l:end)
    return l:lines
  endif
  let l:head = '## ' . a:section
  let l:h = index(l:lines[0 : l:end - 1], l:head)
  if l:h < 0
    let l:add = [l:head, a:link]
    if l:end > 0 && trim(l:lines[l:end - 1]) !=# ''
      let l:add = [''] + l:add
    endif
    " 節の最後（### Context の直前）に空行を 1 つ空ける
    if l:p >= 0
      let l:add += ['']
    endif
    call extend(l:lines, l:add, l:end)
    return l:lines
  endif
  let l:s_end = l:end
  for l:j in range(l:h + 1, l:end - 1)
    if l:lines[l:j] =~# '^#'
      let l:s_end = l:j
      break
    endif
  endfor
  for l:j in range(l:h + 1, l:s_end - 1)
    if stridx(l:lines[l:j], '](' . l:tgt . ')') >= 0
      return l:lines
    endif
  endfor
  let l:k = l:s_end
  while l:k > l:h + 1 && trim(l:lines[l:k - 1]) ==# ''
    let l:k -= 1
  endwhile
  call insert(l:lines, a:link, l:k)
  return l:lines
endfunction

" 節の中から、そのファイルへのリンク行を外す。リンクが無くなった節は見出しごと消す。
function! s:diary_op_remove(tgt, section, lines) abort
  let l:lines = copy(a:lines)
  let l:p = s:first_section_index_in_lines(l:lines)
  let l:end = l:p >= 0 ? l:p : len(l:lines)
  let l:h = index(l:lines[0 : l:end - 1], '## ' . a:section)
  if l:h < 0
    return l:lines
  endif
  let l:s_end = l:end
  for l:j in range(l:h + 1, l:end - 1)
    if l:lines[l:j] =~# '^#'
      let l:s_end = l:j
      break
    endif
  endfor
  for l:j in range(l:s_end - 1, l:h + 1, -1)
    if stridx(l:lines[l:j], '](' . a:tgt . ')') >= 0
      call remove(l:lines, l:j)
      let l:s_end -= 1
    endif
  endfor
  let l:left = filter(copy(l:lines[l:h + 1 : l:s_end - 1]), 'trim(v:val) !=# ""')
  if empty(l:left)
    call remove(l:lines, l:h, l:s_end - 1)
    if l:h > 0 && trim(l:lines[l:h - 1]) ==# ''
      call remove(l:lines, l:h - 1)
    endif
  endif
  return l:lines
endfunction

" ファイルに a:Fn（行リスト → 行リスト）を適用する。バッファが開いていればバッファを直接
" 書き換える（未保存の変更を壊さない。保存は自動保存に任せる）。変わったら 1。
function! s:diary_edit_file(file, Fn) abort
  let l:nr = bufnr(a:file)
  if l:nr > 0 && bufloaded(l:nr)
    let l:old = getbufline(l:nr, 1, '$')
    let l:new = call(a:Fn, [l:old])
    if l:new ==# l:old
      return 0
    endif
    let l:view = (l:nr == bufnr('%')) ? winsaveview() : {}
    let l:pos = 0
    while l:pos < min([len(l:old), len(l:new)]) && l:old[l:pos] ==# l:new[l:pos]
      let l:pos += 1
    endwhile
    call s:write_note_lines_for_path(a:file, l:new)
    if !empty(l:view)
      if l:view.lnum > l:pos
        let l:view.lnum = max([1, l:view.lnum + len(l:new) - len(l:old)])
      endif
      call winrestview(l:view)
    endif
    return 1
  endif
  let l:old = readfile(a:file)
  let l:new = call(a:Fn, [l:old])
  if l:new ==# l:old
    return 0
  endif
  call s:syn_writefile(l:new, a:file)
  return 1
endfunction

" 本文（### Context より前）から、そのファイルだけのリンク行を外す
function! s:diary_op_unlink_body(tgt, lines) abort
  let l:lines = copy(a:lines)
  let l:p = s:first_section_index_in_lines(l:lines)
  let l:end = l:p >= 0 ? l:p : len(l:lines)
  for l:i in range(l:end - 1, 0, -1)
    if l:lines[l:i] =~# '^\s*\[\%(\\.\|[^\]\\]\)*\](' . escape(a:tgt, '.') . ')\s*$'
      call remove(l:lines, l:i)
    endif
  endfor
  return l:lines
endfunction

" 上側（### Context と ### Group）の範囲 [始まり, 終わり) を返す（0 始まりの行 index）。
" 上側の節が無ければ [-1, -1]。
function! s:diary_up_range(lines) abort
  let l:up_marks = [s:v2_up_mark, s:v2_group_mark] + s:v2_up_marks_legacy
  let l:p = -1
  for l:i in range(0, len(a:lines) - 1)
    if index(l:up_marks, trim(a:lines[l:i])) >= 0
      let l:p = l:i | break
    endif
  endfor
  if l:p < 0
    return [-1, -1]
  endif
  let l:end = len(a:lines)
  for l:j in range(l:p + 1, len(a:lines) - 1)
    if a:lines[l:j] =~# '^#' && index(l:up_marks, trim(a:lines[l:j])) < 0
      let l:end = l:j
      break
    endif
  endfor
  return [l:p, l:end]
endfunction

" ### Context / ### Group の中の a:old へのリンク行を a:newlink に差し替える。
" 無ければ Context（無ければ作る）の先頭に足す。
function! s:diary_op_parent_swap(old, newlink, lines) abort
  let l:lines = copy(a:lines)
  let [l:p, l:end] = s:diary_up_range(l:lines)
  if l:p >= 0
    for l:j in range(l:p + 1, l:end - 1)
      if stridx(l:lines[l:j], '](' . a:old . ')') >= 0
        let l:lines[l:j] = a:newlink
        return l:lines
      endif
    endfor
  endif
  let l:c = index(l:lines, s:v2_up_mark)
  if l:c >= 0
    call insert(l:lines, a:newlink, l:c + 1)
  else
    let l:at = s:context_insert_index(l:lines)
    call extend(l:lines, [s:v2_up_mark, a:newlink], l:at < 0 ? len(l:lines) : l:at)
  endif
  return l:lines
endfunction

" グループ a:file の上側（### Context / ### Group）に a:tgt へのリンクがあるか
function! s:diary_parent_has(root, file, tgt) abort
  let l:lines = readfile(fnamemodify(a:root, ':p') . a:file)
  let [l:p, l:end] = s:diary_up_range(l:lines)
  if l:p < 0
    return 0
  endif
  for l:ln in l:lines[l:p + 1 : l:end - 1]
    if stridx(l:ln, '](' . a:tgt . ')') >= 0
      return 1
    endif
  endfor
  return 0
endfunction

" 新しいグループを作る。親（a:parent_file）があれば、親の本文にもリンクを足す。
function! s:diary_new_group(root, notes, title, parent_file, parent_title, ...) abort
  let l:dir = fnamemodify(a:root, ':p')
  let l:file = s:diary_new_filename(a:root)
  let l:plink = empty(a:parent_file) ? '' : s:diary_link(a:parent_file, a:parent_title)
  call s:syn_writefile(call('s:diary_new_lines', [a:title, 1, l:plink] + a:000), l:dir . l:file)
  if !empty(a:parent_file)
    call s:diary_edit_file(l:dir . a:parent_file,
          \ function('s:diary_op_add', [s:diary_link(l:file, a:title), '']))
  endif
  call add(a:notes, {'file': l:file, 'title': a:title, 'group': 1, 'time': ''})
  return l:file
endfunction

" 年越し: 年グループ a:year が無く、それ以前の月グループ（親が「日記」のもの）があるとき、
" それらを年ごとの年グループ（YYYY）に入れ、新しい年の年グループも作る。
" 戻り値は新しい年の年グループのファイル名（作らなかったときは ''）。
function! s:diary_rollover(root, notes, year, top, ...) abort
  let l:dir = fnamemodify(a:root, ':p')
  let l:old = {}
  for l:n in a:notes
    if l:n.group && l:n.title =~# '^\d\{4}-\d\{2}$' && l:n.title[0 : 3] <# a:year
          \ && s:diary_parent_has(a:root, l:n.file, a:top)
      let l:old[l:n.title[0 : 3]] = get(l:old, l:n.title[0 : 3], []) + [l:n]
    endif
  endfor
  if empty(l:old)
    return ''
  endif
  for [l:yr, l:mgs] in items(l:old)
    let l:yg = s:diary_find_group(a:notes, l:yr)
    if empty(l:yg)
      let l:yg = call('s:diary_new_group', [a:root, a:notes, l:yr, a:top, '日記'] + a:000)
    endif
    for l:m in sort(copy(l:mgs), {x, y -> x.title ==# y.title ? 0 : x.title ># y.title ? 1 : -1})
      call s:diary_edit_file(l:dir . a:top, function('s:diary_op_unlink_body', [l:m.file]))
      call s:diary_edit_file(l:dir . l:yg, function('s:diary_op_add', [s:diary_link(l:m.file, l:m.title), '']))
      call s:diary_edit_file(l:dir . l:m.file,
            \ function('s:diary_op_parent_swap', [a:top, s:diary_link(l:yg, l:yr)]))
    endfor
  endfor
  return call('s:diary_new_group', [a:root, a:notes, a:year, a:top, '日記'] + a:000)
endfunction

" その日の日記を作る。
"   月グループ（YYYY-MM）が無ければ作る。親は、年グループ（YYYY）があればそれ、無ければ
"   グループ「日記」。年が替わって最初の日記なら、それまでの月グループを年グループにまとめて、
"   新しい年の年グループの中に新しい月グループを作る（s:diary_rollover）。
" 作った日記のファイル名を返す。
function! s:diary_create(root, date, notes, ...) abort
  let l:dir = fnamemodify(a:root, ':p')
  let l:title = a:date . '-' . s:diary_weekday(a:date)
  let l:month = a:date[0 : 6]
  let l:year = a:date[0 : 3]
  let l:mg = s:diary_find_group(a:notes, l:month)
  if empty(l:mg)
    let l:top = s:diary_find_group(a:notes, '日記')
    let l:yg = s:diary_find_group(a:notes, l:year)
    if empty(l:yg) && !empty(l:top)
      let l:yg = call('s:diary_rollover', [a:root, a:notes, l:year, l:top] + a:000)
    endif
    if !empty(l:yg)
      let l:mg = call('s:diary_new_group', [a:root, a:notes, l:month, l:yg, l:year] + a:000)
    else
      let l:mg = call('s:diary_new_group', [a:root, a:notes, l:month, l:top, '日記'] + a:000)
    endif
  endif
  let l:file = s:diary_new_filename(a:root)
  let l:lines = call('s:diary_new_lines', [l:title, 0, s:diary_link(l:mg, l:month)] + a:000)
  " 本文の余白 3 行（真ん中がカーソル位置）のあとに、空の「今日のノート」の節を置く
  let l:u = s:first_section_index_in_lines(l:lines)
  if l:u < 0
    " 関係の節を持たないテンプレート: 末尾に空の「今日のノート」の節を置く
    let l:u = len(l:lines)
  endif
  call insert(l:lines, '## ' . get(g:, 'gnosis_diary_section', '今日のノート'), l:u)
  call insert(l:lines, '', l:u + 1)
  call s:syn_writefile(l:lines, l:dir . l:file)
  call s:diary_edit_file(l:dir . l:mg, function('s:diary_op_add', [s:diary_link(l:file, l:title), '']))
  return l:file
endfunction

" ノート a:path（vault 直下）を、入れるべき日記の「今日のノート」に入れる。
" a:1 = そのノートの行（まだ読めない・読むのが重いとき用）
function! s:diary_place(path, ...) abort
  if !get(g:, 'gnosis_diary_auto', 1)
    return
  endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || empty(a:path) || !s:is_markdown_file(a:path)
    return
  endif
  let l:dir = substitute(fnamemodify(l:root, ':p'), '/$', '', '')
  if substitute(fnamemodify(a:path, ':p:h'), '/$', '', '') !=# l:dir
    return
  endif
  let l:tail = fnamemodify(a:path, ':t')
  if index(['index.md', 'Index-write.md', 'Folgezettel-Index.md'], l:tail) >= 0
    return
  endif
  let l:lines = a:0 > 0 ? a:1 : readfile(a:path, '', 30)
  let l:head = s:diary_head(l:lines)
  if l:head.group || l:head.paper
    return
  endif
  let l:st = s:diary_state_read()
  if s:diary_is_diary_title(l:head.title) || index(values(l:st.days), l:tail) >= 0
    return
  endif
  let l:tdate = s:diary_title_date(l:head.title)
  let l:date = empty(l:tdate) ? s:diary_day_of_time(l:head.time) : l:tdate
  let l:notes = s:diary_scan(l:root)
  let l:diary = s:diary_find(l:root, l:date, l:st, l:notes)
  " zn→t: 日記の見出しの下に直接リンクを置いたノートは、同じ日記の「今日のノート」には
  " 重ねて載せない（見出しの下だけで十分）。\ua の足し直しでも戻らないよう記録する。
  if !empty(l:diary) && !empty(s:diary_skip_from)
        \ && fnamemodify(l:dir . '/' . l:diary, ':p') ==# fnamemodify(s:diary_skip_from, ':p')
    let l:st.no_list[l:tail] = 1
    call s:diary_state_write(l:st)
    return
  endif
  if empty(l:diary)
    " 日記が見つからない日に、題が日付で始まる別のノート（昔の日記など）があるときは、
    " 重複した日記を作らない。:GnosisDiaryAdopt でその日記を登録すると使える。
    for l:n in l:notes
      if l:n.file !=# l:tail && l:n.title =~# '^' . l:date . '-' && !has_key(l:st.notes, l:n.file)
        echohl WarningMsg
        echom 'Gnosis: ' . l:date . gnosis#i18n#tr(' の日記が見つかりません（') . l:n.file
              \ . gnosis#i18n#tr(' が日付で始まっています）。日記なら、そのノートで :GnosisDiaryAdopt')
        echohl NONE
        return
      endif
    endfor
    let l:diary = s:diary_create(l:root, l:date, l:notes)
    let l:st.days[l:date] = l:diary
  endif
  let l:title = empty(l:head.title) ? fnamemodify(l:tail, ':r') : l:head.title
  let l:sec = get(g:, 'gnosis_diary_section', '今日のノート')
  call s:diary_edit_file(l:dir . '/' . l:diary,
        \ function('s:diary_op_add', [s:diary_link(l:tail, l:title), l:sec]))
  let l:prev = get(l:st.notes, l:tail, '')
  if !empty(l:prev) && l:prev !=# l:diary && filereadable(l:dir . '/' . l:prev)
    call s:diary_edit_file(l:dir . '/' . l:prev, function('s:diary_op_remove', [l:tail, l:sec]))
  endif
  let l:st.notes[l:tail] = l:diary
  call s:diary_state_write(l:st)
endfunction

function! s:diary_place_safe(path, ...) abort
  try
    call call('s:diary_place', [a:path] + a:000)
  catch
    echohl WarningMsg
    echom gnosis#i18n#tr('Gnosis: 日記への追加に失敗: ') . v:exception
    echohl NONE
  endtry
endfunction

" 保存時: 作成時に日記へ入れたノートの題が日付で始まるようになっていたら、その日の日記へ移す
function! gnosis#diary_on_save() abort
  if !get(g:, 'gnosis_diary_auto', 1)
    return
  endif
  let l:path = expand('%:p')
  let l:tail = fnamemodify(l:path, ':t')
  let l:st = s:diary_state_read()
  if !has_key(l:st.notes, l:tail)
    return
  endif
  let l:head = s:diary_head(getline(1, 30))
  if l:head.paper
    return
  endif
  let l:tdate = s:diary_title_date(l:head.title)
  if empty(l:tdate)
    return
  endif
  let l:cur = get(l:st.days, l:tdate, '')
  if !empty(l:cur) && l:cur ==# l:st.notes[l:tail]
    return
  endif
  call s:diary_place_safe(l:path, getline(1, 30))
endfunction

" :GnosisDiaryAdopt … 今のノート（題が日付で始まる）を、その日付の日記として登録する
function! gnosis#diary_adopt() abort
  let l:head = s:diary_head(getline(1, 30))
  if l:head.paper
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 紙の日記はデジタル日記には登録しません') | echohl NONE
    return
  endif
  let l:date = matchstr(l:head.title, '^\d\{4}-\d\{2}-\d\{2}\ze-')
  if empty(l:date)
    echohl WarningMsg | echo gnosis#i18n#tr('Gnosis: 題が YYYY-MM-DD- で始まるノートで実行して') | echohl NONE
    return
  endif
  let l:st = s:diary_state_read()
  let l:st.days[l:date] = expand('%:t')
  call s:diary_state_write(l:st)
  echo 'Gnosis: ' . l:date . gnosis#i18n#tr(' の日記に登録: ') . expand('%:t')
endfunction

" \ua: 日記として登録されていない日付について、題がその日付で始まる（グループでない）
" ノートがちょうど 1 つならそれを日記として登録する。2 つ以上ある日は曖昧なので登録せず、
" 件数だけ知らせる（そのノートで :GnosisDiaryAdopt）。
function! s:diary_adopt_all() abort
  if !get(g:, 'gnosis_diary_auto', 1)
    return
  endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || gnosis#vault_locked_flag() == 1
    return
  endif
  let l:st = s:diary_state_read()
  let l:notes = s:diary_scan(l:root)
  let l:by = {}
  for l:n in l:notes
    if l:n.group
      continue
    endif
    let l:d = matchstr(l:n.title, '^\d\{4}-\d\{2}-\d\{2}\ze-')
    if !empty(l:d)
      let l:by[l:d] = get(l:by, l:d, []) + [l:n.file]
    endif
  endfor
  let l:added = 0
  let l:amb = 0
  for [l:d, l:files] in items(l:by)
    if !empty(s:diary_find(l:root, l:d, l:st, l:notes))
      continue
    endif
    if len(l:files) == 1
      let l:st.days[l:d] = l:files[0]
      let l:added += 1
    else
      let l:amb += 1
    endif
  endfor
  " さかのぼって入れるのは最初の 1 回だけ。以後は作成時に入る（\ua では全体を見直さない）。
  " もう一度やりたいときは :SimpleDiaryUpdate。
  let l:filled = 0
  if !l:st.backfilled
    let l:filled = s:diary_backfill(l:root, l:st, l:notes)
    let l:st.backfilled = 1
  endif
  call s:diary_state_write(l:st)
  if l:added > 0 || l:amb > 0 || l:filled > 0
    echom gnosis#i18n#tr('Gnosis: 日記を ') . l:added . gnosis#i18n#tr(' 件登録、「今日のノート」を ') . l:filled . gnosis#i18n#tr(' 日分更新')
          \ . (l:amb > 0 ? '（' . l:amb . gnosis#i18n#tr(' 日分は日付のノートが複数あるため日記は未登録。日記のノートで :GnosisDiaryAdopt）') : '')
  endif
endfunction

" まだ日記の節に入れていないノートを、入れるべき日記の「今日のノート」に足す（作成時に
" 入れそびれた分・機能を入れる前に作った分）。対象は直近 g:gnosis_diary_backfill_days
" 日（既定 0 = 全部）。日記が無い日は作らない（作るのは新規ノートのときだけ）。
function! s:diary_backfill(root, st, notes) abort
  let l:days = get(g:, 'gnosis_diary_backfill_days', 0)
  let l:h = get(g:, 'gnosis_diary_day_start_hour', 5)
  let l:since = l:days > 0 ? strftime('%Y-%m-%d', localtime() - l:days * 86400 - l:h * 3600) : ''
  let l:dir = substitute(fnamemodify(a:root, ':p'), '/$', '', '')
  let l:sec = get(g:, 'gnosis_diary_section', '今日のノート')
  let l:diaries = values(a:st.days)
  " 記録（st.notes）に有るかどうかではなく、日記の節に実際にリンクがあるかで判断する
  " （別の Vim の古いバッファの保存などで節から消えていても、\ua で戻る）。
  let l:per = {}
  let l:skip = {}
  let l:made = 0
  for l:n in a:notes
    if l:n.group || index(l:diaries, l:n.file) >= 0
          \ || index(['index.md', 'Index-write.md', 'Folgezettel-Index.md'], l:n.file) >= 0
          \ || s:diary_is_diary_title(l:n.title) || empty(l:n.title) && empty(l:n.time)
          \ || has_key(get(a:st, 'no_list', {}), l:n.file)
      continue
    endif
    let l:tdate = s:diary_title_date(l:n.title)
    let l:date = empty(l:tdate) ? s:diary_day_of_time(l:n.time) : l:tdate
    if !empty(l:since) && l:date <# l:since
      continue
    endif
    let l:diary = s:diary_find(a:root, l:date, a:st, a:notes)
    if empty(l:diary) && !has_key(l:skip, l:date)
      " 日記の無い日は作る。ただし、その日付で始まる題の別のノート（日記かもしれないもの）
      " があるときは重複を避けて作らない（そのノートで :GnosisDiaryAdopt）。
      let l:cand = filter(copy(a:notes), {_, m -> !m.group && m.file !=# l:n.file
            \ && m.title =~# '^' . l:date . '-' && !has_key(a:st.notes, m.file)})
      if empty(l:cand)
        let l:diary = s:diary_create(a:root, l:date, a:notes, l:date . ' 00:00:00')
        let a:st.days[l:date] = l:diary
        let l:made += 1
      else
        let l:skip[l:date] = 1
      endif
    endif
    if empty(l:diary) || l:diary ==# l:n.file
      continue
    endif
    let l:title = empty(l:n.title) ? fnamemodify(l:n.file, ':r') : l:n.title
    let l:per[l:diary] = get(l:per, l:diary, []) + [[l:n.file, l:title]]
  endfor
  let l:n_added = 0
  for [l:diary, l:items] in items(l:per)
    let l:f = l:dir . '/' . l:diary
    let l:Fn = function('s:diary_op_add_many', [l:items, l:sec])
    if s:diary_edit_file(l:f, l:Fn)
      let l:n_added += 1
    endif
    for l:it in l:items
      let l:prev = get(a:st.notes, l:it[0], '')
      if !empty(l:prev) && l:prev !=# l:diary && filereadable(l:dir . '/' . l:prev)
        call s:diary_edit_file(l:dir . '/' . l:prev, function('s:diary_op_remove', [l:it[0], l:sec]))
      endif
      let a:st.notes[l:it[0]] = l:diary
    endfor
  endfor
  if l:made > 0
    echom gnosis#i18n#tr('Gnosis: 日記を ') . l:made . gnosis#i18n#tr(' 日分作りました')
  endif
  return l:n_added
endfunction

" items = [[ファイル名, 題], ...] を節に足す（すでにあるものは足さない）
function! s:diary_op_add_many(items, section, lines) abort
  let l:lines = copy(a:lines)
  for l:it in a:items
    let l:lines = s:diary_op_add(s:diary_link(l:it[0], l:it[1]), a:section, l:lines)
  endfor
  return l:lines
endfunction

function! s:diary_adopt_all_safe() abort
  try
    call s:diary_adopt_all()
  catch
    echom gnosis#i18n#tr('Gnosis: 日記の登録に失敗: ') . v:exception
  endtry
endfunction

" :SimpleDiaryUpdate … 日記まわりをまとめて更新する。
"   1. 日付で始まる題のノートを日記として登録する（\ua と同じ。曖昧な日は登録しない）
"   2. 日記が無い日を作り、「今日のノート」に入っていないノートを全部さかのぼって入れる
"      （zn→t で見出しの下に置いたノートは入れない）
"   3. 全日記の「今日のノート」の見出しとリンクの間に空行を 1 つ空ける
function! gnosis#diary_update() abort
  let l:root = s:get_pkm_root()
  if empty(l:root)
    return
  endif
  call s:diary_adopt_all_safe()
  let l:st = s:diary_state_read()
  let l:n = s:diary_backfill(l:root, l:st, s:diary_scan(l:root))
  let l:st.backfilled = 1
  let l:sec = get(g:, 'gnosis_diary_section', '今日のノート')
  let l:dir = substitute(fnamemodify(l:root, ':p'), '/$', '', '')
  let l:fmt = 0
  for l:f in uniq(sort(values(l:st.days)))
    if filereadable(l:dir . '/' . l:f)
      let l:fmt += s:diary_edit_file(l:dir . '/' . l:f, function('s:diary_section_blank_op', [l:sec]))
    endif
  endfor
  call s:diary_state_write(l:st)
  echo gnosis#i18n#tr('Gnosis: 日記を更新（「今日のノート」に追加 ') . l:n . gnosis#i18n#tr(' 日分・体裁を整えた日記 ') . l:fmt . gnosis#i18n#tr(' 件）')
endfunction

" \d / :GnosisToday … 今日の日記を開く。無ければ作る（日付が変わる時刻は diary_day_start_hour）。
function! gnosis#diary_today() abort
  let l:root = gnosis#ensure_root_and_index()
  if empty(l:root)
    return
  endif
  let l:dir = substitute(fnamemodify(l:root, ':p'), '/$', '', '')
  let l:date = s:diary_day_of_time('')
  let l:st = s:diary_state_read()
  let l:notes = s:diary_scan(l:root)
  let l:diary = s:diary_find(l:root, l:date, l:st, l:notes)
  if empty(l:diary)
    for l:n in l:notes
      if !l:n.group && l:n.title =~# '^' . l:date . '-' && !s:diary_is_diary_title(l:n.title)
        echohl WarningMsg
        echo 'Gnosis: ' . l:date . gnosis#i18n#tr(' の日記が見つかりません（') . l:n.file
              \ . gnosis#i18n#tr(' が日付で始まっています）。日記なら、そのノートで :GnosisDiaryAdopt')
        echohl NONE
        return
      endif
    endfor
    let l:diary = s:diary_create(l:root, l:date, l:notes)
    let l:st.days[l:date] = l:diary
    call s:diary_state_write(l:st)
  endif
  if fnamemodify(expand('%:p'), ':t') !=# l:diary
    call gnosis#push_history()
    execute 'edit ' . fnameescape(l:dir . '/' . l:diary)
  endif
  call s:diary_cursor()
endfunction

" 日記を開いたときのカーソル位置と、その周りの形を整える。
"   本文 / 空行 / ここにカーソル / 空行 / ## 今日のノート
" 「今日のノート」の節の直前に空行が 3 つ無ければ足し（節が無ければ ### Context の前に
" 空の節も作る）、真ん中の空行にカーソルを置く。
function! s:diary_cursor() abort
  let l:sec = '## ' . get(g:, 'gnosis_diary_section', '今日のノート')
  let l:lines = getline(1, '$')
  let l:n = index(l:lines, l:sec) + 1
  if l:n <= 0
    let l:u = s:first_section_index_in_lines(l:lines) + 1
    if l:u <= 0
      " 関係の節がまだ無い日記: 末尾に節を作る
      let l:u = len(l:lines) + 1
    endif
    call append(l:u - 1, [l:sec, ''])
    let l:n = l:u
  endif
  let l:cnt = 0
  while l:cnt < 3 && l:n - 1 - l:cnt >= 1 && trim(getline(l:n - 1 - l:cnt)) ==# ''
    let l:cnt += 1
  endwhile
  if l:cnt < 3
    call append(l:n - 1, repeat([''], 3 - l:cnt))
    let l:n += 3 - l:cnt
  endif
  call cursor(l:n - 2, 1)
endfunction

" 前回の検索ハイライトを消す。関数の中の :nohlsearch / v:hlsearch=0 は関数を抜けると
" 元に戻される（検索状態が復元される）ので、<Cmd> を typeahead に積んで関数の外で実行する。
function! gnosis#clear_search_highlight() abort
  call feedkeys("\<Cmd>nohlsearch\<CR>", 'n')
endfunction
