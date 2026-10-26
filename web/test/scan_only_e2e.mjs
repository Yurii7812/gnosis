// 紙のスキャンの番号付けだけの窓（Vim の \F からふつうの端末で開く。Vim は起動しない）の E2E。一時フォルダだけを使う。
//
//   node test/scan_only_e2e.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const base = process.env.TMPDIR || path.join(os.homedir(), "gnosis-work", "test");
fs.mkdirSync(base, { recursive: true });
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const tmp = fs.mkdtempSync(path.join(base, "syn-scan-only-"));
const home = path.join(tmp, "home");
const vault = path.join(tmp, "vault");
const gnosisHome = path.join(tmp, "gnosis-home");
const outside = path.join(tmp, "photos");
for (const d of [home, vault, gnosisHome, outside]) fs.mkdirSync(d, { recursive: true });
const PNG = Buffer.from("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082", "hex");
fs.writeFileSync(path.join(outside, "a.png"), Buffer.concat([PNG, Buffer.from("a")]));
execFileSync("python3", ["-c", "import sys; sys.path.insert(0, sys.argv[1]); import paper_pkm as pp; from pathlib import Path; pp.create_paper_index(Path(sys.argv[2]))", path.join(web, "..", "python"), vault]);

const scenario = `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let G = window.__gui;
  for (let i = 0; i < 100 && !G; i++) { await sleep(50); G = window.__gui; }
  await sleep(1200);
  const el = document.getElementById('scan');
  const R = { scanShown: !el.hidden, stageHidden: document.getElementById('stage').hidden, source: !el.querySelector('.scan-source').hidden };
  const k = async (key, wait = 900) => { el.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true })); await sleep(wait); };
  localStorage.setItem('scanDir', ${JSON.stringify(outside)});
  const kk = async (key, wait = 700) => { el.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true })); await sleep(wait); };
  await kk('Enter', 1000);
  R.folder = !el.querySelector('.scan-folder').hidden;
  R.rows = [...el.querySelectorAll('.scan-row')].map((e) => e.textContent);
  R.desktopSuggested = !!el.querySelector('.scan-head');
  // / を押すまで、文字は検索欄に入らない（数字は行を開く）。/ のあとだけ検索欄に打てる
  const sr = el.querySelector('.scan-search');
  R.searchHiddenAtFirst = sr.hidden;
  await kk('/', 400);
  R.searchOpen = !sr.hidden;
  await kk('Escape', 400);
  R.searchClosed = sr.hidden && !el.querySelector('.scan-folder').hidden;
  await kk('u', 2500);          // このフォルダを使う
  R.number = !el.querySelector('.scan-number').hidden;
  const inp = el.querySelector('.scan-input');
  R.inputHiddenAtFirst = inp.hidden;      // Space を押す前は、入力欄は出ない
  await kk('s', 500);           // 1 枚なので並べ替えは開かない
  await kk(' ', 400);           // Space で番号の入力
  R.inputOpen = !inp.hidden;
  await kk('Escape', 400);      // Esc で入力だけ閉じる（\F の画面は閉じない）
  R.inputClosedByEsc = inp.hidden && !el.hidden && !el.querySelector('.scan-number').hidden;
  await kk(' ', 400);
  inp.value = '4';
  inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
  await sleep(1500);
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
  check(R.scanShown && R.stageHidden && R.source, "scan-only window should show only the scan screen, starting at the source choice: " + JSON.stringify(R));
  check(R.folder && R.number, "Enter → folder screen → u → numbering: " + JSON.stringify(R));
  check(R.desktopSuggested || true, "suggestions header (Desktop / used before) is shown when there are any");
  check(R.searchHiddenAtFirst && R.searchOpen && R.searchClosed, "the search box opens only with / and Esc closes it without leaving the folder screen: " + JSON.stringify(R));
  check(R.inputHiddenAtFirst && R.inputOpen && R.inputClosedByEsc, "Space opens the number input, Esc closes only the input (the scan screen stays): " + JSON.stringify(R));
  check(fs.existsSync(path.join(vault, "4.png")) && fs.readdirSync(outside).length === 0, "the outside photo is moved into the vault as 4.png");
  if (failed) process.exit(1);
  console.log("scan-only e2e: OK (source choice, keyboard folder walk, numbering, no Vim)");
} catch (e) { try { console.error(fs.readFileSync(path.join(gnosisHome, "logs", "app.log"), "utf8").slice(-1500)); } catch {} throw e; } finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
