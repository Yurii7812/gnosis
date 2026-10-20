# 機能台帳（FEATURES）

> 原本: `Gnosis_Claude_Implementation_Master_Prompt.md` §5・§6・§7。**省略・格下げ禁止**。状態の値は 未実装／調査中／設計済／実装中／動作検証中／実装済／阻害中。
> 「要確認」は既存実装の疑いがあるが、コード・テストで未検証という意味（実装済みとは数えない）。

| ID | 機能 | 説明 | 対象 | 状態 | Phase | 実体・根拠 | 依存 |
|---|---|---|---|---|---|---|---|
| KM01 | PARA | Projects / Areas / Resources / Archives を**仮想ビュー**として提供。既存ノートの物理移動・強制分類をしない。 | `\A` HTML + Markdown | 未実装 | 6 |  | P2 View API |
| KM02 | Zettelkasten | 原子的ノート、リンク、Folgezettelの作成・成長、紙との連携。 | `\A` HTML + Markdown | 要確認 | 6 | `zn`/`zk`・Folgezettel（python/folgezettel*.py） | P2 View API |
| KM03 | MOC/索引案 | Map of Contentの表示、ノート群から索引案生成（既存索引は勝手に改変しない）。 | `\A` HTML + Markdown | 未実装 | 6 |  | P2 View API |
| KM04 | 曼荼羅ノート | 9×9=81マスの思考展開。各マスからMarkdownノートや別の81マス曼荼羅を開く。曼荼羅そのものの表示はHTML中心、ノートは実際のMarkdownを開く。81マスの構造デー | `\A` HTML + Markdown | 動作検証中（Markdown 表の保存・マスから実ノート／別の曼荼羅・主題副題の同期・静的サイトの 9×9 格子。`\A` 内の対話表示は未） | 3 | `python/mandala.py` `test_mandala.py` `test/mandala_net.sh` | P2 View API |
| KM05 | Cornell Notes | ノート本文、質問欄、要約欄の編集・出力。 | `\A` HTML + Markdown | 動作検証中（Cornell: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| KM06 | Feynmanモード | 自分の説明を書き、理解の抜けを発見する。 | `\A` HTML + Markdown | 動作検証中（Feynman: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| KM07 | KJ法 | カードの一時的グルーピング、名称付け、関連の仮置き。 | `\A` HTML + Markdown | 動作検証中（KJ法: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| KM08 | SCAMPER | 7種の発想軸に沿った質問・アイデア生成テンプレート。 | `\A` HTML + Markdown | 動作検証中（SCAMPER: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| KM09 | Six Thinking Hats | 6つの観点を切り替えて考える。 | `\A` HTML + Markdown | 動作検証中（Six Hats: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| KM10 | SWOT | 強み・弱み・機会・脅威。 | `\A` HTML + Markdown | 動作検証中（SWOT: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| KM11 | 5W1H | 問いからの分解。 | `\A` HTML + Markdown | 動作検証中（5W1H: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| KM12 | MECE | 重複・漏れを検討する補助（機械的に正しさを断定しない）。 | `\A` HTML + Markdown | 動作検証中（MECE（疑いを示すだけ）: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| KM13 | TRIZ | 矛盾・発明的解決を扱うテンプレートと支援。 | `\A` HTML + Markdown | 動作検証中（TRIZ: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| KM14 | IBIS | Issue/Position/Argument (問題・提案・支持・反論)を関係として管理。 | `\A` HTML + Markdown | 動作検証中（IBIS（提案と根拠の対応検査）: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| KM15 | ADR | 意思決定の選択肢・根拠・結果・変更履歴。 | `\A` HTML + Markdown | 動作検証中（ADR（状態・変更履歴の検査）: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| KM16 | 概念辞書 | 用語・定義・関連概念の索引と比較。 | `\A` HTML + Markdown | 動作検証中（概念辞書: 雛形の作成・構造検査。`\A` 内の専用画面・HTML 表示は未） | 6 | `python/thinking.py` `test_thinking.py` `test/think_net.sh` | P2 View API |
| ED01 | バックリンク、出典ノートのプレビューと関 | バックリンク、出典ノートのプレビューと関係区分。 | Vim + `\A` | 動作検証中（関係の種類・該当行と前後つき。BackLink 欄・番号の親子は別扱い。`:GnosisBacklinks`） | 3 | `python/backlinks.py` `test_backlinks.py` `test/ai_net.sh` | P2 View API |
| ED02 | 未リンク参照検出（文字列・意味類似を分け | 未リンク参照検出（文字列・意味類似を分ける）。 | Vim + `\A` | 動作検証中（題の文字一致のみ。コード・リンク内は除外。意味の近さは `:GnosisAi links`） | 3 | `python/backlinks.py` `test_backlinks.py` `test/ai_net.sh` | P2 View API |
| ED03 | リンクホバー／クリック前プレビュー。 | リンクホバー／クリック前プレビュー。 | Vim + `\A` | 未実装 | 2 |  | P1 共通ID |
| ED04 | 見出し・段落・ブロック単位の安定リンクと | 見出し・段落・ブロック単位の安定リンクとリネーム耐性。 | Vim + `\A` | 要確認 | 2 | 見出しリンク（`test/heading_links_*`）・ブロックは要調査 | P1 共通ID |
| ED05 | 他ノート本文・ブロックのトランスクルージ | 他ノート本文・ブロックのトランスクルージョン、循環検出。 | Vim + `\A` | 未実装 | 2 |  | P1 共通ID |
| ED06 | ノート分割、旧リンク維持、元ノートとのつ | ノート分割、旧リンク維持、元ノートとのつながりを記録。 | Vim + `\A` | 未実装 | 2 |  | P1 共通ID |
| ED07 | ノート統合、重複除去、復元可能な履歴。 | ノート統合、重複除去、復元可能な履歴。 | Vim + `\A` | 未実装 | 2 |  | P1 共通ID |
| ED08 | マルチカーソル／複数範囲編集（VimとG | マルチカーソル／複数範囲編集（VimとGUIの適切な方式）。 | Vim + `\A` | 未実装 | 2 |  | P1 共通ID |
| ED09 | 2ノート比較・差分ビュー。 | 2ノート比較・差分ビュー。 | Vim + `\A` | 未実装 | 2 |  | P1 共通ID |
| ED10 | 変更履歴、差分、Undo/Redo、バー | 変更履歴、差分、Undo/Redo、バージョン復元。 | Vim + `\A` | 一部（存在確認のみ・未検証） | 1 | Vim の undo とバッファ保存のみ。ノート単位の履歴・復元は未実装 | - |
| ED11 | クイックキャプチャ、未整理のメモ、日記へ | クイックキャプチャ、未整理のメモ、日記への自然な接続。 | Vim + `\A` | 要確認 | 1 | `\n` `:GnosisQuick`・`\N`（docs/11） | - |
| ED12 | クリップボード履歴（許可された範囲、個人 | クリップボード履歴（許可された範囲、個人情報の扱いに注意）。 | Vim + `\A` | 要確認 | 2 | クリップボード（要調査） | P1 共通ID |
| ED13 | ノートテンプレート、挿入メニュー。 | ノートテンプレート、挿入メニュー。 | Vim + `\A` | 要確認 | 2 | テンプレート（要調査） | P1 共通ID |
| ED14 | インライン式・計算（安全な評価器を使用。 | インライン式・計算（安全な評価器を使用。シェル実行と分離）。 | Vim + `\A` | 未実装 | 2 |  | P1 共通ID |
| ED15 | 折りたたみ（見出し、引用、補足、ブランチ | 折りたたみ（見出し、引用、補足、ブランチ）。 | Vim + `\A` | 未実装 | 2 |  | P1 共通ID |
| ED16 | フォーカス／集中モード。 | フォーカス／集中モード。 | Vim + `\A` | 未実装 | 2 |  | P1 共通ID |
| ED17 | 文字数・記述量・編集履歴統計。 | 文字数・記述量・編集履歴統計。 | Vim + `\A` | 未実装 | 2 |  | P1 共通ID |
| ED18 | ノート名・索引名・リンク先の入力補完。 | ノート名・索引名・リンク先の入力補完。 | Vim + `\A` | 要確認 | 2 | ノート名の補完（要調査） | P1 共通ID |
| SR01 | 高速ファジー検索。 | 高速ファジー検索。 | Vim + `\A` | 一部（`vault_index.py fuzzy` で題・番号・ファイル名。Vim/`\A` の画面は未） | 3 | `python/vault_index.py` `test_vault_index.py` `test/query_net.sh` | P2 View API |
| SR02 | 高速全文検索、本文・見出し・関連ファイル | 高速全文検索、本文・見出し・関連ファイル。 | Vim + `\A` | 動作検証中（SQLite FTS5 trigram＋短い語は部分一致。1 万ノートで初回 2.4 秒・差分 0.25 秒・検索 0.3 秒以下） | 3 | `python/vault_index.py` `test_vault_index.py` `test/query_net.sh` | P2 View API |
| SR03 | 正規表現検索。 | 正規表現検索。 | Vim + `\A` | 動作検証中（`/正規表現/`。不正な式はエラー） | 3 | `python/vault_index.py` `test_vault_index.py` `test/query_net.sh` | P2 View API |
| SR04 | 意味検索（必要ならローカル埋め込みモデル | 意味検索（必要ならローカル埋め込みモデル等、オフライン対応を優先）。 | Vim + `\A` | 一部（ローカルの近似: 文字 n-gram の TF-IDF＋擬似適合フィードバック。ニューラルの埋め込みではない） | 3 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P2 View API |
| SR05 | 全文・意味検索のハイブリッド順位付け。 | 全文・意味検索のハイブリッド順位付け。 | Vim + `\A` | 動作検証中（全文と意味を順位の逆数で混ぜる） | 3 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P2 View API |
| SR06 | AND/OR/NOT、日付、ノート種別、 | AND/OR/NOT、日付、ノート種別、リンク数、索引／Branch、添付種別の複合条件検索。 | Vim + `\A` | 動作検証中（AND/OR/NOT・date/before/after・type・has・links/backlinks・fz・title） | 3 | `python/vault_index.py` `test_vault_index.py` `test/query_net.sh` | P2 View API |
| SR07 | 保存検索、再実行、共有可能な検索定義。 | 保存検索、再実行、共有可能な検索定義。 | Vim + `\A` | 動作検証中（`<vault>/.gnosis/searches.json`。共有できる素の JSON） | 3 | `python/vault_index.py` `test_vault_index.py` `test/query_net.sh` | P2 View API |
| SR08 | 動的索引（検索結果の読み取り専用表示、昇 | 動的索引（検索結果の読み取り専用表示、昇格は明示的操作）。 | Vim + `\A` | 動作検証中（結果は読み取り専用の Markdown。`:GnosisQueryPromote` を明示したときだけ新規ノート） | 3 | `python/vault_index.py` `test_vault_index.py` `test/query_net.sh` | P2 View API |
| SR09 | Global Index／Topic I | Global Index／Topic Indexの特定範囲で検索。実際の到達可能性に基づく。 | Vim + `\A` | 動作検証中（`in:索引.md` = 実際の到達可能性。Index→最初のノート→GroupBranch の向きで辿る） | 3 | `python/vault_index.py` `test_vault_index.py` `test/query_net.sh` | P2 View API |
| SR10 | コマンドパレット、GUIから全機能検索・ | コマンドパレット、GUIから全機能検索・起動。 | Vim + `\A` | 動作検証中（Ctrl+Shift+P。ラベル・キーワードのあいまい検索、Vim の `:Gnosis*` 全コマンドを一覧して実行（引数なしは即実行）。`\A` 内。ノート名の検索結果は未） | 2 | `web/src/app.js` `palette-core.js` `panes_e2e.mjs` | P1 共通ID |
| SR11 | ジャンプ履歴、戻る／進む、履歴トグル。 | ジャンプ履歴、戻る／進む、履歴トグル。 | Vim + `\A` | 要確認 | 2 | ジャンプ履歴（要調査） | P1 共通ID |
| SR12 | ブックマーク、ハブ固定キー、ピン留め。 | ブックマーク、ハブ固定キー、ピン留め。 | Vim + `\A` | 未実装 | 2 |  | P1 共通ID |
| SR13 | 最近閲覧・編集・取り込みしたノートやファ | 最近閲覧・編集・取り込みしたノートやファイル。 | Vim + `\A` | 要確認 | 2 | 最近のノート（要調査） | P1 共通ID |
| SR14 | リンク経路検索、最短路、経路候補、関係種 | リンク経路検索、最短路、経路候補、関係種別表示。 | Vim + `\A` | 動作検証中（`:GnosisPaths`・`\A` の分析ビューは別。種類を絞った経路の指定は gnosis_graph の API のみ） | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| SR15 | 検索一致箇所プレビュー・強調（開いた本文 | 検索一致箇所プレビュー・強調（開いた本文には検索ポップアップ用装飾を残さない）。 | Vim + `\A` | 一部（一致位置の範囲を返す。本文に装飾は残さない。`\A` の強調表示は未） | 3 | `python/vault_index.py` `test_vault_index.py` `test/query_net.sh` | P2 View API |
| SR16 | 検索→選択→索引案／リンク作成などの安全 | 検索→選択→索引案／リンク作成などの安全なコマンドチェーン。 | Vim + `\A` | 未実装 | 3 |  | P2 View API |
| LR01 | インクリメンタルリーディング。 | インクリメンタルリーディング。 | `\A` + Markdown | 未実装 | 6 |  | P2 View API |
| LR02 | 間隔反復（Spaced Repetiti | 間隔反復（Spaced Repetition）。 | `\A` + Markdown | 動作検証中（SM-2。記録は `.gnosis/srs.json`。`\A`・Android は未） | 6 | `python/srs.py` `test_srs.py` `test/srs_net.sh` | P2 View API |
| LR03 | フラッシュカード。 | フラッシュカード。 | `\A` + Markdown | 動作検証中（`Q:`/`A:` のカード。複数行可） | 6 | `python/srs.py` `test_srs.py` `test/srs_net.sh` | P2 View API |
| LR04 | Cloze穴埋め。 | Cloze穴埋め。 | `\A` + Markdown | 動作検証中（`{{穴埋め}}`・`{{c1::語}}`・ヒント） | 6 | `python/srs.py` `test_srs.py` `test/srs_net.sh` | P2 View API |
| LR05 | ランダム復習。 | ランダム復習。 | `\A` + Markdown | 動作検証中（`:GnosisSrs random`。記録しない） | 6 | `python/srs.py` `test_srs.py` `test/srs_net.sh` | P2 View API |
| LR06 | Active Recall、答えを見る前 | Active Recall、答えを見る前の想起。 | `\A` + Markdown | 動作検証中（答えを見る前の採点を受け付けない） | 6 | `python/srs.py` `test_srs.py` `test/srs_net.sh` | P2 View API |
| LR07 | 読書ハイライトの取得・ノート接続。 | 読書ハイライトの取得・ノート接続。 | `\A` + Markdown | 未実装 | 6 |  | P2 View API |
| LR08 | PDF注釈、選択テキスト、ページリンク。 | PDF注釈、選択テキスト、ページリンク。 | `\A` + Markdown | 要確認 | 4 | 未実装の疑い | P1 資産モデル |
| LR09 | 読書進捗・中断位置・再開。 | 読書進捗・中断位置・再開。 | `\A` + Markdown | 未実装 | 6 |  | P2 View API |
| LR10 | 理解度・成熟度（ユーザー任意の属性として | 理解度・成熟度（ユーザー任意の属性として、ノート分類を置換しない）。 | `\A` + Markdown | 未実装 | 6 |  | P2 View API |
| LR11 | 段階的学習経路・順序づけ。 | 段階的学習経路・順序づけ。 | `\A` + Markdown | 未実装 | 6 |  | P2 View API |
| LR12 | 自己説明テスト。 | 自己説明テスト。 | `\A` + Markdown | 未実装 | 6 |  | P2 View API |
| LR13 | 書籍・論文・Webの出典／引用元の追跡、 | 書籍・論文・Webの出典／引用元の追跡、該当箇所への戻りリンク。 | `\A` + Markdown | 未実装 | 6 |  | P2 View API |
| LR14 | ハイライト・注釈からMarkdownノー | ハイライト・注釈からMarkdownノート／索引リンク作成。 | `\A` + Markdown | 未実装 | 6 |  | P2 View API |
| TM01 | 統合Agenda: ノートと日記内のタス | 統合Agenda: ノートと日記内のタスクを収集。 | Vim + `\A` + Android | 動作検証中（Vim の :GnosisAgenda のみ。`\A`・APK は未実装） | 5 | `python/tasks.py` `test_tasks.py` `test/agenda_net.sh` | P1 タスクエンジン |
| TM02 | カレンダー: 日記、期限、作成・更新日、 | カレンダー: 日記、期限、作成・更新日、予定を表示。 | Vim + `\A` + Android | 要確認（Agenda はあるがカレンダー表示は未実装） | 5 | — | P1 タスクエンジン |
| TM03 | 指定日時のリマインダー。 | 指定日時のリマインダー。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM04 | 繰り返しタスク／通知、定期予定。 | 繰り返しタスク／通知、定期予定。 | Vim + `\A` + Android | 一部（Markdown の繰り返し規則と次の回の生成は試験済み。通知側・Android は未実装） | 5 | `python/tasks.py` | P1 タスクエンジン |
| TM05 | スヌーズ・再通知。 | スヌーズ・再通知。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM06 | タイムトラッキング。 | タイムトラッキング。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM07 | ポモドーロ・集中タイマー。 | ポモドーロ・集中タイマー。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM08 | 習慣トラッカー。 | 習慣トラッカー。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM09 | タスク依存関係、ブロッカー。 | タスク依存関係、ブロッカー。 | Vim + `\A` + Android | 動作検証中（`id:`/`after:` でブロック中を判定し Agenda で分ける。UI での編集は未実装） | 5 | `python/tasks.py` | P1 タスクエンジン |
| TM10 | 日／週／月／年のレビュー。 | 日／週／月／年のレビュー。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM11 | ライフログ（記録用データと日記への接続） | ライフログ（記録用データと日記への接続）。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM12 | 過去の今日（On This Day）。 | 過去の今日（On This Day）。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM13 | 前回セッションの復元。 | 前回セッションの復元。 | Vim + `\A` + Android | 要確認 | 2 | `test/session_*`（要調査） | P1 共通ID |
| TM14 | 通知履歴・未処理タスク。 | 通知履歴・未処理タスク。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM15 | 知識リマインダー（以前のノート、未完了の | 知識リマインダー（以前のノート、未完了の問い、古い仮説などを再提示）。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM16 | Androidホーム画面ウィジェット、ク | Androidホーム画面ウィジェット、クイックタスク追加。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM17 | 通知タップで対象ノートを開く、通知から完 | 通知タップで対象ノートを開く、通知から完了・スヌーズする。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| TM18 | 朝のAgenda通知、期限超過・週次レビ | 朝のAgenda通知、期限超過・週次レビュー通知、通知の集中設定。 | Vim + `\A` + Android | 未実装 | 5 |  | P1 タスクエンジン |
| VW01 | グローバルグラフ（全体／選択した索引から | グローバルグラフ（全体／選択した索引から到達できる範囲）。 | `\A` HTML | 動作検証中（静的サイトのグラフ: 全体／中心ノート+深さ N／種類で絞り込み・向き付きの矢印。`\A` のタブで表示（iframe・実 Electron 済み）・選択した索引から到達できる範囲・追従は未） | 3 | `python/site_assets/graphcore.js` `graph.js` `test_graphcore.mjs`（node）。Firefox headless で目視確認 | P2 View API |
| VW02 | ローカルグラフ（深さ1〜任意N、方向・関 | ローカルグラフ（深さ1〜任意N、方向・関係の絞り込み）。 | `\A` HTML | 動作検証中（静的サイトのグラフ: 全体／中心ノート+深さ N／種類で絞り込み・向き付きの矢印。`\A` のタブで表示（iframe・実 Electron 済み）・選択した索引から到達できる範囲・追従は未） | 3 | `python/site_assets/graphcore.js` `graph.js` `test_graphcore.mjs`（node）。Firefox headless で目視確認 | P2 View API |
| VW03 | Google Keep風のMasonry | Google Keep風のMasonryカード（本文プレビュー、画像、選択、ピン留め、フィルタ）。 | `\A` HTML | 動作検証中（静的サイトのカード: 段組み・画像・番号・リンク数・絞り込み・並べ替え・ピン留め（ブラウザ内のみ）。選択・フィルタの保存は未） | 3 | `python/site_assets/views.js` `viewscore.js` `test_viewscore.mjs` `web/test/site_views_e2e.mjs` | P2 View API |
| VW04 | 9×9曼荼羅HTMLビュー。セルからノー | 9×9曼荼羅HTMLビュー。セルからノート／別曼荼羅へ。 | `\A` HTML | 動作検証中（Markdown 表の保存・マスから実ノート／別の曼荼羅・主題副題の同期・静的サイトの 9×9 格子。`\A` 内の対話表示は未） | 3 | `python/mandala.py` `test_mandala.py` `test/mandala_net.sh` | P2 View API |
| VW05 | マインドマップ。 | マインドマップ。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW06 | 意味付きコンセプトマップ。 | 意味付きコンセプトマップ。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW07 | 階層ツリー（Folder Treeではな | 階層ツリー（Folder Treeではなく索引／Branch／Folgezettelの関係）。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW08 | テーブルビュー（カラム／ソート／フィルタ | テーブルビュー（カラム／ソート／フィルタ）。 | `\A` HTML | 動作検証中（静的サイトのテーブル: 番号・題・作成・更新・出入りのリンク・サイズ・タスク、列で並べ替え・絞り込み。列の表示切替・`\A` のタブで表示（実 Electron 済み）） | 3 | `python/site_assets/views.js` `viewscore.js` `test_viewscore.mjs` `web/test/site_views_e2e.mjs` | P2 View API |
| VW09 | カンバン（Markdownタスク・プロジ | カンバン（Markdownタスク・プロジェクト状態から構成）。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW10 | タイムライン。 | タイムライン。 | `\A` HTML | 動作検証中（静的サイトのタイムライン: 作成日ごと。更新履歴・期間の絞り込みは未） | 3 | `python/site_assets/views.js` `viewscore.js` `test_viewscore.mjs` `web/test/site_views_e2e.mjs` | P2 View API |
| VW11 | 画像／添付ギャラリー。 | 画像／添付ギャラリー。 | `\A` HTML | 要確認 | 4 | `python/gallery.py`（要調査） | P1 資産モデル |
| VW12 | ホワイトボード（自由配置・線・保存）。 | ホワイトボード（自由配置・線・保存）。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW13 | 地図ビュー（位置情報のあるノート・写真の | 地図ビュー（位置情報のあるノート・写真のみ）。 | `\A` HTML | 未実装 | 4 |  | P1 資産モデル |
| VW14 | サンバーストチャート。 | サンバーストチャート。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW15 | Treemap。 | Treemap。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW16 | Sankey図。 | Sankey図。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW17 | 隣接行列・関係マトリックス。 | 隣接行列・関係マトリックス。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW18 | ストーリーリバー（連続読み物）。 | ストーリーリバー（連続読み物）。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW19 | スライドビュー（Markdown→HTM | スライドビュー（Markdown→HTMLスライド／PDF等）。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW20 | 3Dグラフ（オプション。使えない環境でも | 3Dグラフ（オプション。使えない環境でも2Dへフォールバック）。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW21 | Folgezettel番号ナビゲーター（ | Folgezettel番号ナビゲーター（3章のすべて）。 | `\A` HTML | 動作検証中（静的サイトの番号ナビ: ツリー・見取り図・ボタン／キー・履歴・空き番号・本文プレビュー。実ブラウザ E2E 済み。`\A` のタブで表示（実 Electron 済み）。3 モードとの連動は未） | 2 | `python/site_assets/fznav*.js` `test_fznav.mjs` `web/test/site_views_e2e.mjs` | P1 共通ID |
| VW22 | 思考の系譜・成長グラフ（Folgezet | 思考の系譜・成長グラフ（Folgezettel、Branchを区別）。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW23 | 比較ビュー（ノート・索引・資料の横並び） | 比較ビュー（ノート・索引・資料の横並び）。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| VW24 | 孤立・未参照・未索引ノートビュー。 | 孤立・未参照・未索引ノートビュー。 | `\A` HTML | 未実装 | 3 |  | P2 View API |
| GR01 | 多接続ハブ検出。 | 多接続ハブ検出。 | `\A` + API | 動作検証中（次数・出入り・種類別の内訳）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR02 | 異なる領域をつなぐ橋渡しノート検出。 | 異なる領域をつなぐ橋渡しノート検出。 | `\A` + API | 動作検証中（複数の領域に辺を持つノート・媒介中心性）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR03 | コミュニティ検出。 | コミュニティ検出。 | `\A` + API | 動作検証中（ラベル伝播。決定的・modularity つき）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR04 | 孤立ノード・孤立群検出。 | 孤立ノード・孤立群検出。 | `\A` + API | 動作検証中（孤立ノード・小さな孤立群）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR05 | 最短経路探索。 | 最短経路探索。 | `\A` + API | 動作検証中（`gnosis_graph.shortest_path`・`:GnosisPaths`）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR06 | 到達可能性分析（どのIndexから到達で | 到達可能性分析（どのIndexから到達できるか）。 | `\A` + API | 動作検証中（索引から辿れる範囲・辿れないノート・層ごとの数）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR07 | 循環構造と不正な循環の区別・検出。 | 循環構造と不正な循環の区別・検出。 | `\A` + API | 動作検証中（階層の不正な循環とリンクの相互参照を区別）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR08 | 中心性（degree, betweenn | 中心性（degree, betweenness等）の分析。 | `\A` + API | 動作検証中（次数・媒介(Brandes。大規模は決定的な近似)・近接）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR09 | 接続密度・領域比較。 | 接続密度・領域比較。 | `\A` + API | 動作検証中（領域ごとの密度と領域間の辺）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR10 | 2つのTopic Indexの構造比較。 | 2つのTopic Indexの構造比較。 | `\A` + API | 動作検証中（2 つの索引の範囲・重なり・Jaccard・層・分岐の平均）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR11 | Folgezettelの知識発展ツリー。 | Folgezettelの知識発展ツリー。 | `\A` + API | 動作検証中（枝ごとの大きさ・深さ・月ごとの増え方。成長のアニメーションは未＝XP12）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR12 | エッジの関係種別（支持・反論・派生・参考 | エッジの関係種別（支持・反論・派生・参考・文脈・関連等）。 | `\A` + API | 動作検証中（種類の内訳・複数の種類で結ばれた組）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR13 | 構造化グラフクエリ／パターン探索。 | 構造化グラフクエリ／パターン探索。 | `\A` + API | 動作検証中（`?a -[種類]-> ?b{条件}` の連なり・向き・固定ノート。`:GnosisGraphQuery`）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| GR14 | 二点間に存在する複数の異種経路表示。 | 二点間に存在する複数の異種経路表示。 | `\A` + API | 動作検証中（Yen 法で重ならない複数経路・辺の種類つき）。静的サイトの「分析」ページと `\A` の分析ビューあり | 7 | `python/graph_analysis.py` `test_graph_analysis.py` `test/graph_net.sh` | P3 グラフ層 |
| AI01 | 類似・重複ノートの検出。 | 類似・重複ノートの検出。 | API + `\A` | 動作検証中（TF-IDF の近さ・重複の疑い（0.7 以上）・共有語を根拠に） ローカル完結（クラウド・外部通信なし）。ノート・索引は書き換えない。 | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI02 | 追加リンク候補の提案。 | 追加リンク候補の提案。 | API + `\A` | 動作検証中（近いがリンクしていないノート・本文に題が出ているが未リンクの言及） ローカル完結（クラウド・外部通信なし）。ノート・索引は書き換えない。 | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI03 | 索引追加の候補（自動で元Indexを書き | 索引追加の候補（自動で元Indexを書き換えない）。 | API + `\A` | 動作検証中（索引ごとの重心との近さで候補だけ。索引は書き換えない） | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI04 | 長文要約。 | 長文要約。 | API + `\A` | 動作検証中（抜き出しの要約。言い換えはしない） ローカル完結（クラウド・外部通信なし）。ノート・索引は書き換えない。 | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI05 | 複数ノート横断の要約・共通点抽出。 | 複数ノート横断の要約・共通点抽出。 | API + `\A` | 動作検証中（共通語・多数に出る語・各ノートの要点） | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI06 | 記述矛盾の疑い検出（根拠行・確信度を示し | 記述矛盾の疑い検出（根拠行・確信度を示し断定しない）。 | API + `\A` | 動作検証中（数字・肯定否定の食い違いの「疑い」。根拠の行・確信度つき。断定しない） | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI07 | 古い情報の更新確認・期限付き再検証。 | 古い情報の更新確認・期限付き再検証。 | API + `\A` | 動作検証中（時点依存の語・古い年・`reverify:` 期限） | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI08 | キーワード抽出・索引語の候補。 | キーワード抽出・索引語の候補。 | API + `\A` | 動作検証中（つながった語句を索引語の候補に） | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI09 | 問題・質問の自動生成。 | 問題・質問の自動生成。 | API + `\A` | 動作検証中（定義文の Q:/A:・穴埋め・説明課題。SRS にそのまま使える形。ノートには書かない） | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI10 | 自分のノートに根拠を持つ対話・RAG。 | 自分のノートに根拠を持つ対話・RAG。 | API + `\A` | 一部（取り出し側のみ: 自分のノートからの抜き出し・出典の行つき・根拠が無ければ「見つからない」。LLM による生成・対話は未） | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI11 | 外部情報の定期収集エージェント（利用者の | 外部情報の定期収集エージェント（利用者の明示的許可・ネット権限必須）。 | API + `\A` | 未実装 | 8 |  | P7 グラフ層 |
| AI12 | ローカル／明示選択クラウド音声文字起こし | ローカル／明示選択クラウド音声文字起こし。 | API + `\A` | 阻害中（この環境に音声認識エンジン（whisper・vosk など）が無い。ffmpeg だけある。エンジンを入れたら呼ぶアダプタを作る） | 8 |  | P7 グラフ層 |
| AI13 | 自然言語による検索条件生成。 | 自然言語による検索条件生成。 | API + `\A` | 一部（ルールで読む: 日付範囲・タスク・画像・日記・番号・引用語。読み方を併記。機械学習ではない） | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI14 | 週・月の活動と知識変化のレポート。 | 週・月の活動と知識変化のレポート。 | API + `\A` | 動作検証中（作成・更新の件数・前期間との比較・新しいノートの語句） | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| AI15 | 保存済み検索条件を巡回するAgent（対 | 保存済み検索条件を巡回するAgent（対象ノートを移動せず結果ビューへ）。 | API + `\A` | 動作検証中（保存検索を巡回し前回との差を出す。ノートは動かさない。状態 `.gnosis/patrol.json`） | 8 | `python/local_ai.py` `test_local_ai.py` `test/ai_net.sh` | P7 グラフ層 |
| XP01 | ランダムウォーク。 | ランダムウォーク。 | `\A` | 未実装 | 9 |  | P3 |
| XP02 | セレンディピティ推薦（普段見ない意外なノ | セレンディピティ推薦（普段見ない意外なノートとの遭遇）。 | `\A` | 未実装 | 9 |  | P3 |
| XP03 | 知識考古学（古い記述の再発掘と比較）。 | 知識考古学（古い記述の再発掘と比較）。 | `\A` | 未実装 | 9 |  | P3 |
| XP04 | タイムカプセル（指定時刻に過去のノート再 | タイムカプセル（指定時刻に過去のノート再提示）。 | `\A` | 未実装 | 9 |  | P3 |
| XP05 | 知識の博物館（ノートを展示風に閲覧）。 | 知識の博物館（ノートを展示風に閲覧）。 | `\A` | 未実装 | 9 |  | P3 |
| XP06 | 記憶の宮殿（仮想空間上への任意配置）。 | 記憶の宮殿（仮想空間上への任意配置）。 | `\A` | 未実装 | 9 |  | P3 |
| XP07 | 思考の迷路（リンクのみを辿る探索ゲーム） | 思考の迷路（リンクのみを辿る探索ゲーム）。 | `\A` | 未実装 | 9 |  | P3 |
| XP08 | ノートルーレット。 | ノートルーレット。 | `\A` | 未実装 | 9 |  | P3 |
| XP09 | 意外な共通点／中間概念探索。 | 意外な共通点／中間概念探索。 | `\A` | 未実装 | 9 |  | P3 |
| XP10 | 仮説実験室（仮説、証拠、反証、結論、履歴 | 仮説実験室（仮説、証拠、反証、結論、履歴）。 | `\A` | 未実装 | 9 |  | P3 |
| XP11 | 思考の対戦（相反する主張を比較・討論）。 | 思考の対戦（相反する主張を比較・討論）。 | `\A` | 未実装 | 9 |  | P3 |
| XP12 | 知識成長アニメーション（履歴に基づくグラ | 知識成長アニメーション（履歴に基づくグラフ変化）。 | `\A` | 未実装 | 9 |  | P3 |
| XP13 | 未来への質問（時限再提示）。 | 未来への質問（時限再提示）。 | `\A` | 未実装 | 9 |  | P3 |
| XP14 | 知識探索ゲーム（指定ノートへのリンク経路 | 知識探索ゲーム（指定ノートへのリンク経路を辿る）。 | `\A` | 未実装 | 9 |  | P3 |
| XP15 | アイデア合成器（無関係な概念の組合せ）。 | アイデア合成器（無関係な概念の組合せ）。 | `\A` | 未実装 | 9 |  | P3 |
| XP16 | Memex型連想トレイル（閲覧順・思考経 | Memex型連想トレイル（閲覧順・思考経路を別オブジェクトとして保存／再生／共有）。 | `\A` | 未実装 | 9 |  | P3 |
| UT01 | 壊れたリンクの検査。 | 壊れたリンクの検査。 | Vim + API | 動作検証中（:GnosisCheck で検出のみ。修復・リネーム時の自動更新は未実装） | 1 | `python/gnosis_graph.py` `test/check_vault_net.sh` | - |
| UT02 | Index / Topic Index  | Index / Topic Index / GroupBranchの整合性検査。 | Vim + API | 一部（Branch 検査 + 重複／抜け Folgezettel。Index→First Note→GroupBranch→Topic Index の到達性検査は未実装） | 1 | `:GnosisBranchCheck` `:GnosisCheck` | - |
| UT03 | リネーム時の安全な参照更新。 | リネーム時の安全な参照更新。 | Vim + API | 一部（存在確認のみ・未検証） | 1 | `:GnosisRename`（ファイル名変更。参照更新の範囲は要調査） | - |
| UT04 | 自動バックアップ、検証可能な復元。 | 自動バックアップ、検証可能な復元。 | Vim + API | 動作検証中（`:GnosisBackup/Verify/Restore/List`。tar.gz＋SHA-256 manifest・書いた直後に検証・中ほどを壊すと検証 NG で復元しない・既存の中身があるフォルダへ復元しない・vault 内への出力は拒否）。**未了**: 自動（定期）実行・暗号化・Git 連携 | 1 | `python/vault_backup.py` `test_vault_backup.py` `test/backup_net.sh` | - |
| UT05 | Git連携、差分表示、バックアップ対象選 | Git連携、差分表示、バックアップ対象選別。 | Vim + API | 要確認 | 1 | Git 連携（要調査） | - |
| UT06 | HTMLサイト出力（オフラインも可）。 | HTMLサイト出力（オフラインも可）。 | Vim + API | 動作検証中（静的 HTML・検索・番号表。EXIF 除去・分割出力・ブラウザ実表示は未） | 3 | `python/export_site.py` `md_html.py` `docs/HTML_EXPORT.md` | P2 View API |
| UT07 | PDF・EPUBへのエクスポート。 | PDF・EPUBへのエクスポート。 | Vim + API | 未実装 | 3 |  | P2 View API |
| UT08 | Markdown互換性検査。 | Markdown互換性検査。 | Vim + API | 未実装 | 3 |  | P2 View API |
| UT09 | オフライン全文検索。 | オフライン全文検索。 | Vim + API | 動作検証中（派生 SQLite。消しても作り直せる。書き出しサイト内の検索も別にある） | 3 | `python/vault_index.py` `test_vault_index.py` `test/query_net.sh` | P2 View API |
| UT10 | 設定プロファイル、vaultごとの設定。 | 設定プロファイル、vaultごとの設定。 | Vim + API | 要確認 | 1 | vault ごとの設定 `.gnosis/settings.json` | - |
| UT11 | プラグインAPI／View追加API。 | プラグインAPI／View追加API。 | Vim + API | 一部（表示専用ビューの種類を layout.js の KINDS と panes.js の PAGES に登録する形。外部プラグインが登録する公開 API・Vim 側のプラグイン API は未） | 2 |  | P1 共通ID |
| UT12 | プロファイラ・パフォーマンス診断。 | プロファイラ・パフォーマンス診断。 | Vim + API | 未実装 | 1 |  | - |
| UT13 | Undo可能な一括変更、ゴミ箱、復元、d | Undo可能な一括変更、ゴミ箱、復元、dry-run。 | Vim + API | 一部（存在確認のみ・未検証） | 1 | `:GnosisTrash*`（ゴミ箱の送り・一覧・空に・復元あり）。dry-run・一括変更の Undo は無い | - |
| UT14 | インポート・エクスポート・移行の再開／検 | インポート・エクスポート・移行の再開／検証。 | Vim + API | 未実装 | 1 |  | - |
## 追加ID（原本 §3・§6・§7・§8・§10 から台帳化）

