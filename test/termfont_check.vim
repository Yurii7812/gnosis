" 文字サイズ（gnosis#termfont）の回帰網。test/termfont_net.sh から動かす（端末の環境変数は空にしてある）。
let s:w = $TF_WORK
let s:out = []
function! s:ok(name, cond) abort
  call add(s:out, (a:cond ? 'OK ' : 'NG ') . a:name)
endfunction
try
  call gnosis#i18n#set_lang('ja')
  " 以前の版: 文字サイズは最後の vault の設定にだけあった
  let s:v = s:w . '/vault'
  call gnosis#vault#create(s:v)
  call gnosis#vault#select(s:v)
  call gnosis#settings#save(s:v, extend(gnosis#settings#load(s:v), {'fontSize': 21}))
  call s:ok('移行: terminal.json が無いときは vault の文字サイズ', gnosis#termfont#load().fontSize == 21)
  call gnosis#settings#activate(s:v)
  let s:r = gnosis#termfont#set_size(20)
  call s:ok('保存: 成功', s:r.saved && filereadable(gnosis#termfont#file()))
  call s:ok('保存: 値', gnosis#home#read_json(gnosis#termfont#file(), {}).fontSize == 20)
  call s:ok('保存: 開いている vault の設定にも書き写す（アプリ向け）', gnosis#settings#load(s:v).fontSize == 20)
  call s:ok('反映: 端末が分からないときは反映したことにしない', !s:r.applied)
  call s:ok('説明: 反映できない端末では、保存したことと端末側で調整することを伝える',
        \ gnosis#termfont#describe(s:r) =~# '20 を保存しました' && gnosis#termfont#describe(s:r) =~# '変えられません')
  call s:ok('範囲: 大きすぎる値は 48', gnosis#termfont#set_size(100).size == 48)
  call s:ok('範囲: 小さすぎる値は 6', gnosis#termfont#set_size(1).size == 6)
  call gnosis#termfont#command('+3')
  call s:ok(':GnosisFontSize +3', gnosis#termfont#load().fontSize == 9)
  call gnosis#termfont#command('reset')
  call s:ok(':GnosisFontSize reset', gnosis#termfont#load().fontSize == 16)
  call gnosis#termfont#command('18')
  call s:ok(':GnosisFontSize 18（再起動後も読める）', gnosis#home#read_json(gnosis#termfont#file(), {}).fontSize == 18)

  " Konsole: Gnosis が開いていない窓（ふだんの Konsole）ではその場では変えない
  let $KONSOLE_DBUS_SESSION = '/Sessions/1'
  let $KONSOLE_DBUS_SERVICE = ':1.999'
  let s:t = gnosis#termfont#detect()
  call s:ok('Konsole: 見分ける', s:t.name ==# 'konsole' && !s:t.own && !s:t.live)
  let s:r = gnosis#termfont#set_size(19)
  call s:ok('Konsole（ふだんの窓）: 反映したことにしない', s:r.saved && !s:r.applied)
  call s:ok('Konsole（ふだんの窓）: Gnosis の窓なら変わると説明', gnosis#termfont#describe(s:r) =~# 'Gnosis が開いたものではない')
  let $KONSOLE_DBUS_SESSION = ''
  let $KONSOLE_DBUS_SERVICE = ''
  " XFCE Terminal: 開くときだけ
  let $GNOSIS_TERMINAL_KIND = 'xfce4-terminal'
  let s:r = gnosis#termfont#set_size(17)
  call s:ok('XFCE: 次の Gnosis の窓で反映と説明', !s:r.applied && gnosis#termfont#describe(s:r) =~# '次に Gnosis のアイコン')
  let $GNOSIS_TERMINAL_KIND = ''
  " GNOME Terminal: Gnosis からは変えられない
  let $GNOSIS_TERMINAL_KIND = 'gnome-terminal'
  call s:ok('GNOME: 変えられないと説明', gnosis#termfont#status() =~# 'Gnosis からは変えられません')
  let $GNOSIS_TERMINAL_KIND = ''
  call gnosis#termfont#set('fontFamily', 'DejaVu Sans Mono')
  call gnosis#termfont#set('lineSpacing', 4)
  call s:ok('フォント・行間の保存', gnosis#termfont#load().fontFamily ==# 'DejaVu Sans Mono' && gnosis#termfont#load().lineSpacing == 4)
catch
  call add(s:out, 'NG 例外: ' . v:exception . ' @ ' . v:throwpoint)
endtry
call writefile(s:out, s:w . '/result.txt')
qa!
