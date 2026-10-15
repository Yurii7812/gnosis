このノートは Gnosis の操作ガイド。**全キーはここに集約**する。
設定画面（`:GnosisSettings`）で言語を変えると、このガイドもその言語で作り直される。**Vim の基本操作は末尾**。

## 起動・vault・設定

- 起動画面 … Chnoubis のシンボル・選択中の vault・`Enter` で開始。`v` で vault の選択・管理、`s` で設定、`q` で終了
- vault の一覧 … `j` / `k` で選ぶ ・ `Enter` で開く ・ `a` 既存のフォルダを登録 ・ `n` 新しい vault を作る ・ `d` 一覧から外す（ノートとフォルダは消さない） ・ `Esc` 戻る
- `:GnosisStart` 起動画面 ・ `:GnosisVaults` vault の一覧（使用中に切り替える） ・ `:GnosisSettings` 設定画面
- 設定は vault ごと（`.gnosis/settings.json`）: 言語・起動時に最大化・通常のウィンドウサイズ・ライト／ダーク・テーマ・カスタム配色。文字サイズ・フォント・行間・使う端末は Gnosis 全体（Gnosis ホームの `terminal.json`）
- `:GnosisThemeAdd` `Plug '作者/リポジトリ'` … GitHub の Vim テーマを追加してこの vault のテーマにする ・ `:GnosisThemeReset` 標準テーマに戻す
- 配色エディタ（設定の「配色を作る・直す」）では、背景・本文・リンク・見出し・選択範囲・カーソル行に加えて、**リンクの手前の番号（1〜9・0・g1 …）の文字色と背景色**も決められる。変えるとすぐプレビュー（番号つきの例）に出る。決めなければ今までどおり（文字=背景色・札=補助の色）
- `:GnosisFontSize` 文字サイズ（`20` / `+1` / `-1` / `reset`。保存して、できる端末ではその場で反映） ・ `:GnosisLinkSource` リンクの元の Markdown を見せる／隠す
- アプリでは `Ctrl` + `+` / `-` / `0` で画面全体の拡大・縮小・元に戻す（その場だけ。文字サイズの設定は変わらない）
- GUI 版 Vim では `<C-=>` / `<C-+>` / `<C-->` / `<C-0>` で文字の大きさをその場だけ変える。端末の `Ctrl` + `+` / `-` / `0` は端末が処理し、保存されない。保存される大きさは設定画面の文字サイズで `+` / `-` / `0`（Konsole・kitty・Alacritty の Gnosis の窓ではその場で変わる。他の端末は次に Gnosis の窓を開いたとき）

## ノート作成

- `zn` … ノート作成。位置キーを 1 つ選ぶ:
  `h`=カーソル直下（本文） / `Enter`=本文の最後 / `t`=見出しの下 / `c`=Context の末尾 / `b`=ChildBranch（直接の子） / `p`=ParentBranch（直接の親） / `o`=リンク無し（孤立）
  普通の `zn` は `h`/`Enter`/`t`/`c` の置き場所と独立して、元ノートを親・新ノートを子とする Branch（元ノートの `### ChildBranch`、新ノートの `### ParentBranch`）を自動作成する。`Enter` はさらに新ノートの `### Context` に元ノートも置く。`c` の文脈リンクは既存の動作を維持する。`b` は Branch のみ、`p` は逆向き、`o` は孤立。`index.md` からの通常作成と `zk` のグループ作成は自動 Branch を付けない（明示的な `b`/`p` は使用可能）。
