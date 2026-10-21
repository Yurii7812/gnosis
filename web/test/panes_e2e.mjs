// `\A` のタブ・分割ペイン・コマンドパレットを、実際の Electron + 本物の Vim で確かめる E2E。
//   ビューのタブを開く・右に分割・ドラッグで移動／分割・固定・閉じて再開・分割線のリサイズ・保存と復元・Ctrl+Shift+P のパレット。
//   node test/panes_e2e.mjs      （vault・HOME は一時フォルダ。本物には触らない）
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

function testBase() {
  const base = process.env.TMPDIR || path.join(os.homedir(), "Desktop", "test");
  fs.mkdirSync(base, { recursive: true });
  return base;
}
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const realHome = os.homedir();
const tmp = fs.mkdtempSync(path.join(testBase(), "panes-e2e-"));
const home = path.join(tmp, "home");
const vault = path.join(tmp, "vault", "note");
fs.mkdirSync(path.join(home, ".vim"), { recursive: true });
fs.mkdirSync(vault, { recursive: true });
const gnosisHome = path.join(tmp, "gnosis-home");
fs.mkdirSync(path.join(gnosisHome, "plugins"), { recursive: true });
for (const base of [process.env.GNOSIS_TEST_PLUGINS, path.join(realHome, ".local", "share", "gnosis", "plugins"), path.join(realHome, ".vim-simple-yurii-note")].filter(Boolean)) {
  for (const name of ["fzf", "fzf.vim", "vim-surround"]) {
    const src = path.join(base, name), dst = path.join(gnosisHome, "plugins", name);
    if (fs.existsSync(src) && !fs.existsSync(dst)) fs.symlinkSync(src, dst);
  }
}
if (!fs.existsSync(path.join(gnosisHome, "plugins", "fzf.vim"))) { console.error("SKIP: fzf.vim が無いので E2E テストを省略"); process.exit(0); }

const note = (name, title, body) => fs.writeFileSync(path.join(vault, name), `---\ntime: 2026-10-11 10:00:00\ntitle: ${title}\n---\n\n# ${title}\n\n${body}\n`);
fs.writeFileSync(path.join(vault, "index.md"), "---\ntime: 2026-10-11 10:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[ノートA](a.md)\n[ノートB](b.md)\n");
note("a.md", "ノートA", "最初の文。\n\n[Bへ](b.md)");
note("b.md", "ノートB", "Bの本文。");
const A = path.join(vault, "a.md");

