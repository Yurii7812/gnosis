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
          try { win?.webContents.send("vim:state", JSON.parse(line)); } catch { /* 壊れた行は捨てる */ }
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
  if (OPEN) args.push(OPEN);
  bridge = spawn("python3", args, {
    env: { ...process.env, SYN_GUI_PORT: String(port), TERM: "xterm-256color" },
    stdio: ["pipe", "pipe", "pipe", "pipe"],
  });
  ctl = bridge.stdio[3];
  const dec = new StringDecoder("utf8");
  bridge.stdout.on("data", (d) => { const s = dec.write(d); if (s) win?.webContents.send("pty:data", s); });
  bridge.stderr.on("data", (d) => process.stderr.write(d));
  bridge.on("exit", (code) => {
    win?.webContents.send("vim:exit", code);
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
  win.once("ready-to-show", () => { win.show(); win.focus(); });
  win.loadFile(path.join(WEB, "index.html"));
  win.on("page-title-updated", (e) => e.preventDefault());

  // テスト用: PKM_TEST_SCRIPT の JS を画面で実行し、結果を PKM_TEST_OUT に書いて終了する
  if (process.env.PKM_TEST_SCRIPT) {
    win.webContents.on("did-finish-load", async () => {
      let result;
      try {
        const src = fs.readFileSync(process.env.PKM_TEST_SCRIPT, "utf8");
        result = await win.webContents.executeJavaScript(src);
      } catch (e) { result = { fatal: String(e && e.stack || e) }; }
      // 結果を先に書く。画面の撮影（任意）は時間制限つきで、固まってもテストを止めない
      const png = result && result.__png;
      if (result) delete result.__png;
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
app.on("window-all-closed", () => app.quit());
app.on("before-quit", () => { try { bridge?.kill(); } catch { /* ignore */ } try { server?.close(); } catch { /* ignore */ } });