- `c` のあと … 新しいノート（リンク先）に、今のノートへのリンクをどう入れるかを選ぶ: `Enter`=本文の最後 / `t`=見出しを選んでその節の最後 / `w`=リンク先を開いて自分で編集（自動では書かない。元のノートの**ファイル名だけ**をヤンクしてリンク先を開くので、`p` で貼り付けたり Markdown リンクに直したりできる。複数のリンクは 1 件ずつ、残りは `:GnosisWNext`）/ `o`=入れない（今のノートの Context への追加はそのまま）
- `b`（ChildBranch=直接の子）/ `p`（ParentBranch=直接の親）（`zn` / `zk` / `za` / `\l` の位置キー）… `b` は今のノートが親・選んだ（作った）ノートが子、`p` は選んだ（作った）ノートが親・今のノートが子。どちらも内部では同じ処理で、**親のノートの `### ChildBranch` と、子のノートの `### ParentBranch`** の両方にリンクを書く。`p` で親にできるのは 1 つだけ。1 つのノートが持てる親（ParentBranch）は最大 1 つ（子は何本でも）。既に親があるノート・自分自身・循環になる組は拒否して、どちらのノートも変更しない（既存の親は付け替えない。現在の親のタイトルを表示）。Context / Related とは別の関係。`:GnosisBranchCheck` で整合性を検査
- `zk` … グループノート作成（`attribute: group`）。位置キーは `zn` と同じ。
- ノートの `Group:` からグループへのリンクを消すと、次の同期でそのグループの本文からもそのノートへのリンクが外れ、所属から抜ける（戻らない。グループの本文から消した場合は従来どおり `Group:` からも外れる）
- `zk`（ビジュアル）… 選択範囲を中身にしたグループを作り、選択をそのグループへのリンクに置換
- `zh` … カーソル直下にリンク（本文扱い → 相手には BackLink）
- リンク先がグループのとき（`c` のあと `Enter` / `t`）… 入れるリンクの**表示名**を入力（空欄から。空 `Enter` = 今のノートのタイトル、`Esc` = 取り消し）

## リンク

- `\L`（ノーマル）… カーソル下のファイル名を Markdown リンク化
- `\L`（ビジュアル）… 選択範囲を表示名にした新ノートへのリンクで選択を置換（新ノート title はタイムスタンプのまま。Context は付けない＝元ノートは BackLink に出る。付けるなら `\P`）
- `\p`（ノーマル）… カーソル下 or クリップボードのリンクを 1 本追加（`h`/`Enter` で位置を選ぶ）
- `\p`（ビジュアル）… クリップボードのファイル名/URL を選択範囲のリンクに（無ければ何もしない）
- `za` … クリップボード／ヤンクしたリンクを今のノートに追加（複数行・複数リンクも全部）（`h`=カーソル直下 / `Enter`=本文の最後 / `t`=見出しの下 / `c`=Context末尾 / `b`=ChildBranch / `p`=ParentBranch / `r`=Related）。`c` のあとはリンク先に今のノートをどう入れるか（`Enter` / `t` / `o`）を選ぶ
- `zA` … `za` と同じだが、追加前に**表示名**を入力する（空 Enter / Esc で中止）
- `zp` … `za` と同じ追加＋今のノートを相手の Context に書く
- `zap` … カーソル下（無ければクリップボード）のリンクを、今のノートの Context の最後に足す（本文に同じリンクがあっても足す）
- 関連: `za` 等で `r` を押すと `### Related` に**相互追加**（両ノートに。片側で消すと次回同期で両方から消える。BackLink には出ない）
- `\P` … カーソル下リンクの Context に今のノートを確認なしで追加
- クリップボードを関係付きで追加: `ca` / `cu` / `\ca` / `tt` / `ta` / `\at` / `\bc`（`\ca`= `ca`、`\at`= `at` の逆方向）
- `\l`（ノーマル）… 全ノートを全文検索（タイトル優先）→ 選んだら置き場所を聞かれる（`h`=カーソル直下に新しい行 / `Enter`=本文の最後 / `t`=見出しの下 / `c`=Context 末尾 / `b`=ChildBranch / `p`=ParentBranch / `r`=Related / `i`=カーソル位置にそのまま / `n`=表示名を入力して本文の最後へ / `g`=グループを選んで所属にする）（`:GnosisLinkPick`）
- `\l` → `g` … グループを選ぶ（fzf。attribute: group のノートだけ）→ 表示名（`n` と同じ。空 Enter = タイトル）。選んだノートはそのグループの本文にリンクとして入り、相手の Group: がそのグループになる。今のノートの本文末にも同じリンクを置く。`za` の位置キーでも同じ。Esc で何もしない。
- `\l` → `n` … 表示名の入力欄は空から始まる。空 `Enter` = リンク先ノートのタイトル、入力して `Enter` = その文字、`Esc` = 取り消し（ノートのタイトルやファイル名は変えない）
- `\l`（ビジュアル）… 同じ検索で選んだノートへのリンクで選択範囲を置換
- 自動生成の BackLink と、ここで入れたリンクは別もの。入れたリンク（表示名つきも）は保存・同期しても残る

