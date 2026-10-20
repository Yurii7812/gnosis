#!/bin/sh
# :GnosisGit を実 Vim から(本物の一時リポジトリ)。commit は明示のメッセージが要り、.state は含めない。リポジトリでなければ何もしない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/gt.XXXXXX")
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/v" "$D/plain" "$D/home" "$D/gh"
g() { git -C "$D/v" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }
g init -q -b main
printf -- '# A\n\n一行目\n' > "$D/v/a.md"
g add -A; g commit -q -m 初回
printf -- '# A\n\n一行目\n二行目\n' > "$D/v/a.md"
printf -- '# 新\n' > "$D/v/new.md"
printf -- '# P\n' > "$D/plain/p.md"
REPO="$REPO" D="$D" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/git_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
[ "$(g log --pretty=%s | head -1)" = "二行目と新規" ] || { echo "NG: コミットされていない" >&2; exit 1; }
! g ls-files | grep -q '^\.state' || { echo "NG: .state がコミットされた" >&2; exit 1; }
[ ! -d "$D/plain/.git" ] || { echo "NG: リポジトリでない vault に .git ができた" >&2; exit 1; }
printf '%s\n' 'git OK'
