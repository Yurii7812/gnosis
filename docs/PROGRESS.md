# 進捗と引き継ぎ

新セッションは `CLAUDE.md` → このファイル → `docs/FEATURES.md` の順に読んで再開する。

## 現在地（2026-10-20 夜）
- ブランチ `feat/master-roadmap`（worktree `~/src/gnosis-master`、`main` 570de52 から）。**main へは未マージ・push 未**（マージは利用者の指示待ち）。
- 全体回帰 `sh test/run.sh` は `exit=0`（run5）。**試験の実行中にファイルを編集すると失敗する**（`checkbox` の試験が `autoload` の編集と重なった実例あり）ので、回している間は編集しない。`web` の Electron E2E（`GNOSIS_RUN_WEB_E2E=1`）も全件通過（別実行）。
- Phase 0 完了。Phase 1: `\M` の差分更新（同一ノート・日記・記録・トピック・リネーム追跡・競合解決・クラッシュ後の再実行・診断）まで。Phase 2: 静的ビュー（番号ナビ・グラフ・カード・テーブル・タイムライン・曼荼羅・検索）は実ブラウザで確認済み。**`\A` 内のタブ・分割・3 モードは未着手（GUI 編集は設計の承認待ち: DECISIONS D006）**。
- 文書: PHILOSOPHY / ARCHITECTURE / ROADMAP / DECISIONS（D001〜D006）/ FEATURES / PROGRESS / DATA_FORMATS / USER_GUIDE / ANDROID_SYNC / HTML_EXPORT。未作成: MIGRATION。

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

- `python/thinking.py` + `:GnosisThink`/`:GnosisThinkCheck`: 思考法 12 種（KM05〜KM16）の雛形と構造検査。MECE は重複・漏れの「疑い」だけ。日本語の語の区切りはひらがなで分ける簡易方式（試験で弱点を発見して修正）。
- `python/vault_backup.py`: バックアップ・検証・復元（UT04 の一部）。Vim コマンド化は未。

- `\A` のライトを Markdown Viewer 拡張（GitHub スタイル）の見え方に（`web/styles.css` の `html.theme-light`、`web/src/app.js`、試験 `web/test/look_e2e.mjs`）。Electron の theme_e2e・view_swap は通過。※ 実機の Brave 拡張との並べての目視比較は未（GitHub スタイルの寸法・色に合わせた）。

- **`\A` の GUI 編集モード（MD01）**: モード切替（ボタン・Alt+E／Alt+V）・書式ボタン（太字・見出し・リスト・チェック・引用・リンク）・元に戻す／やり直す・Enter でのリスト継続・自動保存（Vim の `:write` 経由で保存時の処理が全部走る）・競合（外が書き換えたら上書きせず確認。捨てる側は `.state/conflicts` に退避）・リンクのクリックで開く。実 Electron + 本物の Vim の E2E（`web/test/gui_edit_e2e.mjs`）で、競合検出を無効にすると落ちることも確認。設計は DECISIONS D006（ユーザー指示で簡素化）。
- 未了（MD01 の完了条件）: Vim の状態表示との細かな差（GUI 編集中の Vim の画面は隠す）・複数カーソル・補完。

- **`\A` のタブ・分割・コマンドパレット（MD02・SR10）**: レイアウトの木（`web/src/layout.js`・純関数・単体試験）、画面（`panes.js`）、パレット（`palette-core.js`）、main の IPC（workspace 保存・ビュー用サイトの書き出し `.gnosis/cache/site`・Vim コマンド一覧）、iframe 用の橋 `python/site_assets/bridge.js`。実 Electron の E2E（`web/test/panes_e2e.mjs`）と、橋の実ブラウザ試験を追加。E2E 中に、Vim へ `ESC` と `:` を続けて送ると Meta キーと読まれる問題に気づき、間を置いて送るよう修正（ノーマルモードへの文字の流れ込みを防ぐ）。`web` の既存 E2E は全件通過。

- **グラフ分析 GR01〜GR14**（`python/graph_analysis.py`）: ハブ・中心性・橋渡し・コミュニティ・孤立・到達可能性・循環（不正と正常の区別）・密度・索引の比較・Folgezettel の成長・関係の種類・パターン探索・複数経路。Markdown のレポート、`:GnosisGraphReport/Query/Paths`、静的サイトの「分析」ページ、`\A` の分析ビュー。試験で、経路の組み立ての添字ミス（辺の種類が空になる）を発見して修正。`gnosis_graph.Node` に作成日時を追加。

