// Gnosis のデスクトップアプリ (Electron)。
// 本物の Vim（Gnosis 専用の vimrc と、そのプラグイン領域だけを読むもの）を擬似端末の中で動かし、
// その画面を、マークダウンのビューアの見た目で表示する。機能は Vim そのもの（作り直していない）。
//
//   起動画面（HTML）… Chnoubis・vault の選択・管理・設定 → Enter で Vim を起動
//   Vim ──(擬似端末)──► xterm.js … メッセージ・質問・fzf などの端末画面
//   Vim ──(TCP/JSON)──► 画面 …… バッファの全文・カーソル・モード・配色（マークダウンで描画）
//   キー入力 ──► 擬似端末 ──► Vim
//
// 環境変数（GNOSIS_* が無ければ旧名 PKM_* も読む）:
//   GNOSIS_ROOT  … vault（指定すると起動画面を出さずにその vault で始める。Vim の \c から）
//   GNOSIS_FILE  … 最初に開くノート
//   GNOSIS_VIMRC … 使う vimrc（既定: Gnosis ホームの vimrc、無ければ本体の vimrc_gnosis）
//   GNOSIS_VIM   … Vim の実行ファイル（既定: PATH の vim）
//   GNOSIS_HOME  … Gnosis ホーム（vault の登録簿など）
const { app, BrowserWindow, ipcMain, Menu, dialog, nativeImage } = require("electron");
const { spawn } = require("child_process");
const { StringDecoder } = require("string_decoder");
const net = require("net");
const path = require("path");
const os = require("os");
const fs = require("fs");
const cfg = require("./config.cjs");
const noteio = require("./noteio.cjs");

const env = (name) => process.env["GNOSIS_" + name] || process.env["PKM_" + name] || "";
const WEB = path.resolve(__dirname, "..");
const REPO = cfg.REPO;
const TEST = env("TEST_SCRIPT");

function vimrcPath() {
  if (env("VIMRC")) return env("VIMRC");
  const home = path.join(cfg.gnosisHome(), "vimrc");
  if (fs.existsSync(home)) return home;
  return path.join(REPO, "vimrc_gnosis");
}
const EXPLICIT_ROOT = env("ROOT") ? path.resolve(env("ROOT")) : "";
const OPEN = env("FILE");

// ログ: <Gnosis ホーム>/logs/app.log（画面のエラー・Vim の標準エラー・終了など）。
const LOG_FILE = path.join(cfg.gnosisHome(), "logs", "app.log");
function log(msg) {
  try {
    fs.mkdirSync(path.dirname(LOG_FILE), { recursive: true });
    fs.appendFileSync(LOG_FILE, new Date().toISOString() + " " + String(msg).replace(/\n+$/, "") + "\n");
  } catch { /* ログが書けなくても動かす */ }
}
try {
  if (fs.existsSync(LOG_FILE) && fs.statSync(LOG_FILE).size > 1024 * 1024) fs.writeFileSync(LOG_FILE, "");
} catch { /* ignore */ }
process.on("unhandledRejection", (e) => log("unhandledRejection: " + (e && e.stack || e)));

const uncaught = [];
process.removeAllListeners("uncaughtException");
process.on("uncaughtException", (e) => { uncaught.push(String(e && e.stack || e)); log("uncaughtException: " + (e && e.stack || e)); });

// 画面（window）へ送る。窓を閉じたあとに「Object has been destroyed」で落ちないよう、生きているときだけ。
function send(channel, ...args) {
  try {
    if (win && !win.isDestroyed() && !win.webContents.isDestroyed()) win.webContents.send(channel, ...args);
  } catch (e) { log("send failed (" + channel + "): " + e); }
}

let win = null;
let bridge = null;
let server = null;
let vimSock = null; // Vim（gui.vim）とつないだソケット。アプリ → Vim の知らせにも使う
let activeVault = "";
let noteRootDir = ""; // 開いている vault のノートのフォルダ（GUI 編集モードの読み書きの範囲）
let ackSeq = 0;
const pendingAck = new Map(); // id → resolve（Vim へ送った知らせの応答待ち）

