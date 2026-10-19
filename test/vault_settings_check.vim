" vault の登録簿・vault ごとの設定・旧環境からの移行・テーマ指定の解析・ガイドの言語の回帰網。
" test/vault_settings_net.sh から呼ぶ（HOME と GNOSIS_HOME は一時フォルダ）。
set nomore
let s:w = $VS_WORK
let s:res = []
function! s:ok(name, cond, ...) abort
  call add(s:res, (a:cond ? 'OK ' : 'NG ') . a:name . (a:cond || !a:0 ? '' : ': ' . a:1))
endfunction

" ---- 旧環境からの移行: 登録簿が無いとき、旧 root.txt（A/note）を 1 回だけ取り込む
let s:legacy_a = s:w . '/旧 vault'
call mkdir(s:legacy_a . '/note', 'p')
call mkdir(s:legacy_a . '/.crypt', 'p')
call writefile(['---', 'title: Index', '---'], s:legacy_a . '/note/index.md')
call mkdir($HOME . '/.vim/simple_yurii_note', 'p')
call writefile([s:legacy_a . '/note/'], $HOME . '/.vim/simple_yurii_note/root.txt')
let s:reg = gnosis#vault#load()
call s:ok('移行: 旧 root.txt の vault を登録', len(s:reg.vaults) == 1 && s:reg.vaults[0].path ==# s:legacy_a, string(s:reg))
call s:ok('移行: 最後の vault になる', gnosis#vault#last() ==# s:legacy_a)
call s:ok('移行: ノートの root は A/note', gnosis#vault#note_root(s:legacy_a) ==# s:legacy_a . '/note')
call s:ok('移行: root.txt は消さない', filereadable($HOME . '/.vim/simple_yurii_note/root.txt'))
call s:ok('移行: 登録簿は Gnosis ホームに書く', filereadable($GNOSIS_HOME . '/vaults.json'))
call s:ok('移行: of_root(A/note) は A', gnosis#vault#of_root(s:legacy_a . '/note') ==# s:legacy_a)

" ---- 作成・登録・選択・一覧から外す
let s:new = s:w . '/新しい vault'
let s:made = gnosis#vault#create(s:new)
call s:ok('作成: フォルダと Index・ガイド', isdirectory(s:new) && filereadable(s:new . '/index.md') && filereadable(s:new . '/gnosis-guide.md'))
call s:ok('作成: 設定ファイル', filereadable(s:new . '/.gnosis/settings.json'))
call s:ok('作成: 一覧に入る', !empty(gnosis#vault#find(s:new)))
let s:exist = s:w . '/既存 フォルダ'
call mkdir(s:exist, 'p')
call writefile(['memo'], s:exist . '/memo.md')
call gnosis#vault#add(s:exist)
call s:ok('登録: 既存フォルダ', !empty(gnosis#vault#find(s:exist)))
let s:threw = 0
try
  call gnosis#vault#add(s:w . '/無いフォルダ')
catch /^gnosis-vault:/
  let s:threw = 1
endtry
call s:ok('登録: 無いフォルダは登録しない・作らない', s:threw && !isdirectory(s:w . '/無いフォルダ'))
let s:threw = 0
try
  call gnosis#vault#create(s:exist)
catch /^gnosis-vault:/
  let s:threw = 1
endtry
call s:ok('作成: ノートのあるフォルダには作らない（登録を使う）', s:threw)
call gnosis#vault#select(s:exist)
call s:ok('選択: 最後の vault を覚える', gnosis#vault#last() ==# s:exist)
call gnosis#vault#remove(s:exist)
call s:ok('一覧から外す: 一覧から消える', empty(gnosis#vault#find(s:exist)))
call s:ok('一覧から外す: フォルダとノートは残る', filereadable(s:exist . '/memo.md'))
call s:ok('一覧から外す: 最後の vault だったら空に', gnosis#vault#last() ==# '')

" ---- vault ごとの設定
call gnosis#settings#save(s:new, extend(gnosis#settings#defaults(), {'language': 'en', 'fontSize': 21, 'appearance': 'dark'}))
call gnosis#settings#save(s:legacy_a, extend(gnosis#settings#defaults(), {'language': 'ja', 'fontSize': 13}))
call s:ok('設定: vault ごとに別', gnosis#settings#load(s:new).fontSize == 21 && gnosis#settings#load(s:legacy_a).fontSize == 13)
call s:ok('設定: vault の中（.gnosis/settings.json）', filereadable(s:legacy_a . '/.gnosis/settings.json'))
call gnosis#settings#activate(s:new)
call s:ok('切り替え: 言語', gnosis#i18n#lang() ==# 'en')
call s:ok('切り替え: テーマ（ダーク）', &background ==# 'dark' && get(g:, 'gnosis_palette', {}).bg ==# '#1E1E1E')
call gnosis#settings#activate(s:legacy_a)
call s:ok('切り替え: 戻すと日本語・既定は標準（青系）', gnosis#i18n#lang() ==# 'ja' && &background ==# 'dark' && get(g:, 'gnosis_palette', {}).bg ==# '#11253D')
call gnosis#settings#save(s:legacy_a, extend(gnosis#settings#load(s:legacy_a), {'appearance': 'light'}))
call gnosis#settings#activate(s:legacy_a)
call s:ok('切り替え: ライト指定は白背景に黒い文字', &background ==# 'light' && get(g:, 'gnosis_palette', {}).bg ==# '#FFFFFF' && get(g:, 'gnosis_palette', {}).fg ==# '#1A1A1A')
call gnosis#settings#save(s:legacy_a, extend(gnosis#settings#load(s:legacy_a), {'appearance': 'dark'}))
call gnosis#settings#activate(s:legacy_a)
call s:ok('切り替え: ダーク指定は灰色の背景', &background ==# 'dark' && get(g:, 'gnosis_palette', {}).bg ==# '#1E1E1E')
call s:ok('検証: 見た目の値が不正なら標準', gnosis#settings#validate(extend(gnosis#settings#defaults(), {'appearance': 'x'})).appearance ==# 'standard')
call gnosis#settings#save(s:legacy_a, extend(gnosis#settings#load(s:legacy_a), {'appearance': 'standard'}))
call gnosis#settings#activate(s:legacy_a)
call writefile(['{"language": "xx", "fontSize": 999, "window": {"maximized": "yes"}, "theme": 3}'], s:w . '/bad.json')
call mkdir(s:w . '/bad/.gnosis', 'p')
call rename(s:w . '/bad.json', s:w . '/bad/.gnosis/settings.json')
let s:bad = gnosis#settings#load(s:w . '/bad')
call s:ok('設定: 壊れた値は既定値・範囲内に直す', s:bad.fontSize == 48 && s:bad.language =~# '^\(ja\|en\)$' && s:bad.theme.kind ==# 'builtin', string(s:bad))
call writefile(['{ 壊れた JSON'], s:w . '/bad/.gnosis/settings.json')
call s:ok('設定: 読めない JSON は既定値', gnosis#settings#load(s:w . '/bad').fontSize == 16)

" ---- カスタム配色・追加テーマの失敗は標準に戻る
let s:s = gnosis#settings#defaults()
let s:s.customThemes = {'mine': {'base': 'light', 'bg': '#fafafa', 'fg': '#111111', 'link': '#aa0000', 'heading': '#00aa00', 'selection': '#ccccff', 'cursorline': '#eeeeee'}}
let s:s.theme = {'kind': 'custom', 'name': 'mine'}
call gnosis#theme#apply(s:s)
call s:ok('カスタム配色: 6 色が反映', g:gnosis_palette.bg ==# '#fafafa' && g:gnosis_palette.link ==# '#aa0000' && synIDattr(synIDtrans(hlID('Normal')), 'bg#', 'gui') ==# '#fafafa')
let s:s.theme = {'kind': 'plugin', 'repo': 'nobody/none', 'colorscheme': 'does-not-exist'}
silent call gnosis#theme#apply(s:s)
call s:ok('追加テーマが読めない: 標準テーマに戻る', g:colors_name ==# 'gnosis' && get(g:gnosis_theme_state, 'kind', '') ==# 'builtin')
call s:ok('テーマ指定: Plug の形', gnosis#theme#parse("Plug 'cocopon/iceberg.vim'") ==# 'cocopon/iceberg.vim')
call s:ok('テーマ指定: URL', gnosis#theme#parse('https://github.com/morhetz/gruvbox.git') ==# 'morhetz/gruvbox')
call s:ok('テーマ指定: Vim script は受け付けない', gnosis#theme#parse("Plug 'a/b' | call system('rm -rf ~')") ==# '' && gnosis#theme#parse("call system('x')") ==# '' && gnosis#theme#parse('../../etc') ==# '')
call s:ok('テーマ: 置き場所は Gnosis ホームの themes', stridx(gnosis#theme#dir_for('a/b'), $GNOSIS_HOME . '/themes/') == 0)

" ---- ガイドの言語（日本語 / 英語）
let g:gnosis_root = s:new . '/'
call gnosis#settings#activate(s:new)
silent call gnosis#write_guide()
let s:g = readfile(s:new . '/gnosis-guide.md')
call s:ok('ガイド: 英語で作り直す', index(s:g, '# Gnosis Guide') >= 0 && match(s:g, 'Every key is collected here') >= 0)
call gnosis#settings#save(s:new, extend(gnosis#settings#load(s:new), {'language': 'ja'}))
call gnosis#settings#activate(s:new)
silent call gnosis#write_guide()
let s:g = readfile(s:new . '/gnosis-guide.md')
call s:ok('ガイド: 日本語で作り直す', index(s:g, '# Gnosis 操作ガイド') >= 0 && match(s:g, '全キーはここに集約') >= 0)
call s:ok('ガイド: 解析に使う見出しは翻訳しない', match(s:g, '### Context') >= 0)
" 旧 vault の旧ガイド名は使い続ける
call writefile(['---', 'title: simple-yurii-note 操作ガイド', '---'], s:legacy_a . '/note/simple-yurii-note-guide.md')
let g:gnosis_root = s:legacy_a . '/note/'
silent call gnosis#write_guide()
call s:ok('ガイド: 旧 vault は旧ファイル名のまま更新', !filereadable(s:legacy_a . '/note/gnosis-guide.md') && match(readfile(s:legacy_a . '/note/simple-yurii-note-guide.md'), '^title: Gnosis 操作ガイド$') >= 0)

" ---- 文言（日英で同じキーがそろう）
call gnosis#i18n#set_lang('en')
call s:ok('文言: 英語', gnosis#i18n#t('start.enter') ==# 'Press Enter to start')
call gnosis#i18n#set_lang('ja')
call s:ok('文言: 日本語', gnosis#i18n#t('start.enter') ==# 'Enter で開始')
call s:ok('文言: 引数', gnosis#i18n#t('vaults.added', 'X') ==# '登録しました: X')

" ---- ふだんの Vim の領域に書いていない（~/.vim には旧 root.txt だけ）
let s:vimfiles = filter(glob($HOME . '/.vim/**/*', 1, 1), '!isdirectory(v:val)')
call s:ok('ふだんの ~/.vim には書かない', s:vimfiles ==# [$HOME . '/.vim/simple_yurii_note/root.txt'], string(s:vimfiles))
call s:ok('runtimepath にふだんの ~/.vim が無い', index(map(split(&runtimepath, ','), 'expand(v:val)'), expand('~/.vim')) < 0)

call writefile(s:res, s:w . '/result.txt')
qa!