## タイトル・表示名

- `zt` / `zT` … タイトル変更（空から / 現在を残して編集）
- `zl` / `zL` … リンク表示名の変更（空から / 現在を残して編集）
- `zo` … カーソル下の .md リンク先の見出し（アウトライン）を選び、リンク先に `#スラッグ` を付ける（先頭の「（見出しなし）」で解除。タイトルと Context/Group/Related/BackLink は一覧に出ない）
- `zy` / `zY` … **今開いているノート**の**よみ**を変更（`zy`=空欄から / `zY`=現在のよみを残して。`zY` で全部消して Enter は削除。Esc で中止）。`yomi:` に表示名が複数あるときは番号で表示名を選ぶ
- `zd` … 子リンクの表示名をリンク先タイトルに更新
- `mp` … YAML `filetype` を変更 ・ `yn` … 今のファイル名をヤンク

## 移動・閲覧

- `<Tab>` / `<S-Tab>` … 次の / 前のリンクへ ・ `<CR>` … カーソル下のリンクを開く
- `<BS>` … 戻る ・ `<S-BS>` / `\.` … 進む ・ `_` … 直前のノートと往復
- `1`〜`9` / `0` … ドキュメントの上から順（冒頭の Context も含む）の通し番号のリンクを開く
- `\k` / `\j` / `\J` … Context へ / BackLink の先頭へ / BackLink の末尾へ
- `\bu` … Context 付近の最後のリンクへ ・ `<S-Space>` … リンク一覧から選んで移動
- `\h` / `\0` … ハブ画面（編集可能なリンク一覧） ・ `\H` … 今のノートをハブに追加
- `\1`〜`\9` … ハブの N 番目へ直行（ハブ内では普通のリンク番号）
- `\i` … `index.md` を開く ・ `\A` … ノートアプリ（Electron / ブラウザ）
- `\q` … 作業タブの一覧（ノートの**タイトル**で表示。同じタイトルは補助にファイル名も出す）。`↑` / `↓`（`j` / `k`）で選び、`Enter` で切り替え、`Esc`（`q`）で閉じる。`/` はタイトルで絞り込み、`a` 追加 ・ `x` 閉じる ・ `X` 他を閉じる ・ `C` 全部閉じる（`:GnosisTabs`）
- `\o` … カーソル下のリンクを新しい作業タブで開く（`<CR>` は今のタブの中で移動。`:GnosisOpenLinkTab`）
- アプリ（`\A`）の `Alt+V` … 見るだけモード ⇔ 普通の Vim。見るだけ（下に VIEW）はカーソルを出さず、編集するキーは送らない。`j`/`k`・矢印・PageUp/Down・`gg`/`G`・`Ctrl-d`/`Ctrl-u` でスクロール。`/` `?` `n` `N` `*` `#` で検索。`gs`・`gm`・Space・Tab・`<CR>`・`<BS>`・`_`・数字・`\h` `\H` `\0` `\i` `\d` `\.` `\L` `\gi` `\r` `\bu` `\k` `\j` `\J` `\sc` も使える
- アプリでリンクを `Alt` + クリック … 開かずにカーソルだけをリンクへ動かす（カーソルだけを動かしたいときに使う）
- アプリは表（`| a | b |`）と `<img src="…" width="50%">` も描く。カーソルが表の中・インサート中は文字のまま
- `\d` … 今日の日記を開く（無ければ作る。`:GnosisToday`）。日記の「今日のノート」には、作ったノートが自動で入る（`:GnosisDiaryUpdate` で日記をまとめて更新・`:GnosisDiaryAdopt` で今のノートをその日付の日記に登録）
- `zw` … 今開いているノート（日記でなくてもよい）の本文の一番下から書き始める。最後の文のあとに空行を 1 つ空けた行にカーソルを置く（その下にも空行を 1 つ）
- `\I` … 画像記法のサイズ変更（ビジュアルは選択範囲）

## 展開・画像・その他

