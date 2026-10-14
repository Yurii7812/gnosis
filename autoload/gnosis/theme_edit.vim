" =============================================================================
" autoload/gnosis/theme_edit.vim — カスタムテーマの編集（カラーパレットとリアルタイムプレビュー付き）
"
" 色を数字で打つだけでは、実際の表示が分からない。この画面は、
"   - 6 つの色（背景・本文・リンク・見出し・選択範囲・カーソル行）を HEX コードと色見本で並べ、
"   - 8 色相 × 9 段階のカラーパレットから選べ（Tab でパレットに移る）、
"   - 日本語の文章で、リンク（表示名＋下線）・見出し・選択範囲・カーソル行を、
"     Gnosis が実際に表示するときと同じ組み合わせで見せる。
" 色を変えると、保存する前でもすぐプレビューに反映される。プレビューは専用のハイライトと
" テキストプロパティだけで描くので、今の画面の配色（実際のテーマ）は変わらない。
" 保存する（s）まで設定は書き換えない。取り消す（Esc / q）と、何も変えずに戻る。
" ノートは一切変更しない。
"
" 使い方: gnosis#theme_edit#open({'target': 'vim' | 'app', 'name': 名前, 'colors': {…},
"                                 'on_close': Funcref(result)})
"   result は 保存したとき {'name': 名前, 'theme': {base, bg, fg, link, heading, selection, cursorline}}、
"   取り消したとき {}。
" キー: ↑ ↓ 項目 / ← → 明るさ / [ ] 色相 / - + 鮮やかさ / Enter・e HEX を入力（打つたびに反映）
"       Tab パレットへ（↑ ↓ ← → で選ぶ。Enter か Tab で戻る） / r この色を元に戻す / n 名前 / s 保存 / Esc・q 取り消し
" =============================================================================

let s:keys = ['bg', 'fg', 'link', 'heading', 'selection', 'cursorline']
let s:hues = [[-1, 0.0], [0, 0.62], [28, 0.72], [50, 0.78], [130, 0.45], [175, 0.5], [212, 0.62], [275, 0.45]]
let s:lights = [0.12, 0.22, 0.34, 0.46, 0.58, 0.70, 0.82, 0.92, 0.98]
let s:st = {}

function! s:t(key, ...) abort
  return call('gnosis#i18n#t', [a:key] + a:000)
endfunction

" ---------------------------------------------------------------------------
" 色の計算（HSL ↔ #rrggbb）
" ---------------------------------------------------------------------------
function! s:hsl2hex(h, s, l) abort
  let l:hd = fmod(a:h + 3600.0, 360.0)
  let l:h = l:hd / 360.0
  if a:s <= 0.0
    let l:r = a:l | let l:g = a:l | let l:b = a:l
  else
    let l:q = a:l < 0.5 ? a:l * (1 + a:s) : a:l + a:s - a:l * a:s
    let l:p = 2 * a:l - l:q
    let l:r = s:hue2rgb(l:p, l:q, l:h + 1.0 / 3)
    let l:g = s:hue2rgb(l:p, l:q, l:h)
    let l:b = s:hue2rgb(l:p, l:q, l:h - 1.0 / 3)
  endif
  return printf('#%02x%02x%02x', float2nr(l:r * 255 + 0.5), float2nr(l:g * 255 + 0.5), float2nr(l:b * 255 + 0.5))
endfunction

function! s:hue2rgb(p, q, t) abort
  let l:t = a:t < 0 ? a:t + 1 : (a:t > 1 ? a:t - 1 : a:t)
  if l:t < 1.0 / 6 | return a:p + (a:q - a:p) * 6 * l:t | endif
  if l:t < 0.5 | return a:q | endif
  if l:t < 2.0 / 3 | return a:p + (a:q - a:p) * (2.0 / 3 - l:t) * 6 | endif
  return a:p
endfunction

