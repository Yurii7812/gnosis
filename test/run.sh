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
python3 "$REPO/test/check_commands.py"
python3 "$REPO/python/test_sort_yomi.py"
python3 "$REPO/python/test_paper_pkm.py"
python3 "$REPO/python/test_branch_ops.py"
python3 "$REPO/python/test_context_ops.py"
python3 "$REPO/python/test_group_removal.py"
python3 "$REPO/python/test_group_semantics.py"
python3 "$REPO/python/test_section_colon.py"
python3 "$REPO/python/test_paper_branchgroup.py"
python3 "$REPO/python/test_theme_palette.py"
python3 "$REPO/python/test_orphans.py"
python3 "$REPO/python/test_folgezettel.py"
python3 "$REPO/python/test_capture_import.py"
python3 "$REPO/python/test_capture_merge.py"
python3 "$REPO/python/test_capture_diag.py"
python3 "$REPO/python/test_gnosis_graph.py"
python3 "$REPO/python/test_graph_analysis.py"
python3 "$REPO/python/test_tasks.py"
python3 "$REPO/python/test_app_model.py"
python3 "$REPO/python/test_vault_index.py"
python3 "$REPO/python/test_srs.py"
python3 "$REPO/python/test_local_ai.py"
python3 "$REPO/python/test_backlinks.py"
python3 "$REPO/python/test_chrono.py"
python3 "$REPO/python/test_explore.py"
python3 "$REPO/python/test_para_moc.py"
python3 "$REPO/python/test_reminders.py"
python3 "$REPO/python/test_tracker.py"
python3 "$REPO/python/test_split_notes.py"
python3 "$REPO/python/test_note_tools.py"
python3 "$REPO/python/test_reading.py"
python3 "$REPO/python/test_nav.py"
python3 "$REPO/python/test_rename_note.py"
python3 "$REPO/python/test_diagnose.py"
python3 "$REPO/python/test_hypotheses.py"
python3 "$REPO/python/test_calc.py"
python3 "$REPO/python/test_blocks.py"
python3 "$REPO/python/test_transclude.py"
python3 "$REPO/python/test_templates.py"
python3 "$REPO/python/test_vault_backup.py"
python3 "$REPO/python/test_thinking.py"
python3 "$REPO/python/test_md_html.py"
python3 "$REPO/python/test_mandala.py"
if command -v node >/dev/null 2>&1; then
  node "$REPO/python/test_graphcore.mjs"
  node "$REPO/python/test_fznav.mjs"
  node "$REPO/python/test_viewscore.mjs"
  node "$REPO/python/test_views2core.mjs"
else echo "graphcore / fznav: node が無いので省略"; fi
python3 "$REPO/python/test_export_site.py"
python3 "$REPO/python/test_export_views2.py"
python3 "$REPO/python/test_export_doc.py"
python3 "$REPO/python/test_gitops.py"
python3 "$REPO/python/test_chain.py"
python3 "$REPO/python/test_import_notes.py"
python3 "$REPO/python/test_collector.py"
python3 "$REPO/python/test_merge_notes.py"
python3 "$REPO/python/test_diary_tree.py"

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

# 日記と Group:（節が増えない・Group: は先頭・二重の節は 1 つにまとまる）
sh "$REPO/test/diary_group_net.sh"

# 保存後の非同期 Python sync と、編集中ノートの上書き競合
sh "$REPO/test/autosync_dirty_guard_net.sh"

# \S（選択なし）のよみ順ソート
sh "$REPO/test/sort_yomi_net.sh"

# グループへの追加は名前とよみの確認画面を通って必ず並ぶ（za・手で貼る・行を消す・Q・:GnosisYomiReview）
sh "$REPO/test/group_review_net.sh"
sh "$REPO/test/requests_7_net.sh"
sh "$REPO/test/requests_8_net.sh"

# i（行の中）・\L の b / c・\l → g（分岐したグループ・空のグループの空行）・\l → m（マージと取り消し）
sh "$REPO/test/requests_1020_net.sh"
sh "$REPO/test/requests_1020b_net.sh"

# - [ ] の行で Enter すると次の行にも - [ ] を作る
sh "$REPO/test/checkbox_net.sh"

