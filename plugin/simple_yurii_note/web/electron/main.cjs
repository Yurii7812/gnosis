// simple_yurii_note アプリ (Electron)。
// 本物の Vim（SYN などのプラグインが入った ~/.vimrc-simple-yurii-note）を擬似端末の中で動かし、
// その画面を、マークダウンのビューアの見た目で表示する。機能は Vim そのもの（作り直していない）。
//
//   Vim ──(擬似端末)──► xterm.js … メッセージ・質問・fzf などの端末画面
//   Vim ──(TCP/JSON)──► 画面 …… バッファの全文・カーソル・モード（マークダウンで描画）
//   キー入力 ──► 擬似端末 ──► Vim
//
// 環境変数: PKM_ROOT … SYN の root（vault）。PKM_FILE … 最初に開くノート。
//           HOME のかわりに別の場所の設定を使うときは PKM_VIMRC。
const { app, BrowserWindow, ipcMain, Menu } = require("electron");
const { spawn } = require("child_process");
const { StringDecoder } = require("string_decoder");
const net = require("net");
const path = require("path");
const os = require("os");
const fs = require("fs");

const WEB = path.resolve(__dirname, "..");
const VIMRC = process.env.PKM_VIMRC || path.join(os.homedir(), ".vimrc-simple-yurii-note");
const ROOT = process.env.PKM_ROOT ? path.resolve(process.env.PKM_ROOT) : "";
const OPEN = process.env.PKM_FILE || "";

// ログ: ~/.local/state/simple-yurii-note-app/app.log （画面のエラー・Vim の標準エラー・終了など）。
// アプリは Vim から起動するので、標準エラーが捨てられてしまう。何か起きたときの手がかりに残す。
const LOG_FILE = path.join(os.homedir(), ".local", "state", "simple-yurii-note-app", "app.log");
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

// 画面（window）へ送る。窓を閉じたあと・Vim が遅れて終了したときに「Object has been destroyed」で
// 落ちないよう、窓が生きているときだけ送る。
const uncaught = [];
process.removeAllListeners("uncaughtException");
process.on("uncaughtException", (e) => { uncaught.push(String(e && e.stack || e)); log("uncaughtException: " + (e && e.stack || e)); });

function send(channel, ...args) {
  try {
    if (win && !win.isDestroyed() && !win.webContents.isDestroyed()) win.webContents.send(channel, ...args);
  } catch (e) { log("send failed (" + channel + "): " + e); }
}

let win = null;
let bridge = null;
let server = null;
let ctl = null;

function startServer() {
  return new Promise((resolve) => {
    server = net.createServer((sock) => {
      let buf = "";
      sock.setEncoding("utf8");
      sock.on("data", (d) => {
        buf += d;
        let i;
        while ((i = buf.indexOf("\n")) >= 0) {
          const line = buf.slice(0, i);
          buf = buf.slice(i + 1);
          let st; try { st = JSON.parse(line); } catch { continue; } /* 壊れた行は捨てる */ send("vim:state", st);
        }
      });
      sock.on("error", () => {});
    });
    server.listen(0, "127.0.0.1", () => resolve(server.address().port));
  });
}

async function startVim(cols, rows) {
  if (bridge) return;
  const port = await startServer();
  const args = [path.join(WEB, "bridge", "ptybridge.py"), String(cols), String(rows), "--", "vim", "-u", VIMRC];
  if (ROOT) args.push("--cmd", `let g:simple_yurii_note_root='${ROOT.replace(/'/g, "''")}/'`);
  args.push("-S", path.join(WEB, "vim", "gui.vim"));
  bridge = spawn("python3", args, {
    env: { ...process.env, SYN_GUI_PORT: String(port), TERM: "xterm-256color", PKM_FILE: OPEN },
    stdio: ["pipe", "pipe", "pipe", "pipe"],
  });
  ctl = bridge.stdio[3];
  const dec = new StringDecoder("utf8");
  bridge.stdout.on("data", (d) => { const s = dec.write(d); if (s) send("pty:data", s); });
  bridge.stderr.on("data", (d) => { process.stderr.write(d); log("vim/bridge stderr: " + d); });
  bridge.on("exit", (code) => {
    log("vim exited: code=" + code);
    send("vim:exit", code);
    // Vim を終了したら（:q など）アプリも終える。テスト時は呼び出し側が終了を制御する。
    if (!process.env.PKM_TEST_SCRIPT) app.quit();
  });
}

