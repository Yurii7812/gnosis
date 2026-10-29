// 番号付けの画面の矢印キー・hjkl（↓ j 子・→ l 次の連番・← h 取り消し・↑ k 前の番号を直す）の E2E。一時フォルダだけを使う。
//
//   node test/scan_steps_e2e.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const base = process.env.TMPDIR || path.join(os.homedir(), "gnosis-work", "test");
fs.mkdirSync(base, { recursive: true });
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const tmp = fs.mkdtempSync(path.join(base, "syn-scan-steps-"));
const home = path.join(tmp, "home");
const vault = path.join(tmp, "vault");
const gnosisHome = path.join(tmp, "gnosis-home");
const outside = path.join(tmp, "photos");
for (const d of [home, vault, gnosisHome, outside]) fs.mkdirSync(d, { recursive: true });
const PNG = Buffer.from("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082", "hex");
for (const c of "abcde") fs.writeFileSync(path.join(outside, c + ".png"), Buffer.concat([PNG, Buffer.from(c)]));
execFileSync("python3", ["-c", "import sys; sys.path.insert(0, sys.argv[1]); import paper_pkm as pp; from pathlib import Path; pp.create_paper_index(Path(sys.argv[2]))", path.join(web, "..", "python"), vault]);

const scenario = `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let G = window.__gui;
  for (let i = 0; i < 100 && !G; i++) { await sleep(50); G = window.__gui; }
  await sleep(1200);
  const el = document.getElementById('scan');
  const kk = async (key, wait = 700) => { el.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true })); await sleep(wait); };
  localStorage.setItem('scanDir', ${JSON.stringify(outside)});
  const R = {};
  await kk('Enter', 1000);
  await kk('u', 2500);                 // このフォルダを使う（写真 5 枚）
  const inp = el.querySelector('.scan-input');
  const prev = () => el.querySelector('.scan-prev').textContent;
  const count = () => el.querySelector('.scan-count').textContent;
  R.count0 = count();
  await kk('j', 500);                  // 最初の画像は Space で番号を入れる（j は何も付けない）
  R.msgNoLast = el.querySelector('.scan-msg').textContent;
  await kk(' ', 400);
  inp.value = '1';
  inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
  await sleep(1500);
  await kk('Escape', 400);
  R.afterFirst = prev();
  await kk('j', 1500);                 // 1 の子 → 1a
  R.afterDown = prev();
  await kk('ArrowRight', 1500);        // 次の連番 → 1b
  R.afterRight = prev();
  await kk('l', 1500);                 // 次の連番 → 1c
  R.afterL = prev();
  await kk('h', 1500);                 // 取り消し → 前は 1b に戻る
  R.afterUndo = prev(); R.countAfterUndo = count();
  await kk('ArrowLeft', 1500);         // もう一度取り消し → 前は 1a
  R.afterUndo2 = prev();
  await kk('k', 500);                  // 前の番号（1a）が入力欄に出る
  R.kOpen = !inp.hidden; R.kValue = inp.value;
  await kk('Escape', 400);
  R.__closeWindow = true;
  return R;
})()`;
const scenarioPath = path.join(tmp, "scenario.js");
fs.writeFileSync(scenarioPath, scenario);
const outPath = path.join(tmp, "out.json");
const env = { ...process.env, HOME: home, GNOSIS_HOME: gnosisHome, PKM_ROOT: vault, PKM_SCAN_ONLY: "1", PKM_TEST_SCRIPT: scenarioPath, PKM_TEST_OUT: outPath };
delete env.WAYLAND_DISPLAY; delete env.XDG_SESSION_TYPE; delete env.DISPLAY;
let failed = 0;
const check = (ok, msg) => { if (!ok) { console.error("FAIL: " + msg); failed++; } };
try {
  execFileSync("xvfb-run", ["-a", "-s", "-screen 0 1100x880x24", path.join(web, "node_modules/.bin/electron"), web, "--no-sandbox", "--disable-gpu", "--ozone-platform=x11"], { env, stdio: ["ignore", "inherit", "inherit"], timeout: 150000 });
  const R = JSON.parse(fs.readFileSync(outPath, "utf8"));
  const has = (s, x) => String(s).includes(x);
  check(has(R.count0, "1 / 5"), "five scans: " + JSON.stringify(R));
  check(R.msgNoLast !== "", "j with no previous number shows a message instead of numbering: " + JSON.stringify(R));
  check(has(R.afterFirst, "1") && !has(R.afterFirst, "1a"), "Space 1 sets the first number: " + JSON.stringify(R));
  check(has(R.afterDown, "1a"), "j (or down) = child of the previous number: " + JSON.stringify(R));
  check(has(R.afterRight, "1b"), "ArrowRight = next number: " + JSON.stringify(R));
  check(has(R.afterL, "1c"), "l = next number: " + JSON.stringify(R));
  check(has(R.afterUndo, "1b"), "h undoes the last numbering (previous goes back to 1b): " + JSON.stringify(R));
  check(has(R.countAfterUndo, "/ 2"), "the undone scan is back in the list: " + JSON.stringify(R));
  check(has(R.afterUndo2, "1a"), "ArrowLeft undoes once more: " + JSON.stringify(R));
  check(R.kOpen && R.kValue === "1a", "k opens the input with the previous number: " + JSON.stringify(R));
  const files = fs.readdirSync(vault).filter((f) => f.endsWith(".png")).sort();
  check(JSON.stringify(files) === JSON.stringify(["1.png", "1a.png"]), "the vault keeps 1.png and 1a.png only: " + JSON.stringify(files));
  if (failed) process.exit(1);
  console.log("scan-steps e2e: OK (↓ j child, → l next, ← h undo, ↑ k edit)");
} catch (e) { try { console.error(fs.readFileSync(path.join(gnosisHome, "logs", "app.log"), "utf8").slice(-1500)); } catch {} throw e; } finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
