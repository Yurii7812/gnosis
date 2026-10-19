#!/bin/sh
# グループへの追加は、名前とよみの確認画面を通ってから必ず並べ替わることの回帰網。
#   za（複数）/ 手で貼って保存 / 行を消す / Q / :GnosisYomiReview
# 使い方: test/group_review_net.sh   （一時フォルダだけを使う。本物の vault には触らない）
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-$HOME/Desktop/test}/grv.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/home" "$D/gh"
mk() { printf -- "---\ntime: 2026-01-01 00:00:00\ntitle: %s\n---\n\n# %s\n" "$2" "$2" > "$D/v/$1.md"; }
mk k 筋トレ; mk i イルカ; mk a アヒル; mk u ウシ; mk z ゼブラ
printf -- "---\ntime: 2026-01-01 00:00:00\ntitle: テスト\nattribute: group\n---\n\n# テスト\n\n[イルカ](i.md)\n" > "$D/v/g.md"
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -S "$REPO/test/group_review_check.vim" </dev/null 2>"$D/err" || true
WANT="screen1 1
guess 1
enter k.md
back 1 1
after1 ['[アヒル](a.md)', '[イルカ](i.md)', '[筋トレ](k.md)']
yomi ['  \"筋トレ\": \"きんとれ\"']
screen2 1 n=2
after2 ['[アヒル](a.md)', '[イルカ](i.md)', '[ウシ](u.md)', '[筋トレ](k.md)']
screen3 1 n=4
back g.md"
if [ "$(cat "$D/out.txt" 2>/dev/null)" = "$WANT" ]; then
  echo "group_review OK"
else
  echo "NG: 名前とよみの確認画面の流れが期待どおりでない" >&2
  cat "$D/out.txt" "$D/err" >&2 2>/dev/null || true
  exit 1
fi
