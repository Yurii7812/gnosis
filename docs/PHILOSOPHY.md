# 哲学と不変条件

原本 §1 の要約。判断に迷ったらここに戻る（全文は `Gnosis_Claude_Implementation_Master_Prompt.md`）。

1. **ダブルインデックス**: Global Index → 最初のノート → GroupBranch → Topic Index → ノート。Global Index から Topic Index へ直接飛ばさない。既存リンクを付け替えず、新しいノート・索引・リンクの追加で育てる。
2. **関係の意味を保つ**: Folgezettel／ParentBranch／ChildBranch／Context／Group／Related／BackLink の方向・表示名・手書き順序・自動同期の境界は現行コード・テストが正。
3. **タグ・フォルダ分類を強制しない**。検索・グラフ・カード・PARA は索引を置換しない別経路（仮想ビュー）。写真のタグ等は資産メタデータで、知識ノートには強制しない。
4. **操作の中心は本物の Vim**。独立した Workspace 画面は作らず、`\A`（Electron）を拡張する。`\A` の全機能にボタン・メニュー経路を用意し、キーとボタンは同じ内部コマンド。3 モード: Real Vim／GUI 編集／閲覧専用。1 つの原本に同時に 2 つの書き込み主体を許さない。
5. **原本は可搬な Markdown**。SQLite 等は再構築可能な派生物。Markdown ビューアで読める索引を作り、リッチな操作は HTML。
6. **データを失わない**: 原子的書込・ゴミ箱・dry-run・復元。`\M` は重複を作らず同一ノートを 3-way merge で更新し、競合を隠さない。
7. AI・外部通信は任意で明示許可。AI は索引や手書き本文を勝手に書き換えない。
