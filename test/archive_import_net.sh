#!/bin/sh
# :GnosisImportArchive の本体（gnosis#archive#run）を実 Vim で。一時フォルダだけを使う。7z が無ければ飛ばす。
set -e
command -v 7z >/dev/null 2>&1 || { echo "archive_import OK (7z が無いので飛ばした)"; exit 0; }
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO/test/noclip.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home" "$WORK/src/v/sub"
printf 'old\n' > "$WORK/vault/a.md"
printf 'NEW\n' > "$WORK/src/v/a.md"
printf 'c\n' > "$WORK/src/v/sub/c.md"
(cd "$WORK/src" && 7z a -t7z -mhe=on -ppw "$WORK/x.7z" v >/dev/null)
cat > "$WORK/t.vim" <<VIM
let g:gnosis_root = '$WORK/vault/'
let s:res = []
let s:bad = gnosis#archive#run('$WORK/x.7z', v:null)
call add(s:res, (get(s:bad, 'need_password', 0) ? 'OK' : 'NG') . ' パスワードが要る書庫は need_password')
let s:wrong = gnosis#archive#run('$WORK/x.7z', 'zzz')
call add(s:res, (get(s:wrong, 'wrong', 0) ? 'OK' : 'NG') . ' 違うパスワードは弾く')
let s:r = gnosis#archive#run('$WORK/x.7z', 'pw')
call add(s:res, (get(s:r, 'added', -1) == 1 && get(s:r, 'updated', -1) == 1 ? 'OK' : 'NG ' . string(s:r)) . ' 追加 1・更新 1')
call add(s:res, (join(readfile('$WORK/vault/a.md'), '') ==# 'NEW' && filereadable('$WORK/vault/sub/c.md') ? 'OK' : 'NG') . ' vault が更新された')
call writefile(s:res, '$WORK/result.txt')
qa!
VIM
GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= timeout 60 vim -u "$REPO/vimrc_gnosis" -N -es -S "$WORK/t.vim" </dev/null >/dev/null 2>&1 || true
[ -s "$WORK/result.txt" ] || { echo "NG: archive_import の結果が無い" >&2; exit 1; }
if grep -q '^NG' "$WORK/result.txt"; then grep -v '^OK' "$WORK/result.txt" >&2; echo "NG: archive_import" >&2; exit 1; fi
ls "$WORK/vault/.trash"/archive-import-*/a.md >/dev/null 2>&1 || { echo "NG: 元のファイルが .trash に残っていない" >&2; exit 1; }
echo "archive_import OK ($(wc -l < "$WORK/result.txt") 項目)"