function! s:hex2hsl(hex) abort
  let l:r = str2nr(a:hex[1:2], 16) / 255.0
  let l:g = str2nr(a:hex[3:4], 16) / 255.0
  let l:b = str2nr(a:hex[5:6], 16) / 255.0
  let l:mx = l:r > l:g ? (l:r > l:b ? l:r : l:b) : (l:g > l:b ? l:g : l:b)
  let l:mn = l:r < l:g ? (l:r < l:b ? l:r : l:b) : (l:g < l:b ? l:g : l:b)
  let l:l = (l:mx + l:mn) / 2
  if l:mx == l:mn
    return [0.0, 0.0, l:l]
  endif
  let l:d = l:mx - l:mn
  let l:s = l:l > 0.5 ? l:d / (2 - l:mx - l:mn) : l:d / (l:mx + l:mn)
  if l:mx == l:r
    let l:h = (l:g - l:b) / l:d + (l:g < l:b ? 6 : 0)
  elseif l:mx == l:g
    let l:h = (l:b - l:r) / l:d + 2
  else
    let l:h = (l:r - l:g) / l:d + 4
  endif
  return [l:h * 60, l:s, l:l]
endfunction

function! s:clamp(v, lo, hi) abort
  return a:v < a:lo ? a:lo : (a:v > a:hi ? a:hi : a:v)
endfunction

" ---------------------------------------------------------------------------
" 開く・閉じる
" ---------------------------------------------------------------------------
function! gnosis#theme_edit#open(opts) abort
  let l:colors = {}
  for l:k in s:keys
    let l:v = gnosis#color#normalize(get(get(a:opts, 'colors', {}), l:k, ''))
    let l:colors[l:k] = empty(l:v) ? '#808080' : l:v
  endfor
  let s:st = {
        \ 'target': get(a:opts, 'target', 'vim'),
        \ 'name': get(a:opts, 'name', 'my-theme'),
        \ 'colors': l:colors,
        \ 'orig': copy(l:colors),
        \ 'orig_name': get(a:opts, 'name', 'my-theme'),
        \ 'sel': 0, 'focus': 'list', 'grid': [0, 4],
        \ 'msg': '', 'on_close': get(a:opts, 'on_close', 0),
        \ 'prev': bufnr('%'), 'done': 0, 'result': {}, 'typing': 0,
        \ }
  enew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nonumber norelativenumber nowrap nolist
  setlocal nocursorline nospell nofoldenable colorcolumn= signcolumn=no
  silent! file Gnosis\ Theme
  let b:gnosis_theme_edit = 1
  let s:st.buf = bufnr('%')
  augroup gnosis_theme_edit
    autocmd! * <buffer>
    autocmd VimResized <buffer> call gnosis#theme_edit#render()
  augroup END
  let l:keys = ['<Up>', '<Down>', '<Left>', '<Right>', 'j', 'k', 'h', 'l', '[', ']', '-', '+', '=', '<CR>', 'e', '<Tab>',
        \ '<S-Tab>', 'r', 'R', 'n', 's', 'q', '<Esc>', '<kPlus>', '<kMinus>']
  for l:k in l:keys
    execute printf('nnoremap <buffer><silent><nowait> %s <Cmd>call gnosis#theme_edit#key(%s)<CR>', l:k, substitute(string(l:k), '<', '<lt>', 'g'))
  endfor
  for l:k in ['i', 'I', 'o', 'O', 'a', 'A', 'x', 'p', 'P', 'c', 'C', 'u', 'd', 'v', 'V']
    execute 'nnoremap <buffer><silent><nowait> ' . l:k . ' <Nop>'
  endfor
  call s:apply_highlights()
  call s:define_types()
  call gnosis#theme_edit#render()
endfunction

function! s:finish(result) abort
  let l:Cb = s:st.on_close
  let l:prev = s:st.prev
  let s:st.done = 1
  let s:st.result = a:result
  " 編集用のバッファを閉じる（bufhidden=wipe）
  if bufexists(l:prev) && l:prev != bufnr('%')
    execute 'silent! buffer ' . l:prev
  else
    enew
  endif
  if type(l:Cb) == v:t_func
    call l:Cb(a:result)
  endif
endfunction

" 編集中の状態（試験用）
function! gnosis#theme_edit#state() abort
  return s:st
endfunction

