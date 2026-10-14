" Test \q work tabs and outline remaps without the real user vault.
let s:out = []
function! s:ok(label, passed) abort
  call add(s:out, (a:passed ? 'OK ' : 'NG ') . a:label)
endfunction
try
  let g:gnosis_root = $TABS_TEST_VAULT
  let g:gnosis_open_index_on_startup = 0
  let g:gnosis_autosync = 0
  execute 'edit ' . fnameescape(g:gnosis_root . '/a.md')
  call s:ok('mode indicator hides old showmode', !&showmode && &laststatus == 2)
  call s:ok('mode is on a distinctive statusline', gnosis#ui#statusline() =~# 'GnosisModeNormal')
  call s:ok('high-contrast mode palette exists', hlexists('GnosisModeInsert') && hlexists('GnosisModeVisual'))
  call s:ok('tab popup shortcut', maparg('\q', 'n') =~# 'gnosis#tabs#popup')
  call s:ok('separate tab open shortcut', maparg('\o', 'n') =~# 'gnosis#tabs#open_link')
  call s:ok('hub is still available', maparg('\h', 'n') =~# 'hub_open')
  call s:ok('numeric hub shortcuts removed', empty(maparg('\1', 'n')) && empty(maparg('\9', 'n')) && empty(maparg('\0', 'n')))
  call s:ok('outline editor relocated away from \o', maparg('\O', 'n') =~# 'OutlineEdit')
  let s:first = gnosis#tabs#snapshot()
  call s:ok('first work tab represents current file', len(s:first.tabs) == 1 && s:first.tabs[0].file =~# '/a.md$')
  call cursor(7, 3)
  call gnosis#tabs#open_link()
  let s:now = gnosis#tabs#snapshot()
  call s:ok('\o makes one new tab', len(s:now.tabs) == 2 && s:now.active == 1)
  call s:ok('original tab remains a.md', s:now.tabs[0].file =~# '/a.md$')
  call s:ok('new tab shows link target b.md', expand('%:t') ==# 'b.md' && s:now.tabs[1].file =~# '/b.md$')
  call s:ok('switch to original tab', gnosis#tabs#select(0) && expand('%:t') ==# 'a.md')
  execute 'edit ' . fnameescape(g:gnosis_root . '/b.md')
  let s:after = gnosis#tabs#snapshot()
  call s:ok('normal navigation reuses tab, no addition', len(s:after.tabs) == 2 && s:after.tabs[0].file =~# '/b.md$')
  call gnosis#tabs#close('others')
  call s:ok('close other tabs retains active one', len(gnosis#tabs#snapshot().tabs) == 1)
  call gnosis#tabs#close('all')
  call s:ok('close all clears list but not document', empty(gnosis#tabs#snapshot().tabs) && filereadable(g:gnosis_root . '/a.md'))
  call s:ok('tab state is saved inside the vault', filereadable(g:gnosis_root . '/.state/work-tabs.json'))

  execute 'edit ' . fnameescape(g:gnosis_root . '/outline.md')
  call gnosis#outline_edit()
  call s:ok('outline buffer opened', get(b:, 'gnosis_outline_editor', 0) == 1)
  let s:base = get(b:, 'gnosis_outline_base', 6)
  call s:ok('normal h/l indent mappings installed', maparg('h', 'n') =~# 'outline_shift_current' && maparg('l', 'n') =~# 'outline_shift_current')
  call s:ok('visual h/l and arrows use actual visual range', maparg('h', 'x') =~# ",'>call gnosis#outline_shift_visual" && maparg('<Right>', 'x') =~# ",'>call gnosis#outline_shift_visual")
  call s:ok('insert h/l not remapped', empty(maparg('h', 'i')) && empty(maparg('l', 'i')))
  let s:original = getline(s:base)
  execute s:base . ',' . (s:base+1) . 'call gnosis#outline_shift_visual(1)'
  call s:ok('visual range modifies both headings', getline(s:base) =~# '^## ' && getline(s:base + 1) =~# '^### ')
  call cursor(s:base, 1)
  call gnosis#outline_shift_current(-1)
  call s:ok('normal outdent modifies just one heading', getline(s:base) =~# '^# ' && getline(s:base+1) =~# '^### ')
catch
  call add(s:out, 'NG exception: ' . v:exception . ' at ' . v:throwpoint)
endtry
call writefile(s:out, $TABS_TEST_RESULT)
qall!
