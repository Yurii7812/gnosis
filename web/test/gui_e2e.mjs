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
fs.writeFileSync(path.join(vault, "page.html"), "<!doctype html><html><head><meta charset=utf-8><title>t</title></head><body><h1 id=hh>HTML ページ</h1></body></html>");
mk("p1.md", "PKM の設計", "言語化は後回し。", "[Index](index.md)");


// 紙のスキャンの番号付け（\F）用: 受け皿に 3 枚。Paper-Zettelkasten-Index も作っておく
const TINY_PNG = Buffer.from("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082", "hex");
fs.mkdirSync(path.join(vault, ".gnosis", "scans"), { recursive: true });
for (const [i, n] of ["paper-scan-20261024-100000-01.png", "paper-scan-20261024-100000-02.png", "paper-scan-20261024-100000-03.png"].entries())
  fs.writeFileSync(path.join(vault, ".gnosis", "scans", n), Buffer.concat([TINY_PNG, Buffer.from(String(i))]));
const outside = path.join(tmp, "outside-scans");
fs.mkdirSync(outside, { recursive: true });
for (const n of ["x1.png", "x2.png"]) fs.writeFileSync(path.join(outside, n), Buffer.concat([TINY_PNG, Buffer.from(n)]));
execFileSync("python3", ["-c", "import sys; sys.path.insert(0, sys.argv[1]); import paper_pkm as pp; from pathlib import Path; pp.create_paper_index(Path(sys.argv[2]))", path.join(web, "..", "python"), vault]);

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
  // 本物の \\zz の窓で YAML を隠す（Space で切り替え、q で閉じる）。アプリの画面で実際に隠れる
  const shown = () => [...document.querySelectorAll('.cm-line')].filter((e) => getComputedStyle(e).display !== 'none').length;
  const fmEl = document.querySelector('.cm-md-fm');
  R.fm = fmEl ? { fm: getComputedStyle(fmEl).color, body: getComputedStyle(document.querySelector('.cm-content')).color } : null;
  const hid0 = shown();
  await press('\\\\zz', 900);
  await press(' ', 900);
  const hid1 = shown();
  await press('q', 700);
  R.zz = { before: hid0, open: hid1, after: shown(), st: JSON.stringify(G.state().hide) };
  await press(':call gnosis#settings#set("hide.yaml", v:false)|call gnosis#hide#apply_all()\\r', 700);
  // :GnosisSettings（特別なバッファ）は、端末の画面が全面に出て読める
  await press(':GnosisSettings\\r', 1300);
  R.settings = { expanded: G.isExpanded(), text: G.screen().join('\\n').includes('Gnosis — 設定') };
  await press('q', 900);
  R.settings.back = !G.isExpanded();
  // \\zz の設定（YAML・上下の名前: 系を隠す）
  await press(':call gnosis#settings#set("hide.yaml", v:true)|call gnosis#settings#set("hide.top", v:true)|call gnosis#settings#set("hide.bottom", v:true)|call gnosis#hide#apply_all()\\r', 800);
  // 曼荼羅を開く
  if (document.getElementById('mandala').hidden) await press(' ', 1500);
  await waitFor(() => G.state().mandala && G.state().mandala.cells);
  const m = G.state().mandala || {};
  R.mandala = { size: m.size, cells: document.querySelectorAll('.m-cell').length, shown: !document.getElementById('mandala').hidden,
    withNote: document.getElementById('main').classList.contains('with-mandala'),
    kinds: [...new Set((m.cells || []).flat().map((c) => c.k))], legend: document.querySelectorAll('.m-legend span').length, center: m.title };
  // リンクの HTML は、この画面の中（重ね表示）で開き、q で閉じる。vault の外の HTML は開かない
  {
    R.html = {};
    await G.openHtml('page.html');
    await sleep(400);
    R.html.open = G.htmlIsOpen() && !document.getElementById('htmlview').hidden && /page\.html$/.test(document.getElementById('hv-frame').src);
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'q', bubbles: true, cancelable: true }));
    await sleep(200);
    R.html.closed = !G.htmlIsOpen() && document.getElementById('htmlview').hidden;
    R.html.outside = await window.gui.linkHtml(G.state().file, '../../../../../etc/passwd.html');
    R.html.web = await window.gui.linkExternal('javascript:alert(1)');
  }
  // 曼荼羅の下: 選んでいるノートの題は出さず、種類の凡例を出す。選んでいるマスは内側が塗られ（::after）、右のノートにカーソルがあるときは消える
  {
    const selEl = document.querySelector('.m-cell.sel');
    R.mand2 = { foot: !!document.querySelector('.m-foot'), legend: !document.querySelector('.m-legend').hidden, legendN: document.querySelectorAll('.m-legend span').length,
      selAfter: selEl ? getComputedStyle(selEl, '::after').content : null, focusedClass: !document.getElementById('mandala').classList.contains('unfocused') };
    await press('\\x17l', 900);
    R.mand2.unfocusedAfterNote = document.getElementById('mandala').classList.contains('unfocused');
    R.mand2.selAfterGone = selEl ? getComputedStyle(document.querySelector('.m-cell.sel'), '::after').display : null;
    await press('\\x17h', 900);
    R.mand2.refocused = !document.getElementById('mandala').classList.contains('unfocused');
  }
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
  // 紙のスキャンの番号付け: 開く → 番号 + Enter で次へ → d で日記 → Esc で終了
  {
    const scanEl = document.getElementById('scan');
    const inp = scanEl.querySelector('.scan-input');
    const key = async (k, wait = 700) => { inp.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })); await sleep(wait); };
    const typeIn = async (v) => { inp.value = v; await sleep(50); };
    const rootKey = async (k, wait = 800) => { scanEl.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })); await sleep(wait); };
    await press(':call GnosisGuiScan()\\r', 1500);
    const choose = { shown: !scanEl.querySelector('.scan-source').hidden, inText: scanEl.querySelector('.c-in').textContent, outText: scanEl.querySelector('.c-out').textContent };
    await rootKey('v', 1200);
    const sc = { choose, opened: !scanEl.hidden, count1: scanEl.querySelector('.scan-count').textContent, imgShown: !!scanEl.querySelector('img').getAttribute('src') };
    sc.inputHiddenBeforeSpace = inp.hidden;
    await rootKey(' ', 400);                                    // Space で番号の入力を開く
    await typeIn('1a2'); await key('Enter', 1500);
    sc.afterFirst = { count: scanEl.querySelector('.scan-count').textContent, prev: scanEl.querySelector('.scan-prev').textContent };
    await key('Escape', 400);                                   // Esc は入力だけ閉じる
    sc.afterEscOpen = !scanEl.hidden && inp.hidden;
    await rootKey('d', 400);                                    // 入力が閉じていれば d は日記
    sc.dateLabel = scanEl.querySelector('.scan-label').textContent;
    await typeIn('2026-10-24'); await key('Enter', 1500);
    sc.afterDiary = scanEl.querySelector('.scan-count').textContent;
    // 同じ番号をもう一度付けると上書き（前の画像は .trash に残る）
    await key('Tab', 200);
    sc.tab = inp.value;
    await key('Enter', 1500);
    sc.empty = scanEl.querySelector('.scan-empty').textContent;
    await rootKey('q', 6000);                                   // q で \\F の画面を閉じる
    sc.closed = scanEl.hidden;
    // vault の外のフォルダ: Enter → フォルダを選ぶ → Enter で使う → 番号付け
    localStorage.setItem('scanDir', ${JSON.stringify(outside)});
    await press(':call GnosisGuiScan()\\r', 1500);
    await rootKey('Enter', 1000);
    sc.folder = { shown: !scanEl.querySelector('.scan-folder').hidden, path: scanEl.querySelector('.scan-path').textContent, rows: scanEl.querySelector('.scan-row.use')?.textContent };
    await rootKey('Enter', 2500);
    await rootKey(' ', 400);
    sc.outside = { count: scanEl.querySelector('.scan-count').textContent, imgShown: !!scanEl.querySelector('img').getAttribute('src') };
    await typeIn('9'); await key('Enter', 1200);
    await typeIn('9a'); await key('Enter', 1200);
    await key('Escape', 500);
    await rootKey('q', 6000);
    R.scan = sc;
  }
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
  check(R.mandala?.size === 3 && R.mandala.cells === 9 && R.mandala.shown && R.mandala.withNote && R.mandala.legend === 11, "mandala should draw 3x3 colored cells: " + JSON.stringify(R.mandala));
  check(R.settings && R.settings.expanded && R.settings.text && R.settings.back, ":GnosisSettings should show the terminal screen and q should return: " + JSON.stringify(R.settings));
  check(R.html && R.html.open && R.html.closed && R.html.outside === null && R.html.web === false, "HTML link opens inside the app and q closes it; outside-vault and non-http are refused: " + JSON.stringify(R.html));
  check(R.fm && R.fm.fm === R.fm.body, "YAML should not be gray (same color as the body text): " + JSON.stringify(R.fm));
  check(R.zz && R.zz.after < R.zz.before, "\\\\zz in the app should really hide YAML: " + JSON.stringify(R.zz));
  check(R.mand2 && !R.mand2.foot && R.mand2.legend && R.mand2.legendN === 11 && R.mand2.selAfter === '""' && R.mand2.focusedClass && R.mand2.unfocusedAfterNote && R.mand2.selAfterGone === 'none' && R.mand2.refocused, "mandala: no title footer, legend shown, selected cell filled, unfocused hides it: " + JSON.stringify(R.mand2));
  check(R.hide && R.hide.lines > 0, "YAML in the right note pane should be hidden: " + JSON.stringify(R.hide));
  check(R.noteText, "the note pane should show the note, not the mandala's box characters");
  check(R.click && R.click.before !== R.click.after && R.click.sel, "clicking a cell should move the cursor: " + JSON.stringify(R.click));
  check(R.screenWidth && R.screenWidth.w1 !== R.screenWidth.w0, "< should change the screen width: " + JSON.stringify(R.screenWidth));
  {
    const sc = R.scan || {};
    check(sc.choose?.shown && /vault/.test(sc.choose.outText) && /3/.test(sc.choose.inText), "\\F first asks where the scans are (Enter = outside the vault, v = inside): " + JSON.stringify(sc.choose));
    check(sc.folder?.shown && /2/.test(sc.folder.rows || "") && sc.outside && /1 \/ 2/.test(sc.outside.count) && sc.outside.imgShown, "outside folder: pick the folder with the keyboard and number its photos: " + JSON.stringify([sc.folder, sc.outside]));
    check(fs.existsSync(path.join(vault, "9.png")) && fs.existsSync(path.join(vault, "9a.png")) && fs.readdirSync(outside).length === 0, "outside photos are moved into the vault as numbered scans");
    check(sc.opened && /1 \/ 3/.test(sc.count1) && sc.imgShown, "scan screen should open with 3 unnumbered scans and show the image: " + JSON.stringify(sc));
    check(/2 ?\/ ?2|1 \/ 2/.test(sc.afterFirst?.count || "") && /1a2/.test(sc.afterFirst?.prev || ""), "after Enter the next scan is shown and the previous number is displayed: " + JSON.stringify(sc.afterFirst));
    check(/YYYY/.test(sc.dateLabel || "") && /1 \/ 1/.test(sc.afterDiary || ""), "d should ask for a date and register the diary: " + JSON.stringify(sc));
    check(sc.inputHiddenBeforeSpace && sc.afterEscOpen && sc.tab === "1a2" && sc.closed, "Space opens the input, Esc closes only the input, d works when it is closed, Tab puts the previous number, q closes: " + JSON.stringify(sc));
    check(fs.existsSync(path.join(vault, "1a2.png")), "1a2.png should exist in the vault");
    const trash = fs.existsSync(path.join(vault, ".trash")) ? fs.readdirSync(path.join(vault, ".trash")).filter((n) => n.endsWith("_1a2.png")) : [];
    check(trash.length === 1, "overwriting the same number keeps the old image in .trash: " + JSON.stringify(trash));
    check(fs.readdirSync(path.join(vault, ".gnosis", "scans")).length === 0, "the inbox should be empty after numbering all scans");
  }
  check(R.closed?.hidden && !R.closed.mandala, "Q should close the mandala: " + JSON.stringify(R.closed));
  const png = path.join(tmp, "final.png");
  if (fs.existsSync(png) && process.env.KEEP_PNG) fs.copyFileSync(png, process.env.KEEP_PNG);
  if (failed) process.exit(1);
  console.log("gui e2e: OK (markdown view, mandala board, click, widths)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
