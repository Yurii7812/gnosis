" Terminal Gnosis regression: actual Braille splash + Markdown conceal + palette #10.
let s:errors = []
call gnosis#theme#apply(gnosis#settings#defaults())
call assert_equal('#22272E', g:gnosis_palette.bg, 'Gnosis #10 background')
call assert_equal('#CDD5DE', g:gnosis_palette.fg, 'Gnosis #10 foreground')
call assert_equal('#6CB6FF', g:gnosis_palette.link, 'Gnosis dark link')

let s:logo = gnosis#start#logo(80, 23)
let s:art = gnosis#start#pick_art(80, 23, len(s:logo) + 4)
call assert_equal(4, len(s:logo), '80x24 terminal Braille GNOSIS logo')
call assert_equal(14, len(s:art), '80x24 terminal proportion-adjusted Chnoubis')
call assert_true(len(s:logo) + len(s:art) + 4 <= 23, 'splash must fit on standard TUI')

enew
call setline(1, ['[Rosemary](261013140412.md) sample'])
setlocal filetype=markdown
call assert_equal('markdown', &l:syntax, 'Markdown syntax enabled')
call assert_equal(2, &l:conceallevel, 'Markdown links conceal enabled')
call assert_equal('nvi', &l:concealcursor, 'Markdown links stay hidden in insert/normal/visual')
call assert_equal(1, synconcealed(1, 1)[0], 'Open bracket hidden')
call assert_equal(1, synconcealed(1, 13)[0], 'Link destination hidden')
call assert_equal('gnosisLinkText', synIDattr(synID(1, 2, 1), 'name'), 'Link title highlighted')
call assert_equal('#6cb6ff', tolower(synIDattr(synIDtrans(hlID('gnosisLinkText')), 'fg#', 'gui')), 'Link highlight color')

" 日本語の表示名・長いファイル名
call setline(2, ['本文 [ローズマリーの育て方](261013140412-very-long-file-name.md) 続き'])
call assert_equal('gnosisLinkText', synIDattr(synID(2, strlen('本文 [') + 1, 1), 'name'), 'Japanese link title highlighted')
call assert_equal(1, synconcealed(2, strlen('本文 [ローズマリーの育て方]') + 2)[0], 'Japanese link destination hidden')
" 再描画・テーマの再適用・:syntax on の後もリンクの構文と色が残る
syntax on
call assert_equal(1, synconcealed(1, 13)[0], 'Concealed after :syntax on')
call assert_equal('gnosisLinkText', synIDattr(synID(1, 2, 1), 'name'), 'Link syntax after :syntax on')
call gnosis#theme#apply(gnosis#settings#defaults())
call assert_equal('#6cb6ff', tolower(synIDattr(synIDtrans(hlID('gnosisLinkText')), 'fg#', 'gui')), 'Link color after theme reapply')
call assert_equal('1', synIDattr(synIDtrans(hlID('gnosisLinkText')), 'underline', 'gui'), 'Link underline after theme reapply')
colorscheme default
call assert_equal('1', synIDattr(synIDtrans(hlID('gnosisLinkText')), 'underline', 'gui'), 'Link underline survives another colorscheme')
call gnosis#theme#apply(gnosis#settings#defaults())
" 本文は白系・リンクと見出しは本文と違う色（WCAG コントラスト比）
function! s:lum(h) abort
  let l:c = map([a:h[1:2], a:h[3:4], a:h[5:6]], 'str2nr(v:val, 16) / 255.0')
  call map(l:c, 'v:val <= 0.03928 ? v:val / 12.92 : pow((v:val + 0.055) / 1.055, 2.4)')
  return 0.2126 * l:c[0] + 0.7152 * l:c[1] + 0.0722 * l:c[2]
endfunction
function! s:cr(a, b) abort
  let [l:x, l:y] = [s:lum(a:a), s:lum(a:b)]
  " max() / min() は小数を扱えないので比べて並べる
  return l:x > l:y ? (l:x + 0.05) / (l:y + 0.05) : (l:y + 0.05) / (l:x + 0.05)
endfunction
let s:p = g:gnosis_palette
call assert_true(s:cr(s:p.fg, s:p.bg) >= 7.0, 'body contrast >= 7:1')
call assert_true(s:cr(s:p.muted, s:p.bg) >= 4.5, 'muted contrast >= 4.5:1')
call assert_true(s:cr(s:p.link, s:p.bg) >= 4.5, 'link contrast >= 4.5:1')
call assert_true(s:cr(s:p.fg, s:p.selection) >= 4.5, 'selected text contrast >= 4.5:1')
call assert_notequal(tolower(s:p.fg), tolower(s:p.link), 'link differs from body')
call assert_notequal(tolower(s:p.fg), tolower(s:p.heading), 'heading differs from body')
call assert_equal('1', synIDattr(synIDtrans(hlID('markdownH1')), 'bold', 'gui'), 'heading bold')
call assert_equal('', synIDattr(synIDtrans(hlID('Comment')), 'italic', 'gui'), 'no italic comments')
call assert_equal('#6cb6ff', tolower(synIDattr(synIDtrans(hlID('gnosisStartArt')), 'fg#', 'gui')), 'Chnoubis art uses the dark link color #6CB6FF')
" 起動画面の図案は、ふつうの等幅フォント（点が正方形に近い）では元の図案
let g:gnosis_test_cell_pixels = [11, 24]
call assert_equal(readfile(expand('<sfile>:p:h:h') . '/assets/chnoubis/chnoubis-44.txt')[0], gnosis#start#art(44)[0], 'original art for normal cells')
let g:gnosis_test_cell_pixels = [20, 24]
call assert_equal(readfile(expand('<sfile>:p:h:h') . '/assets/chnoubis/chnoubis-fit-44.txt')[0], gnosis#start#art(44)[0], 'fit art for wide cells')
" 行の高いフォント（縦長のマス）では、点が正方形になるよう縦に縮める（幅は同じ・細い線は消えない）
let s:orig = readfile(expand('<sfile>:p:h:h') . '/assets/chnoubis/chnoubis-44.txt')
call filter(s:orig, '!empty(v:val)')
let g:gnosis_test_cell_pixels = [8, 24]
let s:tall = gnosis#start#art(44)
call assert_true(len(s:tall) < len(s:orig) && len(s:tall) >= len(s:orig) * 0.6, 'tall cells squash the art vertically: ' . len(s:tall) . ' / ' . len(s:orig))
call assert_equal(max(map(copy(s:orig), 'strchars(v:val)')), max(map(copy(s:tall), 'strchars(v:val)')), 'squashed art keeps its width')
call assert_true(len(filter(copy(s:tall), 'v:val =~# "[^\u2800 ]"')) == len(s:tall), 'every squashed row still has dots')
unlet g:gnosis_test_cell_pixels

call writefile(v:errors, $GNOSIS_TEST_OUT)
if !empty(v:errors)
  cquit 1
endif
qa!