" ---------------------------------------------------------------------------
" 色を変える（ここを通れば、プレビューがすぐ変わる）
" ---------------------------------------------------------------------------
function! gnosis#theme_edit#set_color(key, hex) abort
  let l:c = gnosis#color#normalize(a:hex)
  if index(s:keys, a:key) < 0 || empty(l:c) || empty(s:st)
    return 0
  endif
  let s:st.colors[a:key] = l:c
  call gnosis#theme_edit#render()
  return 1
endfunction

function! s:cur_key() abort
  return s:keys[s:st.sel]
endfunction

function! s:modified() abort
  return s:st.colors !=# s:st.orig || s:st.name !=# s:st.orig_name
endfunction

" 明るさ・色相・鮮やかさを少しずつ動かす
function! s:nudge(dim, delta) abort
  let l:key = s:cur_key()
  let [l:h, l:s, l:l] = s:hex2hsl(s:st.colors[l:key])
  if a:dim ==# 'l'
    let l:l = s:clamp(l:l + a:delta, 0.0, 1.0)
  elseif a:dim ==# 'h'
    let l:h = l:h + a:delta * 360
  else
    let l:s = s:clamp(l:s + a:delta, 0.0, 1.0)
  endif
  call gnosis#theme_edit#set_color(l:key, s:hsl2hex(l:h, l:s, l:l))
endfunction

" パレット（8 色相 × 9 段階）の色
function! s:palette_color(r, c) abort
  let [l:hue, l:sat] = s:hues[a:r]
  return s:hsl2hex(l:hue < 0 ? 0 : l:hue, l:sat, s:lights[a:c])
endfunction

" ---------------------------------------------------------------------------
" キー
" ---------------------------------------------------------------------------
function! gnosis#theme_edit#key(k) abort
  if empty(s:st) || s:st.done
    return
  endif
  let s:st.msg = ''
  let l:k = a:k
  if s:st.focus ==# 'grid'
    let [l:r, l:c] = s:st.grid
    if l:k ==# '<Up>' || l:k ==# 'k'
      let l:r = max([l:r - 1, 0])
    elseif l:k ==# '<Down>' || l:k ==# 'j'
      let l:r = min([l:r + 1, len(s:hues) - 1])
    elseif l:k ==# '<Left>' || l:k ==# 'h'
      let l:c = max([l:c - 1, 0])
    elseif l:k ==# '<Right>' || l:k ==# 'l'
      let l:c = min([l:c + 1, len(s:lights) - 1])
    elseif l:k ==# '<CR>' || l:k ==# '<Tab>' || l:k ==# '<S-Tab>' || l:k ==# '<Esc>'
      let s:st.focus = 'list'
      call gnosis#theme_edit#render()
      return
    elseif l:k ==# 's'
      call s:save()
      return
    elseif l:k ==# 'q'
      call s:cancel()
      return
    endif
    let s:st.grid = [l:r, l:c]
    call gnosis#theme_edit#set_color(s:cur_key(), s:palette_color(l:r, l:c))
    return
  endif
  if l:k ==# '<Up>' || l:k ==# 'k'
    let s:st.sel = max([s:st.sel - 1, 0])
  elseif l:k ==# '<Down>' || l:k ==# 'j'
    let s:st.sel = min([s:st.sel + 1, len(s:keys) - 1])
  elseif l:k ==# '<Left>' || l:k ==# 'h'
    call s:nudge('l', -0.04)
    return
  elseif l:k ==# '<Right>' || l:k ==# 'l'
    call s:nudge('l', 0.04)
    return
  elseif l:k ==# '['
    call s:nudge('h', -0.03)
    return
  elseif l:k ==# ']'
    call s:nudge('h', 0.03)
    return
  elseif l:k ==# '-' || l:k ==# '<kMinus>'
    call s:nudge('s', -0.08)
    return
  elseif l:k ==# '+' || l:k ==# '=' || l:k ==# '<kPlus>'
    call s:nudge('s', 0.08)
    return
  elseif l:k ==# '<CR>' || l:k ==# 'e'
    call s:enter_hex()
    return
  elseif l:k ==# '<Tab>' || l:k ==# '<S-Tab>'
    let s:st.focus = 'grid'
  elseif l:k ==# 'r'
    call gnosis#theme_edit#set_color(s:cur_key(), s:st.orig[s:cur_key()])
    return
  elseif l:k ==# 'R'
    let s:st.colors = copy(s:st.orig)
  elseif l:k ==# 'n'
    call s:rename()
  elseif l:k ==# 's'
    call s:save()
    return
  elseif l:k ==# 'q' || l:k ==# '<Esc>'
    call s:cancel()
    return
  endif
  call gnosis#theme_edit#render()