- **ローカル AI 支援（`python/local_ai.py`・`:GnosisAi`）**: AI01〜AI10・AI13〜AI15・SR04/SR05。純 Python・外部通信なし・ノートを書き換えない。1 万ノートで構築 1.9 秒。試験中に「根拠の行番号が関係ブロック除去でずれる」「見出しだけの段落が質問の根拠の最上位に出る」「重複の閾値が厳しすぎる」を発見して修正。**未了**: AI11（外部情報の収集）・AI12（音声認識。エンジンが無く阻害中）・AI10 の生成（LLM）。

- **バックリンク（`python/backlinks.py`・`:GnosisBacklinks`）**: ED01・ED02。試験の行番号期待値の誤り（実ファイルで確認）を直した。

- **スナップショットの Vim コマンド化（UT04）**: `:GnosisSnapshot` ほか（当初 `:GnosisBackup` と名付けて、既存の暗号 vault 7z バックアップ `:GnosisBackup` を上書きしてしまう退行を起こし、のちに改名して修正）。試験の壊し方が弱く（末尾追記では中身のハッシュが合うので検証 OK が正しい）、中ほどのバイト反転に直した。自動実行は未。

- **時間軸（`python/chrono.py`・`:GnosisCalendar/Day/OnThisDay/PeriodReview/PeriodReviewWrite`）**: TM02・TM10・TM12。既存の `:GnosisReview`（review_reopen）と名前が衝突して上書きしていたのを試験で発見し、`GnosisPeriodReview` に改名した。

- **探索（`python/explore.py`・`:GnosisExplore`）**: XP01/02/03/08/09。読み取り専用。
- 再開用の定期実行（CronCreate・毎時 17/47 分）をセッション内に登録（セッションを閉じると消える・7 日で失効）。

- **PARA・MOC（`python/para_moc.py`）**: KM01・KM03。`\A` の HTML 表示は未（Vim の読み取り画面のみ）。

- **リマインダー（`python/reminders.py`・`:GnosisReminders` ほか）**: TM03・TM05・TM14 の PC 側。状態は `.state/reminders.json`、ノートは書き換えない。実際のデスクトップ通知（notify-send）は注入した関数で試験し、実表示は未確認。

- **時間・習慣・ライフログ（`python/tracker.py`）**: TM06/07/08/11 の PC 側。書くのは 記録.md への追記だけ。試験の時刻依存（現在時刻より未来の開始・今年以外の集計）を 2 回直した（実装は正しかった）。

- **分割・統計・比較（`split_notes.py` `note_tools.py`）**: ED06/09/17。試験で実バグを 3 件発見・修正（取り消し済みの控え `.done` を再び取り消せてしまう／タスクの `[x]` が語に数えられる／題だけのノートが空と判定されない）。

- **読書・学習（`python/reading.py`）**: LR01/07/09/10/11/12/13/14。試験で Vim 側の不具合を 1 件発見・修正（`-nargs=?` に `<q-args>` を渡すと引数なしでも空文字が 1 つ入り、一覧のつもりが使い方エラーになる）。LR08（PDF 注釈）は未。

- **退行の修正**: 先に追加した `:GnosisBackup`（tar.gz スナップショット）が、既存の `:GnosisBackup`（暗号化 vault の 7z バックアップ）を上書きしていた。`:GnosisSnapshot` 系に改名して既存を復元。同じ種類の衝突（`:GnosisReview`）は既に 1 回起きていたため、`test/check_commands.py`（plugin 全体のコマンド名の重複検査）を回帰に追加。既存の暗号 vault バックアップ自体の試験は元から無い（未）。

- **ブックマーク・履歴・再提示・トレイル（`python/nav.py` と Vim の履歴）**: SR11〜13・TM15・XP04・XP13・XP16。試験で Vim スクリプトの実バグを発見・修正: `list[-n:]` は要素数が n 未満だと**空リスト**になる（履歴の保存・トレイル保存が空になる）。同じ書き方の既存コード（APK ビルド失敗時の出力表示）も修正。

- **全体回帰 run7（`sh test/run.sh`）は exit=0**（2026-10-21。Electron E2E は未実行）。履歴機能が全 vault に `.state/history.json` を書くため、先行の読み取り専用の試験が「ファイル一覧が不変」を厳密に比べて落ちた→ノート以外（`.state`・`*.un~`）を除いて比べるよう直した（ノートの書き換えではない）。

- **安全なリネーム（`python/rename_note.py`・`:GnosisRename`）**: UT03。従来の `:GnosisRename`（= `:Rename`: saveas + 削除）は参照を更新せずリンクが壊れていたため、参照更新つきの安全版に**置き換えた**（素の `:Rename` は残す）。