function createWindow() {
  win = new BrowserWindow({
    width: 1100,
    height: 880,
    show: false,
    title: "simple_yurii_note",
    backgroundColor: "#ffffff",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });
  Menu.setApplicationMenu(null);
  log(`start: root=${ROOT || "(vim default)"} file=${OPEN || "(none)"} vimrc=${VIMRC}`);
  // 画面（renderer）のエラーと、画面が落ちたことを記録する
  win.webContents.on("console-message", (...a) => {
    const d = a[1] && typeof a[1] === "object" ? a[1] : null;
    const lvl = d ? d.level : a[1];
    const msg = d ? d.message : a[2];
    if ((lvl === "error" || lvl === 3) && !/Electron Security Warning/.test(String(msg))) log("renderer error: " + msg);
  });
  win.webContents.on("render-process-gone", (_e, det) => log("render-process-gone: " + JSON.stringify(det)));
  // 最大化して開く（前のアプリと同じ）
  win.once("ready-to-show", () => { win.maximize(); win.show(); win.focus(); });
  win.loadFile(path.join(WEB, "index.html"));
  win.on("page-title-updated", (e) => e.preventDefault());

  // テスト用: PKM_TEST_SCRIPT の JS を画面で実行し、結果を PKM_TEST_OUT に書いて終了する
  const consoleLog = [];
  if (process.env.PKM_TEST_SCRIPT) {
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
        const src = fs.readFileSync(process.env.PKM_TEST_SCRIPT, "utf8");
        result = await win.webContents.executeJavaScript(src);
      } catch (e) { result = { fatal: String(e && e.stack || e) }; }
      // 結果を先に書く。画面の撮影（任意）は時間制限つきで、固まってもテストを止めない
      const png = result && result.__png;
      const closeWindow = !!(result && result.__closeWindow);
      if (result) { delete result.__png; delete result.__closeWindow; }
      if (result && typeof result === "object" && !Array.isArray(result)) result.__console = consoleLog.slice(0, 20);
      fs.writeFileSync(process.env.PKM_TEST_OUT, JSON.stringify(result, null, 2));
      if (png) {
        try {
          const img = await Promise.race([
            win.webContents.capturePage(),
            new Promise((_, rej) => setTimeout(() => rej(new Error("capture timeout")), 8000)),
          ]);
          fs.writeFileSync(png, img.toPNG());
        } catch { /* ignore */ }
      }
      // 窓を壊した状態で Vim が終わっても、アプリが例外を出さないこと（「Object has been destroyed」の回帰確認）
      if (closeWindow) {
        try { win.destroy(); } catch { /* ignore */ }
        try { bridge?.kill("SIGKILL"); } catch { /* ignore */ }
        await new Promise((r) => setTimeout(r, 1500));
        try {
          const cur = JSON.parse(fs.readFileSync(process.env.PKM_TEST_OUT, "utf8"));
          cur.__uncaught = uncaught.slice(0, 5);
          fs.writeFileSync(process.env.PKM_TEST_OUT, JSON.stringify(cur, null, 2));
        } catch { /* ignore */ }
      }
      try { bridge?.kill("SIGKILL"); } catch { /* ignore */ }
      setTimeout(() => process.exit(0), 100);
    });
  }
}

ipcMain.on("vim:start", (_e, cols, rows) => startVim(cols, rows));
ipcMain.on("pty:write", (_e, data) => { try { bridge?.stdin.write(data); } catch { /* ignore */ } });
ipcMain.on("pty:resize", (_e, cols, rows) => { try { ctl?.write(JSON.stringify({ cols, rows }) + "\n"); } catch { /* ignore */ } });
ipcMain.on("app:quit", () => app.quit());

// 画像: ノートのあるフォルダからの相対パスで読む（vault の外は読まない）
ipcMain.handle("img:read", async (_e, file, src) => {
  try {
    if (!file) return null;
    const base = path.dirname(file);
    const p = path.resolve(base, decodeURIComponent(src));
    const allowed = [base, ROOT, path.dirname(base)].filter(Boolean).map((x) => path.resolve(x));
    if (!allowed.some((a) => p === a || p.startsWith(a + path.sep))) return null;
    return await fs.promises.readFile(p);
  } catch { return null; }
});

app.whenReady().then(createWindow);
app.on("window-all-closed", () => { if (!process.env.PKM_TEST_SCRIPT) app.quit(); });
app.on("before-quit", () => { try { bridge?.kill(); } catch { /* ignore */ } try { server?.close(); } catch { /* ignore */ } });
