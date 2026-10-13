#!/bin/sh
# 分割リファクタ用の回帰網: Vim の公開APIが変わっていないことを確認する。
# 使い方: test/run.sh
set -e
# 試験の一時フォルダはデスクトップの test（本物の vault には触らない）
TMPDIR=${TMPDIR:-$HOME/Desktop/test}
mkdir -p "$TMPDIR"
export TMPDIR
# Gnosis ホーム（vault の登録簿など）も試験用の一時フォルダにする（本物の登録簿に触らない）
GNOSIS_HOME=${GNOSIS_HOME:-$(mktemp -d)}
export GNOSIS_HOME
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GOLDEN="$REPO/test/api_public.txt"
OUT=$(mktemp)
ERR=$(mktemp)
trap 'rm -f "$OUT" "$ERR"' EXIT

python3 "$REPO/test/vim_static_check.py"
python3 "$REPO/test/check_guide.py"
python3 "$REPO/test/i18n_check.py"
python3 "$REPO/python/test_sort_yomi.py"
python3 "$REPO/python/test_paper_pkm.py"

timeout 60 vim -u "$REPO/vimrc_gnosis" -es \
  -c "let g:gnosis_api_out='$OUT'" \
  -c "source $REPO/test/vim_api_check.vim" \
  -c 'qa!' </dev/null 2>"$ERR" || true

if [ ! -s "$OUT" ]; then
  echo "NG: Vim から関数一覧を得られなかった（ロード失敗の疑い）" >&2
  cat "$ERR" >&2 || true
  exit 1
fi
if [ -s "$ERR" ]; then
  echo "注意: Vim が stderr に出力した:" >&2
  cat "$ERR" >&2
fi
if diff -u "$GOLDEN" "$OUT"; then
  echo "Vim API OK ($(wc -l < "$OUT") funcs)"
else
  echo "NG: 公開APIが変化した（上記の差分）" >&2
  exit 1
fi

# 保存タイミング（Esc 即保存・gm 前保存・\tD 前保存など）の回帰網
sh "$REPO/test/autosave_net.sh"

# \S（選択なし）のよみ順ソート
sh "$REPO/test/sort_yomi_net.sh"

# \F の GUI（日記として登録）。tkinter・Pillow・xvfb があるときだけ
if command -v xvfb-run >/dev/null 2>&1; then xvfb-run -a python3 "$REPO/python/test_folgezettel_scan_diary.py"; fi

# 紙の日記（題がデジタル日記と同じ形）を \d の機能が拾わない
sh "$REPO/test/diary_paper_net.sh"

# 同期の冪等性（試験用の小さな vault）
sh "$REPO/test/sync_net.sh"

# リンク操作（c → Enter / t / o・表示名・zk → g・グループの \S）
sh "$REPO/test/link_ops_net.sh"

# vault の登録簿・vault ごとの設定・移行・テーマ・ガイドの言語
sh "$REPO/test/vault_settings_net.sh"

# Terminal: Chnoubis縦横補正版・GNOSIS点描ロゴ・リンク省略・色
sh "$REPO/test/terminal_visual_net.sh"

# Vim の起動画面（pty）
sh "$REPO/test/start_screen_net.sh"

# インストーラー（一時 HOME・空白/日本語/' を含むパス・ふだんの Vim は不変）
sh "$REPO/test/install_net.sh"
