#!/bin/sh
# リンク操作（zn / zk / za / \l の c → Enter / t / o、表示名、zk → g、グループの \S）の回帰網。
# 一時フォルダ（既定 ~/Desktop/test）だけを使う。本物の vault や Gnosis ホームには触らない。
# 操作のあとに同期（note_format_v2.py update）を 2 回かけ、入れたリンクと表示名が残ることも確かめる。
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault" "$WORK/home"
# クリップボードは読まない（本物のクリップボードの内容で結果が変わらないように）
LINKOPS_WORK="$WORK" GNOSIS_HOME="$WORK/home" WAYLAND_DISPLAY= DISPLAY= \
  timeout 120 vim -u "$REPO/vimrc_gnosis" -N -es -V1"$WORK/vim.log" -S "$REPO/test/link_ops_check.vim" </dev/null >"$WORK/out.txt" 2>"$WORK/err.txt" || true
if [ ! -s "$WORK/result.txt" ]; then
  echo "NG: link_ops の結果が無い（Vim のエラー）" >&2; cat "$WORK/out.txt" "$WORK/err.txt" >&2; tail -80 "$WORK/vim.log" >&2; exit 1
fi
# 同期しても、入れたリンク・表示名が残る
python3 "$REPO/python/note_format_v2.py" update "$WORK/vault" >/dev/null
python3 "$REPO/python/note_format_v2.py" update "$WORK/vault" >/dev/null
V="$WORK/vault"
chk() { if grep -qF -- "$2" "$V/$1"; then echo "OK 同期後: $3"; else echo "NG 同期後: $3"; fi; }
{
  cat "$WORK/result.txt"
  chk g.md '[ノートJG4](jg4.md)' "g でグループに入れたリンクが残る"
  chk jg4.md '[グループG:ノートJG4](g.md)' "g で入れたノートの Group: が残る"
  chk gz.md '[いちご](' "グループの zn で入れた表示名が残る"
  chk e.md '[ノートA](a.md)' "\\l c Enter で E の Context に入れた A が残る"
  chk a.md '[ノートE](e.md)' "\\l c Enter で A に置いたリンクが残る"
  if grep -q '^Context:$' "$V/a.md"; then echo "NG 同期後: A に Context ができた"; else echo "OK 同期後: c で A には Context を作らない"; fi
  if grep -q '^Group:$' "$V/ze.md"; then echo "NG 同期後: za Enter でグループに登録された"; else echo "OK 同期後: za Enter は暗黙のグループ登録にならない"; fi
} > "$WORK/all.txt"
if grep -q '^NG' "$WORK/all.txt"; then
  grep -v '^OK' "$WORK/all.txt" >&2
  echo "NG: link_ops" >&2; exit 1
fi
[ -n "$LINKOPS_VERBOSE" ] && cat "$WORK/all.txt"
echo "link_ops OK ($(grep -c '^OK' "$WORK/all.txt") 項目)"
