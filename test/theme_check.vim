" テーマ（配色）の回帰網（test/theme_net.sh から呼ぶ）。HOME と GNOSIS_HOME は一時フォルダ。
"   - 通常の Vim の標準配色が変わらない（背景 #1E1E1E・本文 #DADADA・リンク #6CB6FF・見出し #DADADA）
"   - \c のアプリの既定は通常の Vim と同じ見た目（ダーク・ライト。リンクと見出しも読める）
"   - 通常の Vim のテーマと \c のテーマは独立（一方を変えても他方は変わらない）
"   - カスタムテーマの編集: 色の変更がプレビューへ即時に反映される・取り消しでは保存されない・保存後に読み直しても残る
"   - 保存した設定で再起動（読み直し）しても配色が維持される・古い設定ファイルとの互換
" 結果は $THEME_WORK/result.txt に「OK 名前」「NG 名前: 詳細」で書く。
set nomore
let s:w = $THEME_WORK
let s:res = []
function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
function! s:gui(group, what) abort
  return tolower(synIDattr(synIDtrans(hlID(a:group)), a:what . '#', 'gui'))
endfunction

let s:v = s:w . '/vault'
call mkdir(s:v . '/.gnosis', 'p')
call writefile(['---', 'title: Index', 'attribute: group', '---', '', '# Index'], s:v . '/index.md')

