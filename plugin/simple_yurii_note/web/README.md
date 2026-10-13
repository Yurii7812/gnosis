# simple_yurii_note app

SYN（simple_yurii_note）を、**マークダウンのビューアの見た目**で使うアプリ（Electron）。
中身は**本物の Vim**（`~/.vimrc-simple-yurii-note`、SYN・fzf・vim-surround などのプラグイン入り）。
機能を作り直していないので、操作は Vim で使っているものと同じ（`zn`・Tab・数字キー・`\ua`・`\l` ほか全部）。
違いは、バッファがマークダウンとして描画されること（見出し・箇条書き・チェックボックス・引用・画像・リンク）だけ。

```
Vim ──(擬似端末)──► xterm.js …… メッセージ・質問・fzf・Enter 待ちなどの端末画面
Vim ──(TCP/JSON)──► 画面 ……… バッファの全文・カーソル・モード・リンクの数字のしるし（仮想テキスト）
キー入力 ──► 擬似端末 ──► Vim
```

- 画面の上: マークダウン表示（読み取り専用。カーソルは Vim のものを映す）。リンクをクリックすると開く。
- 画面の下: 本物の Vim の画面の下 3 行（ステータス行・コマンド行・メッセージ）。確認・fzf・ポップアップ・
  Enter 待ちのときは、端末の画面全体に広がる。
- **F2: 見るだけモード ⇔ 普通の Vim**。見るだけ（下に VIEW と出る）は、カーソルも選択も出さず、ノートを
  変えるキーは Vim に送らない。j/k・矢印・PageUp/Down・gg/G・Ctrl-d/u はスクロール。編集しない SYN の操作は
  Vim に届く: `gs` `gm` Space Tab/Shift-Tab Enter Backspace `_` 数字キー(0-9) `\h` `\H` `\0` `\i` `\d` `\.`
  `\L` `\gi` `\r` `\bu` `\k` `\j` `\J` `\sc`。リンクはクリックでも開く。確認・fzf・コマンドライン入力中は
  すべてのキーが Vim へ届く。起動時は普通の Vim。許可するキーは `src/app.js` の `VIEW_PASS`。
- 一番下: モード表示（NORMAL / INSERT / VISUAL …）。

## 起動

```bash
npm install            # 初回
npm run build          # src/*.js -> bundle.js
npm run app            # = electron .
```

Vim からは `\A` / `:YuriiWeb`。直接: `bin/simple-yurii-note-app.sh [VAULT_DIR]`。

環境変数: `PKM_ROOT`（SYN の root。省略すると Vim が前回の root を使う）、`PKM_FILE`（最初に開くノート）、
`PKM_VIMRC`（使う vimrc。既定 `~/.vimrc-simple-yurii-note`）。

## 作り

- `bridge/ptybridge.py` … Vim を擬似端末で動かす。Node は pty を扱えないので、この Python が間に入る。
- `vim/gui.vim` … Vim に `-S` で読ませる。状態（全行・カーソル・モード・仮想テキスト）を JSON で送る。
- `electron/main.cjs` … 擬似端末と TCP を持つ。`electron/preload.cjs` … 画面との橋渡し。
- `src/view.js` … 読み取り専用のマークダウン描画（CodeMirror 6）。`src/app.js` … 端末と状態の反映。

## テスト

```bash
npm test               # = node test/gui_e2e.mjs
```

実際の Electron + 本物の Vim を、仮想ディスプレイ (xvfb) と一時フォルダ（HOME も別）で動かす。
本物の vault や設定は書き換えない。

過去の Obsidian 風アプリは、git タグ `app-obsidian-style` と `~/.archive-projects/` に残してある。