# スマホのメモの取り込み
sh "$REPO/test/capture_import_net.sh"
sh "$REPO/test/capture_merge_net.sh"
sh "$REPO/test/capture_diary_net.sh"
sh "$REPO/test/capture_embed_net.sh"
sh "$REPO/test/agenda_net.sh"
sh "$REPO/test/check_vault_net.sh"
sh "$REPO/test/graph_net.sh"
sh "$REPO/test/query_net.sh"
sh "$REPO/test/srs_net.sh"
sh "$REPO/test/ai_net.sh"
sh "$REPO/test/snapshot_net.sh"
sh "$REPO/test/chrono_net.sh"
sh "$REPO/test/explore_net.sh"
sh "$REPO/test/para_net.sh"
sh "$REPO/test/remind_net.sh"
sh "$REPO/test/tracker_net.sh"
sh "$REPO/test/split_net.sh"
sh "$REPO/test/reading_net.sh"
sh "$REPO/test/nav_net.sh"
sh "$REPO/test/rename_net.sh"
sh "$REPO/test/diagnose_net.sh"
sh "$REPO/test/edit_net.sh"
sh "$REPO/test/hyp_net.sh"
sh "$REPO/test/book_net.sh"
sh "$REPO/test/preset_net.sh"
sh "$REPO/test/git_net.sh"
sh "$REPO/test/restore_net.sh"
sh "$REPO/test/phone_agenda_net.sh"
python3 "$REPO/python/test_pdf_notes.py"
sh "$REPO/test/pdf_net.sh"
python3 "$REPO/python/test_versions.py"
sh "$REPO/test/versions_net.sh"
python3 "$REPO/python/test_bulk.py"
sh "$REPO/test/bulk_net.sh"
python3 "$REPO/python/test_dedupe.py"
sh "$REPO/test/dedupe_net.sh"
sh "$REPO/test/seal_net.sh"
python3 "$REPO/python/test_agenda_push.py"
python3 "$REPO/python/test_agenda_pull.py"
# Android アプリの純粋なロジック（メモ・予定）の単体試験。JDK と SDK があるときだけ（実機・通知・ウィジェットの実表示は対象外）
if [ -x "$HOME/Android/jdk/bin/java" ] && [ -d "$HOME/Android/Sdk" ]; then
  (cd "$REPO/android" && JAVA_HOME="$HOME/Android/jdk" ANDROID_HOME="$HOME/Android/Sdk" ./gradlew --offline test -q)
else echo "Android: JDK/SDK が無いので Gradle の単体試験は省略"; fi
sh "$REPO/test/chain_net.sh"
sh "$REPO/test/import_net.sh"
sh "$REPO/test/collect_net.sh"
sh "$REPO/test/think_net.sh"
sh "$REPO/test/export_site_net.sh"
sh "$REPO/test/mandala_net.sh"
sh "$REPO/test/capture_topics_net.sh"

# 時刻の挿入（Ctrl-T）と時刻モード（\T）
sh "$REPO/test/time_mode_net.sh"

# 時系列記録（:GnosisRecordNew・\R・:GnosisRecordMigrate）
sh "$REPO/test/record_net.sh"
sh "$REPO/test/heading_links_net.sh"

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

# Linux / macOS の 1 行インストーラー（空の環境から 1 回・更新・未コミットの変更を消さない・git が無いとき）
sh "$REPO/test/bootstrap_net.sh"

# インストーラーの更新（古い版の取り込み・未コミットの変更は残す・別の clone への切り替え）
sh "$REPO/test/install_update_net.sh"

# --- 擬似端末（pty）で本物の Vim を動かす試験（pyte が要る。無ければ省略） ---
# 矢印キー: `:` の履歴・ノーマル/挿入/ビジュアル・起動画面・設定画面・作業タブ（\q）・fzf の検索画面
python3 "$REPO/test/keys_pty_check.py"
# カスタムテーマ編集画面（プレビューの色を画面の 1 文字ごとの色で確かめる）
python3 "$REPO/test/theme_pty_check.py"
# 新規ノート（zn → Enter）の本文入力位置（Context の後ろの空行に、すぐ書ける）
python3 "$REPO/test/context_pty_check.py"
python3 "$REPO/test/link_source_pty_check.py"
# 本物の gocryptfs の暗号化 vault を複数のウィンドウで使う（gocryptfs / fusermount3 / /dev/fuse が無ければ省略）
python3 "$REPO/test/session_real_check.py"

# 書き出した静的サイトのビュー（番号ナビ・グラフ・検索・曼荼羅）を本物のブラウザ（Electron の Chromium・xvfb）で操作する試験
# （web/node_modules と xvfb-run が無ければ省略する）
node "$REPO/web/test/site_views_e2e.mjs"
node "$REPO/web/test/views2_e2e.mjs"

# Electron アプリ（\A）全体の E2E（実 Vim・約 10 分）。普段は省略し、GNOSIS_RUN_WEB_E2E=1 のときだけ実行する
if [ "${GNOSIS_RUN_WEB_E2E:-}" = "1" ]; then
  (cd "$REPO/web" && npm test && node test/gui_edit_e2e.mjs)
fi

# `\A` のライトの見え方（Markdown Viewer 拡張＝GitHub スタイル）と、ダークが変わらないこと（chromium が無ければ省略）
node "$REPO/web/test/look_e2e.mjs"

# `\A` の GUI 編集モード: 純関数（書式・履歴・ノートの読み書き）の単体試験。実 Electron の E2E は GNOSIS_RUN_WEB_E2E=1 で web/test/gui_edit_e2e.mjs
node "$REPO/web/test/editcmds_test.mjs"
node "$REPO/web/test/noteio_test.cjs"
# `\A` のタブ配置と追加ビュー（23 種）の純関数の試験（追加ビューの一覧が export_views2.py と一致するか）
node "$REPO/web/test/layout_test.mjs"
node "$REPO/web/test/extra_views_test.mjs"
# `\A` の曼荼羅・キャンバスの保存形式（表の差し替え・3-way・キャンバスのブロック）の純関数の試験
node "$REPO/web/test/workbench_core_test.mjs"
