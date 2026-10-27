#!/bin/sh
# tools/agents（複数の AI が並行して作業するための補助）の回帰網。使い捨てのリポジトリだけを使う。
# 本物の ~/gnosis・~/src・~/gnosis-work/agents には触らない。
set -e
TMPDIR=${TMPDIR:-$HOME/gnosis-work/test}
mkdir -p "$TMPDIR"
export TMPDIR
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
git init -q --bare "$W/origin.git"
git clone -q "$W/origin.git" "$W/main" 2>/dev/null
cd "$W/main"
git checkout -q -b main
mkdir -p test python
printf 'a\n' > a.txt; printf 'b\n' > b.txt; printf 'g\n' > guide.txt
printf '#!/bin/sh\necho related-ok\n' > test/related.sh
printf '#!/bin/sh\necho parallel-ok\n' > test/run_parallel.sh
git add -A; git commit -q -m init; git push -q origin main
export GNOSIS_REPO="$W/main" GNOSIS_WORKTREES="$W/wt" GNOSIS_AGENT_REG="$W/reg" HOME="$W/home"
mkdir -p "$W/home"
AG="bash $REPO/tools/agents"
fail() { echo "NG: $1" >&2; exit 1; }

$AG start one --agent codex --desc 1つ目 --area python/ >/dev/null || fail "start one"
$AG start two --agent claude --desc 2つ目 --area python/fznav.py guide.txt >"$W/two.out" 2>&1 || fail "start two"
grep -q '重なって' "$W/two.out" || fail "担当範囲の重なりの警告が出ない: $(cat "$W/two.out")"
$AG start one >/dev/null 2>&1 && fail "同じ名前で二重に始められた"
$AG list | grep -q 'one' || fail "list に one が出ない"
$AG list | grep -q 'two' || fail "list に two が出ない"
$AG env one | grep -q "TMPDIR=" || fail "env"

# one: a.txt を直して反映
( cd "$W/wt/gnosis-one" && echo one >> a.txt && git commit -qam "one" )
( cd "$W/wt/gnosis-one" && git status --porcelain | grep -q . ) && fail "ship で作業ツリーが汚れた"
$AG ship one || fail "ship one"
git -C "$W/main" fetch -q origin; [ "$(git -C "$W/main" show origin/main:a.txt | tail -1)" = one ] || fail "one が main に入っていない"
[ ! -f "$W/reg/one.claim" ] || fail "反映後に担当が片づいていない"

# two: 別のファイルを直して反映（one が先に main を進めているので、rebase される）
( cd "$W/wt/gnosis-two" && echo two >> b.txt && git commit -qam "two" )
$AG ship two --test >"$W/ship2.out" 2>&1 || fail "ship two: $(cat "$W/ship2.out")"
grep -q 'parallel-ok' "$W/ship2.out" || fail "--test で run_parallel.sh が流れていない"
grep -q 'related-ok' "$W/ship2.out" || fail "他の作業が main を進めたあと、related.sh が流れていない"
git -C "$W/main" fetch -q origin
[ "$(git -C "$W/main" show origin/main:a.txt | tail -1)" = one ] && [ "$(git -C "$W/main" show origin/main:b.txt | tail -1)" = two ] || fail "両方が main に入っていない"
[ "$(git -C "$W/main" log --oneline origin/main | wc -l)" -eq 3 ] || fail "履歴が直線でない（merge コミットができた）"

# 衝突: 同じ行を 2 つの作業が直す → あとの方は止まって main を壊さない
$AG start three >/dev/null; $AG start four >/dev/null
( cd "$W/wt/gnosis-three" && echo three > guide.txt && git commit -qam three )
( cd "$W/wt/gnosis-four" && echo four > guide.txt && git commit -qam four )
$AG ship three >/dev/null 2>&1 || fail "ship three"
set +e; $AG ship four >"$W/ship4.out" 2>&1; rc=$?; set -e
[ "$rc" -eq 2 ] || fail "衝突したのに終了コード 2 でない（rc=$rc）: $(cat "$W/ship4.out")"
grep -q 'guide' "$W/ship4.out" || fail "衝突しやすい所の案内が出ない"
git -C "$W/main" fetch -q origin; [ "$(git -C "$W/main" show origin/main:guide.txt)" = three ] || fail "衝突したのに main が変わった"
[ -f "$W/reg/four.claim" ] || fail "衝突したのに担当が消えた"
git -C "$W/wt/gnosis-four" status | grep -q 'rebase in progress' && fail "衝突のあと rebase が途中のまま"

# 未反映のまま片づけない
set +e; $AG done four >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -ne 0 ] || fail "未反映なのに --force なしで片づいた"
$AG done four --force >/dev/null || fail "done --force"
echo "agents OK (worktree・担当の宣言と重なりの警告・順番待ちで ff-only 反映・衝突で止まる・未反映は片づけない)"