// Vim（gui.vim）へ知らせを送り、{ack: id, ...} の応答を待つ。Vim がつながっていない・応答が無いときは {ok:false, error}。
function vimCall(msg, timeoutMs = 10000) {
  return new Promise((resolve) => {
    if (!vimSock) return resolve({ ok: false, error: "Vim がつながっていません" });
    const id = ++ackSeq;
    const timer = setTimeout(() => { pendingAck.delete(id); resolve({ ok: false, error: "Vim から応答がありません" }); }, timeoutMs);
    pendingAck.set(id, (r) => { clearTimeout(timer); resolve(r); });
    try { vimSock.write(JSON.stringify({ ...msg, id }) + "\n"); } catch (e) { clearTimeout(timer); pendingAck.delete(id); resolve({ ok: false, error: String(e) }); }
  });
}
let newVaults = new Set(); // このアプリで作ったばかりの vault（Index を黙って作る）

function startServer() {
  return new Promise((resolve) => {
    server = net.createServer((sock) => {
      vimSock = sock;
      let buf = "";
      sock.setEncoding("utf8");
      sock.on("data", (d) => {
        buf += d;
        let i;
        while ((i = buf.indexOf("\n")) >= 0) {
          const line = buf.slice(0, i);
          buf = buf.slice(i + 1);
          let st; try { st = JSON.parse(line); } catch { continue; } /* 壊れた行は捨てる */
          if (st && typeof st.ack === "number") { const f = pendingAck.get(st.ack); if (f) { pendingAck.delete(st.ack); f(st); } continue; }
          if (st.vault && !cfg.same(st.vault, activeVault)) { activeVault = st.vault; }
          send("vim:state", st);
        }
      });
      sock.on("error", () => {});
    });
    server.listen(0, "127.0.0.1", () => resolve(server.address().port));
  });
}

// 擬似端末。Linux/macOS … 同梱の bridge/ptybridge.py（python3 の pty）。Windows … node-pty（ConPTY）。
function startPty(cmd, args, penv, cols, rows, onData, onExit) {
  const kind = env("PTY") || (process.platform === "win32" ? "node-pty" : "python");
  if (kind === "node-pty") {
    let pty;
    try { pty = require("node-pty"); } catch (e) {
      throw new Error("node-pty が読み込めません / cannot load node-pty: npm install && npm run rebuild:pty — " + e.message);
    }
    const p = pty.spawn(cmd, args, { name: "xterm-256color", cols, rows, env: penv, cwd: os.homedir() });
    p.onData(onData);
    p.onExit(({ exitCode }) => onExit(exitCode));
    return {
      write: (d) => p.write(d),
      resize: (c, r) => { try { p.resize(c, r); } catch { /* 終了後は無視 */ } },
      kill: () => { try { p.kill(); } catch { /* ignore */ } },
    };
  }
  const py = process.platform === "win32" ? "python" : "python3";
  const bridgeArgs = [path.join(WEB, "bridge", "ptybridge.py"), String(cols), String(rows), "--", cmd, ...args];
  const child = spawn(py, bridgeArgs, { env: penv, stdio: ["pipe", "pipe", "pipe", "pipe"] });
  const dec = new StringDecoder("utf8");
  child.stdout.on("data", (d) => { const t = dec.write(d); if (t) onData(t); });
  child.stderr.on("data", (d) => { process.stderr.write(d); log("vim/bridge stderr: " + d); });
  child.on("exit", (code) => onExit(code));
  const ctl = child.stdio[3];
  return {
    write: (d) => child.stdin.write(d),
    resize: (c, r) => { try { ctl?.write(JSON.stringify({ cols: c, rows: r }) + "\n"); } catch { /* ignore */ } },
    kill: () => { try { child.kill("SIGKILL"); } catch { /* ignore */ } },
  };
}