- **互換性検査・性能診断（`python/diagnose.py`）**: UT08・UT12。診断が実 vault に索引を書かないよう、シンボリックリンクの一時フォルダで索引を測る。

- **編集の補助（ED03〜05・08・12〜16・18）**: Python 4 本（calc/blocks/transclude/templates）と Vim 内の機能。試験で実バグを 5 件発見・修正: 折りたたみのレベルを `=` にすると引用などの後ろの行が取り込まれ続ける／`:GnosisFold off` で manual に戻しても折りたたみが残り `yy` が閉じた折りたたみ全体をコピーする／補完が題でなくファイル名だけで絞っていた／テンプレート挿入が余計な空行を足す／ブロック ID 付与後にカーソルが飛ぶ。

- **追加ビュー 16 種（VW05〜VW24、`export_views2.py`・`site_assets/views2*.js`）**: 静的サイトに階層ツリー・マインドマップ・Sunburst・Treemap・隣接行列・Sankey・比較・孤立/未参照/未索引・カンバン・成長・川・地図・3D・スライド・ホワイトボード・ギャラリーを追加。核の純関数は node 単体試験、書き出しは Python 試験、描画は実 Electron で操作する E2E、さらに headless Chromium のスクリーンショットを目で確認。発見・修正した実バグ: (1) `md_html.inline` がリンクの表示文字にコード・画像を含むと IndexError → **サイトの書き出し全体が止まる**（退避表を共有して修正）／(2) スライドでサブフォルダのノートの相対パス（画像・リンク）が壊れる（書き出し時に補正）／(3) 3D の配置が枠からはみ出し手前だけ極端に大きい（重心と半径を正規化）／(4) マインドマップの深さの意味が他のビューと不一致。

- **実験ビュー 7 種と仮説実験室（XP05/06/07/10/11/12/14/15）**: `hypotheses.py`（仮説の解析・目安・対戦）、静的サイトに博物館・記憶の宮殿・迷路・成長アニメーション・アイデア合成器・仮説実験室・思考の対戦。核（種から決まる擬似乱数・迷路の規則・出題・コマ割り）は node 単体試験、23 ページを実ブラウザで操作する E2E。試験で見つけた設計の問題: 記憶の宮殿の選択肢を置いたノートだけから作ると 2 件で 2 択になる→全ノートから選ぶよう変更。**まだ `\A` への埋め込みはしていない**。

- **本への書き出し（`python/export_doc.py`・`:GnosisExportBook`）**: UT07。EPUB・単一 HTML・PDF。試験で実バグを 1 件発見・修正（章の見出しと本文先頭の `# 題` が二重に出る）。EPUB は実リーダ・EPUBCheck では未確認（構造と XML の妥当性までを自前で確認）。

- **全体回帰 run8（`sh test/run.sh`）は exit=0**（2026-10-21。ビュー 23 ページ・本の書き出し・`md_html` の修正を含む。Electron の `\A` E2E は未実行）。`docs/MIGRATION.md` を追加。

- **設定プリセット（`:GnosisPreset`）**: UT10。既存の `:GnosisSettings`（設定画面）と名前が衝突しかけたが、`check_commands.py` が即座に検出したので改名した。

- **Git 連携とバックアップ対象の選別（`python/gitops.py`・`:GnosisGit`・`.gnosis/backup-ignore`）**: UT05。試験で実バグを 1 件発見・修正（読めない除外ファイルでバックアップ全体が例外で止まる）。本物の一時リポジトリで試験（変更の種類・名前変更・日本語名・ドット始まりの除外・危険な引数の拒否・コミットの範囲）。

## 次の具体的タスク
1. （完了）ノート側 source ID `capture_id:` とリネーム追跡。残: 旧ノート（`capture_id` 無し）への後付け（`capture_id` を state から補う移行コマンド・dry-run 付き）。
2. （完了）日記・時系列記録・まとめるトピックへの埋め込みの差分更新。残: トピック側の画像・つながり行の変更、スマホでトピックを移した埋め込みメモ。
3. 競合の解決操作（`:GnosisCaptureConflicts` の一覧／差分／どちらを採るか）。
4. 取り込みのジャーナル（クラッシュ後の再実行）、画像 hash。
5. Phase 1 の残り（UT 系: 壊れたリンク検査・バックアップ等の「要確認」の監査）→ Phase 2。

## 再現
`cd ~/src/gnosis-master && export TMPDIR=$HOME/Desktop/test GNOSIS_HOME=$(mktemp -d)` のうえで各試験を個別実行（上記の通り）。
