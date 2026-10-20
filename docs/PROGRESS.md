# 進捗と引き継ぎ

新セッションは `CLAUDE.md` → このファイル → `docs/FEATURES.md` の順に読んで再開する。

## 現在地（2026-10-20）
- ブランチ `feat/master-roadmap`（worktree `~/src/gnosis-master`、`main` 570de52 から）。main へは未マージ・push 未。
- **Phase 0 実施中**。完了: 原本の保存、CLAUDE.md、PHILOSOPHY / ARCHITECTURE / ROADMAP / DECISIONS / FEATURES（165 機能 + 追加 ID）、テスト基準線の取得。
- 未作成の文書（必要な Phase で作る）: DATA_FORMATS / MIGRATION / USER_GUIDE / ANDROID_SYNC / HTML_EXPORT。

## テスト基準線
- 2026-10-20 時点、`sh test/run.sh` が**最後まで通る**（Electron E2E・Android Gradle・Windows/macOS 実機は未実行）。
- 取得時（main 570de52）の失敗は、いずれも**仕様変更への試験の追随漏れ**で、実装と現行仕様を確認してから試験側を直した:
  - `test_paper_pkm.py`: 関係が `### Group` 節→先頭の `Group:` ブロックになった（5dbf429）。
  - `related_check.vim`: **試験は正しく、製品の不具合だった**。英語の `\l` の短縮案内が、`a=自分Ctx` の追加で 80 桁を超え、末尾の `a=… r=Related` が切れていた。`i18n/en.json` の短縮文言を直した（試験は元のまま）。※最初「未マージ枝の機能」と誤って説明していたのを訂正。
  - `context_pty_check.py`: `zn`+Enter は ParentBranch: だけを付ける（旧: Context: も）。
  - `requests_1020_net.sh`: 単独実行では通る（取得時は負荷による一時失敗の疑い）。再発したら調査。
- **`web` の Electron E2E（`cd web && npm test`、約 10 分）は、現行仕様に合わせて全件通る（2026-10-20）**。main の時点では多数失敗していた（仕様変更への追随漏れ）。実際の出力と実装の定義で確認してから直した: `### Group` 節→`Group:` ブロック、`\l` の案内の短縮、`zn` がグループの上では登録方法→表示名→よみの 3 つを聞く、`zk → g`（リンク 1 本をグループに）の廃止、`zn → c` の意味（リンク先に今のノートを Context）、既定テーマがダーク `#22272E`・ライトが `#FAFAFA`、色の編集が 8 色。`web/node_modules` は ~/gnosis/web への読み取り専用リンクで使う（ワークツリーの `info/exclude` に登録）。`test/run.sh` からは `GNOSIS_RUN_WEB_E2E=1` のときだけ実行。
- `test/run.sh` は `set -e` で最初の失敗で止まる。全体は約 10 分かかる。作業中は関係する試験だけ回し、区切りで全体を回す。
- CI（`.github/workflows/gnosis-regression.yml`）は一部の試験しか回さない。

## 現状監査の要点
- `\M`（`python/capture_import.py` ＋ `autoload/gnosis.vim`）: id 単位で重複防止（`.state/capture_imported.json`）。本文を書き直すと**別版ノートを作る**（原本 §7.3 と衝突・Phase 1 の最優先）。トピック変更は同一ノートへ反映する。base 保存・3-way merge・日記埋め込みの境界は無い。
- `\A`: `web/`。読み取り専用の MD 描画＋端末。閲覧専用モード（Alt+V）はある。タブ・分割・GUI 編集・番号ナビ・コマンドパレットは無い。
- グラフ・カード・曼荼羅・カンバン・FTS・XMP・ポモドーロ・Cornell 等は grep でヒットなし（未実装）。

## 完了（このブランチ）
- Phase 0 文書一式。
- **`\M` 差分更新（M01/M02 の一部）**: `python/capture_merge.py`（3-way merge・競合は記録のみ）、`capture_import.py` の `plan` に `merge`、`merge` CLI、`gnosis#capture_import` の分岐、i18n。試験: `test_capture_merge.py` `test_capture_import.py`（旧「別版を作る」を新仕様に変更）`capture_merge_net.sh` `capture_topics_check.vim`（同）。詳細・未実装は `docs/ANDROID_SYNC.md`。

