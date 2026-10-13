" Terminal Gnosis regression: actual Braille splash + Markdown conceal + palette #10.
let s:errors = []
call gnosis#theme#apply(gnosis#settings#defaults())
call assert_equal('#14283D', g:gnosis_palette.bg, 'Gnosis #10 background')
call assert_equal('#79CFFF', g:gnosis_palette.fg, 'Gnosis #10 foreground')
call assert_equal('#BCEEFF', g:gnosis_palette.link, 'Gnosis #10 link')

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
call assert_equal('#BCEEFF', synIDattr(synIDtrans(hlID('gnosisLinkText')), 'fg#', 'gui'), 'Link highlight color')

call writefile(v:errors, $GNOSIS_TEST_OUT)
if !empty(v:errors)
  cquit 1
endif
qa!
