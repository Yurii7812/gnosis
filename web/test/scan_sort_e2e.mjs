// 紙のスキャンの番号付けだけの窓（Vim の \F からふつうの端末で開く。Vim は起動しない）の E2E。一時フォルダだけを使う。
//
//   node test/scan_only_e2e.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const base = process.env.TMPDIR || path.join(os.homedir(), "Desktop", "test");
fs.mkdirSync(base, { recursive: true });
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const tmp = fs.mkdtempSync(path.join(base, "syn-scan-sort-"));
const home = path.join(tmp, "home");
const vault = path.join(tmp, "vault");
const gnosisHome = path.join(tmp, "gnosis-home");
const desktop = path.join(home, "Desktop");
const outside = path.join(desktop, "scans2");
for (const d of [home, vault, gnosisHome, outside]) fs.mkdirSync(d, { recursive: true });
const PNG = Buffer.from("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082", "hex");
const mk = (n, extra) => { const f = path.join(outside, n); fs.writeFileSync(f, Buffer.concat([PNG, Buffer.alloc(extra, 7)])); return f; };
const t0 = Date.now() / 1000;
for (const [n, extra, age] of [["b.png", 300, 3000], ["a.png", 100, 1000], ["c.png", 200, 2000]]) { const f = mk(n, extra); fs.utimesSync(f, t0 - age, t0 - age); }
execFileSync("python3", ["-c", "import sys; sys.path.insert(0, sys.argv[1]); import paper_pkm as pp; from pathlib import Path; pp.create_paper_index(Path(sys.argv[2]))", path.join(web, "..", "python"), vault]);

const scenario = `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let G = window.__gui;
  for (let i = 0; i < 100 && !G; i++) { await sleep(50); G = window.__gui; }
  await sleep(1200);
  const el = document.getElementById('scan');
  const R = { scanShown: !el.hidden, stageHidden: document.getElementById('stage').hidden, source: !el.querySelector('.scan-source').hidden };
  const k = async (key, wait = 900) => { el.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true })); await sleep(wait); };
  const kk = async (key, wait = 700) => { el.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true })); await sleep(wait); };
  await kk('Enter', 1200);                                      // フォルダを選ぶ画面（Desktop から始まる）
  R.folderPath = el.querySelector('.scan-path').textContent;
  R.rows0 = [...el.querySelectorAll('.scan-row')].map((e) => e.textContent);
  // / のあとだけ検索欄に文字を打てる。打つと、今のフォルダの下を探して絞り込む（深さ 3 まで）
  await kk('/', 300);
  const sr = el.querySelector('.scan-search');
  sr.value = 'scan'; sr.dispatchEvent(new Event('input', { bubbles: true }));
  await sleep(900);
  R.searchRows = [...el.querySelectorAll('.scan-row')].map((e) => e.textContent);
  sr.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
  await sleep(400);
  await kk('1', 1500);                                          // 数字キー 1 = scans2 を開く
  R.afterDigit = el.querySelector('.scan-path').textContent;
  R.useRow = el.querySelector('.scan-row.use').textContent;
  await kk('u', 3000);                                          // このフォルダを使う
  R.number = !el.querySelector('.scan-number').hidden;
  const names = () => [...el.querySelectorAll('.ss-file')].map((e) => e.textContent.trim().split(' ').filter(Boolean)[1]);
  await kk('s', 600);
  R.sortOpen = !el.querySelector('.scan-sort').hidden;
  R.filesInit = names();
  await kk('ArrowDown', 500);                                   // 名前 降順
  R.filesDesc = names();
  await kk('Escape', 500);                                      // 元に戻す
  R.sortClosed = el.querySelector('.scan-sort').hidden;
  await kk('s', 500);
  R.filesAfterEsc = names();
  for (let i = 0; i < 4; i++) await kk('ArrowDown', 300);       // 大きさ 小さい順
  R.filesSize = names();
  await kk('Enter', 600);                                       // 決める
  R.sortKept = el.querySelector('.scan-sort').hidden;
  const cnt = el.querySelector('.scan-count').textContent;
  R.count = cnt;
  await kk('Escape', 600);                                      // Esc では \\F の画面は閉じない（q で閉じる。アプリごと終わるので試験では押さない）
  R.stayedOpenAfterEsc = !el.hidden && !el.querySelector('.scan-number').hidden;
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
  execFileSync("xvfb-run", ["-a", "-s", "-screen 0 1100x880x24", path.join(web, "node_modules/.bin/electron"), web, "--no-sandbox", "--disable-gpu", "--ozone-platform=x11"], { env, stdio: ["ignore", "inherit", "inherit"], timeout: 120000 });
  const R = JSON.parse(fs.readFileSync(outPath, "utf8"));
  check(R.rows0 && R.rows0.length && R.afterDigit && /scans2$/.test(R.afterDigit), "digit key 1 opens the first numbered folder (scans2 under Desktop): " + JSON.stringify([R.folderPath, R.rows0, R.afterDigit]));
  check(R.searchRows && R.searchRows.some((t) => /scans2/.test(t)), "folder search finds scans2 under Desktop: " + JSON.stringify(R.searchRows));
  check(R.number && R.sortOpen && R.filesInit.length === 3 && R.filesDesc.length === 3 && R.filesDesc[0] !== R.filesInit[0] && R.filesDesc[0] === R.filesInit[2], "sort popup shows the real files and re-orders them at once (name desc): " + JSON.stringify(R));
  check(R.sortClosed && R.filesAfterEsc[0] === R.filesInit[0], "Esc puts the order back: " + JSON.stringify(R));
  check(R.filesSize.length === 3 && R.sortKept && R.stayedOpenAfterEsc, "Enter keeps the sort, Esc does not close the screen: " + JSON.stringify(R));
  const rec = path.join(gnosisHome, "scan_recent.json");
  check(fs.existsSync(rec) && JSON.parse(fs.readFileSync(rec, "utf8"))[0] === outside, "the used folder is remembered in the Gnosis home (scan_recent.json)");
  if (failed) process.exit(1);
  console.log("scan sort e2e: OK (digit keys, sort popup with live file list, Esc puts it back, recent folder remembered)");
} catch (e) { try { console.error(fs.readFileSync(path.join(gnosisHome, "logs", "app.log"), "utf8").slice(-1500)); } catch {} throw e; } finally {
  if (!process.env.KEEP) fs.rmSync(tmp, { recursive: true, force: true }); else console.log('kept ' + tmp);
}
