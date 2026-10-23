// 実際の Electron アプリ（小さく作り直した版: 表示・曼荼羅・端末の下の 2 行） + 本物の Vim（SYN）を、仮想ディスプレイ (xvfb) と一時フォルダで動かす E2E テスト。
// 本物の vault や HOME には触らない（HOME は一時フォルダに差し替え、設定ファイルへはリンクで読むだけ）。
//
//   node test/gui_e2e.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

// 試験の一時フォルダは、デスクトップの test（TMPDIR があればそれ）。本物の vault には触らない。
function testBase() {
  const base = process.env.TMPDIR || path.join(os.homedir(), "Desktop", "test");
  fs.mkdirSync(base, { recursive: true });
  return base;
}
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const realHome = os.homedir();
const tmp = fs.mkdtempSync(path.join(testBase(), "syn-gui-e2e-"));
const home = path.join(tmp, "home");
const vault = path.join(tmp, "vault", "note");
fs.mkdirSync(path.join(home, ".vim"), { recursive: true });
fs.mkdirSync(vault, { recursive: true });
// Gnosis ホーム（一時フォルダ）。fzf などの Vim プラグインは、入っていればその場所へのリンクで読むだけ。
const gnosisHome = path.join(tmp, "gnosis-home");
fs.mkdirSync(path.join(gnosisHome, "plugins"), { recursive: true });
for (const base of [process.env.GNOSIS_TEST_PLUGINS, path.join(realHome, ".local", "share", "gnosis", "plugins"), path.join(realHome, ".vim-simple-yurii-note")].filter(Boolean)) {
  for (const name of ["fzf", "fzf.vim", "vim-surround"]) {
    const src = path.join(base, name);
    const dst = path.join(gnosisHome, "plugins", name);
    if (fs.existsSync(src) && !fs.existsSync(dst)) fs.symlinkSync(src, dst);
  }
}
if (!fs.existsSync(path.join(gnosisHome, "plugins", "fzf.vim"))) { console.error("SKIP: fzf.vim が無いので E2E テストを省略"); process.exit(0); }

// テスト用 vault
const mk = (name, title, body, parent) => fs.writeFileSync(path.join(vault, name),
  `---\ntime: 2026-10-11 10:00:00\ntitle: ${title}\n---\n\n# ${title}\n\n${body}\n\n### Parent\n${parent}\n### BackLink\n`);
fs.writeFileSync(path.join(vault, "index.md"), "---\ntime: 2026-10-11 10:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[数学とは何か](m1.md)\n[PKM の設計](p1.md)\n");
mk("m1.md", "数学とは何か", "数学は**形式**と行動の間。\n\n- 箇条書き\n- [ ] 未完了\n\n[PKM の設計](p1.md) と [一貫性](m2.md)", "[Index](index.md)");
mk("m2.md", "一貫性", "同じ条件に同じ規則。\n\n## sec\n\n見出しの本文", "[数学とは何か](m1.md)");
mk("anchor.md", "アンカー", "[二](m2.md#sec)", "[Index](index.md)");
mk("p1.md", "PKM の設計", "言語化は後回し。", "[Index](index.md)");


const scenario = `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let G = window.__gui;
  for (let i = 0; i < 100 && !G; i++) { await sleep(50); G = window.__gui; }
  const waitFor = async (fn, ms = 8000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { try { const v = fn(); if (v) return v; } catch (e) {} await sleep(60); } return null; };
  const press = async (keys, wait = 600) => { G.send(keys); await sleep(wait); };
  const base = (f) => (f || '').split('/').pop();
  const R = {};
  await sleep(2500);
  R.start = { file: base(G.state().file), h1: !!document.querySelector('.cm-md-h1'), hidden: [...document.querySelectorAll('.cm-hide-line')].length, mandalaHidden: document.getElementById('mandala').hidden };
  // 曼荼羅を開く
  if (document.getElementById('mandala').hidden) await press(' ', 1500);
  await waitFor(() => G.state().mandala && G.state().mandala.cells);
  const m = G.state().mandala || {};
  R.mandala = { size: m.size, cells: document.querySelectorAll('.m-cell').length, shown: !document.getElementById('mandala').hidden,
    withNote: document.getElementById('main').classList.contains('with-mandala'),
    kinds: [...new Set((m.cells || []).flat().map((c) => c.k))], legend: document.querySelectorAll('.m-legend span').length, center: m.title };
  // 曼荼羅が開いている間も、右にノートが映る（罫線の文字が出ない）
  R.hide = { st: JSON.stringify(G.state().hide), lines: document.querySelectorAll('.cm-hide-line').length, nw: G.state().mandala.noteWin };
  R.noteText = G.view.getText().includes('数学とは何か') && !/[─│┌┐└┘]/.test(G.view.getText());
  // マスのクリックでカーソルが動く
  const before = JSON.stringify(G.state().mandala.cur);
  const cells = [...document.querySelectorAll('.m-cell')].filter((e) => e.textContent.trim());
  const target = cells.find((e) => !e.classList.contains('sel')) || cells[0];
  target.click();
  await sleep(900);
  R.click = { before, after: JSON.stringify(G.state().mandala.cur), sel: document.querySelector('.m-cell.sel')?.dataset.r + ',' + document.querySelector('.m-cell.sel')?.dataset.c };
  // ( ) で盤面の幅、< > で画面の幅
  const w0 = document.getElementById('mandala').getBoundingClientRect().width;
  await press(')', 700);
  R.stretch = G.state().mandala.flags && true;
  await press('<', 700);
  const w1 = document.getElementById('mandala').getBoundingClientRect().width;
  R.screenWidth = { w0, w1 };
  await press('Q', 1000);
  R.closed = { hidden: document.getElementById('mandala').hidden, mandala: !!(G.state().mandala && G.state().mandala.cells) };
  R.__png = ${JSON.stringify(path.join(tmp, "final.png"))};
  R.__closeWindow = true;
  return R;
})()`;
const scenarioPath = path.join(tmp, "scenario.js");
fs.writeFileSync(scenarioPath, scenario);
const outPath = path.join(tmp, "out.json");

