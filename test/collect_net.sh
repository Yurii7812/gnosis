#!/bin/sh
# :GnosisCollect を実 Vim から(ローカルの HTTP サーバーに対して)。既定は通信しない。許可した URL だけ。既存のノートは変えない。
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
D=$(mktemp -d "${TMPDIR:-/tmp}/cl.XXXXXX")
trap 'rm -rf "$D"; [ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null || true' EXIT
mkdir -p "$D/v" "$D/www" "$D/home" "$D/gh"
printf -- '# 既存\n' > "$D/v/keep.md"
cat > "$D/www/feed.xml" <<'XML'
<?xml version="1.0"?><rss version="2.0"><channel><title>T</title><item><title>外部の記事</title><link>https://example.com/a</link><guid>g1</guid><description>本文 &lt;b&gt;です&lt;/b&gt;</description></item></channel></rss>
XML
PORT=$(python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()")
( cd "$D/www" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 > "$D/server.log" 2>&1 ) &
SRV=$!
for i in 1 2 3 4 5 6 7 8 9 10; do python3 -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:$PORT/feed.xml',timeout=1)" 2>/dev/null && break; sleep 0.3; done
: > "$D/server.log"
( cd "$D/v" && find . -type f | sort | xargs md5sum > "$D/before.md5" )
REPO="$REPO" D="$D" PORT="$PORT" PYTHONUSERBASE=${PYTHONUSERBASE:-$HOME/.local} HOME="$D/home" GNOSIS_HOME="$D/gh" \
  timeout 120 vim -u NONE -N -es -V1"$D/vim.log" -S "$REPO/test/collect_check.vim" </dev/null >"$D/o.txt" 2>"$D/err" \
  || { cat "$D/errors" "$D/o.txt" "$D/err" "$D/vim.log" >&2; exit 1; }
( cd "$D/v" && md5sum -c --quiet "$D/before.md5" ) || { echo "NG: 既存のノートが変わった" >&2; exit 1; }
[ "$(ls "$D/v/収集" | wc -l)" = 1 ] || { echo "NG: 収集のノートが 1 つではない" >&2; exit 1; }
grep -q 'GET /feed.xml' "$D/server.log" || { echo "NG: 許可した URL に接続していない" >&2; exit 1; }
# 有効にしてからの run は 2 回(2 回目は「増えない」の確認)。有効にする前・許可だけ・disable のあと・確認で「いいえ」のときは 0 回
[ "$(grep -c 'GET' "$D/server.log")" = 2 ] || { echo "NG: 接続が 2 回ではない(想定外のタイミングで通信した)" >&2; exit 1; }
printf '%s\n' 'collect OK'