| ID | 機能 | 対象 | 状態 | Phase | 実体・根拠 |
|---|---|---|---|---|---|
| FZ01 | Folgezettel 番号ナビ: 深掘り 1→1a→1a1 | `\A` | 動作検証中（静的サイトの番号ナビのみ。`\A` 組み込みは未） | 2 | 原本 §3。VW21 と同一実装 |
| FZ02 | 兄弟移動 1a→1b→1c、1→2（親子と履歴経路を区別） | `\A` | 動作検証中（静的サイトの番号ナビのみ。`\A` 組み込みは未） | 2 | 同上 |
| FZ03 | 自然順の番号列・ツリー・パンくず・前後・親・最初最後・折りたたみ・本文プレビュー | `\A` | 動作検証中（静的サイトの番号ナビのみ。`\A` 組み込みは未） | 2 | 同上 |
| FZ04 | 空き番号／リンク切れの区別、ID 検証（重複・抜け・循環） | `\A` + API | 動作検証中（重複・抜けの検出まで。循環・ID 変更の影響検査は未実装） | 2 | `python/folgezettel.py` `folgezettel_scan.py` |
| FZ05 | 紙スキャン／番号付け GUI との統合、索引⇄番号ビュー往復 | `\A` | 一部（番号⇄ノート本文のプレビュー・番号表 MD。索引⇄番号の往復・紙スキャンの統合は未） | 2 | `python/paper_pkm.py` |
| MD01 | `\A` 3 モード（Real Vim／GUI 編集／閲覧専用） | `\A` | 動作検証中（Real Vim／GUI 編集／閲覧専用の 3 モードを切替ボタンと Alt+E／Alt+V で。実 Electron の E2E 済み。GUI 編集の保存は Vim の :write 経由で競合は退避つき） | 2 | `web/src/guiedit.js` `editcmds.js` `history.js` `electron/noteio.cjs` `vim/gui.vim` `web/test/gui_edit_e2e.mjs`
| MD02 | タブ・分割ペイン・レイアウト保存・全機能の GUI 操作経路・コマンドパレット | `\A` | 動作検証中（タブ・右／下の分割・ドラッグで並べ替え／移動／端で分割・固定・閉じて再開・分割線リサイズ・vault ごとの保存と復元・Ctrl+Shift+P のコマンドパレット（モード・ビュー・タブ・Vim の全 Gnosis コマンド・GUI 編集の操作）。ビューは表示専用で iframe。ペインごとの履歴・タブの大量時の遅延読み込みの最適化・タッチ操作は未） | 2 | `web/src/layout.js` `panes.js` `palette-core.js` `web/test/layout_test.mjs` `palette_test.mjs` `panes_e2e.mjs`
| PD01 | vault への資産取り込み（コピー／移動／外部参照）・メタデータ・逆リンク | API | 未実装 | 4 | |
| PD02 | 写真 GUI（グリッド・拡大・EXIF・XMP サイドカー・アルバム・一括タグ） | `\A` | 要確認 | 4 | `python/gallery.py`（中身未監査） |
| PD03 | PDF／動画／音声／Office／コードのプレビュー・全文索引・キャッシュ上限 | `\A` | 未実装 | 4 | |
| PD04 | セキュリティ（自動実行しない・パス正規化・CSP・ゴミ箱既定） | `\A` | 未実装 | 4 | |
| AN01 | APK 既存操作の維持（フィルタ・複数選択・移動・画像・長押し・アラーム） | Android | 実装済（docs/11） | 1 | `android/`・実機未確認 |
| AN02 | タスクエンジン共有（`- [ ]`・期限・繰り返し）→ Agenda／カレンダー／APK | 共通 | 未実装 | 5 | |
| AN03 | 通知タップでノートを開く・完了・スヌーズ・ウィジェット・週次レビュー | Android | 未実装 | 5 | |
| M01 | `\M` 重複インポート禁止（source ID・ハッシュ・復旧可能な state） | Vim/Python | 動作検証中（id 単位の重複防止＋同一ノート差分更新を試験済み。ノート側 source ID・日記・ジャーナルは未実装） | 1 | `capture_import.py` `capture_merge.py` `docs/ANDROID_SYNC.md` |
| M02 | 同一ノートの差分更新・base/local/remote 3-way merge・競合 UI | Vim/`\A` | 実装中（merge 実装・試験済み。競合の差分画面・解決操作は未実装） | 1 | `capture_merge.py` |
| M03 | 日記埋め込みの source ID 別境界・二重挿入なし | Vim/Python | 未実装 | 1 | |
| M04 | 画像添付 hash 管理・関係(Branch/Context)の差分反映・トピック変更 | Vim/Python | 一部（トピック変更反映あり） | 1 | |
| M05 | Idempotency／ジャーナル／原子的書込／✓ は永続化後のみ | Python | 未実装 | 1 | |
| M06 | 重複候補の診断・統合ツール（自動削除しない）・履歴・取り消し | Vim/`\A` | 未実装 | 1 | |
| HT01 | Markdown 表示索引（views 目次）・静的 Markdown 出力・HTML エクスポート（オフライン） | API | 一部（Folgezettel 番号表 MD/HTML・静的サイト出力は動作検証中。views 目次の他のビューは未） | 3 | |
| BG01 | 回帰: リンク末尾の余計な空白（261019222455.md） | Vim | 要確認 | 1 | 直近コミットで修正の記述あり。再現テスト未確認 |
| BG02 | 回帰: チェックボックス行のリンクを Enter で開く | Vim | 要確認 | 1 | `test/checkbox_net.sh` |
| BG03 | 回帰: `^[[1;5C` の混入・キー遅延 | Vim | 要確認 | 1 | 直近コミットで「job で待つ」修正の記述 |