" ------------------------------------------------------------ 標準配色（通常の Vim）
let s:def = gnosis#settings#defaults()
let s:vp = gnosis#theme#palette(s:def)
call s:ok('通常の Vim の標準配色: 背景', toupper(s:vp.bg) ==# '#1E1E1E', s:vp.bg)
call s:ok('通常の Vim の標準配色: 本文', toupper(s:vp.fg) ==# '#DADADA')
call s:ok('通常の Vim の標準配色: リンク', toupper(s:vp.link) ==# '#6CB6FF')
call s:ok('通常の Vim の標準配色: 見出し', toupper(s:vp.heading) ==# '#DADADA')
call gnosis#settings#apply(s:def)
call s:ok('通常の Vim: 適用した Normal の背景・本文', s:gui('Normal', 'bg') ==# '#1e1e1e' && s:gui('Normal', 'fg') ==# '#dadada', s:gui('Normal', 'bg') . ' ' . s:gui('Normal', 'fg'))
call s:ok('通常の Vim: 見出しの色・リンクの色', s:gui('markdownH1', 'fg') ==# '#dadada' && s:gui('markdownLinkText', 'fg') ==# '#6cb6ff')

" ------------------------------------------------------------ \c のアプリの既定（白）
let s:ap = gnosis#theme#app_palette(s:def)
call s:ok('\c の既定: 通常の Vim と同じダークの背景', toupper(s:ap.bg) ==# '#1E1E1E', s:ap.bg)
call s:ok('\c の既定: 本文も同じ', toupper(s:ap.fg) ==# '#DADADA')
call s:ok('\c の既定: ダークは暗い配色', s:ap.base ==# 'dark')
call s:ok('\c: ライトの見た目なら白い背景', toupper(gnosis#theme#app_palette(extend(copy(s:def), {'appearance': 'light'})).bg) ==# '#FFFFFF' && gnosis#theme#app_palette(extend(copy(s:def), {'appearance': 'light'})).base ==# 'light')
call s:ok('\c: ダークの見た目なら灰色の背景', toupper(gnosis#theme#app_palette(extend(copy(s:def), {'appearance': 'dark'})).bg) ==# '#1E1E1E')
call s:ok('\c の既定: 本文と背景のコントラスト 7 以上', gnosis#color#contrast(s:ap.fg, s:ap.bg) >= 7, string(gnosis#color#contrast(s:ap.fg, s:ap.bg)))
call s:ok('\c の既定: リンクは読める（4.5 以上）', gnosis#color#contrast(s:ap.link, s:ap.bg) >= 4.5, string(gnosis#color#contrast(s:ap.link, s:ap.bg)))
call s:ok('\c の既定: 見出しは読める（4.5 以上）', gnosis#color#contrast(s:ap.heading, s:ap.bg) >= 4.5, string(gnosis#color#contrast(s:ap.heading, s:ap.bg)))
call s:ok('\c の既定: リンクと本文は別の色', tolower(s:ap.link) !=# tolower(s:ap.fg) && tolower(s:ap.heading) !=# tolower(s:ap.link))
" アプリの中の Vim（$GNOSIS_GUI_PORT がある）は、アプリ用の配色を使う
let $GNOSIS_GUI_PORT = '1'
call gnosis#settings#apply(s:def)
call s:ok('\c の中の Vim: Normal は通常の Vim と同じダークの色', s:gui('Normal', 'bg') ==# '#1e1e1e' && s:gui('Normal', 'fg') ==# '#dadada', s:gui('Normal', 'bg') . ' ' . s:gui('Normal', 'fg'))
call s:ok('\c の中の Vim: リンクは下線つき（本文と区別できる）', synIDattr(synIDtrans(hlID('markdownLinkText')), 'underline', 'gui') ==# '1' && s:gui('markdownLinkText', 'fg') !=# s:gui('Normal', 'fg'))
call s:ok('\c の中の Vim: 渡す配色はダーク', toupper(g:gnosis_palette.bg) ==# '#1E1E1E' && g:gnosis_palette.base ==# 'dark')
let $GNOSIS_GUI_PORT = ''
call gnosis#settings#apply(s:def)
call s:ok('アプリの外に戻れば通常の Vim の配色', s:gui('Normal', 'bg') ==# '#1e1e1e')

" ------------------------------------------------------------ 独立性
let s:both = deepcopy(s:def)
let s:both.theme = {'kind': 'custom', 'name': 'v'}
let s:both.customThemes = {'v': {'base': 'dark', 'bg': '#220000', 'fg': '#ffeeee', 'link': '#ffaaaa', 'heading': '#ffdd00', 'selection': '#440000', 'cursorline': '#330000'}}
call s:ok('独立: Vim のテーマを変えても \c は組み込みのまま', toupper(gnosis#theme#app_palette(s:both).bg) ==# '#1E1E1E' && gnosis#theme#palette(s:both).bg ==# '#220000')
let s:both2 = deepcopy(s:def)
let s:both2.appTheme = {'kind': 'custom', 'name': 'a'}
let s:both2.appCustomThemes = {'a': {'base': 'dark', 'bg': '#001122', 'fg': '#eeeeff', 'link': '#aaccff', 'heading': '#ffcc00', 'selection': '#113355', 'cursorline': '#0a1a2a'}}
call s:ok('独立: \c のテーマを変えても Vim は標準のまま', toupper(gnosis#theme#palette(s:both2).bg) ==# '#1E1E1E' && gnosis#theme#app_palette(s:both2).bg ==# '#001122')
call s:ok('\c のカスタム: 補助の色は作り直す（muted / accent が組み込みのまま残らない）', !has_key(gnosis#theme#app_palette(s:both2), 'muted') || gnosis#theme#app_palette(s:both2).muted !=# '#57606A')
" 存在しない appTheme の名前は組み込み（白）に戻る
let s:miss = deepcopy(s:def)
let s:miss.appTheme = {'kind': 'custom', 'name': 'nothing'}
call s:ok('存在しない \c のテーマ名は組み込みに戻る', toupper(gnosis#theme#app_palette(s:miss).bg) ==# '#1E1E1E')
" 壊れた設定は直る
let s:bad = gnosis#settings#merge(s:def, {'appTheme': {'kind': 'plugin'}, 'appCustomThemes': 5})
call s:ok('検証: 壊れた appTheme / appCustomThemes は既定に戻る', s:bad.appTheme.kind ==# 'builtin' && type(s:bad.appCustomThemes) == v:t_dict)

" ------------------------------------------------------------ 保存と再読み込み（再起動）・互換
call gnosis#settings#save(s:v, s:both2)
call s:ok('保存: 再読み込みしても \c のテーマが残る', gnosis#settings#load(s:v).appTheme ==# {'kind': 'custom', 'name': 'a'} && gnosis#settings#load(s:v).appCustomThemes.a.bg ==# '#001122')
call s:ok('保存: Vim 側のテーマは標準のまま', gnosis#settings#load(s:v).theme.kind ==# 'builtin')
call gnosis#settings#save(s:v, s:both)
call s:ok('保存: Vim のテーマを保存しても、読み直した \c のテーマは標準', gnosis#settings#load(s:v).appTheme.kind ==# 'builtin' && gnosis#settings#load(s:v).customThemes.v.bg ==# '#220000')
" 古い設定ファイル（appTheme が無い）を読んでも壊れない
call writefile([json_encode({'version': 1, 'language': 'ja', 'appearance': 'dark', 'theme': {'kind': 'custom', 'name': 'old'}, 'customThemes': {'old': {'base': 'dark', 'bg': '#101010', 'fg': '#eeeeee', 'link': '#99ccff', 'heading': '#ffcc66', 'selection': '#333333', 'cursorline': '#222222'}}})], s:v . '/.gnosis/settings.json')
let s:old = gnosis#settings#load(s:v)
call s:ok('互換: 古い設定ファイルのカスタムテーマはそのまま', s:old.theme.name ==# 'old' && gnosis#theme#palette(s:old).bg ==# '#101010')
call s:ok('互換: 古い設定ファイルでも \c は組み込み（その見た目）', toupper(gnosis#theme#app_palette(s:old).bg) ==# toupper(gnosis#theme#palette(extend(copy(s:old), {'theme': {'kind': 'builtin'}})).bg))
" 設定を読んだだけでは、ファイルは書き換えない（既存の vault を開いただけで書き換えない）
let s:before = readfile(s:v . '/.gnosis/settings.json')
call gnosis#settings#load(s:v)
call s:ok('互換: 読み込みだけではファイルを書き換えない', readfile(s:v . '/.gnosis/settings.json') ==# s:before)

" ------------------------------------------------------------ カスタムテーマの編集（リアルタイムプレビュー）
call gnosis#settings#apply(s:def)
let s:note_before = readfile(s:v . '/index.md')
let s:settings_before = readfile(s:v . '/.gnosis/settings.json')
let g:te_result = {'untouched': 1}
function! s:closed(r) abort
  let g:te_result = a:r
endfunction
let s:colors = {'bg': '#1e1e1e', 'fg': '#dadada', 'link': '#6cb6ff', 'heading': '#dadada', 'selection': '#474747', 'cursorline': '#262626'}
call gnosis#theme_edit#open({'target': 'vim', 'name': 'my-theme', 'colors': s:colors, 'on_close': function('s:closed')})
call s:ok('編集: プレビューの背景（最初は今の色）', s:gui('GnosisTeText', 'bg') ==# '#1e1e1e' && s:gui('GnosisTeText', 'fg') ==# '#dadada')
call s:ok('編集: プレビューのリンクは下線・見出しは太字', synIDattr(hlID('GnosisTeLink'), 'underline', 'gui') ==# '1' && synIDattr(hlID('GnosisTeHead'), 'bold', 'gui') ==# '1')
call s:ok('編集: リンク番号の札は今の表示と同じ色から始まる（文字=背景色・札=補助の色）', s:gui('GnosisTeHint', 'fg') ==# '#1e1e1e' && s:gui('GnosisTeHint', 'bg') ==# gnosis#color#mix('#dadada', '#1e1e1e', 0.35) && synIDattr(hlID('GnosisTeHint'), 'bold', 'gui') ==# '1', s:gui('GnosisTeHint', 'fg') . ' ' . s:gui('GnosisTeHint', 'bg'))
" 背景を変えると、保存する前でもすぐプレビューに反映される
call gnosis#theme_edit#set_color('bg', '#ffffff')
call s:ok('編集: 背景の変更がすぐプレビューに反映', s:gui('GnosisTeText', 'bg') ==# '#ffffff' && s:gui('GnosisTeLink', 'bg') ==# '#ffffff' && s:gui('GnosisTeHead', 'bg') ==# '#ffffff')
call gnosis#theme_edit#set_color('fg', '#222222')
call gnosis#theme_edit#set_color('link', '#0b57d0')
call gnosis#theme_edit#set_color('heading', '#7c2d12')
call s:ok('編集: 本文・リンク・見出しも個別にすぐ反映', s:gui('GnosisTeText', 'fg') ==# '#222222' && s:gui('GnosisTeLink', 'fg') ==# '#0b57d0' && s:gui('GnosisTeHead', 'fg') ==# '#7c2d12')
call gnosis#theme_edit#set_color('selection', '#b6d6ff')
call gnosis#theme_edit#set_color('cursorline', '#f2f5f8')
call s:ok('編集: 選択状態とカーソル行も反映', s:gui('GnosisTeSel', 'bg') ==# '#b6d6ff' && s:gui('GnosisTeCurText', 'bg') ==# '#f2f5f8')
call gnosis#theme_edit#set_color('hintfg', '#ffffff')
call gnosis#theme_edit#set_color('hintbg', '#2d70be')
call s:ok('編集: リンク番号の文字と背景がすぐプレビューに反映', s:gui('GnosisTeHint', 'fg') ==# '#ffffff' && s:gui('GnosisTeHint', 'bg') ==# '#2d70be')
call s:ok('編集: プレビューのリンクの手前に番号が出る', join(getline(1, '$'), "\n") =~# '1ローズマリー' && join(getline(1, '$'), "\n") =~# '2レモンバーム' && join(getline(1, '$'), "\n") =~# 'リンク番号の文字\|link number text')
call s:ok('編集: 実際のテーマ（Normal）は保存するまで変わらない', s:gui('Normal', 'bg') ==# '#1e1e1e')
call s:ok('編集: 保存するまで設定ファイルもノートも変わらない', readfile(s:v . '/.gnosis/settings.json') ==# s:settings_before && readfile(s:v . '/index.md') ==# s:note_before)
call s:ok('編集: 画面に HEX・日本語のプレビュー・リンクの表示名が出る', join(getline(1, '$'), "\n") =~# '#FFFFFF' && join(getline(1, '$'), "\n") =~# '植物について' && join(getline(1, '$'), "\n") =~# 'ローズマリー' && join(getline(1, '$'), "\n") !~# 'example\.md')
call s:ok('編集: 見出し・Context・ChildBranch・リンクの例が出る', join(getline(1, '$'), "\n") =~# 'ChildBranch' && join(getline(1, '$'), "\n") =~# 'レモンバーム' && join(getline(1, '$'), "\n") =~# '植物の栽培')
" HEX を打つたびに反映（g:gnosis_ui_keys で打鍵を渡す）
let g:gnosis_ui_keys = ['a', 'b', 'c', 'd', 'e', 'f']
call gnosis#theme_edit#key('<Down>')   " 本文の行へ
let g:gnosis_ui_keys = ['1', '2', '3', '4', '5', '6', "\<CR>"]
call gnosis#theme_edit#key('<CR>')
call s:ok('編集: HEX を直接入力して確定', gnosis#theme_edit#state().colors.fg ==# '#123456' && s:gui('GnosisTeText', 'fg') ==# '#123456')
" Esc で入力前に戻る
let g:gnosis_ui_keys = ['f', 'f', 'f', "\<Esc>"]
call gnosis#theme_edit#key('<CR>')
call s:ok('編集: HEX 入力を Esc でやめると元の色', gnosis#theme_edit#state().colors.fg ==# '#123456')
" 不正な HEX は確定しない
let g:gnosis_ui_keys = ['z', '1', '2', "\<CR>"]
call gnosis#theme_edit#key('<CR>')
call s:ok('編集: 桁が足りない HEX は確定しない', gnosis#theme_edit#state().colors.fg ==# '#123456')
" 3 桁の HEX
let g:gnosis_ui_keys = ['a', 'b', 'c', "\<CR>"]
call gnosis#theme_edit#key('<CR>')
call s:ok('編集: 3 桁の HEX は 6 桁に直る', gnosis#theme_edit#state().colors.fg ==# '#aabbcc')
" パレットから選ぶ（Tab で移り、矢印で選ぶとすぐ反映）
call gnosis#theme_edit#key('<Tab>')
let s:g0 = gnosis#theme_edit#state().colors.fg
call gnosis#theme_edit#key('<Right>')
call s:ok('編集: パレットで選ぶと色がすぐ変わる', gnosis#theme_edit#state().colors.fg !=# s:g0 && s:gui('GnosisTeText', 'fg') ==# gnosis#theme_edit#state().colors.fg)
call gnosis#theme_edit#key('<Tab>')
" 明るさ・色相の調整
let s:l0 = gnosis#theme_edit#state().colors.fg
call gnosis#theme_edit#key('<Right>')
call s:ok('編集: → で明るくなる', gnosis#color#luminance(gnosis#theme_edit#state().colors.fg) > gnosis#color#luminance(s:l0))
" 取り消し（変更があるので確認 → はい）
let g:gnosis_test_confirm = 1
call gnosis#theme_edit#key('<Esc>')
unlet g:gnosis_test_confirm
call s:ok('編集: 取り消すと何も保存せず、設定ファイルも元のまま', g:te_result ==# {} && readfile(s:v . '/.gnosis/settings.json') ==# s:settings_before)
call s:ok('編集: 取り消したあとも実際のテーマは変わらない', s:gui('Normal', 'bg') ==# '#1e1e1e')
" もう一度開いて、保存する
let g:te_result = {'untouched': 1}
call gnosis#theme_edit#open({'target': 'app', 'name': 'my-app-theme', 'colors': s:ap, 'on_close': function('s:closed')})
call s:ok('編集（アプリ用）: 今の \c の配色（ダーク）から始まる', gnosis#theme_edit#state().colors.bg ==# '#1e1e1e')
call gnosis#theme_edit#set_color('link', '#006400')
call gnosis#theme_edit#key('s')
call s:ok('編集（アプリ用）: 保存すると結果が返る（base は背景から決まる）', get(g:te_result, 'name', '') ==# 'my-app-theme' && g:te_result.theme.link ==# '#006400' && g:te_result.theme.base ==# 'dark', string(g:te_result))
call s:ok('編集（アプリ用）: 保存の操作そのものは、まだ設定ファイルを書かない（呼び出し側が保存する）', readfile(s:v . '/.gnosis/settings.json') ==# s:settings_before)

" ------------------------------------------------------------ 設定画面 → 保存 → 再読み込み（Vim 側とアプリ側が別々に残る）
let s:ui = deepcopy(s:def)
let s:ui.customThemes = {'mine': deepcopy(g:te_result.theme)}
let s:ui.theme = {'kind': 'custom', 'name': 'mine'}
let s:ui.appCustomThemes = {'app1': deepcopy(g:te_result.theme)}
let s:ui.appTheme = {'kind': 'custom', 'name': 'app1'}
call gnosis#settings#save(s:v, s:ui)
let s:re = gnosis#settings#load(s:v)
call s:ok('再起動: Vim のテーマとアプリのテーマが別々に残る', s:re.theme.name ==# 'mine' && s:re.appTheme.name ==# 'app1' && gnosis#theme#palette(s:re).link ==# '#006400' && gnosis#theme#app_palette(s:re).link ==# '#006400')
let s:ui.appCustomThemes.app1.link = '#880000'
call gnosis#settings#save(s:v, s:ui)
call s:ok('再起動: アプリ側だけ変えても Vim 側は変わらない', gnosis#theme#palette(gnosis#settings#load(s:v)).link ==# '#006400' && gnosis#theme#app_palette(gnosis#settings#load(s:v)).link ==# '#880000')

" リンクの番号の札（GnosisLinkHint）: 配色に hintfg / hintbg があればその色、無ければ 文字=背景色・札=補助の色
let g:gnosis_palette = copy(gnosis#settings#builtin_palettes().dark)
" GUI と CUI のダーク/ライトは別々（appAppearance。無ければ appearance と同じ）。CUI のライトは目に優しいよう少し灰色（GitHub の #F6F8FA）、GUI のライトは GitHub の白
let s:l_dark = extend(copy(s:def), {'appearance': 'light', 'appAppearance': 'dark'})
call s:ok('GUI だけダーク: CUI がライトでも GUI は暗い', toupper(gnosis#theme#app_palette(s:l_dark).bg) ==# '#1E1E1E' && gnosis#theme#app_palette(s:l_dark).base ==# 'dark' && toupper(gnosis#theme#palette(s:l_dark).bg) ==# '#F6F8FA')
let s:d_light = extend(copy(s:def), {'appearance': 'dark', 'appAppearance': 'light'})
call s:ok('GUI だけライト: CUI がダークでも GUI は白（CUI はダークのまま）', toupper(gnosis#theme#app_palette(s:d_light).bg) ==# '#FFFFFF' && toupper(gnosis#theme#palette(s:d_light).bg) ==# '#1E1E1E')
call s:ok('GUI のライトの本文は GitHub の #1F2328、CUI のライトも同じ文字色', toupper(gnosis#theme#app_palette(s:d_light).fg) ==# '#1F2328' && toupper(gnosis#theme#palette(extend(copy(s:def), {'appearance': 'light'})).fg) ==# '#1F2328')
call s:ok('未設定なら GUI は CUI（appearance）と同じ', toupper(gnosis#theme#app_palette(extend(copy(s:def), {'appearance': 'light'})).bg) ==# '#FFFFFF' && toupper(gnosis#theme#app_palette(extend(copy(s:def), {'appearance': 'dark'})).bg) ==# '#1E1E1E')
call s:ok('壊れた appAppearance は無かったことにする', !has_key(gnosis#settings#validate(extend(copy(s:def), {'appAppearance': 'blue'})), 'appAppearance'))
silent! colorscheme gnosis
call s:ok('リンク番号の札: 設定が無ければ 文字=背景色・札=補助の色', s:gui('GnosisLinkHint', 'fg') ==# tolower(g:gnosis_palette.bg) && s:gui('GnosisLinkHint', 'bg') ==# tolower(g:gnosis_palette.muted), s:gui('GnosisLinkHint', 'fg') . ' ' . s:gui('GnosisLinkHint', 'bg'))
let g:gnosis_palette = extend(copy(gnosis#settings#builtin_palettes().dark), {'hintfg': '#ffffff', 'hintbg': '#2d70be'})
silent! colorscheme gnosis
call s:ok('リンク番号の札: hintfg / hintbg が実際の表示に効く', s:gui('GnosisLinkHint', 'fg') ==# '#ffffff' && s:gui('GnosisLinkHint', 'bg') ==# '#2d70be', s:gui('GnosisLinkHint', 'fg') . ' ' . s:gui('GnosisLinkHint', 'bg'))

call writefile(s:res, s:w . '/result.txt')
qa!
