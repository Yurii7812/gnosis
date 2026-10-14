" High contrast dedicated statusline with a visible mode badge.
function! gnosis#ui#statusline() abort
  let l:m = mode(1)
  if l:m =~# '^[i]'
    let l:kind = 'Insert'
    let l:label = ' INSERT '
  elseif l:m =~# '^[Rr]'
    let l:kind = 'Replace'
    let l:label = ' REPLACE '
  elseif l:m =~# '^[vV]' || l:m ==# "\<C-v>"
    let l:kind = 'Visual'
    let l:label = ' VISUAL '
  else
    let l:kind = 'Normal'
    let l:label = ' NORMAL '
  endif
  return '%#GnosisMode' . l:kind . '#' . l:label
        \ . '%#StatusLine#  %f %m%r%=%l:%c  %p%% '
endfunction
