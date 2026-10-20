# 進捗と引き継ぎ

新セッションは `CLAUDE.md` → このファイル → `docs/FEATURES.md` の順に読んで再開する。

## 現在地（2026-10-20）
- ブランチ `feat/master-roadmap`（worktree `~/src/gnosis-master`、`main` 570de52 から）。main へは未マージ・push 未。
- **Phase 0 実施中**。完了: 原本の保存、CLAUDE.md、PHILOSOPHY / ARCHITECTURE / ROADMAP / DECISIONS / FEATURES（165 機能 + 追加 ID）、テスト基準線の取得。
- 未作成の文書（必要な Phase で作る）: DATA_FORMATS / MIGRATION / USER_GUIDE / ANDROID_SYNC / HTML_EXPORT。

## テスト基準線（main 570de52・個別実行、2026-10-20）
- 実行したもの: `test/vim_static_check.py` `check_guide.py` `i18n_check.py`、`python/test_*.py` 全部、`test/*_net.sh` 全部。**63 本中 60 本成功・3 本失敗**。
- 失敗（main で元から。今回の変更が原因ではない）:
  1. `python/test_paper_pkm.py` — 関係ブロックが `### Group` 節から先頭の `Group:` ブロックへ変わった（5dbf429）のに期待値が古い。一部（Folgezettel-Index・日記グループ・月グループ）は直したが、あと 8 件（Index-write の Group、画像と節の間の空行 4 件、日記グループ、キーワード間の空行）が古い期待値のまま。**製品の不具合ではなくテストの追随漏れ**（要・1 件ずつ現行仕様に合わせる）。
  2. `test/related_net.sh` — `related_check.vim:114` が古い表示文言 `r=Related` を期待。
  3. `test/requests_1020_net.sh` — 「i・\L・g・マージの流れ」。原因未調査。
- `test/run.sh` は `set -e` なので 1 に当たった時点で止まり、以降を実行しない（それが分かりにくい原因）。
- **未実行**: `web` の Electron E2E（`npm test`・xvfb 要）、Android Gradle、Windows／macOS 実機。実行するまで「通った」と書かない。
- CI（`.github/workflows/gnosis-regression.yml`）は一部の試験しか回していない。

## 現状監査の要点
- `\M`（`python/capture_import.py` ＋ `autoload/gnosis.vim`）: id 単位で重複防止（`.state/capture_imported.json`）。本文を書き直すと**別版ノートを作る**（原本 §7.3 と衝突・Phase 1 の最優先）。トピック変更は同一ノートへ反映する。base 保存・3-way merge・日記埋め込みの境界は無い。
- `\A`: `web/`。読み取り専用の MD 描画＋端末。閲覧専用モード（Alt+V）はある。タブ・分割・GUI 編集・番号ナビ・コマンドパレットは無い。
- グラフ・カード・曼荼羅・カンバン・FTS・XMP・ポモドーロ・Cornell 等は grep でヒットなし（未実装）。

## 次の具体的タスク
1. 失敗 3 本の原因を直す（テスト追随: paper_pkm 8 件・related 文言／requests_1020 は原因調査）。直ったら基準線を更新。
2. `\M` を精密監査: `capture_import.py` の plan／state／別版を作る分岐、`gnosis#capture_import`（Vim 側）、`test/capture_import_*`。結果を DECISIONS（state 版 2・source ID・base 保存）に書く。
3. 3-way merge の純関数（Python 単体試験）→ 取り込みへ接続 → 原本 §7.3 の必須 E2E を 1 本ずつ追加。

## 再現
`cd ~/src/gnosis-master && export TMPDIR=$HOME/Desktop/test GNOSIS_HOME=$(mktemp -d)` のうえで各試験を個別実行（上記の通り）。
