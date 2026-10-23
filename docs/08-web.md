# 08 アプリ（マークダウン表示で使う本物の Vim）

**2026-10-13〜 Gnosis**: 起動するとまず HTML の**起動画面**（白背景・黒文字。Chnoubis のシンボル・Gnosis・選択中の vault・Enter で開始）。
`v` / ボタンで vault の一覧（登録・新規作成・一覧から外す）、`s` / ボタンで設定画面（言語・最大化・ウィンドウサイズ・文字サイズ・
ライト/ダーク・テーマ・Plug でテーマ追加・カスタム配色。`<vault>/.gnosis/settings.json`）。Enter で、その vault の Vim を起動する。
vault を開いたあとは、Vim が読み込んだテーマの色を画面にも使う。
**アプリ（`\c`）の配色は通常の Vim の配色とは別の設定**（`appTheme` / `appCustomThemes`）。既定は白に近い背景（`#FAFAFA`・本文 `#1F1F1F`・リンク `#21538C` 下線つき・見出し `#603510`。どれもカラーパレットにある色）。設定画面の「配色を作る・直す」で、色（HEX・カラーピッカー・8×9 のパレット）を変えると、保存する前でも日本語のサンプル（見出し・リンク・選択範囲・カーソル行）にすぐ反映される。「保存して使う」まで設定は書き換えない。キャンセルで元の配色に戻る。通常の Vim の配色も同じ画面で別に編集できる。`Ctrl` + `+`/`-`/`0` は画面全体の拡大縮小（その場だけ）。
リンクを `Alt` + クリックすると、開かずにカーソルだけを動かす。Vim の `\c` から開いたときは、起動画面を出さずにその vault で始める。
実装: `web/electron/config.cjs`（Vim 側と同じ規則の登録簿・設定・テーマ）、`web/src/launcher.js`（画面）、`web/vim/gui.vim`（色・文字サイズ・vault を送る、設定の読み直しを受ける）。

SYN を、**マークダウンのビューアの見た目**で使うデスクトップアプリ（Electron）。
中身は**本物の Vim**（`~/.vimrc-simple-yurii-note`、SYN・fzf・vim-surround などのプラグイン入り）。
機能を作り直していないので、操作は Vim で使っているものと同じ（`zn`・Tab・数字キー・`\ua`・`\L` ほか全部）。
**Vim との違いは、バッファがマークダウンとして描画されることだけ**（見出し・箇条書き・チェックボックス・
引用・画像・リンク。カーソルのある行は生の Markdown）。

過去の Obsidian 風アプリ（サイドバー・タブ・グラフ付き）は、git タグ `app-obsidian-style` と
`~/.archive-projects/simple-yurii-note-app-obsidian/` に残してある。

## 起動

- Vim から: `\c` または `:GnosisWeb`。今の root と、今開いているノートを渡して起動する。
- 直接: `bin/gnosis --app [VAULT_DIR]`（引数なしなら Vim が前回の root を使う）。
  アプリメニュー: `~/.local/share/applications/simple-yurii-note.desktop`。
- 初回だけ `cd web && npm install && npm run build`。

## 画面

- 上: マークダウン表示（読み取り専用）。カーソル・ビジュアル選択・リンクの数字のしるし（1〜9, 0, g1 など）
  も、Vim のものをそのまま映す。リンクをクリックするとそのリンクへ移る。
- 下: 本物の Vim の画面の下 3 行（ステータス行・コマンド行・メッセージ）。確認（`confirm`）・fzf・
  ポップアップ・Enter 待ち（`:ls` など）のときは、端末の画面全体に広がり、終わると戻る。
- 一番下: モード表示（NORMAL / INSERT / VISUAL / V-LINE / V-BLOCK / REPLACE / COMMAND …）。
- 色は vault の設定のテーマ（起動画面だけは白黒）。

## 仕組み

```
Vim ──(擬似端末)──► xterm.js …… 端末の画面（メッセージ・質問・fzf）
Vim ──(TCP/JSON)──► 画面 ……… バッファの全文・カーソル・モード・仮想テキスト（数字のしるし）
キー入力 ──► 擬似端末 ──► Vim
```

- `web/bridge/ptybridge.py` … Vim を擬似端末で動かす（Node は pty を直接扱えない）。
- `web/vim/gui.vim` … Vim に `-S` で読ませ、状態を JSON で送る。`ttimeoutlen=20`（Esc をすぐ効かせる）だけ
  端末版と違う。
- `web/electron/main.cjs` … 擬似端末と TCP を持つ。画像は、ノートのあるフォルダからの相対パスで読む。
- `web/src/view.js` … 読み取り専用のマークダウン描画（CodeMirror 6）。`web/src/app.js` … 端末と状態の反映。
- 環境変数: `GNOSIS_ROOT`（root）、`GNOSIS_FILE`（最初に開くノート）、`GNOSIS_VIMRC`（使う vimrc）。

## 注意

- アプリの Vim と、ターミナルで開いている Vim は別のプロセス。同じノートを両方で開いて編集しない
  （SYN の保存・同期は Vim ごとに動く）。
- テスト: `cd web && npm test`（実際の Electron + 本物の Vim を xvfb と一時フォルダで動かす。本物の vault や
  設定は書き換えない）。

## Windows

Windows でも動くように作ってあります（Linux は今のまま）。**Windows で実機の確認はまだしていません**（開発は Linux）。

1. Windows 版の Vim（`vim.exe`。`+channel` が効くもの）を入れて、PATH を通す。
2. Node.js を入れて、`web` フォルダで次を実行する:
   ```bat
   npm install
   npm run rebuild:pty
   ```
   `rebuild:pty` は `node-pty`（Windows の擬似端末 ConPTY）を、Electron 用に作り直す。
3. Vim の設定は Windows 用に用意する。`GNOSIS_VIMRC` で vimrc の場所を指定できる。SYN のプラグインの
   `runtimepath` は、Windows のパスで書く。
4. 起動: `bin\gnosis.cmd --app [VAULT_DIR]`、または Vim で `\c`（`:GnosisWeb`）。

環境変数: `GNOSIS_VIM`（Vim の実行ファイル。既定は PATH の `vim`）、`GNOSIS_PTY`（`node-pty` / `python`。
既定は Windows だけ `node-pty`）。`node-pty` の経路は、Linux でも `GNOSIS_PTY=node-pty` で動くことを確認済み。

## ライトの見え方（2026-10-20〜）
`\c` のライト（白）は、ブラウザの **Markdown Viewer 拡張（GitHub スタイル）と同じ見え方**にする。配色が明るいとき `html.theme-light` が付き、`web/styles.css` の該当ブロックが効く: 本文の幅 980px・余白 45px・行間 1.5・GitHub のフォント・見出し（h1/h2 に下線・本文と同じ色）・インラインコードの背景・コードブロック・引用の左線・表の罫線と偶数行・太い水平線・リンクは通常は下線なし。色は配色（palette）に従う。ダークは従来どおり。試験: `web/test/look_e2e.mjs`（計算済みスタイルの検査。`LOOK_SHOT=フォルダ` で目視用の画像も保存）。