endfunction

" HEX コードを直接入力する。打つたびに（3 桁か 6 桁そろったら）プレビューに反映する。
" Enter で確定、Esc で入力前に戻す。
function! s:enter_hex() abort
  let l:key = s:cur_key()
  let l:orig = s:st.colors[l:key]
  let l:buf = ''
  let s:st.typing = 1
  try
    while 1
      call gnosis#theme_edit#render()
      echo s:t('theme_edit.prompt_hex', s:t('settings.color.' . l:key)) . '#' . l:buf . '_'
      let l:c = gnosis#ui#getkey()
      if l:c ==# "\<Esc>" || l:c ==# "\<C-c>"
        let s:st.colors[l:key] = l:orig
        break
      elseif l:c ==# "\<CR>" || l:c ==# "\<NL>"
        if !empty(gnosis#color#normalize(l:buf))
          let s:st.colors[l:key] = gnosis#color#normalize(l:buf)
        else
          let s:st.colors[l:key] = l:orig
          let s:st.msg = s:t('settings.bad_color', '#' . l:buf)
        endif
        break
      elseif l:c ==# "\<BS>" || l:c ==# "\x08" || l:c ==# "\x7f" || l:c ==# "\<Del>"
        let l:buf = strpart(l:buf, 0, max([0, len(l:buf) - 1]))
      elseif l:c ==# "\<C-u>"
        let l:buf = ''
      elseif l:c =~# '^[0-9a-fA-F]$' && len(l:buf) < 6
        let l:buf .= l:c
      elseif l:c ==# '#'
        " 先頭の # は読み飛ばす
      endif
      let l:n = gnosis#color#normalize(l:buf)
      if !empty(l:n) && (len(l:buf) == 3 || len(l:buf) == 6)
        let s:st.colors[l:key] = l:n
      else
        let s:st.colors[l:key] = l:orig
      endif
    endwhile
  finally
    let s:st.typing = 0
  endtry
  call gnosis#theme_edit#render()
endfunction

function! s:rename() abort
  let l:r = ''
  if exists('g:gnosis_test_display_name') && !empty(g:gnosis_test_display_name)
    let l:r = remove(g:gnosis_test_display_name, 0)
  else
    try
      let l:r = inputdialog(s:t('settings.prompt_custom_name'), s:st.name, "\x01")
    catch /^Vim:Interrupt$/
      let l:r = "\x01"
    endtry
  endif
  redraw
  if l:r !=# "\x01" && !empty(trim(l:r))
    let s:st.name = trim(l:r)
  endif
endfunction

function! s:save() abort
  let l:name = trim(s:st.name)
  if empty(l:name)
    let s:st.msg = s:t('theme_edit.need_name')
    call gnosis#theme_edit#render()
    return
  endif
  let l:theme = copy(s:st.colors)
  let l:theme.base = gnosis#color#base_of(s:st.colors.bg)
  call s:finish({'name': l:name, 'theme': l:theme})
endfunction

function! s:cancel() abort
  if s:modified()
    let l:ans = exists('g:gnosis_test_confirm') ? g:gnosis_test_confirm : confirm(s:t('theme_edit.confirm_discard'), "&Yes\n&No", 2)
    if l:ans != 1
      call gnosis#theme_edit#render()
      return
    endif
  endif
  call s:finish({})
endfunction

" ---------------------------------------------------------------------------
" プレビュー用のハイライトとテキストプロパティ
"   プレビューの色は専用のグループ（GnosisTe*）だけで決め、実際のテーマ（Normal など）は触らない。
" ---------------------------------------------------------------------------
function! s:hlset(group, fg, bg, attr) abort
  let l:cmd = 'highlight ' . a:group
  let l:cmd .= ' guifg=' . (empty(a:fg) ? 'NONE' : a:fg) . ' ctermfg=' . (empty(a:fg) ? 'NONE' : gnosis#theme#to_cterm(a:fg))
  let l:cmd .= ' guibg=' . (empty(a:bg) ? 'NONE' : a:bg) . ' ctermbg=' . (empty(a:bg) ? 'NONE' : gnosis#theme#to_cterm(a:bg))
  let l:a = empty(a:attr) ? 'NONE' : a:attr
  execute l:cmd . ' gui=' . l:a . ' cterm=' . l:a . ' term=' . l:a
endfunction

let s:type_names = []
function! s:define_types() abort
  let l:names = ['GnosisTeText', 'GnosisTeDim', 'GnosisTeHead', 'GnosisTeLink', 'GnosisTeSel',
        \ 'GnosisTeCurText', 'GnosisTeCurDim', 'GnosisTeCurLink', 'GnosisTeCurSel']
  for l:i in range(len(s:keys))
    call add(l:names, 'GnosisTeSw' . l:i)
  endfor
  for l:r in range(len(s:hues))
    for l:c in range(len(s:lights))
      call add(l:names, 'GnosisTeGr' . l:r . '_' . l:c)
    endfor
  endfor
  for l:n in l:names
    if empty(prop_type_get(l:n))
      call prop_type_add(l:n, {'highlight': l:n, 'priority': 10})
    endif
  endfor
  let s:type_names = l:names
endfunction

" 色見本の文字色（背景が明るければ黒、暗ければ白）
function! s:on(bg) abort
  return gnosis#color#luminance(a:bg) > 0.45 ? '#000000' : '#ffffff'
endfunction

" 保存する前のプレビューで使う色（試験用に公開）。表示で使う補助の色は、Gnosis の配色と同じ求め方。
function! gnosis#theme_edit#derived() abort
  let l:c = s:st.colors
  let l:dark = gnosis#color#base_of(l:c.bg) ==# 'dark'
  return {
        \ 'dim': gnosis#color#mix(l:c.fg, l:c.bg, 0.35),
        \ 'strong': gnosis#color#mix(l:c.fg, l:dark ? '#ffffff' : '#000000', 0.6),
        \ }
endfunction

function! s:apply_highlights() abort
  let l:c = s:st.colors
  let l:d = gnosis#theme_edit#derived()
  call s:hlset('GnosisTeText', l:c.fg, l:c.bg, '')
  call s:hlset('GnosisTeDim', l:d.dim, l:c.bg, '')
  call s:hlset('GnosisTeHead', l:c.heading, l:c.bg, 'bold')
  call s:hlset('GnosisTeLink', l:c.link, l:c.bg, 'underline')
  call s:hlset('GnosisTeSel', l:d.strong, l:c.selection, '')
  call s:hlset('GnosisTeCurText', l:c.fg, l:c.cursorline, '')
  call s:hlset('GnosisTeCurDim', l:d.dim, l:c.cursorline, '')
  call s:hlset('GnosisTeCurLink', l:c.link, l:c.cursorline, 'underline')
  call s:hlset('GnosisTeCurSel', l:d.strong, l:c.selection, '')
  for l:i in range(len(s:keys))
    let l:v = l:c[s:keys[l:i]]
    call s:hlset('GnosisTeSw' . l:i, s:on(l:v), l:v, 'bold')
  endfor
  for l:r in range(len(s:hues))
    for l:cc in range(len(s:lights))
      let l:v = s:palette_color(l:r, l:cc)
      call s:hlset('GnosisTeGr' . l:r . '_' . l:cc, s:on(l:v), l:v, 'bold')
    endfor
  endfor
endfunction

" プレビューの 1 行（セグメント [[文字, グループ], …]）。幅をそろえて返す: [行の文字列, [[桁, 長さ, グループ], …]]
function! s:preview_line(segs, width, base_group) abort
  let l:text = ''
  let l:props = []
  for [l:t, l:g] in a:segs
    if empty(l:t) | continue | endif
    call add(l:props, [strlen(l:text) + 1, strlen(l:t), l:g])
    let l:text .= l:t
  endfor
  let l:pad = a:width - strdisplaywidth(l:text)
  if l:pad > 0
    call add(l:props, [strlen(l:text) + 1, l:pad, a:base_group])
    let l:text .= repeat(' ', l:pad)
  endif
  return [l:text, l:props]
endfunction

" 実際に Gnosis が出す見た目の例（日本語の文章。リンクは表示名だけ・下線、見出しは見出しの色・太字、
" # は控えめな色、選択範囲とカーソル行つき）
function! s:sample(width) abort
  let l:out = []
  call add(l:out, s:preview_line([['# ', 'GnosisTeDim'], ['植物について', 'GnosisTeHead']], a:width, 'GnosisTeText'))
  call add(l:out, s:preview_line([], a:width, 'GnosisTeText'))
  call add(l:out, s:preview_line([['植物', 'GnosisTeText'], ['についての情報', 'GnosisTeSel'], ['をまとめる。', 'GnosisTeText']], a:width, 'GnosisTeText'))
  call add(l:out, s:preview_line([], a:width, 'GnosisTeText'))
  call add(l:out, s:preview_line([['関連する情報：', 'GnosisTeText']], a:width, 'GnosisTeText'))
  call add(l:out, s:preview_line([['ローズマリー', 'GnosisTeCurLink'], ['  ← カーソル行', 'GnosisTeCurDim']], a:width, 'GnosisTeCurText'))
  call add(l:out, s:preview_line([['レモンバーム', 'GnosisTeLink']], a:width, 'GnosisTeText'))
  call add(l:out, s:preview_line([], a:width, 'GnosisTeText'))
  call add(l:out, s:preview_line([['### ', 'GnosisTeDim'], ['Context', 'GnosisTeHead']], a:width, 'GnosisTeText'))
  call add(l:out, s:preview_line([['ハーブ', 'GnosisTeLink']], a:width, 'GnosisTeText'))
  call add(l:out, s:preview_line([['### ', 'GnosisTeDim'], ['ChildBranch', 'GnosisTeHead']], a:width, 'GnosisTeText'))
  call add(l:out, s:preview_line([['植物の栽培', 'GnosisTeLink']], a:width, 'GnosisTeText'))
  return l:out
endfunction

function! s:ratio_line(label, fg, bg) abort
  let l:r = gnosis#color#contrast(a:fg, a:bg)
  return [printf('%s  %.1f : 1  %s', a:label, l:r, l:r >= 4.5 ? '✓' : s:t('theme_edit.low_contrast')), l:r >= 4.5]
endfunction

" ---------------------------------------------------------------------------
" 画面
" ---------------------------------------------------------------------------
function! gnosis#theme_edit#render() abort
  if !get(b:, 'gnosis_theme_edit', 0) || empty(s:st)
    return
  endif
  call s:apply_highlights()
  let l:width = winwidth(0)
  let l:c = s:st.colors
  let l:lines = []
  let l:hls = []   " [group, lnum, col, len]（col = 0 なら行全体）
  let l:props = [] " [lnum, col, len, group]
  call add(l:lines, ' Gnosis — ' . s:t('theme_edit.title_' . s:st.target))
  call add(l:hls, ['gnosisSettingsTitle', 1, 0, 0])
  call add(l:lines, ' ' . s:t('theme_edit.name') . ' ' . s:st.name . (s:modified() ? '  *' : ''))
  call add(l:hls, ['gnosisSettingsDim', 2, 0, 0])
  call add(l:lines, '')
  " ---- 6 つの色（HEX と色見本）
  let l:w = 0
  for l:k in s:keys
    let l:w = max([l:w, strdisplaywidth(s:t('settings.color.' . l:k))])
  endfor
  let s:rows = []
  for l:i in range(len(s:keys))
    let l:k = s:keys[l:i]
    let l:label = s:t('settings.color.' . l:k)
    let l:mark = (l:i == s:st.sel && s:st.focus ==# 'list') ? ' > ' : (l:i == s:st.sel ? ' · ' : '   ')
    let l:row = l:mark . l:label . repeat(' ', l:w - strdisplaywidth(l:label) + 2) . toupper(l:c[l:k]) . '   '
    call add(l:lines, l:row . '    ')
    call add(s:rows, len(l:lines))
    call add(l:props, [len(l:lines), strlen(l:row) + 1, 4, 'GnosisTeSw' . l:i])
    if l:i == s:st.sel && s:st.focus ==# 'list'
      call add(l:hls, ['gnosisSettingsSel', len(l:lines), 1, strlen(l:row)])
    endif
  endfor
  call add(l:lines, '')
  " ---- カラーパレット（8 色相 × 9 段階）
  call add(l:lines, ' ' . s:t('theme_edit.palette') . (s:st.focus ==# 'grid' ? '  [' . s:t('theme_edit.palette_active') . ']' : ''))
  call add(l:hls, ['gnosisSettingsDim', len(l:lines), 0, 0])
  for l:r in range(len(s:hues))
    let l:text = '   '
    let l:cell = []
    for l:cc in range(len(s:lights))
      let l:on = s:st.focus ==# 'grid' && s:st.grid == [l:r, l:cc]
      call add(l:cell, [strlen(l:text) + 1, l:on ? '<>' : '  ', 'GnosisTeGr' . l:r . '_' . l:cc])
      let l:text .= (l:on ? '<>' : '  ') . ' '
    endfor
    call add(l:lines, l:text)
    for [l:col, l:t, l:g] in l:cell
      call add(l:props, [len(l:lines), l:col, 2, l:g])
    endfor
  endfor
  call add(l:lines, '')
  " ---- プレビュー
  call add(l:lines, ' ' . s:t('theme_edit.preview'))
  call add(l:hls, ['gnosisSettingsDim', len(l:lines), 0, 0])
  let l:pw = max([36, min([64, l:width - 6])])
  let s:preview_top = len(l:lines) + 1
  for [l:text, l:ps] in s:sample(l:pw)
    call add(l:lines, '   ' . l:text)
    for [l:col, l:len, l:g] in l:ps
      call add(l:props, [len(l:lines), l:col + 3, l:len, l:g])
    endfor
  endfor
  call add(l:lines, '')
  " ---- 読みやすさ（コントラスト比）
  for [l:lab, l:fg, l:bg] in [[s:t('settings.color.fg'), l:c.fg, l:c.bg], [s:t('settings.color.link'), l:c.link, l:c.bg], [s:t('settings.color.heading'), l:c.heading, l:c.bg]]
    let [l:txt, l:good] = s:ratio_line(l:lab, l:fg, l:bg)
    call add(l:lines, '   ' . l:txt)
    call add(l:hls, [l:good ? 'gnosisSettingsOk' : 'gnosisSettingsWarn', len(l:lines), 0, 0])
  endfor
  call add(l:lines, '')
  call add(l:lines, '   ' . s:t('theme_edit.keys'))
  call add(l:hls, ['gnosisSettingsDim', len(l:lines), 0, 0])
  call add(l:lines, '   ' . s:t('theme_edit.keys2'))
  call add(l:hls, ['gnosisSettingsDim', len(l:lines), 0, 0])
  if !empty(s:st.msg)
    call extend(l:lines, ['', '   ' . s:st.msg])
    call add(l:hls, ['gnosisSettingsWarn', len(l:lines), 0, 0])
  endif
  setlocal modifiable
  silent %delete _
  call setline(1, l:lines)
  setlocal nomodifiable
  call clearmatches()
  silent! call prop_clear(1, line('$'))
  for [l:g, l:ln, l:col, l:len] in l:hls
    if l:col == 0
      call matchaddpos(l:g, [l:ln], l:g ==# 'gnosisSettingsSel' ? 5 : 10)
    else
      call matchaddpos(l:g, [[l:ln, l:col, l:len]], 10)
    endif
  endfor
  for [l:ln, l:col, l:len, l:g] in l:props
    call prop_add(l:ln, l:col, {'length': l:len, 'type': l:g})
  endfor
  call cursor(s:rows[s:st.sel], 4)
  redraw
endfunction