- `\e` … 現ノート周辺を 1 つの md に展開（`expand_v2.py`。**シンプル/詳細**を選ぶ。詳細は 5 項目を指定し、名前を付けてプリセット保存・呼び出し・削除できる。出力 `.trash/T_*.md`）
- `\se` … S ノートを A ノートに展開（`expand_s.py`。出力 `.trash/T_*.md`）
- `\gi` … 画像ギャラリー（画像リンクがあればそれ、無ければ Index 以下の全画像をブラウザで）
- `\oe` / `\O` … 見出しを別バッファで編集（`:write` で元ノートへ反映。`:OutlineEdit`）
- `\sc` … CopyStack（`y` で行 / 選択を積み、もう一度 `:CopyStack` でクリップボードに確定）
- `mx` … 行（ビジュアルは選択範囲）のチェックボックス `[ ]` / `[x]` を切替

## 検索（fzf）

- `gs` … vault を全文検索（タイトル優先。左はタイトル、右はヒット箇所を強調）→ `⏎` でヒット行を開く（`:GnosisSearch`）
- `<Space>` … 今のノートのリンク先を検索（タイトル優先。リンク先ノートの本文も検索対象）→ `⏎` で開く
- `\l` … 同じ全文検索でノートを選び、置き場所キーでリンクを入れる（`:GnosisLinkPick`）
- `rg` … ripgrep で全文（行）検索（`:Rg`）

## 貼り付け（クリップボード）

- `\v` / `\V` … システムクリップボード（PC の直近のコピー / Vim のヤンク）を `p` / `P` の要領で貼る
- `p` / `P` … Vim 標準（`"` レジスタ） ・ `gp` … 末尾改行を落として行下に追加
- Vim でヤンク（`yy` / `x` / `ciw`）した内容は PC 側のクリップボードにも流れる

## 表（テーブル）

- `\tn` 新規 / `\ta` 整形 / `\te` 行を別バッファで編集 / `\tc` CSV へ / `\tt` CSV から / `\tnc` 別 CSV 作成
- `\tar` / `\tac` … 行・列を追加 ・ `\tdr` / `\tdc` … 行・列を削除
- 表バッファ内: `<Tab>` / `<S-Tab>` セル移動 ・ `<CR>` 確定 ・ `<Left>` / `<Right>` 表示移動 ・ `\ta` `\te` `\tc` `\tar` `\tac` `\tdr` `\tdc` もその場で有効

## 環境のその他

- `\w` … 全バッファを保存（`:wa`） ・ `\r` … 画面の残像を消す（`:redraw!`） ・ `gm` … 今のノートを既定アプリで開く
- 編集は約1.5秒無操作で自動保存（挿入中も。Esc でも即保存。vault の .md / .csv 対象。バッファを離れるときも即保存。`g:gnosis_autosave=0` で無効）。`gm` / `\A` / `\tD` / 同期の前は必ず保存してから実行。swap は作らない
- `<C-v>` … システムクリップボードを貼る ・ `<C-c>`（ビジュアル）… システムクリップボードへコピー
- `j` / `k` / `<Up>` / `<Down>` … 表示行で上下（挿入モードでも同じ。挿入モードを抜けないので IME は維持される）

## vault の暗号化（gocryptfs）

- vault は `A/note`（平文ビュー）+ `A/.crypt`（暗号実体）の兄弟構成。起動時にパスワードを聞いてマウントし、終了時に自動ロックする
- `:GnosisMount` … 手動マウント ・ `:GnosisLock` … 手動ロック（アンマウント）。別のウィンドウ・アプリが使っている vault は、ロックしない（`:GnosisLock!` で強制）
- 複数のウィンドウ（Vim・`\A` のアプリ）で、別々の vault も同じ vault も同時に開ける。暗号化 vault は、**使っている最後のウィンドウ**が終わる（または別の vault へ切り替える）ときだけロックされる。登録簿は vault の外（Gnosis ホームの `sessions/`）にあり、異常終了したプロセスの登録は自動で消える。同じノートを複数のウィンドウで編集して他で書き換えられたときは、自動保存は上書きせず、未保存の内容を `.state/conflicts/` に退避して警告する
- `:GnosisBackup` `[出力先]` … プロジェクトフォルダ（`.crypt` 他。`note/` の中身は除く）を vault のパスワードで 7z 化
- `:GnosisSetPassword` … 未暗号化なら暗号化、暗号化済みならパスワード変更
- `:GnosisRemovePassword` … 暗号化を解除して平文に戻す
- `:GnosisExitCleanup` … 終了時の後始末（viminfo 書き出し等）
- `:GnosisChooseIndex` / `:GnosisChooseIndexDir` … vault のフォルダを入力して選び直す（`A/note` があれば必ずそれを root に）
- 注意: gocryptfs は**空でないマウントポイントを拒否**する。中身とファイル名は暗号化されるが、時刻・サイズ・構造は漏れる

