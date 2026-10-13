// 実際の Electron アプリ + 本物の Vim（SYN）を、仮想ディスプレイ (xvfb) と一時フォルダで動かす E2E テスト。
// 本物の vault や HOME には触らない（HOME は一時フォルダに差し替え、設定ファイルへはリンクで読むだけ）。
//
//   node test/gui_e2e.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";

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
mk("m2.md", "一貫性", "同じ条件に同じ規則。\n\n## sec\n\n見出しの本文", "[数学とは何か](m1.md)");
mk("anchor.md", "アンカー", "[二](m2.md#sec)", "[Index](index.md)");
mk("p1.md", "PKM の設計", "言語化は後回し。", "[Index](index.md)");

// 縦長の PNG（文字より背が高いので、スクロールすると画面に出入りする）
function makePng(w, h, seed) {
  const crc = (buf) => { let c, t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } let x = 0xffffffff; for (const b of buf) x = t[(x ^ b) & 0xff] ^ (x >>> 8); return (x ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  const rows = []; for (let y = 0; y < h; y++) { const r = [0]; for (let x = 0; x < w; x++) r.push((x * 3 + seed * 40) & 255, (y / 4 + seed * 20) & 255, 200); rows.push(Buffer.from(r)); }
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(Buffer.concat(rows))), chunk("IEND", Buffer.alloc(0))]);
}
for (const [i, name] of ["a.png", "b.png", "c.png", "d.png"].entries()) fs.writeFileSync(path.join(vault, name), makePng(240, 900, i));
fs.writeFileSync(path.join(vault, "plain.md"), "---\ntime: 2026-01-01 00:00:00\ntitle: 本文だけ\n---\n\n# 本文だけ\n\n本文だけのノート（関係の節が無い）。\n");
fs.writeFileSync(path.join(vault, "grp.md"), "---\ntime: 2026-01-01 00:00:00\ntitle: グループG\nattribute: group\n---\n\n# グループG\n\n[節あり](sec.md)\n");
fs.writeFileSync(path.join(vault, "sec.md"), "---\ntime: 2026-01-01 00:00:00\ntitle: 節あり\n---\n\n# 節あり\n\n本文の文。\n\n### Group\n[グループG](grp.md)\n");
fs.writeFileSync(path.join(vault, "pick.md"), "---\ntime: 2026-01-01 00:00:00\ntitle: ピッカー\n---\n\n# ピッカー\n\n本文の文。\n");
fs.writeFileSync(path.join(vault, "multi.md"), "---\ntime: 2026-01-01 00:00:00\ntitle: 複数\n---\n\n# 複数\n\n本文の文。\n");
mk("img.md", "画像", ["a", "b", "c", "d"].map((n) => `## 画像 ${n}\n\n![](${n}.png)\n`).join("\n"), "[Index](index.md)");

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

  // Space の検索ポップアップ: 背景のマークダウン表示は変えず、ポップアップの場所だけ端末を重ねる
  {
    const hBefore = G.view.view.dom.innerHTML.length;
    await press(' ', 900);
    const wrap = document.getElementById('termwrap');
    R.popup = { n: (G.state().popuppos || []).length, expanded: G.isExpanded(), clip: wrap.style.clipPath.slice(0, 5), sameBg: G.view.view.dom.innerHTML.length === hBefore && !!document.querySelector('.cm-md-h1, .cm-line') };
    await press('\x1b', 700);
    R.popup.closed = !G.isExpanded() || (G.state().popuppos || []).length === 0;
    await sleep(400);
    R.popup.collapsed = !G.isExpanded() && wrap.style.clipPath === '';
  }

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

  // アンカー（#見出し）つきのリンクをクリックして、そのノートが開く（クリック → Vim の Enter）
  await press(':e anchor.md\\r', 1500);
  const alink = document.querySelector('[data-md-href="m2.md#sec"]');
  R.anchor = { found: !!alink };
  if (alink) {
    const ar = alink.getBoundingClientRect();
    alink.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, clientX: ar.left + ar.width / 2, clientY: ar.top + ar.height / 2, button: 0 }));
    await sleep(1800);
    R.anchor.opened = base(G.state().file);
  }

  // 画像: 画面に出入りしても、読み直さず（Blob を作り直さず）、見えている画像は表示され、全体の高さが跳ばない
  window.__blobs = 0; const origBlob = URL.createObjectURL.bind(URL); URL.createObjectURL = (b) => { window.__blobs++; return origBlob(b); };
  await press(':e img.md\\r', 2500);
  const sc = document.querySelector('.cm-scroller');
  const heights = [];
  let notLoaded = 0;
  // record=true のときだけ全体の高さを記録する（初めて画面に出る画像の分は、1 周目で高さが確定する）
  const lookImgs = (record) => {
    const sr = sc.getBoundingClientRect();
    const vis = [...document.querySelectorAll('.cm-md-img')].filter((w) => { const r = w.getBoundingClientRect(); return r.bottom > sr.top + 5 && r.top < sr.bottom - 5; });
    for (const w of vis) { const i = w.querySelector('img'); if (!(i && i.complete && i.naturalWidth > 0)) notLoaded++; }
    if (record) heights.push(sc.scrollHeight);
  };
  await sleep(1200); lookImgs(false);
  const maxTop = sc.scrollHeight - sc.clientHeight;
  // 1 周目（上から下まで）: 表示されるかだけ見る
  for (let y = 0; y <= maxTop + 300; y += 300) { sc.scrollTop = y; await sleep(150); lookImgs(false); }
  // 2 周目（下から上、さらに上から下）: 全体の高さが跳ばないこと
  const maxTop2 = sc.scrollHeight - sc.clientHeight;
  for (let y = maxTop2; y >= 0; y -= 400) { sc.scrollTop = y; await sleep(150); lookImgs(true); }
  for (let y = 0; y <= maxTop2; y += 500) { sc.scrollTop = y; await sleep(150); lookImgs(true); }
  await sleep(800); lookImgs(true);
  R.images = { file: base(G.state().file), blobs: window.__blobs, notLoaded, hMin: Math.min(...heights), hMax: Math.max(...heights), steps: heights.length };

  // 見るだけモード（Alt+V）: キーは Vim に届かず、j/k でスクロールだけ。カーソルは出ない。もう一度 Alt+V で戻る
  {
    const ta = document.querySelector('.xterm-helper-textarea');
    const key = (k, extra = {}) => ta.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true, ...extra }));
    const label = () => document.getElementById('mode').textContent;
    const sc2 = G.view.view.scrollDOM;
    sc2.scrollTop = 0; await sleep(200);
    const before = G.state();
    key('v', { altKey: true, code: 'KeyV' }); await sleep(300);
    const vo = { on: G.isViewOnly(), label: label() };
    key('i'); key('x'); key('d'); key('d'); await sleep(500);
    const after = G.state();
    const t0 = sc2.scrollTop; key('j'); key('j'); await sleep(200);
    const scrolled = sc2.scrollTop > t0;
    // 見るだけでも / で検索できて、見つかった行まで表示が動いて色づく
    sc2.scrollTop = 0; await sleep(200);
    key('/');
    ta.dispatchEvent(new KeyboardEvent('keypress', { key: '/', charCode: 47, keyCode: 47, bubbles: true, cancelable: true }));
    ta.dispatchEvent(new KeyboardEvent('keyup', { key: '/', bubbles: true, cancelable: true }));
    await sleep(500);
    const cmdline = G.screen().slice(-1)[0].trim();
    G.send('画像 d\\r'); await sleep(1200);
    const search = { cmdline, scrolled: sc2.scrollTop > 100, hit: !!document.querySelector('.cm-vim-hit'), modeBack: G.state().mode[0] === 'n' };
    const f0 = G.state().file;
    key('Backspace'); await sleep(900); // 戻る（SYN の操作）は Vim に届いて、前のノートへ戻る
    const passed = G.state().file !== f0;
    const curHidden = [...document.querySelectorAll('.cm-vim-block, .cm-vim-bar, .cm-vim-under')].every((e) => getComputedStyle(e).display === 'none' || getComputedStyle(e).backgroundColor === 'rgba(0, 0, 0, 0)');
    key('v', { altKey: true, code: 'KeyV' }); await sleep(400);
    R.viewOnly = { search, vo, mode: after.mode, sameFile: after.file === before.file, unmodified: !after.mod, scrolled, passed, curHidden, backOff: !G.isViewOnly(), backLabel: label() };
  }

  // zn の位置キー c: 新しいノートが今のノートの Context（文脈）になる
  {
    await press(':e plain.md\\r', 1200);
    const baseFile = base(G.state().file);
    await press('zn', 700);
    await press('c', 1800);
    R.znC = { from: baseFile, now: base(G.state().file), body: G.view.getText(), mode: G.state().mode };
    await press('\\x1b', 300);
    await press(':w\\r', 800);
  }

  // zn Enter: 新ノートへのリンクは、本文の最後（最初の関係の節の直前）に入る
  {
    await press(':e sec.md\\r', 1200);
    await press('zn', 700);
    await press('\\r', 1800);
    R.znEnter = { now: base(G.state().file) };
    await press('\\x1b', 300);
    await press(':w\\r', 800);
  }

  // \\l の確定: 選んだリンクを za と同じ置き場所キーで入れる（fzf の選択そのものは対象外。
  // sink が呼ぶ gnosis#insert_links_pick を直接呼ぶ）。h = カーソル直下
  {
    await press(':e pick.md\\r', 1200);
    await press('G', 300);
    await press(':call gnosis#insert_links_pick(["[数学とは何か](m1.md)"], getpos("."))\\r', 800);
    R.pickPrompt = G.screen().slice(-3).join('|').trim().slice(0, 200);
    await press('h', 1200);
    await press(':w\\r', 800);
  }

  // \\l → 検索 → 確定 の直後: fzf を閉じたあとの画面が描き直されていて、置き場所の質問が見える。
  // （fzf の exit_cb の中で getchar すると、再描画前に待ちに入って白い／途中までの画面が残った）
  {
    await press(':e pick.md\\r', 1200);
    await press('G', 300);
    await press('\\\\l', 2500);
    await press('数学', 3500);
    await press('\\r', 2500);
    const rows = G.screen().map((r) => r.trimEnd());
    R.pick = { prompt: rows.slice(-1)[0], hasLink: (rows[8] || '').includes('数学とは何か'), fullLinesBeforePrompt: rows.filter(Boolean).length,
               st: { mode: G.state().mode, bt: G.state().bt, popups: G.state().popups }, expanded: G.isExpanded() };
    await press('\\x1b', 500);
  }

  // \\e 詳細モード: 5 項目を入力し、名前を付けて保存（2 件）→ 1 件削除。vault の JSON を後で確認する
  {
    const menu = () => G.screen().slice(-3).join('|').replace(/\\s+/g, ' ').slice(0, 300);
    await press(':e m1.md\\r', 1200);
    await press('\\\\e', 800);
    await press('2', 600);                 // 詳細
    R.eMenu1 = menu();
    await press('1', 600);                 // 新しく設定する
    for (let k = 0; k < 5; k++) await press('\\r', 300);   // 既定値のまま 5 項目
    await press('2', 600);                 // 名前を付けて保存して展開する
    await press('テスト設定\\r', 1500);
    R.eAfterSave = { file: base(G.state().file) };
    // 2 件目: 値を変えて保存（入力欄は既定値入りなので Ctrl-U で消してから打つ）
    await press(':e m1.md\\r', 1200);
    await press('\\\\e', 800);
    await press('2', 600);
    R.eMenu2 = menu();
    await press('2', 600);                 // 新しく設定する（前回の設定があるので 2 番）
    for (const v of ['2', '0', '1', '2', 'f']) await press('\\x15' + v + '\\r', 300);
    await press('2', 600);
    await press('残す設定\\r', 1500);
    R.eAfterSave2 = { file: base(G.state().file) };
    // 呼び出し → 削除
    await press(':e m1.md\\r', 1200);
    await press('\\\\e', 800);
    await press('2', 600);
    await press('4', 800);                 // プリセットを削除する
    R.eDeleteList = G.screen().filter((r) => r.trim()).slice(-6).join('|').replace(/\\s+/g, ' ').slice(0, 300);
    await press('1\\r', 800);              // 一覧の 1 番（名前順で「テスト設定」）
    await press('y', 800);                 // 削除の確認 Yes
    R.eAfterDelete = menu();
    await press('\\x1b', 500);
    await press('\\x1b', 500);
  }

  // za: クリップボード（ヤンク）に複数のリンクがあれば全部足す。h = カーソル直下
  {
    await press(':e multi.md\\r', 1200);
    await press('G', 300);
    await press(':let @" = "[一つ目](m1.md)\\\\n[二つ目](m2.md)\\\\n[三つ目](index.md)"\\r', 500);
    await press('za', 800);
    await press('h', 1200);
    await press(':w\\r', 800);
  }

  R.__png = ${JSON.stringify(path.join(tmp, "final.png"))};
  R.__closeWindow = true;
  return R;
})()`;
const scenarioPath = path.join(tmp, "scenario.js");
fs.writeFileSync(scenarioPath, scenario);
const outPath = path.join(tmp, "out.json");

// クリップボードを読むコマンドは、何も出さない代役に差し替える（実機のクリップボードの中身で za などの結果が
// 変わらないように。za は取得元を順に見て、最初に有効なリンクがあったものを使う）
const stubBin = path.join(tmp, "stub-bin");
fs.mkdirSync(stubBin, { recursive: true });
for (const cmd of ["wl-paste", "wl-copy", "xclip", "xsel", "qdbus6", "qclip"]) {
  fs.writeFileSync(path.join(stubBin, cmd), "#!/bin/sh\nexit 1\n", { mode: 0o755 });
}
const env = { ...process.env, PATH: stubBin + path.delimiter + (process.env.PATH || ""), HOME: home, PKM_ROOT: vault, PKM_TEST_SCRIPT: scenarioPath, PKM_TEST_OUT: outPath };
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
  check(R.anchor?.found && R.anchor.opened === "m2.md", "clicking an anchor link (m2.md#sec) did not open the note: " + JSON.stringify(R.anchor));
  check(R.images?.file === "img.md", "could not open the image note: " + JSON.stringify(R.images));
  check(R.images && R.images.blobs <= 4, "images were re-read on scroll (blob URLs created: " + R.images?.blobs + ", images: 4)");
  check(R.images && R.images.notLoaded === 0, "visible images were not loaded while scrolling: " + JSON.stringify(R.images));
  check(R.images && R.images.hMax - R.images.hMin < 400, "scroll height jumped while scrolling: " + JSON.stringify(R.images));
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
  check(R.popup?.n > 0 && R.popup.expanded && R.popup.clip === "path(" && R.popup.sameBg && R.popup.collapsed, "search popup should overlay only its rectangle: " + JSON.stringify(R.popup));
  check(R.viewOnly?.vo.on && R.viewOnly.vo.label === "VIEW" && R.viewOnly.mode[0] === "n" && R.viewOnly.sameFile && R.viewOnly.unmodified && R.viewOnly.scrolled && R.viewOnly.search.cmdline === '/' && R.viewOnly.search.scrolled && R.viewOnly.search.hit && R.viewOnly.search.modeBack && R.viewOnly.passed && R.viewOnly.curHidden && R.viewOnly.backOff && R.viewOnly.backLabel === "NORMAL", "view-only mode: " + JSON.stringify(R.viewOnly));
  {
    const z = R.znC || {};
    check(/^\d{12}\.md$/.test(z.now || "") && z.from === "plain.md", "zn c did not create a new note: " + JSON.stringify(z));
    const oldTxt = fs.readFileSync(path.join(vault, "plain.md"), "utf8");
    const ctx = oldTxt.split("### Context")[1] || "";
    check(ctx.includes("(" + z.now + ")"), "zn c: the old note (no sections before) should get ### Context with the new note: " + oldTxt.slice(-200));
    check(!/\n### Parent\n/.test(oldTxt), "zn c: no ### Parent should remain");
    check((z.body || "").includes("(plain.md)"), "zn c: the new note body should link the old note: " + (z.body || "").slice(0, 200));
  }
  {
    const txt = fs.readFileSync(path.join(vault, "sec.md"), "utf8");
    const lines = txt.split("\n");
    const linkAt = lines.findIndex((l) => /^\[\d{12}\]\(\d{12}\.md\)$/.test(l));
    const groupAt = lines.indexOf("### Group");
    check(groupAt > 0, "sec.md should still have its ### Group: " + JSON.stringify(lines));
    const bodyAt = lines.indexOf("本文の文。");
    check(linkAt > bodyAt && linkAt < groupAt && lines.indexOf("### Context") < 0,
      "zn Enter: the link should be at the end of the body, just before the first section (### Group): " + JSON.stringify(lines.slice(6)));
    check(lines.slice(linkAt + 1, groupAt).every((l) => l === ""), "zn Enter: nothing but blanks between the link and ### Group: " + JSON.stringify(lines.slice(linkAt, groupAt + 1)));
  }
  {
    const txt = fs.readFileSync(path.join(vault, "pick.md"), "utf8");
    check(/^\[[^\]]*\]\(m1\.md\)$/m.test(txt), "\\L h: the picked note should be linked on its own line: " + JSON.stringify(txt.slice(-160)));
  }
  {
    const k = R.pick || {};
    check(/h=カーソル直下/.test(k.prompt || "") && /c=Context末尾/.test(k.prompt || ""), "\\l: the place-key prompt should be visible after confirming: " + JSON.stringify(k));
    check(k.hasLink, "\\l: the buffer should be fully redrawn behind the prompt (not a blank/half-drawn screen): " + JSON.stringify(k));
    check(k.st?.mode === "n" && k.st.bt === "" && k.st.popups === 0 && !k.expanded, "\\l: back in the normal buffer: " + JSON.stringify(k));
  }
  {
    check(/新しく設定する/.test(R.eMenu1 || "") && !/プリセット/.test(R.eMenu1 || ""), "\\e detail: first time shows only 'new settings': " + R.eMenu1);
    check(/^T_\d+\.md$/.test(R.eAfterSave?.file || "") && /^T_\d+\.md$/.test(R.eAfterSave2?.file || ""), "\\e detail: expansion files are opened after saving: " + JSON.stringify([R.eAfterSave, R.eAfterSave2]));
    check(/プリセットを呼び出す/.test(R.eMenu2 || "") && /プリセットを削除する/.test(R.eMenu2 || "") && /前回の設定で展開/.test(R.eMenu2 || ""), "\\e detail: menu offers last/recall/delete once presets exist: " + R.eMenu2);
    check(/テスト設定.*文中3 Context1 Group1 BL\/Rel1 日記t/.test(R.eDeleteList || ""), "\\e detail: preset list shows names and their 5 settings: " + R.eDeleteList);
    const pre = JSON.parse(fs.readFileSync(path.join(vault, ".pkm_expand_presets.json"), "utf8")).presets;
    check(!("テスト設定" in pre) && JSON.stringify(pre["残す設定"]) === JSON.stringify({ body: 2, context: 0, group: 1, br: 2, diary: false }),
      "\\e detail: deleted preset is gone, the other keeps its 5 values on disk: " + JSON.stringify(pre));
    const last = JSON.parse(fs.readFileSync(path.join(vault, ".pkm_expand_prefs.json"), "utf8"));
    check(last.body === 2 && last.diary === false, "\\e detail: last settings are recorded separately: " + JSON.stringify(last));
    const m1 = fs.readFileSync(path.join(vault, "m1.md"), "utf8");
    check(!m1.includes("テスト設定") && !m1.includes("残す設定"), "\\e detail: notes are untouched by preset operations");
  }
  {
    const txt = fs.readFileSync(path.join(vault, "multi.md"), "utf8");
    check(/\[一つ目\]\(m1\.md\)/.test(txt) && /\[二つ目\]\(m2\.md\)/.test(txt) && /\[三つ目\]\(index\.md\)/.test(txt),
      "za: all links on the clipboard should be added, not only the first: " + JSON.stringify(txt.slice(-200)));
  }
  const png = path.join(tmp, "final.png");
  if (fs.existsSync(png) && process.env.KEEP_PNG) fs.copyFileSync(png, process.env.KEEP_PNG);
  if (failed) process.exit(1);
  console.log("gui e2e: OK (real Vim + SYN in the app: hints, digit/Tab/BS, zn, insert/visual, :w, terminal strip)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
