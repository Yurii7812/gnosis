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
python3 "$REPO/python/test_branch_ops.py"
python3 "$REPO/python/test_context_ops.py"

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

# 保存後の非同期 Python sync と、編集中ノートの上書き競合
sh "$REPO/test/autosync_dirty_guard_net.sh"

# \S（選択なし）のよみ順ソート
sh "$REPO/test/sort_yomi_net.sh"

# \F の GUI（日記として登録）。tkinter・Pillow・xvfb があるときだけ
if command -v xvfb-run >/dev/null 2>&1; then xvfb-run -a python3 "$REPO/python/test_folgezettel_scan_diary.py"; fi

# 紙の日記（題がデジタル日記と同じ形）を \d の機能が拾わない
sh "$REPO/test/diary_paper_net.sh"

# 日記の初回作成・Indexリンク・年越し・3年目の階層
sh "$REPO/test/diary_hierarchy_net.sh"

# Branch（b モード: ChildBranch / ParentBranch・親は最大 1 つ・循環と自己参照の拒否・同期後の維持）
sh "$REPO/test/branch_net.sh"

# Context（本文冒頭の Context: ブロック）と w モード・旧 ### Context の保護・同期後の維持
sh "$REPO/test/context_net.sh"

# テーマ（配色）: 通常の Vim の標準配色・\A の白い既定・独立した設定・カスタムテーマ編集のリアルタイムプレビュー・取り消し/保存
sh "$REPO/test/theme_net.sh"

# 複数ウィンドウで vault を使う: 暗号化 vault のロック管理（偽 gocryptfs）・異常終了した登録の掃除・同時編集の上書き防止
sh "$REPO/test/session_net.sh"

# 同期の冪等性（試験用の小さな vault）
sh "$REPO/test/sync_net.sh"

# リンク操作（c → Enter / t / o・表示名・zk → g・グループの \S）
sh "$REPO/test/link_ops_net.sh"

# vault の登録簿・vault ごとの設定・移行・テーマ・ガイドの言語
sh "$REPO/test/vault_settings_net.sh"

# Terminal: Chnoubis の図案・GNOSIS点描ロゴ・リンク省略・配色（コントラスト）
sh "$REPO/test/terminal_visual_net.sh"

# 操作ガイドの所属関係（### Group / BackLink）を更新・同期・言語切り替えで失わない
sh "$REPO/test/guide_relations_net.sh"

# 文字サイズ（terminal.json の保存・ランチャーが読む値・端末ごとの説明）
sh "$REPO/test/termfont_net.sh"

# Vim の起動画面（pty）
sh "$REPO/test/start_screen_net.sh"

# インストーラー（一時 HOME・空白/日本語/' を含むパス・ふだんの Vim は不変）
sh "$REPO/test/install_net.sh"

# インストーラーの更新（古い版の取り込み・未コミットの変更は残す・別の clone への切り替え）
sh "$REPO/test/install_update_net.sh"

# --- 擬似端末（pty）で本物の Vim を動かす試験（pyte が要る。無ければ省略） ---
# 矢印キー: `:` の履歴・ノーマル/挿入/ビジュアル・起動画面・設定画面・作業タブ（\q）・fzf の検索画面
python3 "$REPO/test/keys_pty_check.py"
# カスタムテーマ編集画面（プレビューの色を画面の 1 文字ごとの色で確かめる）
python3 "$REPO/test/theme_pty_check.py"
# 新規ノート（zn → Enter）の本文入力位置（Context の後ろの空行に、すぐ書ける）
python3 "$REPO/test/context_pty_check.py"
# 本物の gocryptfs の暗号化 vault を複数のウィンドウで使う（gocryptfs / fusermount3 / /dev/fuse が無ければ省略）
python3 "$REPO/test/session_real_check.py"