## ラベル記法（関係の接尾辞）

- `語:` … 相手側は `(語):` でミラー
- `語:;` … 相手側も `語:;`（括弧なし）
- `語;` … 相手側には書かない
- `語::` … 両方の同じセクションに `語:`
- **Context は本文の冒頭（H1 タイトルの直後）の `Context:` ブロック**（Markdown の見出しではなく、ふつうのテキスト行。直下にリンクが並ぶ）。`c` で足したリンクは既存リンクの最後に入り、同じノートは重複しない。旧形式 `### Context` も読める（`c` で足したノートは、リンクを失わず新形式へ移る。旧形式のノートは開いただけ・同期しただけでは書き換えない。移行は `:GnosisContextMigrate`（今のノート）/ `:GnosisContextMigrate all`（試走）/ `:GnosisContextMigrate! all`（vault 全体）で明示的に）。コードブロックの中の `Context:` は Context ではない
- グループ（`attribute: group`）へのリンクは `### Group` に、普通のノートへのリンクは `Context:` に、sync が自動で振り分ける。中身が空の節（ParentBranch / Group / ChildBranch / Related / BackLink）は見出しごと無い
- 本文の後ろの節の並びは ParentBranch → Group → ChildBranch → Related → BackLink（Context は冒頭のブロックなので含まない）。`### ParentBranch` / `### ChildBranch` は `b` で明示した関係で、sync は追加も削除もしない（表示名の追従と、消えたファイルの掃除だけ。Context には変換しない）。コードブロックの中の見出しは節として扱わない

## 同期

- 保存時に自動同期（`:UpdateMD` / `:UpdateAll` / `\ua` で全体を整合。`:UpdateAll` / `\ua` は index.md もよみ順に並べ替える）
- 相手側のラベルは自動でミラー。括弧を外して手書きしたら sticky
- 消えたファイルへのリンクは自動で掃除（行ごと。文章中のリンクは文字だけ残す）

## ハブ

- `\1`〜`\9` … ハブへ直行 ・ `\H` … 現在ノートを登録 ・ `\0` / `\h` … 一覧
- ハブは Index（vault）ごとに保存。別の vault では別のハブ表になる

## ゴミ箱

- `\tD` … 今のノートをゴミ箱（`.trash/`）へ移す（ソフト削除。`:GnosisTrash` も同じ）
- `\tr` … ゴミ箱を fzf で覗く（プレビュー付き）。`⏎`=開くだけ / `^r`=vault 直下へ復元して開く / `^e`=ゴミ箱を空にする（`:GnosisTrashList`）
- `\tE` … ゴミ箱を全部空にする（完全削除・確認あり。`:GnosisTrashEmpty` も同じ）
- `.trash/` はドット始まりなので検索・一覧・同期・リンクには出ない

## よみ順ソート

- `\S`（ノーマル）… **リンクだけの行**を表示名のよみ順（五十音 → ローマ字は末尾）に並べ替え（未登録のよみは `yomi:` に自動追加）
- `\S`（ノーマル・グループ）… グループでは、本文の最後の「空行で区切られたブロック」だけを並べ替える（それより上の文章・リンクは動かさない）
- `\S`（ビジュアル）… 選択した行のリンクだけの行を同じ規則で並べ替え（選択の外は変えない）
- `:SortYomi` / `:GnosisSortYomi` … `\S`（ノーマル）と同じ
- 文章（リンクでない行）・コードブロックの中と、`### Context` / `### Related` / `### BackLink` 以降のリンクは動かさない。リンクが 0〜1 本なら何も変えない
- よみはリンク先ノートの front matter `yomi:`（表示名 → よみ）を優先。未登録は pykakasi で `yomi:` に自動追加
- `zy` / `zY` で表示名ごとのよみを手で修正/削除できる