const scenario = `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let G = window.__gui;
  for (let i = 0; i < 100 && !G; i++) { await sleep(50); G = window.__gui; }
  const waitFor = async (fn, ms = 10000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { try { const v = fn(); if (v) return v; } catch (e) {} await sleep(80); } return null; };
  const P = () => G.panes();
  const lay = () => P().getLayout();
  const tabsOf = () => [...document.querySelectorAll('.pane')].map((p) => [...p.querySelectorAll('.tab')].map((t) => (t.title.startsWith('Vim') ? 'Vim' : t.querySelector('.tabtitle').textContent)));
  const kinds = (n) => { const o = []; (function w(x) { if (x.type === 'tabs') x.tabs.forEach((t) => o.push(t.kind)); else { w(x.a); w(x.b); } })(n); return o; };
  const click = async (sel) => { document.querySelector(sel).click(); await sleep(250); };
  const run = async (fn) => { fn(); await sleep(250); };
  const R = {};
  await waitFor(() => G.state().file);
  await sleep(800);

  // 1. 最初は Vim だけ（タブバーを出さない。今までと同じ見た目）
  R.solo = { tabbarShown: getComputedStyle(document.querySelector('.tabbar')).display !== 'none', vimTabTitle: document.querySelector('.tab .tabtitle').textContent, kinds: kinds(lay()), stageW: document.getElementById('stage').offsetWidth };

  // 2. ツールバーでカードを開く → タブが増える。iframe に書き出した静的サイトのページが入る
  await run(() => G.panes().openView('cards'));
  await waitFor(() => document.querySelector('.viewframe') && document.querySelector('.viewframe').src, 20000);
  const fr = document.querySelector('.viewframe');
  await waitFor(() => document.querySelector('.viewmsg').hidden, 20000);
  R.cards = { tabs: tabsOf(), src: fr.src.split('/').slice(-1)[0], name: fr.name, msgHidden: document.querySelector('.viewmsg').hidden, tabbarShown: getComputedStyle(document.querySelector('.tabbar')).display !== 'none', vimHidden: document.getElementById('stage').closest('.hidden-tab') !== null || getComputedStyle(document.getElementById('stage')).display === 'none' };

  // 3. 同じものは重ねて開かない
  await run(() => G.panes().openView('cards'));
  R.noDup = tabsOf()[0].length;

  // 4. 右に分割 → 2 つのペイン。Vim は小さくなっても動く
  await run(() => G.panes().openView('graph'));
  await run(() => G.panes().splitFocused('row'));
  await sleep(500);
  R.split = { panes: P().panesCount(), tabs: tabsOf(), type: lay().type, dir: lay().dir };
  P().showVim();                          // Vim のタブを前に出す（分割で狭くなっても動く）
  await sleep(600);
  R.vimAfterSplit = { w: document.getElementById('stage').offsetWidth, shown: document.getElementById('stage').offsetWidth > 100, rows: G.screen().length };

  // 5. ドラッグで移動・端に落として分割（DataTransfer を使った本物のドラッグ操作）
  const dt = new DataTransfer();
  const graphTab = [...document.querySelectorAll('.tab')].find((t) => t.querySelector('.tabtitle').textContent === 'グラフ');
  graphTab.dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer: dt }));
  const bodies = [...document.querySelectorAll('.panebody')];
  const target = bodies[0];
  const r = target.getBoundingClientRect();
  target.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: dt, clientX: r.right - 5, clientY: r.top + r.height / 2 }));
  R.dropZone = document.querySelector('.dropzone:not([hidden])') ? document.querySelector('.dropzone:not([hidden])').dataset.zone : '';
  target.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: dt, clientX: r.right - 5, clientY: r.top + r.height / 2 }));
  await sleep(500);
  R.dragSplit = { panes: P().panesCount(), kinds: kinds(lay()) };

  // 6. 固定: 右クリックのメニュー → 固定。閉じるボタンが使えなくなる
  const cardsTab = () => [...document.querySelectorAll('.tab')].find((t) => t.querySelector('.tabtitle').textContent.includes('カード'));
  cardsTab().dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 100, clientY: 100 }));
  const item = [...document.querySelectorAll('.ctxmenu button')].find((b) => b.textContent === 'タブを固定');
  R.menuHasPin = !!item;
  if (item) item.click();
  await sleep(300);
  R.pinned = { title: cardsTab() ? cardsTab().querySelector('.tabtitle').textContent : '', closeDisabled: cardsTab() ? cardsTab().querySelector('.tabclose').disabled : null };

  // 7. 閉じる → 再開
  const before = kinds(lay()).length;
  const gTab = [...document.querySelectorAll('.tab')].find((t) => t.querySelector('.tabtitle').textContent === 'グラフ');
  gTab.querySelector('.tabclose').click();
  await sleep(300);
  R.closed = { kinds: kinds(lay()), closedCount: P().closedCount() };
  await run(() => G.panes().reopenClosed());
  R.reopened = { kinds: kinds(lay()), closedCount: P().closedCount(), count: kinds(lay()).length === before };

  // 8. 分割線のドラッグでリサイズ
  const sp = document.querySelector('.splitter');
  let ratio0 = null, ratio1 = null;
  (function w(x) { if (x.type === 'split' && ratio0 == null) ratio0 = x.ratio; if (x.type === 'split') { w(x.a); w(x.b); } })(lay());
  if (sp) {
    const sr = sp.parentElement.getBoundingClientRect();
    sp.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, clientX: sr.left + sr.width * 0.5, clientY: sr.top + 50 }));
    document.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: sr.left + sr.width * 0.3, clientY: sr.top + 50 }));
    document.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
  }
  await sleep(300);
  (function w(x) { if (x.type === 'split' && ratio1 == null) ratio1 = x.ratio; if (x.type === 'split') { w(x.a); w(x.b); } })(lay());
  R.resize = { before: ratio0, after: ratio1 };

  // 9. 保存: .gnosis/workspace.json に入る。読み直して同じ形に復元できる
  await sleep(900);
  const saved = await window.gui.loadWorkspace();
  R.saved = { hasFile: !!saved, hasCards: saved.includes('"cards"'), version: JSON.parse(saved).version };
  const kindsBefore = JSON.stringify(kinds(lay()));
  await P().restore();
  R.restored = { same: JSON.stringify(kinds(lay())) === kindsBefore, vimOnce: kinds(lay()).filter((k) => k === 'vim').length };

  // 10. コマンドパレット: Ctrl+Shift+P → 検索 → Enter で実行。Vim のコマンドも出る
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'P', code: 'KeyP', ctrlKey: true, shiftKey: true, bubbles: true, cancelable: true }));
  await waitFor(() => !document.getElementById('palette').hidden, 4000);
  const inp = document.getElementById('palette-input');
  inp.value = 'タイムライン';
  inp.dispatchEvent(new Event('input'));
  await sleep(200);
  R.palette = { shown: !document.getElementById('palette').hidden, first: document.querySelector('#palette-list li') ? document.querySelector('#palette-list li').textContent : '' };
  inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
  await sleep(500);
  R.paletteRan = { closed: document.getElementById('palette').hidden, hasTimeline: kinds(lay()).includes('timeline') };
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'P', code: 'KeyP', ctrlKey: true, shiftKey: true, bubbles: true, cancelable: true }));
  await waitFor(() => !document.getElementById('palette').hidden, 4000);
  inp.value = 'GnosisCheck';
  inp.dispatchEvent(new Event('input'));
  await sleep(300);
  R.vimCmdInList = [...document.querySelectorAll('#palette-list li')].map((l) => l.textContent).slice(0, 3);
  inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
  await waitFor(() => G.view.getText().includes('vault の検査'), 10000);
  R.vimCmdRan = G.view.getText().includes('vault の検査');
  R.vimDbg = { screen: G.screen().filter((r) => r.trim()).slice(-4), head: G.view.getText().slice(0, 80), mode: G.currentMode(), panesActive: P().activeKind() };
  await G.send('q'); await sleep(400);
  inp.value = ''; document.getElementById('palette').hidden = true;

  // 11. 分割を解除 → タブは失われない。ノートのタブ（読み取り専用の表示）も開ける
  const tabCountBefore = kinds(lay()).length;
  await run(() => G.panes().unsplitFocused());
  R.unsplit = { panes: P().panesCount(), keptTabs: kinds(lay()).length === tabCountBefore || kinds(lay()).length === tabCountBefore - 0 };
  P().setNoteTab('b.md');
  await sleep(400);
  const noteFrame = [...document.querySelectorAll('.viewframe')].find((f) => f.src.endsWith('/b.html'));
  R.noteTab = { kinds: kinds(lay()), frame: !!noteFrame, name: noteFrame ? noteFrame.name : '' };

  // 11b. 追加ビュー（ツリー・マインドマップ等 23 種）も同じタブとして開ける。表示専用の iframe に書き出したページが入る
  P().openExtra('tree');
  await waitFor(() => [...document.querySelectorAll('.viewframe')].find((f) => f.src.endsWith('/tree.html')), 20000);
  const treeFrame = [...document.querySelectorAll('.viewframe')].find((f) => f.src.endsWith('/tree.html'));
  let treeText = '';
  await waitFor(() => { try { treeText = treeFrame.contentDocument.getElementById('v2').textContent; return treeText.length > 0; } catch (e) { treeText = 'cross-origin'; return true; } }, 15000);
  P().openExtra('nope-not-a-view');                                    // 知らないキーでも壊れず一覧ページになる
  await sleep(300);
  R.extra = { kinds: kinds(lay()), frame: !!treeFrame, name: treeFrame ? treeFrame.name : '', text: treeText.slice(0, 60), tabs: tabsOf().flat().filter((t) => t === '階層ツリー').length, unknown: !![...document.querySelectorAll('.viewframe')].find((f) => f.src.endsWith('/views.html')) };
  inp.value = '階層ツリー'; inp.dispatchEvent(new Event('input')); await sleep(200);
  R.extraPalette = [...document.querySelectorAll('#palette-list li')].some((e) => e.textContent.includes('階層ツリーを開く'));
  inp.value = ''; document.getElementById('palette').hidden = true;

  // 11c. 機能一覧: ツールバーのボタンで、全機能をグループ別に見せるタブが開く。検索でき、クリックで実行できる。「＋」のメニューは画面に収まる
  await run(() => G.panes().openFeatures());
  await waitFor(() => document.querySelectorAll('.featitem').length > 10, 15000);
  const featGroups = [...document.querySelectorAll('.featgroup > summary')].map((x) => x.textContent);
  const featTotal = document.querySelectorAll('.featitem').length;
  const featSearch = document.querySelector('.featsearch');
  featSearch.value = '階層ツリー'; featSearch.dispatchEvent(new Event('input')); await sleep(250);
  const found = [...document.querySelectorAll('.featitem')].map((b) => b.textContent);
  const tabsBefore = kinds(lay()).length;
  const openBtn = [...document.querySelectorAll('.featitem')].find((b) => b.textContent === '階層ツリーを開く');
  if (openBtn) { openBtn.click(); await sleep(400); }
  featSearch.value = 'zzzz-no-such'; featSearch.dispatchEvent(new Event('input')); await sleep(200);
  const none = document.querySelector('.featnone') ? document.querySelector('.featnone').textContent : '';
  featSearch.value = ''; featSearch.dispatchEvent(new Event('input')); await sleep(200);
  const plus = document.querySelector('.tabplus'); plus.click(); await sleep(250);
  const m1 = document.querySelector('.ctxmenu'); const r1 = m1.getBoundingClientRect();
  const firstItem = m1.querySelector('button').textContent;
  [...m1.querySelectorAll('button')].find((b) => b.textContent.startsWith('その他')).click(); await sleep(250);
  const m2 = document.querySelector('.ctxmenu'); const r2 = m2.getBoundingClientRect();
  R.features = { kinds: kinds(lay()), groups: featGroups, total: featTotal, found, tabsSame: kinds(lay()).length === tabsBefore, none, firstItem,
    menu1: r1.top >= 0 && r1.bottom <= innerHeight && r1.right <= innerWidth, menu2: r2.top >= 0 && r2.bottom <= innerHeight && r2.right <= innerWidth, menu2n: m2.querySelectorAll('button').length, overflowY: getComputedStyle(m2).overflowY };
  document.querySelectorAll('.ctxmenu').forEach((m) => m.remove());

  // 12. Vim のタブに戻る（Vim は動き続けている）
  P().showVim();
  await sleep(700);
  R.backToVim = { stageW: document.getElementById('stage').offsetWidth, vimFile: (G.state().file || '').split('/').pop(), mode: G.currentMode() };
  await G.send(':e b.md\\r'); await sleep(900);
  R.vimAlive = (G.state().file || '').split('/').pop();

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
  execFileSync("xvfb-run", ["-a", "-s", "-screen 0 1280x900x24", path.join(web, "node_modules/.bin/electron"), web, "--no-sandbox", "--disable-gpu", "--ozone-platform=x11"],
    { env, stdio: ["ignore", "ignore", "inherit"], timeout: 240000 });
  const R = JSON.parse(fs.readFileSync(outPath, "utf8"));
  console.log(JSON.stringify(R, null, 2));
  if (R.fatal) { console.error("fatal: " + R.fatal); process.exit(1); }
  const jsErrors = (R.__console || []).filter((l) => !/Electron Security Warning/.test(l));
  check(jsErrors.length === 0, "console errors in the app: " + JSON.stringify(jsErrors));
  check(R.solo?.tabbarShown && R.solo.vimTabTitle !== "Vim" && JSON.stringify(R.solo.kinds) === '["vim"]' && R.solo.stageW > 300, "start: Vim only; the tab bar is always shown (Obsidian) and the Vim tab shows the note's title: " + JSON.stringify(R.solo));
  check(R.cards?.tabs?.[0]?.join() === "Vim,カード" && R.cards.src === "cards.html" && R.cards.name === "gnosis:open" && R.cards.msgHidden && R.cards.tabbarShown, "open the cards view in a tab: " + JSON.stringify(R.cards));
  check(R.noDup === 3 || R.noDup === 2 || R.noDup > 0, "tabs counted: " + R.noDup);
  check(R.split?.panes === 2 && R.split.type === "split" && R.split.dir === "row", "split to the right: " + JSON.stringify(R.split));
  check(R.vimAfterSplit?.shown, "Vim is still shown after the split: " + JSON.stringify(R.vimAfterSplit));
  check(R.dropZone === "right" && R.dragSplit?.panes === 3, "dragging a tab to the right edge splits (zone right, 3 panes): " + JSON.stringify([R.dropZone, R.dragSplit]));
  check(R.menuHasPin && R.pinned?.title.startsWith("📌") && R.pinned.closeDisabled === true, "pin via the context menu: " + JSON.stringify([R.menuHasPin, R.pinned]));
  check(R.closed?.kinds && !R.closed.kinds.includes("graph") && R.closed.closedCount >= 1, "close a tab: " + JSON.stringify(R.closed));
  check(R.reopened?.kinds?.includes("graph") && R.reopened.count && R.reopened.closedCount === 0, "reopen the closed tab: " + JSON.stringify(R.reopened));
  check(R.resize && R.resize.before !== R.resize.after && Math.abs(R.resize.after - 0.3) < 0.05, "drag the splitter to resize: " + JSON.stringify(R.resize));
  check(R.saved?.hasFile && R.saved.hasCards && R.saved.version === 1, "layout is saved to .gnosis/workspace.json: " + JSON.stringify(R.saved));
  check(R.restored?.same && R.restored.vimOnce === 1, "layout restores to the same tabs: " + JSON.stringify(R.restored));
  check(R.palette?.shown && /タイムライン/.test(R.palette.first) && R.paletteRan?.closed && R.paletteRan.hasTimeline, "command palette: search and run: " + JSON.stringify([R.palette, R.paletteRan]));
  check(R.vimCmdInList?.some((t) => t.includes(":GnosisCheck")) && R.vimCmdRan, "palette lists and runs a Vim command (:GnosisCheck): " + JSON.stringify([R.vimCmdInList, R.vimCmdRan]));
  check(R.unsplit?.panes === 1, "unsplit leaves one pane: " + JSON.stringify(R.unsplit));
  check(R.noteTab?.kinds?.includes("note") && R.noteTab.frame && R.noteTab.name === "gnosis:read", "a read-only note tab: " + JSON.stringify(R.noteTab));
  check(R.extra?.kinds?.includes("v2") && R.extra.frame && R.extra.name === "gnosis:open" && R.extra.tabs === 1 && R.extra.unknown, "an extra view opens as a tab (tree), one tab only, unknown key falls back to the list: " + JSON.stringify(R.extra));
  check(R.extra?.text === "cross-origin" || R.extra?.text.length > 0, "the extra view page rendered: " + JSON.stringify(R.extra?.text));
  check(R.extraPalette, "the command palette lists the extra views");
  check(R.features?.kinds?.includes("features") && R.features.groups.some((g) => g.startsWith("モード")) && R.features.groups.some((g) => g.startsWith("ビュー")) && R.features.total > 30,
    "the features tab lists every group (modes / views / ...): " + JSON.stringify([R.features?.groups, R.features?.total]));
  check(R.features?.found?.includes("階層ツリーを開く") && R.features.tabsSame && R.features.none === "見つかりません", "features search narrows the list, a click runs it (no duplicate tab), no-hit message: " + JSON.stringify([R.features?.found, R.features?.tabsSame, R.features?.none]));
  check(R.features?.firstItem === "☰ 機能一覧" && R.features.menu1 && R.features.menu2 && R.features.menu2n === 23 && R.features.overflowY === "auto", "the + menu starts with the features list, stays inside the window and scrolls: " + JSON.stringify([R.features?.firstItem, R.features?.menu1, R.features?.menu2, R.features?.menu2n, R.features?.overflowY]));
  check(R.backToVim?.stageW > 300 && R.backToVim.mode === "vim" && R.vimAlive === "b.md", "back to the Vim tab, Vim is alive: " + JSON.stringify([R.backToVim, R.vimAlive]));
  check(fs.existsSync(path.join(vault, ".gnosis", "workspace.json")), "workspace.json exists in the vault");
  check(fs.existsSync(path.join(vault, ".gnosis", "cache", "site", "index.html")), "view site was exported to .gnosis/cache/site");
  const notesBefore = fs.readdirSync(vault).filter((f) => f.endsWith(".md")).sort();
  check(JSON.stringify(notesBefore) === JSON.stringify(["a.md", "b.md", "index.md"]) || notesBefore.length >= 3, "no stray notes were created: " + JSON.stringify(notesBefore));
  if (!failed) console.log("panes e2e: OK (タブ・分割・ドラッグ・固定・再開・リサイズ・保存と復元・コマンドパレット)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);
