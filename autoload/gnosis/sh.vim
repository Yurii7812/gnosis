" ---------------------------------------------------------------------------
" 外部コマンドの実行（system() / systemlist() の代わり）
"   Vim の system() は、終わるまで端末を「ふつうのモード」（cooked）に戻す。その間に押した
"   矢印キーなどは端末がそのまま画面に書き出し、^[[1;5C のような文字が出る。
"   ここではコマンドを job で動かし、終わるまで :sleep で待つ（端末のモードは変わらない）。
"   待っている間に押したキーは、終わったあとでふつうに効く。
"   終了コードは v:shell_error ではなく gnosis#sh#error() で受け取る。
" ---------------------------------------------------------------------------

let s:status = 0

function! gnosis#sh#error() abort
  return s:status
endfunction

function! gnosis#sh#system(cmd, ...) abort
  if !s:use_job()
    let l:out = a:0 ? system(a:cmd, a:1) : system(a:cmd)
    let s:status = v:shell_error
    return l:out
  endif
  return join(s:run(a:cmd, a:0 ? a:1 : v:null), '')
endfunction

function! gnosis#sh#systemlist(cmd, ...) abort
  if !s:use_job()
    let l:out = a:0 ? systemlist(a:cmd, a:1) : systemlist(a:cmd)
    let s:status = v:shell_error
    return l:out
  endif
  let l:text = join(s:run(a:cmd, a:0 ? a:1 : v:null), '')
  " systemlist() と同じく、最後の改行のあとは空の行を足さない。行の中の NUL は改行として扱う
  let l:lines = split(l:text, "\n", 1)
  if !empty(l:lines) && l:lines[-1] ==# ''
    call remove(l:lines, -1)
  endif
  return l:lines
endfunction

" 端末の Vim（Unix）でだけ job を使う。GUI や Windows は端末のモードの問題が無いので system() のまま
function! s:use_job() abort
  return has('job') && has('channel') && !has('win32') && !has('gui_running')
        \ && !get(g:, 'gnosis_plain_system', 0)
endfunction

function! s:run(cmd, input) abort
  let l:out = []
  let l:opts = {'out_mode': 'raw', 'err_io': 'out',
        \ 'out_cb': {ch, msg -> add(l:out, msg)},
        \ 'in_io': a:input is v:null ? 'null' : 'pipe'}
  let l:job = job_start(['/bin/sh', '-c', a:cmd], l:opts)
  if job_status(l:job) ==# 'fail'
    let s:status = -1
    return []
  endif
  try
    if a:input isnot v:null
      let l:ch = job_getchannel(l:job)
      let l:in = type(a:input) == v:t_list ? join(a:input, "\n") . (empty(a:input) ? '' : "\n") : a:input
      if !empty(l:in)
        call ch_sendraw(l:ch, l:in)
      endif
      call ch_close_in(l:ch)
    endif
    " 終わって、出力を読み終えるまで待つ（:sleep のあいだも出力は out_cb に届く）
    while job_status(l:job) ==# 'run' || ch_status(job_getchannel(l:job), {'part': 'out'}) !=# 'closed'
      sleep 1m
    endwhile
  finally
    " Ctrl-C で待つのをやめたときは、コマンドも止める
    if job_status(l:job) ==# 'run'
      call job_stop(l:job, 'kill')
    endif
  endtry
  let s:status = job_info(l:job).exitval
  return l:out
endfunction
