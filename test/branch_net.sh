#!/bin/sh
# Branch（b モード）の回帰網。一時フォルダ（既定 ~/Desktop/test）だけを使う。
# 操作のあとに同期（note_format_v2.py update）を 2 回かけても、親子関係が維持されて親が増えないことも確かめる。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
BRANCH_WORK="$WORK" GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= \
  timeout 120 vim -u "$REPO/vimrc_gnosis" -N -es -S "$REPO/test/branch_check.vim" </dev/null >"$WORK/out.txt" 2>"$WORK/err.txt" || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: branch の結果が無い（Vim のエラー）" >&2; cat "$WORK/out.txt" "$WORK/err.txt" >&2; exit 1
fi
V="$WORK/vault"
python3 "$REPO/python/note_format_v2.py" update "$V" >/dev/null
python3 "$REPO/python/note_format_v2.py" update "$V" >/dev/null
chk() { if grep -qF -- "$2" "$V/$1"; then echo "OK 同期後: $3"; else echo "NG 同期後: $3"; fi; }
{
  cat "$WORK/result.txt"
  chk a.md 'ChildBranch:' "A の ChildBranch が残る"
  chk a.md '[ノートB](b.md)' "A の子 B が残る"
  chk b.md '[ノートA](a.md)' "B の親 A が残る"
  if [ "$(grep -c '^ParentBranch:$' "$V/b.md")" = 1 ] && [ "$(grep -c '(a.md)' "$V/b.md")" = 1 ] && ! grep -q '(c.md)' "$V/b.md"; then echo "OK 同期後: B の親は A だけ（C を足さない）"; else echo "NG 同期後: B の親"; fi
  if grep -q '^### Context' "$V/b.md"; then echo "NG 同期後: ParentBranch が Context に変換された"; else echo "OK 同期後: Context に変換されない"; fi
  chk r1.md '[ノートS1](s1.md)' "p で作った親 R1 の子 S1 が残る"
  chk s1.md '[ノートR1](r1.md)' "p で作った S1 の親 R1 が残る"
  if [ "$(grep -c '^ParentBranch:$' "$V/s1.md")" = 1 ] && ! grep -q '(t1.md)' "$V/s1.md"; then echo "OK 同期後: S1 の親は R1 だけ（T1 を足さない）"; else echo "NG 同期後: S1 の親"; fi
  python3 "$REPO/python/branch_ops.py" check "$V" >/dev/null && echo "OK 同期後: Branch の整合性に問題なし" || echo "NG 同期後: 整合性エラー"
} > "$WORK/all.txt"
if grep -q '^NG' "$WORK/all.txt"; then
  grep -v '^OK' "$WORK/all.txt" >&2
  echo "NG: branch" >&2; exit 1
fi
[ -n "$BRANCH_VERBOSE" ] && cat "$WORK/all.txt"
echo "branch OK ($(grep -c '^OK' "$WORK/all.txt") 項目)"