const stubBin = path.join(tmp, "stub-bin");
fs.mkdirSync(stubBin, { recursive: true });
for (const cmd of ["wl-paste", "wl-copy", "xclip", "xsel", "qdbus6", "qclip"]) fs.writeFileSync(path.join(stubBin, cmd), "#!/bin/sh\nexit 1\n", { mode: 0o755 });
const env = { ...process.env, PATH: stubBin + path.delimiter + (process.env.PATH || ""), HOME: home, GNOSIS_HOME: gnosisHome, GNOSIS_VIMRC: path.join(web, "..", "vimrc_gnosis"), PKM_ROOT: vault, PKM_TEST_SCRIPT: scenarioPath, PKM_TEST_OUT: outPath };
delete env.WAYLAND_DISPLAY; delete env.XDG_SESSION_TYPE; delete env.DISPLAY;
let failed = 0;
const check = (ok, msg) => { if (!ok) { console.error("FAIL: " + msg); failed++; } };
try {
  execFileSync("xvfb-run", ["-a", "-s", "-screen 0 1100x880x24", path.join(web, "node_modules/.bin/electron"), web, "--no-sandbox", "--disable-gpu", "--ozone-platform=x11", ...(process.env.DEBUG_E2E ? ["--enable-logging=stderr"] : [])],
    { env, stdio: ["ignore", "ignore", "inherit"], timeout: 120000 });
  const R = JSON.parse(fs.readFileSync(outPath, "utf8"));
  console.log(JSON.stringify(R, null, 2));
  if (R.fatal) { console.error("fatal: " + R.fatal); process.exit(1); }
  check(Array.isArray(R.__uncaught) && R.__uncaught.length === 0, "uncaught exception after the window was destroyed: " + JSON.stringify(R.__uncaught));
  const jsErrors = (R.__console || []).filter((l) => !/Electron Security Warning/.test(l));
  check(jsErrors.length === 0, "console errors in the app: " + JSON.stringify(jsErrors));
  check(R.start?.h1, "markdown should render at start: " + JSON.stringify(R.start));
  check(R.mandala?.size === 3 && R.mandala.cells === 9 && R.mandala.shown && R.mandala.withNote && R.mandala.legend === 10, "mandala should draw 3x3 colored cells: " + JSON.stringify(R.mandala));
  check(R.hide && R.hide.lines > 0, "YAML in the right note pane should be hidden: " + JSON.stringify(R.hide));
  check(R.noteText, "the note pane should show the note, not the mandala's box characters");
  check(R.click && R.click.before !== R.click.after && R.click.sel, "clicking a cell should move the cursor: " + JSON.stringify(R.click));
  check(R.screenWidth && R.screenWidth.w1 !== R.screenWidth.w0, "< should change the screen width: " + JSON.stringify(R.screenWidth));
  check(R.closed?.hidden && !R.closed.mandala, "Q should close the mandala: " + JSON.stringify(R.closed));
  const png = path.join(tmp, "final.png");
  if (fs.existsSync(png) && process.env.KEEP_PNG) fs.copyFileSync(png, process.env.KEEP_PNG);
  if (failed) process.exit(1);
  console.log("gui e2e: OK (markdown view, mandala board, click, widths)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