## 紙のPKM（フォルゲゼッテル）

- `\f` … 紙PKM Index（`Paper-Zettelkasten-Index.md`）を開く／無ければ作る（`:GnosisPaperIndex`）。Index-write と Folgezettel-Index も作られる。更新は `\ua`
- `\F` … スキャン画像に番号を付けて vault 直下へ移動（`:GnosisScan`。番号付け GUI が開く）。GUI で `d` = **紙の日記として登録**
- `Index-write` … `キーワード(よみ): 1,1a10b,3` の形式で手書き。複数IDのキーワードはグループノート、単一IDは直接リンクとして紙PKM Index に並ぶ（保存で自動再生成）
- `\S` … Index-write ではキーワード行もよみ順に並べる
- Folgezettel-Index は存在する全IDの一覧（自然順）。生成物なので `\S` しない

## Ex コマンド一覧

すべてのコマンドの正式名は `:Gnosis` で始まる（`:Gnosis` のあと Tab で候補）。旧名の `:Yurii` で始まるコマンドは、同じ名前の `:Gnosis` のコマンドの別名（互換）。短い旧名（`:NF` など）も互換のため残している。

### 起動・vault・設定
- `:GnosisStart` `:GnosisVaults` `:GnosisSettings` `:GnosisThemeAdd` `:GnosisThemeReset` `:GnosisIndex` `:GnosisChooseIndex` `:GnosisChooseIndexDir` `:GnosisGuide` `:GnosisWeb`

### ノート作成・移行
- `:GnosisNF` / `:NF` タイトル指定で素早く新規 ・ `:GnosisNA` / `:NA` カーソル直下に「A」型 ・ `:GnosisNH` / `:NH` ここに新規
- `:GnosisNP` / `:NP` 親として新規 ・ `:GnosisNC` / `:NC` 子として新規 ・ `:GnosisV2Migrate` / `:V2Migrate` 旧形式から移行

### リンク・関係
- `:GnosisLinkify` / `:Linkify` カーソル下をリンク化 ・ `:GnosisLinkifySelection` / `:LinkifySelection` 選択を新ノートに ・ `:GnosisPasteLink` / `:PasteLink` クリップボードをリンク追加
- `:GnosisAT` `:GnosisBC` `:GnosisCA` `:GnosisCU` `:GnosisTT` / `:AT` `:BC` `:CA` `:CU` `:TT` … クリップボードを関係付きで追加 ・ `:GnosisYN` / `:YN` ファイル名ヤンク
- `:GnosisLT` / `:LT` / `:GnosisRenameLinkText` / `:RenameLinkText` 表示名変更 ・ `:GnosisNT` / `:NT` タイトル変更 ・ `:GnosisRenameChildLinkTitles` / `:RenameChildLinkTitles` / `:GnosisRenameDownLinkTitles` / `:RenameDownLinkTitles` 子リンク表示名を追従
- `:GnosisWNext` w で残したリンク先を次々に開く ・ `:GnosisContextMigrate` 旧形式の Context を新形式へ明示的に移す ・ `:GnosisBranchCheck` Branch の整合性を検査（親が複数・片側だけ・循環・自己参照を報告。何も書き換えない） ・ `:GnosisLinkPick` / `:LinkPick` 全文検索してリンク挿入 ・ `:GnosisSearch` / `:GnosisFSearch` / `:FSearch` 全文検索 ・ `:GnosisFileContentSearch` / `:FileContentSearch` 全文検索

### 移動
- `:GnosisTabs` 作業タブの一覧（`\q`） ・ `:GnosisOpenLinkTab` リンクを新しい作業タブで開く（`\o`）
- `:GnosisJumpParent` / `:JumpParent` / `:GnosisJumpUp` / `:JumpUp` 親へ ・ `:GnosisJumpChildTop` / `:JumpChildTop` / `:GnosisJumpDownTop` / `:JumpDownTop` 子の先頭 ・ `:GnosisJumpChildBottom` / `:JumpChildBottom` / `:GnosisJumpDownBottom` / `:JumpDownBottom` 子の末尾
- `:GnosisJumpLastLinkBeforeParent` / `:JumpLastLinkBeforeParent` / `:GnosisJumpLastLinkBeforeUp` / `:JumpLastLinkBeforeUp` Context 付近の最後のリンクへ

