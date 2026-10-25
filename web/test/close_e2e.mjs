// \x / \X でアプリを閉じる（キーボードだけで閉じる）の E2E。一時フォルダだけを使う。
//   A) アプリの中の Vim で \x → アプリが終了し、登録（run/gui-<pid>.json）が消える
//   B) 登録されているアプリに、閉じる依頼のファイル（run/close-gui-<pid>）を置く（CUI の Vim の \X がやること）→ アプリが終了する
//   node test/close_e2e.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const base = process.env.TMPDIR || path.join(os.homedir(), "Desktop", "test");
fs.mkdirSync(base, { recursive: true });
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const realHome = os.homedir();
const tmp = fs.mkdtempSync(path.join(base, "syn-close-e2e-"));
const home = path.join(tmp, "home");
const vault = path.join(tmp, "vault", "note");
const gnosisHome = path.join(tmp, "gnosis-home");
for (const d of [path.join(home, ".vim"), vault, path.join(gnosisHome, "plugins")]) fs.mkdirSync(d, { recursive: true });
for (const b of [process.env.GNOSIS_TEST_PLUGINS, path.join(realHome, ".local", "share", "gnosis", "plugins"), path.join(realHome, ".vim-simple-yurii-note")].filter(Boolean)) {
  for (const name of ["fzf", "fzf.vim", "vim-surround"]) {
    const src = path.join(b, name), dst = path.join(gnosisHome, "plugins", name);
    if (fs.existsSync(src) && !fs.existsSync(dst)) fs.symlinkSync(src, dst);
  }
}
if (!fs.existsSync(path.join(gnosisHome, "plugins", "fzf.vim"))) { console.error("SKIP: fzf.vim が無いので E2E テストを省略"); process.exit(0); }
fs.writeFileSync(path.join(vault, "index.md"), "---\ntime: 2026-10-11 10:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[メモ](m1.md)\n");
fs.writeFileSync(path.join(vault, "m1.md"), "---\ntime: 2026-10-11 10:00:00\ntitle: メモ\n---\n\n# メモ\n\n本文\n");

const run = path.join(gnosisHome, "run");
const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));
async function runCase(name, scenarioBody, trigger) {
  const scenarioPath = path.join(tmp, name + ".js");
  fs.writeFileSync(scenarioPath, `(async () => { const sleep = (ms) => new Promise((r) => setTimeout(r, ms)); let G = window.__gui; for (let i = 0; i < 100 && !G; i++) { await sleep(50); G = window.__gui; } ${scenarioBody} return { done: true }; })()`);
  const env = { ...process.env, HOME: home, GNOSIS_HOME: gnosisHome, PKM_ROOT: vault, PKM_FILE: path.join(vault, "m1.md"), PKM_TEST_SCRIPT: scenarioPath, PKM_TEST_OUT: path.join(tmp, name + ".json") };
  delete env.WAYLAND_DISPLAY; delete env.XDG_SESSION_TYPE; delete env.DISPLAY;
  const t0 = Date.now();
  const child = spawn("xvfb-run", ["-a", "-s", "-screen 0 1100x880x24", path.join(web, "node_modules/.bin/electron"), web, "--no-sandbox", "--disable-gpu", "--ozone-platform=x11"], { env, stdio: ["ignore", "ignore", "inherit"] });
  let exited = null;
  child.on("exit", () => { exited = Date.now() - t0; });
  // 登録（run/gui-<pid>.json）が現れるまで待つ
  let reg = null;
  for (let i = 0; i < 60 && !reg && exited == null; i++) {
    await sleepMs(500);
    try { const f = fs.readdirSync(run).find((n) => /^gui-\d+\.json$/.test(n)); if (f) reg = f; } catch { /* まだ */ }
  }
  if (trigger && reg) { await sleepMs(3500); trigger(reg.match(/\d+/)[0]); }
  for (let i = 0; i < 40 && exited == null; i++) await sleepMs(500);
  const timedOut = exited == null;
  if (timedOut) { try { process.kill(-child.pid); } catch { /* ignore */ } child.kill("SIGKILL"); }
  await sleepMs(500);
  const left = fs.existsSync(run) ? fs.readdirSync(run).filter((n) => /^gui-/.test(n)) : [];
  return { name, registered: !!reg, exitedMs: exited, timedOut, left };
}

let failed = 0;
const check = (ok, msg) => { if (!ok) { console.error("FAIL: " + msg); failed++; } };
try {
  // A) アプリの中の Vim で \x
  const A = await runCase("a", "await sleep(4000); G.send('\\\\x'); await sleep(60000);", null);
  check(A.registered && !A.timedOut && A.left.length === 0, "\\x inside the app closes the app and its registration is removed: " + JSON.stringify(A));
  // B) 閉じる依頼のファイル（CUI の \X がやること）
  const B = await runCase("b", "await sleep(60000);", (pid) => fs.writeFileSync(path.join(run, `close-gui-${pid}`), ""));
  check(B.registered && !B.timedOut && B.left.length === 0, "a close request file makes the app quit: " + JSON.stringify(B));
  if (failed) process.exit(1);
  console.log("close e2e: OK (\\x in the app closes it; a close request file from the CUI closes it)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
