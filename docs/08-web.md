# 08 アプリ（マークダウン表示で使う本物の Vim）

SYN を、**マークダウンのビューアの見た目**で使うデスクトップアプリ（Electron）。
中身は**本物の Vim**（`~/.vimrc-simple-yurii-note`、SYN・fzf・vim-surround などのプラグイン入り）。
機能を作り直していないので、操作は Vim で使っているものと同じ（`zn`・Tab・数字キー・`\ua`・`\l` ほか全部）。
**Vim との違いは、バッファがマークダウンとして描画されることだけ**（見出し・箇条書き・チェックボックス・
引用・画像・リンク。カーソルのある行は生の Markdown）。

過去の Obsidian 風アプリ（サイドバー・タブ・グラフ付き）は、git タグ `app-obsidian-style` と
`~/.archive-projects/simple-yurii-note-app-obsidian/` に残してある。

## 起動

- Vim から: `\A` または `:SimpleWeb`。今の root と、今開いているノートを渡して起動する。
- 直接: `web/bin/simple-yurii-note-app.sh [VAULT_DIR]`（引数なしなら Vim が前回の root を使う）。
  アプリメニュー: `~/.local/share/applications/simple-yurii-note.desktop`。
- 初回だけ `cd web && npm install && npm run build`。

## 画面

- 上: マークダウン表示（読み取り専用）。カーソル・ビジュアル選択・リンクの数字のしるし（1〜9, 0, g1 など）
  も、Vim のものをそのまま映す。リンクをクリックするとそのリンクへ移る。
- 下: 本物の Vim の画面の下 3 行（ステータス行・コマンド行・メッセージ）。確認（`confirm`）・fzf・
  ポップアップ・Enter 待ち（`:ls` など）のときは、端末の画面全体に広がり、終わると戻る。
- 一番下: モード表示（NORMAL / INSERT / VISUAL / V-LINE / V-BLOCK / REPLACE / COMMAND …）。
- 色は常にライト。

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
- 環境変数: `PKM_ROOT`（root）、`PKM_FILE`（最初に開くノート）、`PKM_VIMRC`（使う vimrc）。

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
3. Vim の設定は Windows 用に用意する。`PKM_VIMRC` で vimrc の場所を指定できる。SYN のプラグインの
   `runtimepath` は、Windows のパスで書く。
4. 起動: `web\bin\simple-yurii-note-app.cmd [VAULT_DIR]`、または Vim で `\A`（`:SimpleWeb`）。

環境変数: `PKM_VIM`（Vim の実行ファイル。既定は PATH の `vim`）、`PKM_PTY`（`node-pty` / `python`。
既定は Windows だけ `node-pty`）。`node-pty` の経路は、Linux でも `PKM_PTY=node-pty` で動くことを確認済み。

