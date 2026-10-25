" ノートで隠すもの（YAML・上の「名前:」系・下の「名前:」系）の回帰網（test/hide_net.sh から呼ぶ）。
set nomore
let s:work = $HIDE_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0
let g:gnosis_open_index_on_startup = 0
function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
let s:note = ['---', 'time: 2026-01-01 00:00:00', 'title: 隠す試験', '---', '', '# 隠す試験', '',
      \ 'ParentBranch:', '[親](p.md)', '', 'Context:', '[文脈](c.md)', '', '本文の一行目', '本文の二行目', '',
      \ 'ChildBranch:', '[子](k.md)', '', 'BackLink:', '[逆](b.md)']
call writefile(s:note, s:v . '/n.md')
call writefile(['---', 'title: 親', '---', '', '# 親'], s:v . '/p.md')

" 領域の検出
let s:r = gnosis#hide#regions(s:note)
call s:ok('YAML の範囲', index(map(copy(s:r), 'v:val.kind . ":" . v:val.from . "-" . v:val.to'), 'yaml:1-4') >= 0, string(s:r))
call s:ok('上の関係の範囲（Group 系と Context）', index(map(copy(s:r), 'v:val.kind . ":" . v:val.from . "-" . v:val.to'), 'top:8-12') >= 0, string(s:r))
call s:ok('下の関係の範囲（ChildBranch から最後まで）', index(map(copy(s:r), 'v:val.kind . ":" . v:val.from . "-" . v:val.to'), 'bottom:17-21') >= 0, string(s:r))

execute 'edit ' . s:v . '/n.md'
call s:ok('はじめは何も隠さない', foldclosed(1) == -1 && foldclosed(8) == -1 && foldclosed(17) == -1)
call gnosis#settings#set('hide.yaml', v:true)
call gnosis#hide#apply_all()
call s:ok('YAML を隠すと 1〜4 行目が畳まれる', foldclosed(1) == 1 && foldclosedend(1) == 4 && foldclosed(8) == -1, string([foldclosed(1), foldclosedend(1), foldclosed(8)]))
call s:ok('畳んだ行の目印', foldtextresult(1) =~# 'YAML (4)', foldtextresult(1))
call gnosis#settings#set('hide.top', v:true)
call gnosis#settings#set('hide.bottom', v:true)
call gnosis#hide#apply_all()
call s:ok('上の関係と下の関係も畳まれる', foldclosed(8) == 8 && foldclosedend(8) == 12 && foldclosed(17) == 17 && foldclosedend(17) == 21 && foldclosed(14) == -1, string([foldclosed(8), foldclosedend(8), foldclosed(17), foldclosed(14)]))
call s:ok('ファイルの中身は変わらない', readfile(s:v . '/n.md') ==# s:note && getline(1, '$') ==# s:note)

" 保存されて、読み直しても（再起動しても）続く
let s:saved = join(readfile(s:v . '/.gnosis/settings.json'), '')
call s:ok('設定ファイルに保存される', s:saved =~# '"hide"' && s:saved =~# '"yaml":\s*true' && s:saved =~# '"top":\s*true' && s:saved =~# '"bottom":\s*true', s:saved)
call gnosis#settings#activate(g:gnosis_root)
call s:ok('読み直しても続く', gnosis#hide#get() ==# {'yaml': 1, 'top': 1, 'bottom': 1, 'image': 0}, string(gnosis#hide#get()))
enew
execute 'edit ' . s:v . '/n.md'
call s:ok('開き直しても畳まれたまま', foldclosed(1) == 1 && foldclosed(8) == 8 && foldclosed(17) == 17)

" 別々に戻せる
call gnosis#settings#set('hide.top', v:false)
call gnosis#hide#apply_all()
call s:ok('上の関係だけ戻すと、YAML と下はそのまま', foldclosed(8) == -1 && foldclosed(1) == 1 && foldclosed(17) == 17)
call gnosis#settings#set('hide.yaml', v:false)
call gnosis#settings#set('hide.bottom', v:false)
call gnosis#hide#apply_all()
call s:ok('全部戻すと何も畳まれない（元の折りたたみ設定に戻る）', foldclosed(1) == -1 && foldclosed(17) == -1 && &foldmethod !=# 'expr', &foldmethod)

" \zz の窓
call feedkeys('\zz', 'xt')
call s:ok('\zz で窓が出る', len(popup_list()) == 1 && join(getbufline(winbufnr(popup_list()[0]), 1, '$'), "\n") =~# 'YAML', string(popup_list()))
call feedkeys(' ', 'xt')
call s:ok('Space で YAML が切り替わる', gnosis#hide#get().yaml == 1, string(gnosis#hide#get()))
call feedkeys('q', 'xt')
call s:ok('q で閉じる', len(popup_list()) == 0)

" 挿入モードでリンクの中身を見せて編集する（\zz の一番下の行）
call s:ok('はじめは挿入モードでもリンクの中身を隠す（concealcursor に i）', gnosis#link_edit_insert() == 0 && gnosis#conceal_modes() ==# 'nvi')
call gnosis#hide#window()
call feedkeys('jjjj', 'xt')
call feedkeys(' ', 'xt')
call s:ok('\zz の 5 番目（挿入について）で切り替わる', gnosis#link_edit_insert() == 1, string(gnosis#settings#current().linkEditInsert))
call s:ok('オンのとき concealcursor から i が外れる', gnosis#conceal_modes() ==# 'nv')
call s:ok('開いている窓にも反映される', &l:conceallevel == 0 || &l:concealcursor ==# 'nv', &l:concealcursor)
call s:ok('窓にその行が出る', join(getbufline(winbufnr(popup_list()[0]), 1, '$'), "\n") =~# '挿入モードで、カーソルの行のリンクの中身を見せて編集する', '')
call feedkeys(' ', 'xt')
call s:ok('もう一度で元に戻る', gnosis#link_edit_insert() == 0 && gnosis#conceal_modes() ==# 'nvi')
call feedkeys('q', 'xt')

" 番号キーで切り替え・並び（ノートの表示だけ見出し）・画像は「ノートの中の画像」でチェック＝隠す
call gnosis#hide#window()
let s:tx = join(getbufline(winbufnr(popup_list()[0]), 1, '$'), "\n")
call s:ok('見出しは「ノートの表示」だけ', s:tx =~# 'ノートの表示' && s:tx !~# '画像の表示' && s:tx !~# '挿入について', s:tx)
call s:ok('番号が 1〜6 で付く', s:tx =~# '1 \[.\] YAML' && s:tx =~# '4 \[.\] ノートの中の画像' && s:tx =~# '5 \[.\] 挿入モード' && s:tx =~# '6 gz で画像', s:tx)
call feedkeys('2', 'xt')
call s:ok('2 で「上の名前:系」が切り替わる', gnosis#hide#get().top == 1, string(gnosis#hide#get()))
call feedkeys('4', 'xt')
call s:ok('4 で画像を隠す（チェック＝隠す）', gnosis#hide#get().image == 1 && join(getbufline(winbufnr(popup_list()[0]), 1, '$'), "\n") =~# '4 \[x\] ノートの中の画像')
call feedkeys('4', 'xt')
call s:ok('もう一度 4 で戻る', gnosis#hide#get().image == 0)
call feedkeys('5', 'xt')
call s:ok('5 で挿入モードのリンク編集が切り替わる', gnosis#link_edit_insert() == 1)
call feedkeys('5', 'xt')
call s:ok('もう一度 5 で戻る', gnosis#link_edit_insert() == 0)
call feedkeys('q', 'xt')

call writefile(s:res, s:work . '/result.txt')
qa!
