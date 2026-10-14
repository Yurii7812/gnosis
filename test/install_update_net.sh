#!/bin/sh
# インストーラーの更新の回帰網。手元に作った「GitHub の代わり」のリポジトリで試す（ネットに出ない）。
#   - 古い版のフォルダで install.sh を動かすと、新しい版を取り込んでから入れ直す
#   - 未コミットの変更があるときは、ファイルを残してエラー終了する
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "NG: install_update: $1" >&2; exit 1; }
mkdir -p "$WORK/home" "$WORK/mirror"
for name in fzf fzf.vim vim-surround; do
  mkdir -p "$WORK/mirror/$name/plugin" && echo '" dummy' > "$WORK/mirror/$name/plugin/$name.vim"
  git -C "$WORK/mirror/$name" init -q && git -C "$WORK/mirror/$name" add -A && git -C "$WORK/mirror/$name" -c user.email=t@t -c user.name=t commit -qm t
done
git clone -q --bare "$REPO" "$WORK/origin.git"
# 「GitHub に新しい版が出た」状態を作る（今の版の上に試験用のコミットを 1 つ）
git clone -q "$WORK/origin.git" "$WORK/pub"
echo '新しい版' > "$WORK/pub/UPDATE-TEST.txt"
git -C "$WORK/pub" add UPDATE-TEST.txt
git -C "$WORK/pub" -c user.email=t@t -c user.name=t commit -qm '試験: 新しい版'
git -C "$WORK/pub" push -q origin HEAD
latest=$(git -C "$WORK/origin.git" rev-parse HEAD)
run() { # フォルダ ログ
  HOME="$WORK/home" XDG_DATA_HOME= GNOSIS_HOME= GNOSIS_PLUGIN_MIRROR="$WORK/mirror" LANG=ja_JP.UTF-8 \
    sh "$1/install/install.sh" --yes --no-system --no-app --no-venv >"$2" 2>&1
}
# 1. 古い版（1 つ前のコミット）から更新
git clone -q "$WORK/origin.git" "$WORK/old"
git -C "$WORK/old" reset -q --hard HEAD~1
run "$WORK/old" "$WORK/old.log" || { cat "$WORK/old.log" >&2; fail "install.sh が失敗した"; }
[ "$(git -C "$WORK/old" rev-parse HEAD)" = "$latest" ] || { cat "$WORK/old.log" >&2; fail "最新に更新されていない"; }
grep -q '更新しました' "$WORK/old.log" || fail "更新したことを知らせていない"
grep -q '最新 / latest' "$WORK/old.log" || { cat "$WORK/old.log" >&2; fail "要約で最新と表示していない"; }
# 2. 未コミットの変更があるときは更新しない
git clone -q "$WORK/origin.git" "$WORK/dirty"
git -C "$WORK/dirty" reset -q --hard HEAD~1
echo '自分の変更' >> "$WORK/dirty/README.md"
old_head=$(git -C "$WORK/dirty" rev-parse HEAD)
if run "$WORK/dirty" "$WORK/dirty.log"; then fail "変更があるのに古い版を正常にインストールした"; fi
[ "$(git -C "$WORK/dirty" rev-parse HEAD)" = "$old_head" ] || fail "未コミットの変更があるのに更新した"
tail -1 "$WORK/dirty/README.md" | grep -q '自分の変更' || fail "未コミットの変更が消えた"
grep -q '安全のため更新を停止' "$WORK/dirty.log" || { cat "$WORK/dirty.log" >&2; fail "更新失敗理由を表示していない"; }
# 3. 別のフォルダに新しく clone して入れると、ランチャーはそちらを指す
git clone -q "$WORK/origin.git" "$WORK/new"
run "$WORK/new" "$WORK/new.log" || { cat "$WORK/new.log" >&2; fail "新しい clone で失敗した"; }
HOME="$WORK/home" "$WORK/home/.local/bin/gnosis" --where | grep -qxF "launcher:      $WORK/new/bin/gnosis" || fail "ランチャーが新しい clone を指していない"
grep -q "$WORK/dirty/bin/gnosis" "$WORK/new.log" || fail "前のインストール先からの切り替えを知らせていない"
echo "install_update OK (自動更新・dirty repository は明示的に失敗・新しい clone へ切り替え)"