### 展開・アウトライン
- `:GnosisSE` / `:SE` / `:GnosisExpandToT` / `:ExpandToT` / `:GnosisExpandLinks` / `:ExpandLinks` S ノートを展開 ・ `:GnosisOutlineEdit` / `:OutlineEdit` 見出し編集（`:OutlineApply` で反映）

### 日記・暗号・ゴミ箱・紙PKM・画像
- `:GnosisRefreshColors` 検索ハイライトなどの残りを消して配色を描き直す ・ `:GnosisColorDoctor` 配色の診断ログを Gnosis ホームの logs に書く
- `:GnosisToday` `:GnosisDiaryAdopt` `:GnosisDiaryUpdate` / `:SimpleDiaryUpdate` 日記
- `:GnosisMount` `:GnosisLock` `:GnosisSetPassword` `:GnosisRemovePassword` `:GnosisBackup` `:GnosisExitCleanup` 暗号化
- `:GnosisTrash` `:GnosisTrashList` `:GnosisTrashEmpty` ゴミ箱 ・ `:GnosisPaperIndex` 紙PKM Index ・ `:GnosisScan` スキャン取り込み
- `:GnosisSetImageSize` / `:SetImageSize` 画像サイズ ・ `:GnosisGallery` / `:Gallery` ・ `:GnosisGalleryFolder` / `:GalleryFolder` 画像ギャラリー

### 表
- `:GnosisTableNew` / `:TN` / `:NewTable` 新規 ・ `:GnosisTableAlign` / `:TA` 整形 ・ `:GnosisTableRowEdit` / `:TRE` 行編集 ・ `:GnosisTableCsvEdit` / `:TCSV` / `:TableCsvEdit` CSV 編集 ・ `:GnosisTableCsvApplySaved` / `:TableCsvApplySaved` CSV 反映
- `:GnosisTableToCsv` / `:TCE` / `:TableToCsv` CSV へ ・ `:GnosisCsvToTable` / `:CsvToTable` CSV から ・ `:GnosisTableCsvNew` / `:TCN` / `:TableCsvNew` 別 CSV ・ `:GnosisTableAddRow` / `:TAR` `:GnosisTableAddCol` / `:TAC` 行/列追加 ・ `:GnosisTableDelRow` / `:TDR` `:GnosisTableDelCol` / `:TDC` 行/列削除

### 同期・その他
- `:GnosisUpdateMD` / `:UpdateMD` / `:GnosisUpdateAll` / `:UpdateAll` / `:UpdateALL` 同期 ・ `:GnosisSortYomi` / `:SortYomi` よみ順 ・ `:GnosisSortTime` / `:SortTime` 時刻順 ・ `:GnosisToggleCheckbox` / `:ToggleCheckbox` チェック切替 ・ `:GnosisCopyStack` / `:CopyStack`
- `:GnosisCheckPrefix` / `:CheckPrefix` 接頭辞検査 ・ `:GnosisRename` / `:Rename` ファイル名変更 ・ `:GnosisAutocwindow` / `:Autocwindow` quickfix 自動ジャンプ切替 ・ `:GnosisRP` / `:RP` 接頭辞リネーム
- `:GnosisFcitxOn` `:GnosisFcitxOff` `:GnosisFcitxStatus` 日本語入力（fcitx）の切り替え（Linux）
- `:Gnosis` … 入口（`:Gnosis` のあとに Tab で候補を出す）

## Vim の基本操作（詳細）

### モード
- ノーマル（起動時。`Esc` で戻る）… 移動・削除・コピー・貼り付けの土台
- 挿入 … `i` 前 / `a` 後 / `I` 行頭 / `A` 行末 / `o` 下に新行 / `O` 上に新行
- ビジュアル … `v` 文字 / `V` 行 / `<C-v>` 矩形。範囲を選んで `y` コピー `d` 削除 `c` 変更 `>` `<` インデント `~` 大小
- コマンドライン … `:`（Ex コマンド） / `/` `?`（検索）
- 迷ったら `Esc` を押してノーマルに戻る