const vimStr = (s) => "'" + String(s).replace(/'/g, "''") + "'";

async function startVim(cols, rows, vaultPath) {
  if (bridge) return;
  { // ワークスペースの読み込みなどが先に来ても vault の場所が分かるように、最初に決めておく
    const v = vaultPath || EXPLICIT_ROOT;
    if (v) noteRootDir = EXPLICIT_ROOT && !vaultPath ? EXPLICIT_ROOT : cfg.noteRoot(v);
  }
  const port = await startServer();
  const vimCmd = env("VIM") || "vim";
  const args = ["-u", vimrcPath(), "--cmd", "let g:gnosis_start_screen = 0"];
  const vault = vaultPath || EXPLICIT_ROOT;
  if (vault) {
    activeVault = cfg.normalize(vault);
    const root = EXPLICIT_ROOT && !vaultPath ? EXPLICIT_ROOT : cfg.noteRoot(vault);
    noteRootDir = root;
    args.push("--cmd", `let g:gnosis_root = ${vimStr(root.replace(/\\/g, "/") + "/")}`);
    if (newVaults.has(cfg.normalize(vault))) args.push("--cmd", "let g:gnosis_new_vault = 1");
  }
  args.push("-S", path.join(WEB, "vim", "gui.vim"));
  const penv = { ...process.env, GNOSIS_GUI_PORT: String(port), TERM: "xterm-256color", COLORTERM: "truecolor", GNOSIS_FILE: OPEN };
  log(`start vim: vault=${vault || "(none)"} vimrc=${vimrcPath()}`);
  try {
    bridge = startPty(vimCmd, args, penv, cols, rows,
      (t) => send("pty:data", t),
      (code) => {
        log("vim exited: code=" + code);
        send("vim:exit", code);
        if (!TEST) app.quit();
      });
  } catch (e) {
    log("start failed: " + (e && e.stack || e));
    send("pty:data", "\r\n[起動できませんでした / could not start] " + String(e && e.message || e) + "\r\n");
    bridge = null;
  }
}

// 最初の窓の大きさ: 起動に使う vault（指定 or 最後に選んだもの）の設定
function initialSettings() {
  const v = EXPLICIT_ROOT ? cfg.normalize(path.basename(EXPLICIT_ROOT) === "note" ? path.dirname(EXPLICIT_ROOT) : EXPLICIT_ROOT) : cfg.lastVault();
  return cfg.loadSettings(v && cfg.isDir(v) ? v : "");
}

// 起動サイズ（最大化は「最大化」であって全画面表示ではない）
let maximizeRequested = null; // 試験用: 最後に求めた状態（ウィンドウマネージャーの無い xvfb では実際には最大化されない）
function applyWindow(s, first) {
  if (!win || win.isDestroyed()) return;
  maximizeRequested = !!s.window.maximized;
  if (s.window.maximized) {
    if (!win.isMaximized()) win.maximize();
  } else {
    if (win.isMaximized()) win.unmaximize();
    if (!first) win.setSize(s.window.width, s.window.height);
  }
}

function iconPath() {
  const p = path.join(REPO, "assets", "icons", process.platform === "win32" ? "gnosis.ico" : "gnosis-256.png");
  return fs.existsSync(p) ? p : undefined;
}

function createWindow() {
  const s = initialSettings();
  win = new BrowserWindow({
    width: s.window.width,
    height: s.window.height,
    show: false,
    title: "Gnosis",
    icon: iconPath(),
    backgroundColor: "#ffffff",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });
  Menu.setApplicationMenu(null);
  log(`start: root=${EXPLICIT_ROOT || "(start screen)"} file=${OPEN || "(none)"} vimrc=${vimrcPath()}`);
  win.webContents.on("console-message", (...a) => {
    const d = a[1] && typeof a[1] === "object" ? a[1] : null;
    const lvl = d ? d.level : a[1];
    const msg = d ? d.message : a[2];
    if ((lvl === "error" || lvl === 3) && !/Electron Security Warning/.test(String(msg))) log("renderer error: " + msg);
  });
  win.webContents.on("render-process-gone", (_e, det) => log("render-process-gone: " + JSON.stringify(det)));
  // Ctrl + / - / 0 … 画面全体の拡大・縮小・元に戻す（その場だけ。文字サイズの設定とは別）
  win.webContents.on("before-input-event", (e, input) => {
    if (input.type !== "keyDown" || !(input.control || input.meta) || input.alt) return;
    const wc = win.webContents;
    if (input.key === "+" || input.key === "=" || input.key === ";") { wc.setZoomLevel(Math.min(wc.getZoomLevel() + 0.5, 5)); e.preventDefault(); }
    else if (input.key === "-" || input.key === "_") { wc.setZoomLevel(Math.max(wc.getZoomLevel() - 0.5, -4)); e.preventDefault(); }
    else if (input.key === "0" && !input.shift) { wc.setZoomLevel(0); e.preventDefault(); }
  });
  win.once("ready-to-show", () => { applyWindow(s, true); win.show(); win.focus(); });
  win.loadFile(path.join(WEB, "index.html"));
  win.on("page-title-updated", (e) => e.preventDefault());

  // テスト用: GNOSIS_TEST_SCRIPT の JS を画面で実行し、結果を GNOSIS_TEST_OUT に書いて終了する
  const consoleLog = [];
  if (TEST) {
    win.webContents.on("console-message", (...a) => {
      const d = a[1] && typeof a[1] === "object" ? a[1] : null;
      const lvl = d ? d.level : a[1];
      const msg = d ? d.message : a[2];
      if (lvl === "error" || lvl === "warning" || lvl === 2 || lvl === 3) consoleLog.push(String(msg).slice(0, 300));
    });
    win.webContents.on("render-process-gone", (_e, det) => consoleLog.push("render-process-gone " + JSON.stringify(det)));
    win.webContents.on("did-finish-load", async () => {
      let result;
      try {
        result = await win.webContents.executeJavaScript(fs.readFileSync(TEST, "utf8"));
      } catch (e) { result = { fatal: String(e && e.stack || e) }; }
      const png = result && result.__png;
      const closeWindow = !!(result && result.__closeWindow);
      if (result) { delete result.__png; delete result.__closeWindow; }
      if (result && typeof result === "object" && !Array.isArray(result)) {
        result.__console = consoleLog.slice(0, 20);
        result.__window = { maximized: win.isMaximized(), maximizeRequested, fullscreen: win.isFullScreen(), zoom: win.webContents.getZoomLevel() };
        // Ctrl + = / Ctrl + 0 を本物のキー入力として送り、画面全体の拡大と元に戻すことを確かめる
        try {
          win.webContents.sendInputEvent({ type: "keyDown", keyCode: "=", modifiers: ["control"] });
          await new Promise((r) => setTimeout(r, 300));
          result.__window.zoomAfterCtrlPlus = win.webContents.getZoomLevel();
          win.webContents.sendInputEvent({ type: "keyDown", keyCode: "0", modifiers: ["control"] });
          await new Promise((r) => setTimeout(r, 300));
          result.__window.zoomAfterCtrl0 = win.webContents.getZoomLevel();
        } catch (e) { result.__window.zoomError = String(e); }
      }
      const out = env("TEST_OUT");
      fs.writeFileSync(out, JSON.stringify(result, null, 2));
      if (png) {
        try {
          const img = await Promise.race([
            win.webContents.capturePage(),
            new Promise((_, rej) => setTimeout(() => rej(new Error("capture timeout")), 8000)),
          ]);
          fs.writeFileSync(png, img.toPNG());
        } catch { /* ignore */ }
      }
      if (closeWindow) {
        try { win.destroy(); } catch { /* ignore */ }
        try { bridge?.kill(); } catch { /* ignore */ }
        await new Promise((r) => setTimeout(r, 1500));
        try {
          const cur = JSON.parse(fs.readFileSync(out, "utf8"));
          cur.__uncaught = uncaught.slice(0, 5);
          fs.writeFileSync(out, JSON.stringify(cur, null, 2));
        } catch { /* ignore */ }
      }
      try { bridge?.kill(); } catch { /* ignore */ }
      setTimeout(() => process.exit(0), 100);
    });
  }
}

// ---------------------------------------------------------------- 起動画面・vault・設定（画面から呼ぶ）

function launcherState(selected) {
  const vaults = cfg.listVaults();
  const sel = selected && vaults.find((v) => cfg.same(v.path, selected)) ? selected : (cfg.lastVault() || (vaults[0] && vaults[0].path) || "");
  const s = cfg.loadSettings(sel && cfg.isDir(sel) ? sel : "");
  return {
    explicitRoot: EXPLICIT_ROOT,
    vaults, selected: sel, settings: s,
    lang: s.language,
    msg: cfg.catalog(s.language),
    art: cfg.art(),
    palettes: cfg.builtinPalettes(),
    themes: cfg.installedThemes(),
    home: cfg.gnosisHome(),
    platform: process.platform,
  };
}

const ok = (v) => ({ ok: true, value: v });
const err = (e) => {
  const m = String(e && e.message || e);
  const i = m.indexOf(":");
  return i > 0 && /^[a-z_.]+$/.test(m.slice(0, i)) ? { ok: false, key: m.slice(0, i), detail: m.slice(i + 1) } : { ok: false, key: "", detail: m };
};

ipcMain.handle("launcher:state", (_e, selected) => launcherState(selected));
ipcMain.handle("vault:pick", async (_e, title) => {
  const r = await dialog.showOpenDialog(win, { title, properties: ["openDirectory", "createDirectory"] });
  return r.canceled || !r.filePaths.length ? "" : r.filePaths[0];
});
ipcMain.handle("vault:add", (_e, p) => { try { return ok(cfg.addVault(p)); } catch (e) { return err(e); } });
ipcMain.handle("vault:create", (_e, p, lang) => {
  try { const v = cfg.createVault(p, "", lang); newVaults.add(cfg.normalize(v)); return ok(v); } catch (e) { return err(e); }
});
ipcMain.handle("vault:remove", (_e, p) => ok(cfg.removeVault(p)));
ipcMain.handle("vault:select", (_e, p) => {
  try {
    const v = cfg.selectVault(p);
    applyWindow(cfg.loadSettings(v), false);
    return ok(v);
  } catch (e) { return err(e); }
});
ipcMain.handle("settings:save", (_e, vault, s) => {
  try {
    const v = cfg.saveSettings(vault, s);
    if (cfg.same(vault, activeVault) || !bridge) applyWindow(v, false);
    // Vim が動いていれば、同じファイルを読み直させる（gui.vim が受けて gnosis#settings#activate）
    if (vimSock && cfg.same(vault, activeVault)) {
      try { vimSock.write(JSON.stringify({ type: "settings", vault }) + "\n"); } catch { /* ignore */ }
    }
    return ok(v);
  } catch (e) { return err(e); }
});
ipcMain.handle("theme:install", (_e, spec) => cfg.installTheme(spec));
ipcMain.handle("theme:palette", (_e, s) => cfg.paletteFor(cfg.validateSettings(s)));
ipcMain.handle("theme:appPalette", (_e, s) => cfg.appPaletteFor(cfg.validateSettings(s)));

ipcMain.on("vim:start", (_e, cols, rows, vault) => startVim(cols, rows, vault));
ipcMain.on("pty:write", (_e, data) => { try { bridge?.write(data); } catch { /* ignore */ } });
ipcMain.on("pty:resize", (_e, cols, rows) => { try { bridge?.resize(cols, rows); } catch { /* ignore */ } });
ipcMain.on("app:quit", () => app.quit());

// ---- GUI 編集モード（アプリの編集モード。書き込みは Vim が普通の :write で行い、保存時の処理が全部走る） ----
const noteErr = (e) => ({ ok: false, error: String((e && e.message) || e) });
// モードに入る前: Vim の未保存の変更を保存させる。{ok, file}
ipcMain.handle("gui:enter", async () => {
  const r = await vimCall({ type: "save" });
  return { ok: !!r.ok, file: r.file || "", error: r.error || "" };
});
// ディスクのノートを読む（内容と、保存のときに添える内容ハッシュ）
ipcMain.handle("note:read", (_e, file) => { try { return { ok: true, ...noteio.readNote(noteRootDir, file) }; } catch (e) { return noteErr(e); } });
// 確定。force=false で、ディスクが読んだときと違えば競合を返す。force=true は、ディスクの版を .state/conflicts に残して上書き。
ipcMain.handle("note:commit", async (_e, file, text, expectedHash, force) => {
  try {
    const cur = noteio.readNote(noteRootDir, file);
    const conflict = cur.hash !== expectedHash;
    let savedAside = "";
    if (conflict) {
      if (!force) return { ok: false, conflict: true, disk: { text: cur.text, hash: cur.hash } };
      savedAside = noteio.saveAside(noteRootDir, file, cur.text, "disk");
    }
    if (!conflict && cur.text === text) return { ok: true, hash: cur.hash, text: cur.text, unchanged: true };
    if (vimSock) {
      const r = await vimCall({ type: "commit", file, text, reload: conflict });
      if (!r.ok) return { ok: false, error: r.error || "Vim が保存できませんでした" };
    } else {
      noteio.writeNote(noteRootDir, file, text, cur.hash, { force: true });
    }
    const now = noteio.readNote(noteRootDir, file); // 保存時の処理（記号の除去など）で内容が変わっているかもしれない
    return { ok: true, hash: now.hash, text: now.text, savedAside };
  } catch (e) { return noteErr(e); }
});
// 競合で捨てる側（自分の版）を .state/conflicts に残す
ipcMain.handle("note:aside", (_e, file, text) => { try { noteio.inside(noteRootDir, file); return { ok: true, path: noteio.saveAside(noteRootDir, file, String(text), "mine") }; } catch (e) { return noteErr(e); } });
ipcMain.handle("note:resolve", (_e, file, href) => { try { return { ok: true, ...noteio.resolveLink(noteRootDir, file, href) }; } catch (e) { return noteErr(e); } });
// ノートを開く（Vim のバッファとして。GUI 編集モードの画面は、そのあとの Vim の状態で入れ替わる）
ipcMain.handle("note:open", async (_e, file) => { const abs = path.isAbsolute(file) ? file : path.join(noteRootDir, file); try { noteio.inside(noteRootDir, abs); } catch (e) { return noteErr(e); } const r = await vimCall({ type: "open", file: abs }); return { ok: !!r.ok, file: r.file || "", error: r.error || "" }; });
// ---- ワークスペース（タブ・分割のレイアウト）の保存。vault ごとの利用者設定で、ノートの原本ではない ----
const workspaceFile = () => path.join(noteRootDir, ".gnosis", "workspace.json");
ipcMain.handle("workspace:load", () => {
  try { return noteRootDir ? fs.readFileSync(workspaceFile(), "utf8") : ""; } catch { return ""; }
});
ipcMain.handle("workspace:save", (_e, text) => {
  try {
    if (!noteRootDir || typeof text !== "string" || text.length > 200000) return { ok: false };
    const f = workspaceFile();
    fs.mkdirSync(path.dirname(f), { recursive: true });
    const tmp = f + ".tmp-" + process.pid;
    fs.writeFileSync(tmp, text, "utf8");
    fs.renameSync(tmp, f);
    return { ok: true };
  } catch (e) { return noteErr(e); }
});

// ---- 表示専用ビューの元になる静的サイト（カード・テーブル・グラフ・番号ナビ・検索…）。派生物なので <vault>/.gnosis/cache/site に作る ----
let siteJob = null;
function siteDir() { return path.join(noteRootDir, ".gnosis", "cache", "site"); }
function buildSite() {
  if (siteJob) return siteJob;
  siteJob = new Promise((resolve) => {
    const out = siteDir();
    const py = process.platform === "win32" ? "python" : "python3";
    const child = spawn(py, [path.join(REPO, "python", "export_site.py"), noteRootDir, out], { stdio: ["ignore", "pipe", "pipe"] });
    let so = "", se = "";
    child.stdout.on("data", (d) => { so += d; });
    child.stderr.on("data", (d) => { se += d; });
    child.on("error", (e) => resolve({ ok: false, error: String(e) }));
    child.on("exit", (code) => {
      if (code === 0) resolve({ ok: true, dir: out, url: require("url").pathToFileURL(out).href + "/" });
      else { let msg = se || so; try { msg = JSON.parse(so).error || msg; } catch { /* そのまま */ } resolve({ ok: false, error: String(msg).slice(0, 300) }); }
    });
  }).finally(() => { siteJob = null; });
  return siteJob;
}
// force=false で、すでにあれば作り直さない（タブを開くたびに待たない）。更新ボタンは force=true
ipcMain.handle("view:site", async (_e, force) => {
  if (!noteRootDir) return { ok: false, error: "vault が開かれていません" };
  if (!force && fs.existsSync(path.join(siteDir(), "index.html"))) return { ok: true, dir: siteDir(), url: require("url").pathToFileURL(siteDir()).href + "/" };
  return buildSite();
});

// ---- コマンドパレット: Vim の Gnosis コマンドの一覧（plugin/gnosis.vim の command! から）----
ipcMain.handle("cmds:vim", () => {
  try {
    const names = new Map();
    for (const f of [path.join(REPO, "plugin", "gnosis.vim")]) {
      for (const line of fs.readFileSync(f, "utf8").split("\n")) {
        const m = /^command!\s+((?:-\S+\s+)*)(Gnosis\w+)\b/.exec(line);
        if (m) { const n = /-nargs=(\S+)/.exec(m[1]); names.set(m[2], n ? n[1] : "0"); }
      }
    }
    return [...names].map(([name, nargs]) => ({ name, nargs })).sort((a, b) => (a.name < b.name ? -1 : 1));
  } catch { return []; }
});

// GUI 編集から Vim に戻る: 外で変わったファイルを Vim に読み直させる
ipcMain.handle("gui:leave", async () => { const r = await vimCall({ type: "reload" }); return { ok: !!r.ok, error: r.error || "" }; });

// 画像: ノートのあるフォルダからの相対パスで読む（vault の外は読まない）
ipcMain.handle("img:read", async (_e, file, src) => {
  try {
    if (!file) return null;
    const base = path.dirname(file);
    const p = path.resolve(base, decodeURIComponent(src));
    const roots = [base, path.dirname(base)];
    if (activeVault) roots.push(activeVault, cfg.noteRoot(activeVault));
    if (EXPLICIT_ROOT) roots.push(EXPLICIT_ROOT);
    const allowed = roots.filter(Boolean).map((x) => path.resolve(x));
    if (!allowed.some((a) => p === a || p.startsWith(a + path.sep))) return null;
    return await fs.promises.readFile(p);
  } catch { return null; }
});

app.setName("Gnosis");
if (process.platform === "win32") app.setAppUserModelId("Gnosis");
app.whenReady().then(() => {
  if (process.platform === "darwin" && iconPath()) { try { app.dock.setIcon(nativeImage.createFromPath(iconPath())); } catch { /* ignore */ } }
  createWindow();
});
app.on("window-all-closed", () => { if (!TEST) app.quit(); });
// 終了: Vim に「未保存を書いて終了」を送り、VimLeave を走らせる（暗号化 vault のロック判定は VimLeave で行う。
// この窓が vault を使う最後のウィンドウならロックし、ほかのウィンドウが使っていればロックしない）。
// 2.5 秒たっても終わらなければ強制終了する（Vim が確認や fzf で待っていても閉じられる）。
let quitting = false;
app.on("before-quit", (e) => {
  if (!quitting && bridge && !TEST) {
    quitting = true;
    e.preventDefault();
    try { bridge.write("\x1b\x1b:silent! wall | qa!\r"); } catch { /* ignore */ }
    setTimeout(() => { try { bridge?.kill(); } catch { /* ignore */ } try { server?.close(); } catch { /* ignore */ } app.quit(); }, 2500);
    return;
  }
  try { bridge?.kill(); } catch { /* ignore */ } try { server?.close(); } catch { /* ignore */ }
});
