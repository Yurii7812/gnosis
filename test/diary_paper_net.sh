#!/bin/sh
# 紙の日記（題がデジタル日記と同じ YYYY-MM-DD-曜日2文字 で、本文が paper-diary-… の画像を参照するノート）と、
# そのリンク階層（月・年・一番上の「日記」グループ）を、デジタル日記（\d）の機能が日記として拾わないことの回帰網。
# 一時フォルダはデスクトップの test（本物の vault には触らない）。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf -- "---\ntime: 2026-10-13 09:00:00\ntitle: 2026-10-13-TU\n---\n\n# 2026-10-13-TU\n" > "$TMP/digital.md"
printf -- "---\ntime: 2026-10-13 12:00:00\ntitle: 2026-10-13-TU\n---\n\n# 2026-10-13-TU\n\n![](paper-diary-20261013-1.jpg)\n" > "$TMP/paper.md"
printf -- "---\ntime: 2026-10-13 12:00:00\ntitle: 2026-10\nattribute: group\n---\n\n# 2026-10\n\n[2026-10-13-TU](paper.md)\n" > "$TMP/paper-month.md"
printf -- "---\ntime: 2026-10-13 12:00:00\ntitle: 日記\nattribute: group\n---\n\n# 日記\n\n[2026-10](paper-month.md)\n" > "$TMP/paper-top.md"
printf -- "---\ntime: 2026-10-01 00:00:00\ntitle: 2026-10\nattribute: group\n---\n\n# 2026-10\n\n[2026-10-13-TU](digital.md)\n" > "$TMP/digital-month.md"
cat > "$TMP/t.vim" <<EOF
set nocp
let g:simple_yurii_note_skip_interactive_mount=1
set rtp^=$REPO/plugin/simple_yurii_note
runtime autoload/simple_yurii_note.vim
redir => sn | silent scriptnames | redir END
let sid = ''
for l in split(sn, "\\n")
  if l =~ 'autoload/simple_yurii_note.vim' | let sid = matchstr(l, '^\\s*\\zs\\d\\+') | endif
endfor
let notes = function('<SNR>'.sid.'_diary_scan')('$TMP')
let found = function('<SNR>'.sid.'_diary_find')('$TMP', '2026-10-13', {'days': {}, 'notes': {}}, notes)
let grp = function('<SNR>'.sid.'_diary_find_group')(notes, '2026-10')
call writefile([join(sort(map(copy(notes), 'v:val.file')), ','), found, grp], '$TMP/out.txt')
qa!
EOF
timeout 30 vim -u NONE -N -es -S "$TMP/t.vim" </dev/null 2>"$TMP/err" || true
if [ "$(cat "$TMP/out.txt" 2>/dev/null)" = "digital-month.md,digital.md
digital.md
digital-month.md" ]; then
  echo "diary_paper OK (デジタル日記の機能は、紙の日記とそのリンク階層のグループを拾わない)"
else
  echo "NG: diary_paper" >&2; cat "$TMP/out.txt" "$TMP/err" >&2 2>/dev/null; exit 1
fi
