#!/bin/sh
# Context ブロック（本文冒頭の `Context:`）と w モードの回帰網。一時フォルダ（既定 ~/Desktop/test）だけを使う。
# 操作のあとに同期を 2 回かけても、新形式が維持され、旧形式が勝手に移行・再生成されないことも確かめる。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
CONTEXT_WORK="$WORK" GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= \
  timeout 150 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/context_check.vim" </dev/null >"$WORK/out.txt" 2>"$WORK/err.txt" || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: context の結果が無い（Vim のエラー）" >&2; cat "$WORK/out.txt" "$WORK/err.txt" >&2; exit 1
fi
V="$WORK/vault"
# 旧形式のまま置いたノート（Vim で触っていない）を控える
printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: 旧\n---\n\n# 旧\n\n本文。\n\n### Context\n[ノートF](f.md)\n' > "$V/legacy-untouched.md"
cp "$V/legacy-untouched.md" "$WORK/legacy.before"
python3 "$REPO/python/note_format_v2.py" update "$V" >/dev/null
python3 "$REPO/python/note_format_v2.py" update "$V" >/dev/null
chk() { if grep -qF -- "$2" "$V/$1"; then echo "OK 同期後: $3"; else echo "NG 同期後: $3"; fi; }
{
  cat "$WORK/result.txt"
  chk b.md '[ノートA](a.md)' "B の Context が残る"
  if awk '/^Context:$/{f=1;next} f&&/^\[/{n++;next} f{exit} END{exit !(n==2)}' "$V/b.md"; then echo "OK 同期後: B の Context は 2 本のまま（A, C の順）"; else echo "NG 同期後: B の Context"; fi
  grep -q '^### Context' "$V/b.md" && echo "NG 同期後: 新形式が ### Context に戻った" || echo "OK 同期後: 新形式が維持される（### Context を再生成しない）"
  if cmp -s "$V/legacy-untouched.md" "$WORK/legacy.before"; then echo "OK 同期後: 旧形式のノートを勝手に移行・書き換えない"; else echo "NG 同期後: 旧形式のノートが書き換わった"; fi
  python3 "$REPO/python/branch_ops.py" check "$V" >/dev/null && echo "OK 同期後: Branch の整合性に問題なし" || echo "NG 同期後: 整合性エラー"
  if [ "$(grep -c '^### ParentBranch$' "$V/x.md")" = 1 ] && grep -q '^Context:$' "$V/x.md"; then echo "OK 同期後: Context と ParentBranch が共存"; else echo "NG 同期後: x.md"; fi
} > "$WORK/all.txt"
if grep -q '^NG' "$WORK/all.txt"; then
  grep -v '^OK' "$WORK/all.txt" >&2
  echo "NG: context" >&2; exit 1
fi
[ -n "$CONTEXT_VERBOSE" ] && cat "$WORK/all.txt"
echo "context OK ($(grep -c '^OK' "$WORK/all.txt") 項目)"
