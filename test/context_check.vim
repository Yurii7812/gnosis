" Context ブロック（本文冒頭の `Context:`）と w モードの回帰網（test/context_net.sh から呼ぶ）。
" 結果は $CONTEXT_WORK/result.txt に「OK 名前」「NG 名前: 詳細」で書く。
set nomore
let s:work = $CONTEXT_WORK
let s:v = s:work . '/vault'
let s:res = []
let g:gnosis_root = s:v . '/'
let g:gnosis_autosync = 0
let g:gnosis_skip_interactive_mount = 1
let g:gnosis_diary_auto = 0

function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction
function! s:mk(name, title, body_lines) abort
  call writefile(['---', 'time: 2026-01-01 00:00:00', 'title: ' . a:title, '---', ''] + a:body_lines, s:v . '/' . a:name)
endfunction
function! s:file(name) abort
  return readfile(s:v . '/' . a:name)
endfunction
function! s:files() abort
  return map(glob(s:v . '/*.md', 1, 1), 'fnamemodify(v:val, ":t")')
endfunction
function! s:newest_except(before) abort
  return get(filter(s:files(), 'index(a:before, v:val) < 0'), 0, '')
endfunction
function! s:ctx(name) abort
  return gnosis#context#links(s:file(name))
endfunction
function! s:links(name) abort
  return map(gnosis#context#links(s:file(a:name)), 'v:val')
endfunction
function! s:msgs() abort
  redir => l:m
  silent messages
  redir END
  return l:m
endfunction
function! s:za(link, keys) abort
  let @" = a:link
  let @0 = a:link
  let g:gnosis_test_keys = copy(a:keys)
  call gnosis#add_clipboard_before_up_note()
endfunction

call mkdir(s:v . '/sub', 'p')
call mkdir(s:v . '/.gnosis', 'p')
call writefile(['---', 'title: Index', 'attribute: group', '---', '', '# Index'], s:v . '/index.md')
call s:mk('a.md', 'ノートA', ['# ノートA', '', '本文A。'])
call s:mk('b.md', 'ノートB', ['# ノートB', '', 'Context:', '[ノートA](a.md)', '', '本文B。'])
call s:mk('c.md', 'ノートC', ['# ノートC', '', '本文C。'])
call s:mk('d.md', 'ノートD（旧形式）', ['# ノートD（旧形式）', '', '本文D。', '', '### Context', '[ノートX](x.md)', '[ノートY](y.md)', '', 'BackLink:', '[ノートZ](z.md)'])
call s:mk('e.md', 'ノートE', ['# ノートE', '', '```', 'Context:', '[偽](fake.md)', '```', '', '本文E。'])
call s:mk('x.md', 'ノートX', ['# ノートX', '', 'Context:', '[ノートA](a.md)', '', '本文X。'])
call s:mk('y.md', 'ノートY', ['# ノートY'])
call s:mk('z.md', 'ノートZ', ['# ノートZ'])
call s:mk('f.md', 'ノートF', ['# ノートF', '', '本文F。'])
call writefile(['---', 'title: 深いノート', '---', '', '# 深いノート', '', '深い本文。'], s:v . '/sub/deep.md')

" ============================================================ 新規ノートのレイアウト（zn → Enter）
" zn の Enter は Context を足さない（c だけが Context を足す）。自動 Branch は残る。
execute 'edit ' . fnameescape(s:v . '/a.md')
let s:before = s:files()
let g:gnosis_test_keys = ["\r"]
sleep 1100m
call gnosis#v2_new_plain()
let s:cur_line = line('.')
stopinsert
let s:n = s:newest_except(s:before)
let s:nl = s:file(s:n)
let s:h1 = index(s:nl, '# ' . fnamemodify(s:n, ':r'))
call s:ok('新規ノート: YAML（time だけ）・空行・H1', s:nl[0] ==# '---' && s:nl[2] ==# '---' && s:nl[3] ==# '' && s:h1 == 4, string(s:nl))
call s:ok('新規ノート（zn Enter）: H1 の次は空行 1 行 → ParentBranch:（Context: は無い）', s:nl[s:h1 + 1] ==# '' && s:nl[s:h1 + 2] ==# 'ParentBranch:'
      \ && s:nl[s:h1 + 3] ==# '[ノートA](a.md)' && empty(gnosis#context#find_block(s:nl)) && index(s:nl, 'Context:') < 0, string(s:nl))
call s:ok('新規ノート: ブロックの後ろに空行 3 行（真ん中がカーソル）', s:nl[s:h1 + 4 : s:h1 + 6] ==# ['', '', ''], string(s:nl))
call s:ok('新規ノート: カーソルは空行の真ん中', s:cur_line == s:h1 + 6, 'cursor=' . s:cur_line . ' h1=' . s:h1)
call s:ok('新規ノート: A 側は本文リンク + ChildBranch', index(s:file('a.md'), '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')') >= 0 && index(s:file('a.md'), 'ChildBranch:') >= 0)
call s:ok('新規ノート: 元ノートに Context を作らない', empty(gnosis#context#find_block(s:file('a.md'))))

" ============================================================ c（\l / za）: B の Context: に A。既存リンク群の最後へ
" A = 今のノート（c.md）、B = 選んだノート（b.md。Context に [ノートA] がある）
execute 'edit ' . fnameescape(s:v . '/c.md')
call s:za('[ノートB](b.md)', ['c', "\r"])
call s:ok('c: B の Context: の最後に A が入る（A の Context に B ではない）', gnosis#context#links(s:file('b.md')) ==# ['[ノートA](a.md)', '[ノートC](c.md)'] && empty(gnosis#context#find_block(s:file('c.md'))), string(s:file('b.md')))
call s:ok('c: B の Context と本文の間に空行・本文はそのまま', index(s:file('b.md'), '[ノートC](c.md)') + 2 == index(s:file('b.md'), '本文B。') && s:file('b.md')[-1] ==# '本文B。')
call s:ok('c → Enter: A の本文の最後に B へのリンク', s:file('c.md')[-1] ==# '[ノートB](b.md)', string(s:file('c.md')))
let s:snap = s:file('b.md')
let s:csnap = s:file('c.md')
call s:za('[ノートB](b.md)', ['c', "\r"])
call s:ok('c: 同じ Context リンクは重複しない（A の本文のリンクも重複しない）', s:file('b.md') ==# s:snap && s:file('c.md') ==# s:csnap)
call s:za('[別名](b.md)', ['c', 'w'])
call s:ok('c: 表示名が違っても同じノートは重複しない', s:file('b.md') ==# s:snap)

" ============================================================ Context が無いノート・コードブロック内の Context:
execute 'edit ' . fnameescape(s:v . '/f.md')
call s:za('[ノートE](e.md)', ['c', 'w'])
let s:el = s:file('e.md')
" 親（Branch）が無かったので、最初の Context の F が親にもなる（ParentBranch: が Context: の上）
call s:ok('Context が無いノートでは H1 の直後に作る（親が無ければ ParentBranch: も）', s:el[5] ==# '# ノートE' && s:el[6] ==# '' && s:el[7] ==# 'ParentBranch:' && s:el[8] ==# '[ノートF](f.md)'
      \ && s:el[9] ==# 'Context:' && s:el[10] ==# '[ノートF](f.md)' && s:el[11] ==# '', string(s:el))
call s:ok('コードブロック内の Context: は Context として扱わない（そのまま残る）', s:el[12 : 16] ==# ['```', 'Context:', '[偽](fake.md)', '```', ''] && s:el[-1] ==# '本文E。', string(s:el))
call s:ok('コードブロック内のリンクは Context に数えない', gnosis#context#links(s:el) ==# ['[ノートF](f.md)'])

" ============================================================ 旧 ### Context からの移行（c で足したノートだけ）
execute 'edit ' . fnameescape(s:v . '/f.md')
call s:za('[ノートD](d.md)', ['c', 'w'])
let s:dl = s:file('d.md')
call s:ok('旧形式: リンクを失わず新形式へ（X, Y, F の順）', gnosis#context#links(s:dl) ==# ['[ノートX](x.md)', '[ノートY](y.md)', '[ノートF](f.md)'] && index(s:dl, '### Context') < 0, string(s:dl))
call s:ok('旧形式: 本文と BackLink は変わらない', index(s:dl, '本文D。') >= 0 && index(s:dl, 'BackLink:') >= 0 && s:dl[-1] ==# '[ノートZ](z.md)')
" 明示的な移行コマンド（今のノート）
call s:mk('g.md', 'ノートG（旧）', ['# ノートG（旧）', '', '本文G。', '', '### Context', '[ノートF](f.md)'])
execute 'edit ' . fnameescape(s:v . '/g.md')
call gnosis#context#migrate_command('', 0)
call s:ok(':GnosisContextMigrate: 今のノートを新形式へ（リンクは維持）', gnosis#context#links(getline(1, '$')) ==# ['[ノートF](f.md)'] && index(getline(1, '$'), '### Context') < 0 && getline(1, '$')[-1] ==# '' || getline(1, '$')[-1] ==# '本文G。')
" 開いただけでは移行されない（ファイルは変わらない）
call s:mk('h.md', 'ノートH（旧）', ['# ノートH（旧）', '', '本文H。', '', '### Context', '[ノートF](f.md)'])
let s:h_before = s:file('h.md')
execute 'edit ' . fnameescape(s:v . '/h.md')
execute 'edit ' . fnameescape(s:v . '/f.md')
call s:ok('旧形式のノートは開いただけでは書き換えない', s:file('h.md') ==# s:h_before)

" ============================================================ ParentBranch と Context に同じノート
execute 'edit ' . fnameescape(s:v . '/a.md')
call s:za('[ノートX](x.md)', ['b'])
call s:ok('ParentBranch と Context に同じノート A を登録できる', gnosis#context#links(s:file('x.md')) ==# ['[ノートA](a.md)'] && index(s:file('x.md'), 'ParentBranch:') >= 0 && count(s:file('x.md'), '[ノートA](a.md)') == 2, string(s:file('x.md')))

" ============================================================ c の置き場所: w / Enter / t / h
call s:mk('w1.md', 'ローズマリー', ['# ローズマリー', '', '本文。', '', '## 育て方', '', '水やり。', '', '## 使い方', '', '料理。'])
call s:mk('w2.md', '相手の2', ['# 相手の2', '', 'Context:', '[ノートC](c.md)', '', '相手の本文。'])
call s:mk('w3.md', '相手の3', ['# 相手の3', '', '三つ目。'])
execute 'edit ' . fnameescape(s:v . '/w1.md')
let s:w1 = s:file('w1.md')
call setreg('"', 'x')
call s:za('[相手の2](w2.md)', ['c', 'w'])
call s:ok('w: B の Context: に A が入る', gnosis#context#links(s:file('w2.md')) ==# ['[ノートC](c.md)', '[ローズマリー](w1.md)'], string(s:file('w2.md')))
call s:ok('w: B を yn と同じ方法でヤンク（B のファイル名だけ）', getreg('"') ==# 'w2.md', string(getreg('"')))
call s:ok('w: A（今のノート）を開いたまま', fnamemodify(expand('%:p'), ':t') ==# 'w1.md')
call s:ok('w: A に B へのリンクは自動で置かない', s:file('w1.md') ==# s:w1 && index(getline(1, '$'), '[相手の2](w2.md)') < 0)
" ヤンクしたものは通常の p で貼れる（\p などは自動で実行しない）
execute 'normal! G'
execute 'normal! p'
call s:ok('w: 通常の p で B のファイル名を貼り付けられる', getline('.') =~# 'w2\.md' && &modified)
silent undo
silent! write
" サブディレクトリのノートからでもファイル名だけ
execute 'edit ' . fnameescape(s:v . '/sub/deep.md')
call s:za('[相手の3](../w3.md)', ['c', 'w'])
call s:ok('w: サブディレクトリのノートからでも B のファイル名だけ（w3.md）・A のまま', getreg('"') ==# 'w3.md' && fnamemodify(expand('%:p'), ':t') ==# 'deep.md', getreg('"') . ' / ' . expand('%:p'))
call s:ok('w: サブディレクトリの A も B の Context に入る', match(s:file('w3.md'), '^\[深いノート\](\%(\./\)\=sub/deep\.md)$') >= 0, string(s:file('w3.md')))
" Esc は何もしない
execute 'edit ' . fnameescape(s:v . '/w1.md')
let s:w1 = s:file('w1.md')
call s:mk('w4.md', '相手の4', ['# 相手の4', '', '四つ目。'])
let s:w4 = s:file('w4.md')
call s:za('[相手の4](w4.md)', ['c', "\x1b"])
call s:ok('c の置き場所で Esc: A も B も変えない・移動しない', s:file('w1.md') ==# s:w1 && s:file('w4.md') ==# s:w4 && fnamemodify(expand('%:p'), ':t') ==# 'w1.md')
" Enter: A の本文の最後に B
call s:za('[相手の4](w4.md)', ['c', "\r"])
call s:ok('c → Enter: B の Context に A・A の本文の最後に B・A のまま', index(s:file('w4.md'), '[ローズマリー](w1.md)') >= 0 && s:file('w1.md')[-1] ==# '[相手の4](w4.md)' && fnamemodify(expand('%:p'), ':t') ==# 'w1.md', string(s:file('w1.md')))
call s:ok('c → Enter: B の本文には A を置かない（A は B の Context と、親が無かったので ParentBranch だけ）', count(s:file('w4.md'), '[ローズマリー](w1.md)') == 2
      \ && index(s:file('w4.md'), 'ParentBranch:') >= 0 && gnosis#context#links(s:file('w4.md')) ==# ['[ローズマリー](w1.md)'], string(s:file('w4.md')))
" t: A の見出しの節の最後に B
call s:mk('w5.md', '相手の5', ['# 相手の5', '', '五つ目。'])
let g:gnosis_test_heading = '育て方'
call s:za('[相手の5](w5.md)', ['c', 't'])
unlet g:gnosis_test_heading
let s:wl = s:file('w1.md')
call s:ok('c → t: A の「育て方」の節の最後（「使い方」の前）に B', index(s:wl, '[相手の5](w5.md)') > index(s:wl, '水やり。') && index(s:wl, '[相手の5](w5.md)') < index(s:wl, '## 使い方') && index(s:file('w5.md'), '[ローズマリー](w1.md)') >= 0, string(s:wl))
" h: A のカーソル行の直下に B
call s:mk('w6.md', '相手の6', ['# 相手の6', '', '六つ目。'])
call cursor(index(getline(1, '$'), '料理。') + 1, 1)
call s:za('[相手の6](w6.md)', ['c', 'h'])
let s:wl = s:file('w1.md')
call s:ok('c → h: A のカーソル行の直下に B', s:wl[index(s:wl, '料理。') + 1] ==# '[相手の6](w6.md)' && index(s:file('w6.md'), '[ローズマリー](w1.md)') >= 0, string(s:wl))
" 複数リンク: 全部の B の Context に A。w ならファイル名を（yn と同じ形で）まとめてヤンク
call s:mk('m1.md', '複数の元', ['# 複数の元', '', '本文。'])
call s:mk('m2.md', 'ターゲット2', ['# ターゲット2', '', 'ふたつめ。'])
call s:mk('m3.md', 'ターゲット3', ['# ターゲット3', '', 'みっつめ。'])
execute 'edit ' . fnameescape(s:v . '/m1.md')
call s:za("[ターゲット2](m2.md)\n[ターゲット3](m3.md)", ['c', 'w'])
call s:ok('c 複数: 両方の B の Context に A', index(s:file('m2.md'), '[複数の元](m1.md)') >= 0 && index(s:file('m3.md'), '[複数の元](m1.md)') >= 0)
call s:ok('c 複数 → w: A のまま・A の本文には自動で置かない（親になったので ChildBranch: だけ）', fnamemodify(expand('%:p'), ':t') ==# 'm1.md' && s:file('m1.md')[: 7] ==# ['---', 'time: 2026-01-01 00:00:00', 'title: 複数の元', '---', '', '# 複数の元', '', '本文。']
      \ && index(s:file('m1.md'), 'ChildBranch:') >= 0 && index(s:file('m1.md'), '[ターゲット2](m2.md)') > index(s:file('m1.md'), 'ChildBranch:'), string(s:file('m1.md')))
" \l（gnosis#insert_links_pick）からも同じ
execute 'edit ' . fnameescape(s:v . '/f.md')
let g:gnosis_test_keys = ['c', 'w']
call gnosis#insert_links_pick(['[相手の3](w3.md)'], getpos('.'))
call s:ok('\l からの c → w: B の Context に A・B をヤンク・A のまま', index(s:file('w3.md'), '[ノートF](f.md)') >= 0 && getreg('"') ==# 'w3.md' && fnamemodify(expand('%:p'), ':t') ==# 'f.md')
" zn → c → w（新ノート B の Context に A・B をヤンク・A を開いたまま・A にリンクを置かない）
execute 'edit ' . fnameescape(s:v . '/f.md')
let s:fbody = filter(s:file('f.md'), 'v:val =~# "^\\[\\d\\+\\]("')
let s:before = s:files()
let g:gnosis_test_keys = ['c', 'w']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:nw = s:newest_except(s:before)
call s:ok('zn → c → w: 新ノート B の Context に A', !empty(s:nw) && gnosis#context#links(s:file(s:nw)) ==# ['[ノートF](f.md)'], string(s:file(s:nw)))
call s:ok('zn → c → w: B をヤンクし、A を開いたまま', getreg('"') ==# s:nw && fnamemodify(expand('%:p'), ':t') ==# 'f.md', getreg('"') . ' / ' . expand('%:p'))
let s:fl = s:file('f.md')
let s:fcb = index(s:fl, 'ChildBranch:')
call s:ok('zn → c → w: A の本文に B へのリンクを自動で置かない（自動 Branch の ChildBranch: だけ）', count(s:fl, '[' . fnamemodify(s:nw, ':r') . '](' . s:nw . ')') == 1 && s:fcb >= 0 && index(s:fl, '[' . fnamemodify(s:nw, ':r') . '](' . s:nw . ')') > s:fcb, string(s:fl))

" ============================================================ 未保存データ
execute 'edit ' . fnameescape(s:v . '/m1.md')
call append(line('$'), 'まだ保存していない行')
call s:za('[ターゲット2](m2.md)', ['c', 'w'])
call s:ok('c: 今のノートの未保存の行は失われない（保存されて残る）', join(s:file('m1.md'), "\n") =~# 'まだ保存していない行')
" B が開いていて未保存なら、何も変えない
execute 'edit ' . fnameescape(s:v . '/m3.md')
call append(line('$'), 'B の未保存の行')
let s:m3 = s:file('m3.md')
execute 'noautocmd hide edit ' . fnameescape(s:v . '/m1.md')
let s:m1 = s:file('m1.md')
call s:za('[ターゲット3](m3.md)', ['c', "\r"])
call s:ok('c: B に未保存の変更があれば、A も B も変えない', s:file('m3.md') ==# s:m3 && s:file('m1.md') ==# s:m1)

call writefile(s:res, s:work . '/result.txt')
qa!
