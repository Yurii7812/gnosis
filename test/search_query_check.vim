" 検索の書き方（autoload/gnosis/query.vim）が、共通の試験データ（test/search_query_cases.json）どおりに解析し、合否も合うこと。
" 結果は $SQ_OUT に OK / NG で書く（test/search_query_net.sh から）
set nomore
let s:res = []
let s:cases = json_decode(join(readfile($SQ_CASES), "\n"))
for s:c in s:cases
  let s:got = map(gnosis#query#parse(s:c[0]), '[v:val.pos, v:val.neg]')
  call add(s:res, (s:got ==# s:c[1] ? 'OK ' : 'NG ') . string(s:c[0]) . ' ' . s:c[2] . (s:got ==# s:c[1] ? '' : ': ' . string(s:got)))
endfor
" 合否（Python と同じ答え）
let s:m = [
      \ ['ハーブ -メモ', 'ハーブの育て方', 1], ['ハーブ -メモ', 'ハーブのメモ', 0], ['a | b', 'xbx', 1], ['a | b', 'xcx', 0], ['a b | c', 'ab', 1], ['a b | c', 'a', 0], ['a b | c', 'c', 1],
      \ ['"育て 方"', '育て 方', 1], ['"育て 方"', '育ての方', 0], ['\-foo', 'a -foo b', 1], ['\-foo', 'foo', 0], ['-foo', 'bar', 1], ['-foo', 'foo', 0],
      \ ['INDEX', 'Index', 1], ['ｉｎｄｅｘ', 'index', 1], ['かたかな', 'カタカナ', 1], ['', 'なんでも', 1], ['a-b', 'xa-bx', 1], ['a-b', 'a b', 0],
      \ ]
for s:t in s:m
  let s:r = gnosis#query#match(s:t[0], s:t[1])
  call add(s:res, (s:r == s:t[2] ? 'OK ' : 'NG ') . 'match ' . string(s:t[0]) . ' / ' . string(s:t[1]) . (s:r == s:t[2] ? '' : ': ' . s:r))
endfor
call writefile(s:res, $SQ_OUT)
qa!
