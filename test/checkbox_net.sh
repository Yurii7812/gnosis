#!/bin/sh
# - [ ] の行で挿入モードの Enter が次の行にも「- [ ] 」を作る・空の項目で Enter ならリストを終えることの回帰網
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-$HOME/Desktop/test}/cbx.XXXXXX")
trap 'rm -rf "$D"' EXIT
cat > "$D/t.vim" <<'EOF'
set nocp
execute 'set rtp^=' . fnameescape($REPO)
runtime plugin/gnosis.vim
filetype on
execute 'edit ' . fnameescape($D . '/cb.md')
setfiletype markdown
call setline(1, ['- [ ] 牛乳', '  - [x] 卵を買う'])
call cursor(1, 1)
call feedkeys("A\<CR>パン\<Esc>", 'xt')
call cursor(3, 1)
call feedkeys("A\<CR>\<CR>x\<Esc>", 'xt')
call writefile(map(getline(1, '$'), '"|" . v:val . "|"'), $D . '/out.txt')
qa!
EOF
REPO="$REPO" D="$D" HOME="$D" GNOSIS_HOME="$D/gh" timeout 30 vim -u NONE -i NONE -N -es -S "$D/t.vim" </dev/null 2>"$D/err" || true
WANT="|- [ ] 牛乳|
|- [ ] パン|
|  - [x] 卵を買う|
|x|"
if [ "$(cat "$D/out.txt")" = "$WANT" ]; then echo "checkbox OK"; else echo "NG: チェックボックスの Enter" >&2; cat "$D/out.txt" >&2; exit 1; fi
