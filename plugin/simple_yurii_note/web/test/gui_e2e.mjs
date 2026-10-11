// 実際の Electron アプリ + 本物の Vim（SYN）を、仮想ディスプレイ (xvfb) と一時フォルダで動かす E2E テスト。
// 本物の vault や HOME には触らない（HOME は一時フォルダに差し替え、設定ファイルへはリンクで読むだけ）。
//
//   node test/gui_e2e.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const realHome = os.homedir();
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "syn-gui-e2e-"));
const home = path.join(tmp, "home");
const vault = path.join(tmp, "vault", "note");
fs.mkdirSync(path.join(home, ".vim"), { recursive: true });
fs.mkdirSync(vault, { recursive: true });
for (const f of [".vimrc-simple-yurii-note", ".vim-simple-yurii-note"]) {
  const src = path.join(realHome, f);
  if (!fs.existsSync(src)) { console.error("SKIP: " + src + " が無いので E2E テストを省略"); process.exit(0); }
  fs.symlinkSync(src, path.join(home, f));
}

// テスト用 vault
const mk = (name, title, body, parent) => fs.writeFileSync(path.join(vault, name),
  `---\ntime: 2026-10-11 10:00:00\ntitle: ${title}\n---\n\n# ${title}\n\n${body}\n\n### Parent\n${parent}\n### BackLink\n`);
fs.writeFileSync(path.join(vault, "index.md"), "---\ntime: 2026-10-11 10:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[数学とは何か](m1.md)\n[PKM の設計](p1.md)\n");
mk("m1.md", "数学とは何か", "数学は**形式**と行動の間。\n\n- 箇条書き\n- [ ] 未完了\n\n[PKM の設計](p1.md) と [一貫性](m2.md)", "[Index](index.md)");
mk("m2.md", "一貫性", "同じ条件に同じ規則。", "[数学とは何か](m1.md)");
mk("p1.md", "PKM の設計", "言語化は後回し。", "[Index](index.md)");

const scenario = `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let G = window.__gui;
  for (let i = 0; i < 100 && !G; i++) { await sleep(50); G = window.__gui; }
  const waitFor = async (fn, ms = 8000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { try { const v = fn(); if (v) return v; } catch (e) {} await sleep(60); } return null; };
  const press = async (keys, wait = 500) => { console.log('STEP press ' + JSON.stringify(keys)); G.send(keys); await sleep(wait); };
  const base = (f) => (f || '').split('/').pop();
  const R = {};
  await waitFor(() => G.state().file);
  await sleep(800);
  R.start = { file: base(G.state().file), mode: document.getElementById('mode').textContent, h1: !!document.querySelector('.cm-md-h1') };

  // リンクの数字のしるし（仮想テキスト）が、リンクの手前に出る
  await press('j', 900);
  R.hints = [...document.querySelectorAll('.cm-vtext')].map((e) => e.textContent.trim());

  // 数字キーでリンクへ移動して開く
  await press('1', 900);
  R.afterDigit = base(G.state().file);
  R.digitDoc = G.view.getText().includes('数学とは何か');
  // Backspace で戻る
  await press('\\x7f', 900);
  R.afterBack = base(G.state().file);

  // Tab でリンク間を移動（開かない）
  const c0 = G.state().cur[0];
  await press('\\t', 500);
  R.tab = { moved: G.state().cur[0] !== c0 || G.state().cur[1] !== 1, file: base(G.state().file), line: G.view.getText().split('\\n')[G.state().cur[0] - 1] };

  // zn で新しいノートを作る（位置を聞かれるので Enter）
  await press('zn', 700);
  R.znPrompt = G.screen().slice(-3).join('|').trim().slice(0, 80);
  await press('\\r', 2200);
  R.newNote = base(G.state().file);

  // 挿入モード → 文字を打つ → Esc → :w
  await press('GA', 400);
  R.insertMode = document.getElementById('mode').textContent;
  await press('abc', 500);
  R.typed = G.view.getText().includes('abc');
  await press('\\x1b', 400);
  R.normalAgain = document.getElementById('mode').textContent;
  await press('V', 400);
  R.visualMode = document.getElementById('mode').textContent;
  await press('\\x1b', 300);
  await press(':w\\r', 900);
  R.modAfterSave = G.state().mod;

  // :ls の出力（Enter 待ち）では、端末の画面を広げて見せ、Enter で戻る
  await press(':ls\\r', 700);
  R.expandedOnLs = G.isExpanded();
  await press('\\r', 700);
  R.collapsedAfter = !G.isExpanded();

  R.__png = ${JSON.stringify(path.join(tmp, "final.png"))};
  return R;
})()`;
const scenarioPath = path.join(tmp, "scenario.js");
fs.writeFileSync(scenarioPath, scenario);
const outPath = path.join(tmp, "out.json");

const env = { ...process.env, HOME: home, PKM_ROOT: vault, PKM_TEST_SCRIPT: scenarioPath, PKM_TEST_OUT: outPath };
delete env.WAYLAND_DISPLAY; delete env.XDG_SESSION_TYPE; delete env.DISPLAY;
let failed = 0;
const check = (ok, msg) => { if (!ok) { console.error("FAIL: " + msg); failed++; } };
try {
  execFileSync("xvfb-run", ["-a", "-s", "-screen 0 1100x880x24", path.join(web, "node_modules/.bin/electron"), web, "--no-sandbox", "--disable-gpu", "--ozone-platform=x11", ...(process.env.DEBUG_E2E ? ["--enable-logging=stderr"] : [])],
    { env, stdio: ["ignore", "ignore", "inherit"], timeout: 120000 });
  const R = JSON.parse(fs.readFileSync(outPath, "utf8"));
  console.log(JSON.stringify(R, null, 2));
  if (R.fatal) { console.error("fatal: " + R.fatal); process.exit(1); }
  check(R.start?.file === "index.md" && R.start?.mode === "NORMAL" && R.start?.h1, "start: " + JSON.stringify(R.start));
  check((R.hints || []).includes("1") && (R.hints || []).includes("2"), "link number hints not shown: " + JSON.stringify(R.hints));
  check(R.afterDigit === "m1.md" && R.digitDoc, "digit key did not open the link: " + R.afterDigit);
  check(R.afterBack === "index.md", "Backspace did not go back: " + R.afterBack);
  check(R.tab?.moved && R.tab.file === "index.md" && /\]\(/.test(R.tab.line || ""), "Tab did not move to a link: " + JSON.stringify(R.tab));
  check(/^\d{12}\.md$/.test(R.newNote || ""), "zn did not create a note: " + R.newNote);
  check(fs.readdirSync(vault).some((f) => f === R.newNote), "new note file does not exist on disk");
  check(R.insertMode === "INSERT" && R.typed && R.normalAgain === "NORMAL" && R.visualMode === "V-LINE", "vim modes: " + JSON.stringify([R.insertMode, R.typed, R.normalAgain, R.visualMode]));
  check(R.modAfterSave === 0 && fs.readFileSync(path.join(vault, R.newNote), "utf8").includes("abc"), ":w did not save");
  check(R.expandedOnLs && R.collapsedAfter, "terminal strip did not expand/collapse for :ls: " + JSON.stringify([R.expandedOnLs, R.collapsedAfter]));
  const png = path.join(tmp, "final.png");
  if (fs.existsSync(png) && process.env.KEEP_PNG) fs.copyFileSync(png, process.env.KEEP_PNG);
  if (failed) process.exit(1);
  console.log("gui e2e: OK (real Vim + SYN in the app: hints, digit/Tab/BS, zn, insert/visual, :w, terminal strip)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
