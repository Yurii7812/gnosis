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
const { app, BrowserWindow, ipcMain, Menu, dialog, nativeImage, shell } = require("electron");
const { spawn } = require("child_process");
const { StringDecoder } = require("string_decoder");
const net = require("net");
const path = require("path");
const os = require("os");
const fs = require("fs");
const cfg = require("./config.cjs");

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
// 紙のスキャンの番号付けだけの窓（Vim の \\F から。Vim は起動せず、この画面だけを出す）
const SCAN_ONLY = !!env("SCAN_ONLY");

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

function focusWindow() {
  if (!win || win.isDestroyed()) return;
  if (win.isMinimized()) win.restore();
  win.show();
  win.focus();
  // KDE Wayland のフォーカス制限にも対応する（アプリ本体は XWayland）。
  if (process.platform === "linux" && process.env.WAYLAND_DISPLAY) {
    const child = spawn("python3", [path.join(REPO, "python", "focus_window.py"), String(process.pid)], { stdio: "ignore" });
    child.on("error", (e) => log("focus: " + e.message));
    child.unref();
  }
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
  win.once("ready-to-show", () => { applyWindow(s, true); focusWindow(); });
  if (SCAN_ONLY && EXPLICIT_ROOT) noteRootDir = EXPLICIT_ROOT;
  win.loadFile(path.join(WEB, "index.html"), SCAN_ONLY ? { query: { scan: "1" } } : undefined);
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

// ---- 紙のスキャンの番号付け画面（python/scan_inbox.py。受け皿は <vault>/.gnosis/scans/）----
const SCAN_PY = path.join(REPO, "python", "scan_inbox.py");
const SCAN_CMDS = { list: 0, assign: 2, diary: 2, finish: 0, importmove: 1 }; // 名前 → 必要な引数の数（vault のあとに）
ipcMain.handle("scan:run", (_e, cmd, args) => new Promise((resolve) => {
  if (!noteRootDir || !(cmd in SCAN_CMDS) || !Array.isArray(args)) return resolve({ ok: false, error: "vault が開かれていません" });
  const list = args.map(String);
  if (list.length < SCAN_CMDS[cmd] || list.length > SCAN_CMDS[cmd] + 1) return resolve({ ok: false, error: "引数が違います" });
  const child = spawn(process.platform === "win32" ? "python" : "python3", [SCAN_PY, cmd, noteRootDir, ...list], { stdio: ["ignore", "pipe", "pipe"] });
  let out = "";
  child.stdout.on("data", (d) => { out += d; });
  child.on("error", (e) => resolve({ ok: false, error: String(e.message || e) }));
  child.on("close", () => { try { resolve(JSON.parse(out.trim().split("\n").pop())); } catch { resolve({ ok: false, error: out.slice(0, 200) || "scan_inbox.py の出力を読めません" }); } });
}));
// vault の外のフォルダを選ぶ画面用: フォルダの中のフォルダと、写真の枚数（キーボードだけで辿る）
ipcMain.handle("scan:ls", async (_e, dir) => {
  try {
    const d = path.resolve(dir || os.homedir());
    const ents = await fs.promises.readdir(d, { withFileTypes: true });
    const dirs = ents.filter((x) => x.isDirectory() && !x.name.startsWith(".")).map((x) => x.name).sort((a, b) => a.localeCompare(b, "ja"));
    const images = ents.filter((x) => x.isFile() && /\.(jpe?g|png|webp|gif|bmp|tiff?)$/i.test(x.name)).length;
    return { ok: true, dir: d, parent: path.dirname(d) === d ? "" : path.dirname(d), dirs, images };
  } catch (e) { return { ok: false, error: String((e && e.message) || e) }; }
});
// 前回使ったフォルダ（Gnosis ホームの scan_recent.json。新しい順・最大 8 つ）と、Desktop。存在するものだけ
const recentFile = () => path.join(cfg.gnosisHome(), "scan_recent.json");
const readRecent = () => { try { const a = JSON.parse(fs.readFileSync(recentFile(), "utf8")); return Array.isArray(a) ? a.filter((x) => typeof x === "string") : []; } catch { return []; } };
ipcMain.handle("scan:recent", () => {
  const desk = path.join(os.homedir(), "Desktop");
  return { recent: readRecent().filter((d) => { try { return fs.statSync(d).isDirectory(); } catch { return false; } }), desktop: fs.existsSync(desk) ? desk : "" };
});
ipcMain.handle("scan:remember", (_e, dir) => {
  try {
    if (typeof dir !== "string" || !dir) return false;
    const list = [dir, ...readRecent().filter((d) => d !== dir)].slice(0, 8);
    fs.mkdirSync(cfg.gnosisHome(), { recursive: true });
    fs.writeFileSync(recentFile(), JSON.stringify(list, null, 1));
    return true;
  } catch { return false; }
});
// フォルダの検索: dir の下を深さ 3 まで、名前に語（大文字小文字・全角半角を無視）を含むフォルダを最大 40 件
ipcMain.handle("scan:find", async (_e, dir, query) => {
  const q = String(query || "").normalize("NFKC").toLowerCase();
  const out = [];
  if (!q) return out;
  const walk = async (d, depth) => {
    if (out.length >= 40 || depth > 3) return;
    let ents = [];
    try { ents = await fs.promises.readdir(d, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      if (!e.isDirectory() || e.name.startsWith(".") || e.name === "node_modules") continue;
      const p = path.join(d, e.name);
      if (e.name.normalize("NFKC").toLowerCase().includes(q)) out.push(p);
      if (out.length >= 40) return;
      await walk(p, depth + 1);
    }
  };
  await walk(path.resolve(dir || os.homedir()), 1);
  return out;
});
ipcMain.handle("scan:image", async (_e, name) => {
  try {
    if (!noteRootDir || /[\\/]/.test(name) || name.startsWith(".")) return null;
    return await fs.promises.readFile(path.join(noteRootDir, ".gnosis", "scans", name));
  } catch { return null; }
});

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

// リンクのクリック: Web サイト（http / https）は普段のブラウザで開く
ipcMain.handle("link:external", (_e, url) => {
  if (typeof url !== "string" || !/^https?:\/\//i.test(url)) return false;
  shell.openExternal(url);
  return true;
});

// リンクのクリック: HTML ファイルは、アプリの画面の中で開く。ノートと同じ vault（かノートのあるフォルダ）の中のファイルだけ。
// 戻り値は { url: "file://…", name } か null（読めない・範囲外）。画面側は、スクリプトを分離した枠（sandbox）の中で表示する
ipcMain.handle("link:html", (_e, file, href) => {
  try {
    if (!file || typeof href !== "string") return null;
    const base = path.dirname(file);
    const clean = decodeURIComponent(href.split("#")[0].split("?")[0]);
    const p = path.resolve(base, clean);
    if (!/\.html?$/i.test(p) || !fs.existsSync(p)) return null;
    const roots = [base, path.dirname(base)];
    if (activeVault) roots.push(activeVault, cfg.noteRoot(activeVault));
    if (EXPLICIT_ROOT) roots.push(EXPLICIT_ROOT);
    const allowed = roots.filter(Boolean).map((x) => path.resolve(x));
    if (!allowed.some((a) => p === a || p.startsWith(a + path.sep))) return null;
    return { url: require("url").pathToFileURL(p).href + (href.includes("#") ? "#" + href.split("#")[1] : ""), name: path.basename(p) };
  } catch { return null; }
});

// 動いている Gnosis としての登録（Gnosis ホームの run/gui-<pid>.json）。Vim の \x \X が、これを見て閉じる依頼
// （run/close-gui-<pid> というファイル）を置く。0.5 秒ごとに見て、あれば消してアプリを終了する（通常の終了の流れ）。
// 起動したのが CUI の Vim なら GNOSIS_PARENT_PID にその pid が入っている
function runDir() { const d = path.join(cfg.gnosisHome(), "run"); fs.mkdirSync(d, { recursive: true }); return d; }
function registerRun() {
  try {
    const dir = runDir();
    const file = path.join(dir, `gui-${process.pid}.json`);
    let registeredVault = null;
    let focusing = false;
    const record = () => fs.writeFileSync(file, JSON.stringify({ kind: "gui", pid: process.pid, vault: noteRootDir || EXPLICIT_ROOT, parent: Number(process.env.GNOSIS_PARENT_PID || 0) || 0, started: Date.now() }));
    record();
    registeredVault = noteRootDir || EXPLICIT_ROOT;
    const req = path.join(dir, `close-gui-${process.pid}`);
    const timer = setInterval(() => {
      try {
        if (registeredVault !== (noteRootDir || EXPLICIT_ROOT)) { record(); registeredVault = noteRootDir || EXPLICIT_ROOT; }
        const focus = path.join(dir, `focus-gui-${process.pid}`);
        if (bridge && !focusing && fs.existsSync(focus)) {
          focusing = true;
          vimCall({ type: "handoff", path: focus }).then((r) => {
            if (r.ok) focusWindow();
          }).finally(() => { focusing = false; });
        }
        if (fs.existsSync(req)) { fs.unlinkSync(req); app.quit(); }
      } catch { /* ignore */ }
    }, 500);
    timer.unref();
    const clean = () => { try { fs.unlinkSync(file); } catch { /* ignore */ } try { fs.unlinkSync(req); } catch { /* ignore */ } try { fs.unlinkSync(path.join(dir, `focus-gui-${process.pid}`)); } catch { /* ignore */ } };
    app.on("will-quit", clean);
    process.on("exit", clean);
  } catch { /* ignore */ }
}

app.setName("Gnosis");
if (process.platform === "win32") app.setAppUserModelId("Gnosis");
app.whenReady().then(() => {
  if (process.platform === "darwin" && iconPath()) { try { app.dock.setIcon(nativeImage.createFromPath(iconPath())); } catch { /* ignore */ } }
  createWindow();
  if (!SCAN_ONLY) registerRun();
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