### カーソル移動
- `h` `j` `k` `l` … 左 下 上 右（この環境は `j`/`k` = 表示行移動 `gj`/`gk`）
- `w` 次単語頭 / `b` 前単語頭 / `e` 単語末 / `ge` 前の単語末
- `0` 行頭 / `^` 最初の非空白 / `$` 行末
- `f<文字>` 次にその文字 / `t<文字>` その手前 / `F` `T` 逆方向 / `;` 繰り返し / `,` 逆の繰り返し
- `gg` 先頭 / `G` 末尾 / `{数}G` 指定行 / `H` `M` `L` 画面の上・中・下
- `<C-d>` 半画面下 / `<C-u>` 半画面上 / `<C-f>` 1画面下 / `<C-b>` 1画面上
- `zz` 中央 / `zb` 下（画面内の位置調整）
- `{` `}` 段落 / `(` `)` 文 / `%` 対応する括弧
- `<C-o>` 前のジャンプへ / `<C-i>` 次のジャンプへ

### 編集
- 削除: `x` 1文字 / `dd` 1行 / `dw` 単語 / `d$` 行末まで / `d` + モーション
- 変更: `cc` 1行 / `cw` 単語 / `ciw` 単語内 / `ci(` 括弧内
- コピー: `yy` 1行 / `yw` 単語 / `y$` 行末まで
- 貼り付け: `p` カーソルの後 / `P` 前（Vim 標準。PC の内容は `\v`）
- `r` 1文字置換 / `R` 上書き / `J` 行結合 / `~` 大文字小文字
- `u` 元に戻す / `<C-r>` やり直す / `.` 直前の変更を繰り返す
- 数え: `3j` `2dd` `5x` のようにコマンドの前に数字を置く
- インデント: `>>` `<<` / ビジュアルで `>` `<` / `=` 自動整形

### テキストオブジェクト（範囲を指定して編集）
- `iw` 単語 / `aw` 単語と空白 / `i"` `a"` 引用符の中 / `i(` `a(` 括弧の中 / `it` タグの中 / `ip` 段落
- 例: `ciw` で単語を書き換え / `di"` で引用符の中を削除 / `ya(` で括弧ごとコピー

### 検索
- `/語` 下へ検索 / `?語` 上へ / `n` 次 / `N` 前
- `*` カーソル下の単語を検索 / `#` 逆向き / `:noh` ハイライト解除

### コマンドライン
- `:w` 保存 / `:q` 終了 / `:wq` 保存して終了 / `:q!` 破棄して終了 / `:e ファイル` 開く
- `:bnext` `:bprev` バッファ移動 / `:help 語` ヘルプ / `:marks` マーク一覧
- この環境は保存時に自動同期（`:UpdateMD` / `:UpdateAll` で全体整合）

### レジスタ / クリップボード
- 無名 `"` / 番号 `0`〜`9` / 名前付き `a`〜`z` / システム `+` `*`
- `"ayy` で a にコピー / `"ap` で a を貼る
- PC のクリップボードは `\v` で貼る。`yy` `dd` `ciw` などでコピーした内容は PC 側にも流れる

### マーク / マクロ
- `ma` でマーク a / バッククォート + `a` でその位置へ / `:marks` で一覧
- `qa` 記録開始 / `q` 終了 / `@a` 再生 / `@@` 再実行

### この環境での Vim 標準との違い
- `j`/`k` は表示行移動（折り返した行も1行ずつ）。論理行は `+` / `-` や `{数}G` を使う
- `1`〜`9` `0` はリンクの番号ジャンプ（該当が無ければ数字はカウントとして素通り）
- `p` / `P` は Vim 標準。PC の内容を貼るのは `\v` / `\V`
- `_` は直前ノートと往復。`,`（f/t リピート）は標準のまま
- `zt` はタイトル変更（Vim 標準の「画面の上へ」ではない）。`zA` は表示名つきの追加
- プラグインの 2 文字コマンドは `z` / `g` / `\` 接頭辞（素のキーを待たせないため）
