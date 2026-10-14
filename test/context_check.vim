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
call s:mk('d.md', 'ノートD（旧形式）', ['# ノートD（旧形式）', '', '本文D。', '', '### Context', '[ノートX](x.md)', '[ノートY](y.md)', '', '### BackLink', '[ノートZ](z.md)'])
call s:mk('e.md', 'ノートE', ['# ノートE', '', '```', 'Context:', '[偽](fake.md)', '```', '', '本文E。'])
call s:mk('x.md', 'ノートX', ['# ノートX', '', 'Context:', '[ノートA](a.md)', '', '本文X。'])
call s:mk('y.md', 'ノートY', ['# ノートY'])
call s:mk('z.md', 'ノートZ', ['# ノートZ'])
call s:mk('f.md', 'ノートF', ['# ノートF', '', '本文F。'])
call writefile(['---', 'title: 深いノート', '---', '', '# 深いノート', '', '深い本文。'], s:v . '/sub/deep.md')

" ============================================================ 新規ノートのレイアウト（zn → Enter）
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
call s:ok('新規ノート: YAML・空行・H1', s:nl[0] ==# '---' && s:nl[3] ==# '---' && s:nl[4] ==# '' && s:h1 == 5, string(s:nl))
call s:ok('新規ノート: H1 の次は空行 1 行 → Context:', s:nl[s:h1 + 1] ==# '' && s:nl[s:h1 + 2] ==# 'Context:', string(s:nl))
call s:ok('新規ノート: Context: は Markdown 見出しではなく通常のテキスト行', s:nl[s:h1 + 2] !~# '^#' && s:nl[s:h1 + 2] ==# 'Context:')
call s:ok('新規ノート: Context の直下に元ノートへのリンク', s:nl[s:h1 + 3] ==# '[ノートA](a.md)')
call s:ok('新規ノート: リンクの後ろに空行 3 行（真ん中がカーソル）', s:nl[s:h1 + 4 : s:h1 + 6] ==# ['', '', ''], string(s:nl))
call s:ok('新規ノート: ### Context は無い・ParentBranch は Context と別に残る', index(s:nl, '### Context') < 0 && index(s:nl, '### ParentBranch') == s:h1 + 7 && s:nl[s:h1 + 8] ==# '[ノートA](a.md)')
call s:ok('新規ノート: カーソルは Context リンクの 2 行下（空行の真ん中）', s:cur_line == s:h1 + 1 + 4 + 2 - 0 + 0 || s:cur_line == s:h1 + 7 - 1, 'cursor=' . s:cur_line . ' h1=' . s:h1)
call s:ok('新規ノート: A 側は本文リンク + ChildBranch', index(s:file('a.md'), '[' . fnamemodify(s:n, ':r') . '](' . s:n . ')') >= 0 && index(s:file('a.md'), '### ChildBranch') >= 0)
call s:ok('新規ノート: Context が無い元ノートに Context を作らない', empty(gnosis#context#find_block(s:file('a.md'))))

" ============================================================ c: 既存リンク群の最後へ
execute 'edit ' . fnameescape(s:v . '/b.md')
let s:b_body = filter(copy(s:file('b.md')), 'v:val ==# "本文B。"')
call s:za('[ノートC](c.md)', ['c', 'o'])
call s:ok('c: 新しいリンクは Context の最後', s:file('b.md')[s:h1 : ] != [] && gnosis#context#links(s:file('b.md')) ==# ['[ノートA](a.md)', '[ノートC](c.md)'], string(s:file('b.md')))
call s:ok('c: Context と本文の間に空行・本文はそのまま', index(s:file('b.md'), '[ノートC](c.md)') + 2 == index(s:file('b.md'), '本文B。') && s:file('b.md')[-1] ==# '本文B。')
let s:snap = s:file('b.md')
call s:za('[ノートC](c.md)', ['c', 'o'])
call s:ok('c: 同じ Context リンクは重複しない', s:file('b.md') ==# s:snap)
call s:za('[別名](c.md)', ['c', 'o'])
call s:ok('c: 表示名が違っても同じノートは重複しない', s:file('b.md') ==# s:snap)
call s:ok('c: バッファも更新されている', !&modified && getline(1, '$') ==# s:snap)

" ============================================================ Context が無いノート・コードブロック内の Context:
execute 'edit ' . fnameescape(s:v . '/e.md')
call s:za('[ノートF](f.md)', ['c', 'o'])
let s:el = s:file('e.md')
call s:ok('Context が無いノートでは H1 の直後に作る', s:el[5] ==# '# ノートE' && s:el[6] ==# '' && s:el[7] ==# 'Context:' && s:el[8] ==# '[ノートF](f.md)' && s:el[9] ==# '', string(s:el))
call s:ok('コードブロック内の Context: は Context として扱わない（そのまま残る）', s:el[10 : 14] ==# ['```', 'Context:', '[偽](fake.md)', '```', ''] && s:el[-1] ==# '本文E。', string(s:el))
call s:ok('コードブロック内のリンクは Context に数えない', gnosis#context#links(s:el) ==# ['[ノートF](f.md)'])

" ============================================================ 旧 ### Context からの移行（c で足したノートだけ）
execute 'edit ' . fnameescape(s:v . '/d.md')
call s:za('[ノートF](f.md)', ['c', 'o'])
let s:dl = s:file('d.md')
call s:ok('旧形式: リンクを失わず新形式へ（X, Y, F の順）', gnosis#context#links(s:dl) ==# ['[ノートX](x.md)', '[ノートY](y.md)', '[ノートF](f.md)'] && index(s:dl, '### Context') < 0, string(s:dl))
call s:ok('旧形式: 本文と BackLink は変わらない', index(s:dl, '本文D。') >= 0 && index(s:dl, '### BackLink') >= 0 && s:dl[-1] ==# '[ノートZ](z.md)')
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
call s:ok('ParentBranch と Context に同じノート A を登録できる', gnosis#context#links(s:file('x.md')) ==# ['[ノートA](a.md)'] && index(s:file('x.md'), '### ParentBranch') >= 0 && count(s:file('x.md'), '[ノートA](a.md)') == 2, string(s:file('x.md')))

" ============================================================ w モード
call s:mk('w1.md', 'ローズマリー', ['# ローズマリー', '', '本文。'])
call s:mk('w2.md', '相手の2', ['# 相手の2', '', 'Context:', '[ノートC](c.md)', '', '相手の本文。'])
call s:mk('w3.md', '相手の3', ['# 相手の3', '', '三つ目。'])
execute 'edit ' . fnameescape(s:v . '/w1.md')
let s:w2 = s:file('w2.md')
call s:za('[相手の2](w2.md)', ['c', 'w'])
call s:ok('w: 元のノート A の Context に B が入る（c の関係は維持）', gnosis#context#links(s:file('w1.md')) ==# ['[相手の2](w2.md)'], string(s:file('w1.md')))
call s:ok('w: 元のノートのファイル名だけがヤンクされる（タイトル・パス・リンク記法なし）', getreg('"') ==# 'w1.md' && getreg('0') ==# 'w1.md', string([getreg('"'), getreg('0')]))
call s:ok('w: ヤンクは文字単位・改行なし', getregtype('"') ==# 'v' && getreg('"') !~# "\n")
call s:ok('w: リンク先 B を通常の Vim で開く', fnamemodify(expand('%:p'), ':t') ==# 'w2.md')
call s:ok('w: リンク先には自動でリンクを書かない（B は変わらない・バッファも未変更）', s:file('w2.md') ==# s:w2 && !&modified && getline(1, '$') ==# s:w2)
" 通常の p で貼り付けられる・保存・Undo
execute 'normal! G'
execute 'normal! p'
call s:ok('w: 通常の p で貼り付けられる', getline('.') =~# 'w1\.md' && &modified)
silent write
call s:ok('w: 通常の保存ができる', !&modified && join(s:file('w2.md'), "\n") =~# 'w1\.md')
silent undo
call s:ok('w: Undo ができる', join(getline(1, '$'), "\n") !~# 'w1\.md')
silent edit!
" サブディレクトリのノートでもファイル名だけ
execute 'edit ' . fnameescape(s:v . '/sub/deep.md')
call s:za('[相手の3](../w3.md)', ['c', 'w'])
call s:ok('w: サブディレクトリのノートでもファイル名だけ（deep.md）', getreg('"') ==# 'deep.md' && fnamemodify(expand('%:p'), ':t') ==# 'w3.md', getreg('"') . ' / ' . expand('%:p'))
" Esc は何もしない
execute 'edit ' . fnameescape(s:v . '/w1.md')
let s:w1 = s:file('w1.md')
call s:za('[相手の3](w3.md)', ['c', "\x1b"])
call s:ok('w の画面で Esc: 何も変えない・移動しない', s:file('w1.md') ==# s:w1 && fnamemodify(expand('%:p'), ':t') ==# 'w1.md')
" 既存の Enter / t / o は変わらない
call s:mk('w4.md', '相手の4', ['# 相手の4', '', '四つ目。'])
call s:za('[相手の4](w4.md)', ['c', "\r"])
call s:ok('Enter は従来どおり（B の本文の最後に A へのリンク）', index(s:file('w4.md'), '[ローズマリー](w1.md)') >= 0 && fnamemodify(expand('%:p'), ':t') ==# 'w1.md')
call s:mk('w5.md', '相手の5', ['# 相手の5', '', '五つ目。'])
let s:w5 = s:file('w5.md')
call s:za('[相手の5](w5.md)', ['c', 'o'])
call s:ok('o は従来どおり（B には書かない・開かない）', s:file('w5.md') ==# s:w5 && fnamemodify(expand('%:p'), ':t') ==# 'w1.md')
" 複数リンク: 1 件ずつ（最初を開き、残りは :GnosisWNext）
call s:mk('m1.md', '複数の元', ['# 複数の元', '', '本文。'])
call s:mk('m2.md', 'ターゲット2', ['# ターゲット2', '', 'ふたつめ。'])
call s:mk('m3.md', 'ターゲット3', ['# ターゲット3', '', 'みっつめ。'])
execute 'edit ' . fnameescape(s:v . '/m1.md')
call s:za("[ターゲット2](m2.md)\n[ターゲット3](m3.md)", ['c', 'w', 'w'])
call s:ok('w 複数: 両方が A の Context に入る', gnosis#context#links(s:file('m1.md')) ==# ['[ターゲット2](m2.md)', '[ターゲット3](m3.md)'], string(s:file('m1.md')))
call s:ok('w 複数: 最初のリンク先だけ開き、残りを知らせる', fnamemodify(expand('%:p'), ':t') ==# 'm2.md' && s:msgs() =~# 'GnosisWNext')
let @" = 'x'
GnosisWNext
call s:ok('w 複数: :GnosisWNext で次を開き、元のファイル名を再びヤンク', fnamemodify(expand('%:p'), ':t') ==# 'm3.md' && getreg('"') ==# 'm1.md')
" \l（gnosis#insert_links_pick）にも w がある
execute 'edit ' . fnameescape(s:v . '/f.md')
let g:gnosis_test_keys = ['c', 'w']
call gnosis#insert_links_pick(['[相手の3](w3.md)'], getpos('.'))
call s:ok('\l からの c → w: Context に入り、f.md をヤンクして相手を開く', gnosis#context#links(s:file('f.md')) ==# ['[相手の3](w3.md)'] && getreg('"') ==# 'f.md' && fnamemodify(expand('%:p'), ':t') ==# 'w3.md')
" zn → c → w（新ノートには自動で書かず、元のノートのファイル名をヤンク）
execute 'edit ' . fnameescape(s:v . '/f.md')
let s:before = s:files()
let g:gnosis_test_keys = ['c', 'w']
sleep 1100m
call gnosis#v2_new_plain()
stopinsert
let s:nw = s:newest_except(s:before)
call s:ok('zn → c → w: 新ノートに元ノートへのリンクを自動で書かない・ファイル名をヤンク', !empty(s:nw) && join(s:file(s:nw), "\n") !~# '\[ノートF\]\(f\.md\)\n\n\n' && getreg('"') ==# 'f.md', string(s:file(s:nw)))

" ============================================================ 未保存データ
execute 'edit ' . fnameescape(s:v . '/m1.md')
call append(line('$'), 'まだ保存していない行')
call s:za('[ターゲット2](m2.md)', ['c', 'w'])
call s:ok('w: 未保存の行は失われない（保存されて残る）', join(s:file('m1.md'), "\n") =~# 'まだ保存していない行')

call writefile(s:res, s:work . '/result.txt')
qa!
