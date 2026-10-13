#!/bin/sh
# 現役同期エンジン(note_format_v2.py の simple_sync)の回帰網。
# vault を一時フォルダにコピーし、2回 sync して冪等（2回目が 0 changes）を確認する。
# 分割リファクタの前後で同じ結果になることが期待値。
# 使い方: test/sync_net.sh [VAULT]
#   VAULT を省略すると、試験用の小さな vault をその場で作る（個人の vault には依存しない）。
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault"
if [ $# -ge 1 ]; then
  cp -a "$1"/. "$WORK/vault/"
else
  V="$WORK/vault"
  printf -- '---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[A](a.md)\n[グループ](g.md)\n' > "$V/index.md"
  printf -- '---\ntime: 2026-01-01 00:00:01\ntitle: A\n---\n\n# A\n\n本文 [B](b.md)\n\n[B](b.md)\n' > "$V/a.md"
  printf -- '---\ntime: 2026-01-01 00:00:02\ntitle: B\n---\n\n# B\n\n### Context\n[A](a.md)\n' > "$V/b.md"
  printf -- '---\ntime: 2026-01-01 00:00:03\ntitle: グループ\nattribute: group\n---\n\n# グループ\n\n[A](a.md)\n[消えた](gone.md)\n' > "$V/g.md"
fi
PY="$REPO/python/note_format_v2.py"

R1=$(python3 "$PY" update "$WORK/vault")
R2=$(python3 "$PY" update "$WORK/vault")
echo "1回目: $R1"
echo "2回目: $R2"

case "$R2" in
  *"updated 0 file(s)"*) echo "sync 冪等 OK";;
  *) echo "NG: 2回目が 0 changes でない" >&2; exit 1;;
esac