## 追加済みの共通層
- `python/gnosis_graph.py`（読み取り専用）: 型付き・有向・多重のグラフ（group / parent_branch / branch_group / child_branch / context / related / backlink / link / folgezettel）、壊れたリンク、孤立、最短経路（種類で絞れる）、到達可能性、連結成分、Folgezettel の見取り図（親・兄弟・前後・子・パンくず・自然順の前後・空き番号の区別）と問題検出（重複 ID・欠けた祖先）。CLI: `check` `graph` `path` `fz`。試験 `python/test_gnosis_graph.py`。
  計測（合成 vault 1 万ノート・約 4 万辺、2026-10-20）: `check` 約 5 秒、`path` 約 5 秒（ほぼ `note_format_v2` のパース時間）。遅くなったらパース結果の差分キャッシュを共有する。
- 台帳への効果: UT01（壊れたリンク）の検出部、FZ04、GR05/GR06 の土台、VW01/VW02/VW21 のデータ源。UI・Vim コマンド化はまだ。

- `python/tasks.py` + `:GnosisAgenda`: Markdown タスクの解析・集約・完了（繰り返し・依存・開始日）。試験 `test_tasks.py` `test/agenda_net.sh`。書式は DECISIONS D004。Android 側（Kotlin）はまだ共有していない（同じ書式をアプリで解析するのは Phase 5）。

- `python/md_html.py` + `python/export_site.py` + `:GnosisExportSite`: 静的サイト／Markdown 番号表の書き出し（詳細 `docs/HTML_EXPORT.md`）。書き出し試験でプライバシーの実バグ（非公開ノートへのリンクが残る）を見つけて修正済み。
- `:GnosisCheck`（UT01 の検出）・`:GnosisAgenda`（TM01）。

- `python/mandala.py` + `:GnosisMandalaNew/Cell/Sync`: 9×9 曼荼羅（保存は `mandala: true` のふつうの Markdown ノートの表。DECISIONS D005）。静的サイトでは格子表示。

- 静的サイトのグラフ表示（全体／ローカル）: `python/site_assets/` + `export_site.py`。`file://` で動く（データは script で読む）。実ブラウザ（Firefox headless）で目視確認、配置の純関数は node 試験。

- 静的サイトの **Folgezettel 番号ナビ**（`fznav.html`）と、書き出したビューを本物のブラウザで操作する E2E（`web/test/site_views_e2e.mjs`。Electron を xvfb でヘッドレスブラウザとして使用）。E2E で実際の不具合を 2 件発見・修正: グラフの種類を全部外しても辺が出る（`[]` を全種類と解釈）、ハッシュ変更（戻る・直接リンク）に追従しない。

- 静的サイトのカード・テーブル・タイムライン（`views.js`/`viewscore.js`）と、その実ブラウザ E2E。核の純関数テストで実バグを 1 件発見・修正（番号なしが降順で先頭に来る）。

- `python/vault_index.py` + `:GnosisQuery*`: 構造化検索の派生インデックス（SR02/03/06/07/08/09 ほか。クエリの書き方は `:GnosisGuide` と `docs/USER_GUIDE.md`）。試験で実バグを 2 件発見・修正（保存検索の昇格が保存名で検索し直す、ヒット行がファイルの行番号とずれる）。
- `test/requests_1020_net.sh` の間欠失敗（約 3/8）の原因は、試験が保存後の非同期自動同期ジョブの完了を待たない競合だった（製品側の確認ダイアログは正しい）。待ちを足して 12/12 通過。

- `python/srs.py` + `:GnosisSrs`/`:GnosisSrsStats`: 間隔反復・フラッシュカード・穴埋め・ランダム復習（SM-2 は原典どおり: 3 未満で ease を変えない）。

## 次の具体的タスク
1. （完了）ノート側 source ID `capture_id:` とリネーム追跡。残: 旧ノート（`capture_id` 無し）への後付け（`capture_id` を state から補う移行コマンド・dry-run 付き）。
2. （完了）日記・時系列記録・まとめるトピックへの埋め込みの差分更新。残: トピック側の画像・つながり行の変更、スマホでトピックを移した埋め込みメモ。
3. 競合の解決操作（`:GnosisCaptureConflicts` の一覧／差分／どちらを採るか）。
4. 取り込みのジャーナル（クラッシュ後の再実行）、画像 hash。
5. Phase 1 の残り（UT 系: 壊れたリンク検査・バックアップ等の「要確認」の監査）→ Phase 2。

## 再現
`cd ~/src/gnosis-master && export TMPDIR=$HOME/Desktop/test GNOSIS_HOME=$(mktemp -d)` のうえで各試験を個別実行（上記の通り）。
