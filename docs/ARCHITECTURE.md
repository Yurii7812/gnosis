# アーキテクチャ（2026-10-20 時点の監査結果）

## 層（現状）
| 層 | 場所 | 規模 |
|---|---|---|
| Vim プラグイン（操作層の大半） | `autoload/gnosis.vim`（約 1.8 万行）、`autoload/gnosis/*.vim`、`plugin/` | 巨大な単一ファイルが中心 |
| Python ヘルパー（データ処理） | `python/`（ノート形式 `note_format_v2.py`、紙 PKM `paper_pkm.py`、Folgezettel、`capture_import.py` ほか） | 単体試験あり（`python/test_*.py`） |
| `\A` / `gnosis --app` | `web/`（Electron＋xterm.js＋CodeMirror 6 の**読み取り専用**描画。`vim/gui.vim` が TCP/JSON で状態を送る。`bridge/ptybridge.py` が Vim を pty で動かす） | `web/test/*.mjs` の E2E |
| Android | `android/`（Kotlin。`Store.kt` `Alarm.kt` `MainActivity.kt`）。PC へは adb `run-as` で `entries.json` を読む | Gradle |
| 試験 | `test/run.sh`（`set -e`）＋ `test/*_net.sh`（実 Vim）＋ CI `.github/workflows/gnosis-regression.yml`（一部のみ） | |

## 計画上の方針（案。DECISIONS に確定を書く）
- 新機能のデータ処理は Python 層（純関数＋単体試験）に置き、Vim コマンドと `\A` ボタンは同じ CLI／API を呼ぶ。
- `\A` は現在「Vim が唯一の書き込み主体、画面は読み取り専用」。GUI 編集モードは、Vim を介して（Vim バッファへ編集を送る）か、保存権を明示的に移す方式で、同時 2 書き込み主体を避ける設計が要る（Phase 2 の最初に設計）。
- `\M` の新 state は既存 `.state/capture_imported.json` を**読める**まま、追加フィールド（source ID・base 内容・ハッシュ）を持つ版 2 にする。
- SQLite FTS 等は派生キャッシュ（再構築可能）。

## 既知の資料矛盾（原本 §2 の指摘の確認）
- `docs/04-キー操作.md` 自身が古い操作を含むと注記。`NOTE_FORMAT.md` は過去形式を含む。正はコードとテスト。
- `docs/11-スマホのメモ.md` の「本文を書き直したら別版として取り込む」は原本 §7.3 により**廃止予定**（移行は Phase 1）。

## Phase 2 設計案: `\A` のタブ・分割と 3 モード（2026-10-20・**GUI 編集モードは承認待ち**）

### 現状（監査）
`\A` は Electron。`#stage` に 2 つ: `#view`（Vim バッファの全文・カーソル・モードを JSON で受け取って映す CodeMirror 6。読み取り専用）と `#termwrap`（xterm.js。擬似端末の中の**本物の Vim**）。Vim が唯一の書き込み主体。閲覧専用モード（Alt+V）はキーを Vim に送らないだけ。

### 方針 A: ペイン層（書き込み主体を増やさない。承認不要で進められる）
- レイアウト = 木。`split(dir, ratio, children)` と `tabs(active, tabs[])`。タブ = `{id, kind, params, pinned, title}`。保存は vault ごと（`<vault>/.gnosis/workspace.json`。ノートの原本ではない派生・利用者設定）。閉じたタブの再開・前回の復元・ペインごとの履歴。
- タブの種類: **`vim`（ちょうど 1 つ。今の `#stage` をそのまま入れる）** と、**表示専用ビュー**（`note`（読み取り専用の本文プレビュー）、`fznav`、`graph`、`agenda`、`cards`、`mandala`、`search`、`check` …）。ビューはどれも書き込まない。ノートを**編集**したいときは「Vim タブで開く」（Vim の `:edit`）。したがって「複数ノートを同時に開いて見比べる」「グラフとノートを並べる」は、書き込み主体を増やさずに実現できる。
- 共通 View API: `registerView(kind, {title, render(container, params, api)})`。`api.data(name, args)` は main プロセスの**許可リスト**の JSON コマンド（`gnosis_graph.py` `tasks.py` `export_site` の部品など）を呼ぶ。任意コマンド・任意パスは通さない（パスは vault 内に正規化）。`api.open(path, {where})` と `api.onChanged(cb)`（ファイル監視でビューを再描画）。
- 静的サイトのビュー（`python/site_assets/*.js`）を、そのまま `\A` のビューとして使う（データの渡し方だけ差し替える: `window.GNOSIS_*` → `api.data`）。→ 同じコードが HTML 書き出しと `\A` の両方で動く。
- 全機能に GUI 経路: コマンドパレット（`registerCommand`）が唯一の入口で、キー・メニュー・ボタンは同じコマンド ID を呼ぶ。

### 方針 B: 3 モードと「書き込み主体は常に 1 つ」（**要承認**）
1. Real Vim: 今のとおり。
2. 閲覧専用: 今の Alt+V を、モードの 1 つとして正式化（ビューのクリック・リンク移動・検索だけ。書き込み経路を持たない）。
3. **GUI 編集（Vim 非依存）**: 通常のテキスト／Markdown 編集（CodeMirror 6 の編集可能版。クリックでカーソル・選択・Undo/Redo・ツールバー・リンク補完・画像挿入）。
- **書き込み権（lease）**: ノートごとに「Vim」か「GUI」のどちらかだけが持つ。切替の手順（Vim → GUI）: ① Vim に `:update`（未保存を保存。保存前フック＝既存の自動同期も走る）② main が内容ハッシュを記録して renderer に渡す ③ CodeMirror に読み込む ④ Vim 側のそのバッファは読み取り扱い（`:set readonly` と、Vim へのキー送信を止める）。GUI → Vim: ① GUI が保存（下記）② Vim に `:checktime`/`:edit!` ③ 書き込み権を返す。
- GUI の保存: main の `gui-write(path, text, expectedHash)`。**期待ハッシュが今のファイルと違えば保存せず競合を返す**（外部変更・Android 取り込み・別ウィンドウ）。書き込みは一時ファイル＋`os.replace`。保存後に Vim 側と同じ同期（`note_format_v2.py update_one`）を main が呼ぶ（Vim の保存時の処理と同じ Python 入口なので二重実装にならない）。競合時は差分と「自分の版を残す／ディスクの版を採る／両方残す」を出す。
- 却下した案: GUI の入力を Vim へキー列として送る（脆い・Vim のモードに依存し GUI 編集の意味が失われる）／両方が同時に書く（データ損失）。
- **この方針 B は「書き込み主体」「保存・競合」の重大な設計判断なので、承認を得てから実装する**（DECISIONS D006）。

### 先に必要な土台
- `web/test/gui_e2e.mjs` が現行仕様で通ること（2026-10-20 に通した。`web` の E2E は Phase 2 の安全網）。
- 静的ビューを `api.data` で動かすための main 側 IPC（許可リスト・パス正規化・試験）。
