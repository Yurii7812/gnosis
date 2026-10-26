#!/bin/sh
# 起動の軽さの回帰網: 配色（colors/gnosis.vim）を起動中に何度も読み直さない。一時フォルダだけを使う。
set -e
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
printf -- '# a\n' > "$WORK/vault/a.md"
cat > "$WORK/cs.vim" <<'V'
let g:cs = 0
autocmd ColorSchemePre * let g:cs += 1
V
GNOSIS_HOME="$WORK/home" timeout 60 vim -u "$REPO/vimrc_gnosis" -N -es --cmd "source $WORK/cs.vim" -c "edit $WORK/vault/a.md" -c "call writefile([g:cs], '$WORK/n.txt')" -c 'qa!' </dev/null >/dev/null 2>&1 || true
n=$(cat "$WORK/n.txt" 2>/dev/null || echo x)
if [ "$n" != 1 ]; then echo "NG: 起動中に配色を $n 回読んだ（1 回のはず）" >&2; exit 1; fi
echo "startup OK (配色は 1 回だけ読む)"
