#!/bin/sh
# Linux / macOS の 1 行インストーラー（install/bootstrap.sh）の回帰網。一時フォルダの HOME だけを使う（ネットに出ない）。
#   - 取得元は、この作業中のリポジトリ（GNOSIS_REPO_URL=file://…）。プラグインもこのマシンのものを使う
#   - 新しい環境（Gnosis が無い）から、取得 → インストールまで 1 回で終わり、ランチャーができる
#   - 2 回目は更新（ff）。未コミットの変更があれば止まって、変更を消さない
#   - git が無くパッケージ管理も無い環境では、成功と言わず理由を出して終わる
set -e
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
H="$WORK/home"
mkdir -p "$H" "$WORK/mirror"
fail() { echo "NG: bootstrap: $1" >&2; exit 1; }
for name in fzf fzf.vim vim-surround; do
  mkdir -p "$WORK/mirror/$name/plugin" && echo '" dummy' > "$WORK/mirror/$name/plugin/$name.vim"
  git -C "$WORK/mirror/$name" init -q && git -C "$WORK/mirror/$name" add -A && git -C "$WORK/mirror/$name" -c user.email=t@t -c user.name=t commit -qm t
done
run() { HOME="$H" XDG_DATA_HOME= GNOSIS_HOME= GNOSIS_DIR="$H/gnosis" GNOSIS_REPO_URL="file://$REPO" GNOSIS_PLUGIN_MIRROR="$WORK/mirror" LANG=ja_JP.UTF-8 \
  sh "$REPO/install/bootstrap.sh" "$@"; }

# 1. 何も無い環境から、1 回で入る
run --yes --no-system --no-app --no-venv >"$WORK/1.log" 2>&1 || { cat "$WORK/1.log" >&2; fail "初回の 1 行インストールが失敗した"; }
[ -d "$H/gnosis/.git" ] || fail "~/gnosis に取得されていない"
[ -x "$H/.local/bin/gnosis" ] || fail "ランチャーができていない"
[ -f "$H/.local/share/gnosis/vimrc" ] || fail "専用 vimrc ができていない"
HOME="$H" "$H/.local/bin/gnosis" --where >/dev/null 2>&1 || fail "gnosis --where が動かない"

# 2. 2 回目は更新（同じ 1 行でよい）
run --yes --no-system --no-app --no-venv >"$WORK/2.log" 2>&1 || { cat "$WORK/2.log" >&2; fail "2 回目（更新）が失敗した"; }
grep -q "更新" "$WORK/2.log" || fail "既にあることを知らせていない"

# 3. 未コミットの変更があれば止まる（変更は消さない）
printf 'mine\n' >> "$H/gnosis/README.md"
if run --yes --no-system --no-app --no-venv >"$WORK/3.log" 2>&1; then fail "未コミットの変更があるのに続けた"; fi
tail -1 "$H/gnosis/README.md" | grep -qx mine || fail "未コミットの変更が消えた"
git -C "$H/gnosis" checkout -q README.md

# 4. git が無く、パッケージ管理も無い環境
mkdir -p "$WORK/nogit"
for f in /usr/bin/* /bin/*; do
  b=$(basename "$f"); case "$b" in git*|apt*|dnf|pacman|zypper|brew|sudo) continue ;; esac
  [ -e "$WORK/nogit/$b" ] || ln -s "$f" "$WORK/nogit/$b"
done
H2="$WORK/home2"; mkdir -p "$H2"
if HOME="$H2" GNOSIS_DIR="$H2/gnosis" GNOSIS_REPO_URL="file://$REPO" PATH="$WORK/nogit" LANG=ja_JP.UTF-8 sh "$REPO/install/bootstrap.sh" --yes >"$WORK/4.log" 2>&1; then
  fail "git もパッケージ管理も無いのに成功と表示した"
fi
grep -q "パッケージ管理" "$WORK/4.log" || { cat "$WORK/4.log" >&2; fail "git が無いときの理由が出ない"; }
[ ! -e "$H2/gnosis" ] || fail "失敗したのに ~/gnosis を作った"
echo "bootstrap OK (空の環境から 1 回で取得とインストール・2 回目は更新・未コミットの変更は消さない・git が無いときは理由を出す)"
