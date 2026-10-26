" =============================================================================
" autoload/gnosis/i18n.vim — 日本語 / 英語の切り替え
"
" 文言は i18n/ja.json・i18n/en.json（Electron の画面と共通）にまとめる。
"   gnosis#i18n#t('key', 引数…)  … キーで引く。%s に引数を入れる（printf と同じ）
"   gnosis#i18n#tr('日本語の文')   … 既存の日本語メッセージ用。英語のときは
"                                     i18n/en.json の "ja" の表で英語に置き換える（無ければ日本語のまま）
" 言語は Gnosis ホーム全体の設定（ホームの language ファイルに ja / en）。起動画面の l で選ぶ。
" ファイルが無ければ英語（g:gnosis_language を指定していればそれが先）。vault の設定の language は、この値の写し。
"
" 注意: ノートの解析に使う見出し・識別子（### Context / ### BackLink / ## 今日のノート
" など）は翻訳しない。表示の文言だけを切り替える。
" =============================================================================

let s:dir = expand('<sfile>:p:h:h:h') . '/i18n'
let s:cat = {}

function! gnosis#i18n#system_lang() abort
  for l:v in [$LC_ALL, $LC_MESSAGES, $LANG, v:lang]
    if !empty(l:v) && l:v !=# 'C' && l:v !=# 'POSIX'
      return l:v =~? '^ja' ? 'ja' : 'en'
    endif
  endfor
  if has('win32')
    return v:lang =~? 'japan\|^ja' ? 'ja' : 'en'
  endif
  return 'en'
endfunction

function! s:lang_file() abort
  return gnosis#home#path('language')
endfunction

" Gnosis ホームに保存した言語（無ければ空）
function! gnosis#i18n#saved() abort
  try
    let l:l = filereadable(s:lang_file()) ? trim(join(readfile(s:lang_file(), '', 1), '')) : ''
  catch
    let l:l = ''
  endtry
  return l:l =~# '^\(ja\|en\)$' ? l:l : ''
endfunction

function! gnosis#i18n#lang() abort
  if !exists('s:lang')
    " g:gnosis_language → 環境変数 GNOSIS_LANG（試験・自動化用）→ Gnosis ホームに保存した言語 → 英語
    let l:l = get(g:, 'gnosis_language', '')
    if l:l !~# '^\(ja\|en\)$'
      let l:l = $GNOSIS_LANG
    endif
    if l:l !~# '^\(ja\|en\)$'
      let l:l = gnosis#i18n#saved()
    endif
    let s:lang = l:l =~# '^\(ja\|en\)$' ? l:l : 'en'
    " Python の補助スクリプトにも伝える（既定が日本語のままにならないように）
    let $GNOSIS_LANG = s:lang
  endif
  return s:lang
endfunction

" 言語を選ぶ: 今すぐ切り替え、Gnosis ホームに覚える
function! gnosis#i18n#choose(lang) abort
  if a:lang !~# '^\(ja\|en\)$'
    return
  endif
  call gnosis#i18n#set_lang(a:lang)
  try
    call gnosis#home#init()
    call writefile([a:lang], s:lang_file())
  catch
  endtry
endfunction

function! gnosis#i18n#set_lang(lang) abort
  if a:lang =~# '^\(ja\|en\)$'
    let s:lang = a:lang
    " Python の補助スクリプト・アプリにも伝える
    let $GNOSIS_LANG = a:lang
  endif
endfunction

function! s:catalog(lang) abort
  if !has_key(s:cat, a:lang)
    let l:f = s:dir . '/' . a:lang . '.json'
    let s:cat[a:lang] = {}
    if filereadable(l:f)
      try
        let s:cat[a:lang] = json_decode(join(readfile(l:f), "\n"))
      catch
      endtry
    endif
  endif
  return s:cat[a:lang]
endfunction

" キーの文言（言語 a:lang を明示するときは gnosis#i18n#t_lang）
function! gnosis#i18n#t(key, ...) abort
  return call('gnosis#i18n#t_lang', [gnosis#i18n#lang(), a:key] + a:000)
endfunction

function! gnosis#i18n#t_lang(lang, key, ...) abort
  let l:s = get(get(s:catalog(a:lang), 'msg', {}), a:key, '')
  if empty(l:s)
    let l:s = get(get(s:catalog('ja'), 'msg', {}), a:key, a:key)
  endif
  if a:0 == 0
    return l:s
  endif
  return call('printf', [substitute(l:s, '%\([^s%]\)', '%%\1', 'g')] + map(copy(a:000), 'type(v:val) == v:t_string ? v:val : string(v:val)'))
endfunction

" 既存の日本語メッセージを、英語のときだけ置き換える
function! gnosis#i18n#tr(ja, ...) abort
  let l:s = a:ja
  if gnosis#i18n#lang() ==# 'en'
    let l:s = get(get(s:catalog('en'), 'ja', {}), a:ja, a:ja)
  endif
  if a:0 == 0
    return l:s
  endif
  return call('printf', [l:s] + a:000)
endfunction

" 読み直し（テスト・文言の更新用）
function! gnosis#i18n#reload() abort
  let s:cat = {}
endfunction
