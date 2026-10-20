// 書き出した静的サイト（HTML）を、本物のブラウザ（Electron の Chromium）で開いて、実際に操作して確かめるための起動スクリプト。
// 使い方（test/site_views_e2e.mjs から）: electron site_views_main.cjs <サイトのフォルダ> <シナリオ.js のパス>
// シナリオは async (page) => 結果 を export する。page.open(相対パス) / page.eval(式) / page.click(selector) / page.key(キー名) を使う。
const { app, BrowserWindow } = require("electron");
const path = require("path");
app.commandLine.appendSwitch("no-sandbox");
app.disableHardwareAcceleration();
const site = process.argv[process.argv.length - 2];
const scenario = require(path.resolve(process.argv[process.argv.length - 1]));
app.whenReady().then(async () => {
  const win = new BrowserWindow({ width: 1200, height: 900, show: false, webPreferences: { contextIsolation: true, sandbox: true, webSecurity: false } /* 試験用: file:// の iframe の中身を調べられるように */ });
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const page = {
    async open(rel) { await win.loadURL("about:blank"); await win.loadFile(path.join(site, rel.split("#")[0]), { hash: rel.includes("#") ? rel.split("#")[1] : "" }); await wait(300); },
    eval: (expr) => win.webContents.executeJavaScript(expr),
    async click(sel) { await win.webContents.executeJavaScript(`document.querySelector(${JSON.stringify(sel)}).click()`); await wait(120); },
    async key(key, mods = {}) {
      for (const type of ["keyDown", "keyUp"]) win.webContents.sendInputEvent({ type, keyCode: key, modifiers: Object.keys(mods).filter((k) => mods[k]) });
      await wait(120);
    },
    async shot(file) { const img = await win.webContents.capturePage(); require("fs").writeFileSync(file, img.toPNG()); },
  };
  let out;
  try { out = { ok: true, result: await scenario(page) }; } catch (e) { out = { ok: false, error: String(e && e.stack || e) }; }
  console.log("RESULT " + JSON.stringify(out));
  app.exit(out.ok ? 0 : 1);
});
