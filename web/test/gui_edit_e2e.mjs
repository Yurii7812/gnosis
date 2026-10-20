// `\A` の GUI 編集モード（Vim を知らなくても書ける）を、実際の Electron + 本物の Vim で確かめる E2E。
//   モード切替（Real Vim ⇄ GUI 編集 ⇄ 閲覧専用）・入力・自動保存（Vim の普通の :write 経由）・書式ボタン・元に戻す・
//   Enter でのリスト継続・競合（外が書き換えた）の解決と退避・リンクを開く・Vim に戻ったとき内容が一致すること。
//   node test/gui_edit_e2e.mjs      （vault・HOME は一時フォルダ。本物には触らない）
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
const tmp = fs.mkdtempSync(path.join(testBase(), "gui-edit-e2e-"));
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
note("a.md", "ノートA", "最初の文。\n\n- 項目\n\n[Bへ](b.md)");
note("b.md", "ノートB", "Bの本文。");
const A = path.join(vault, "a.md");

const scenario = `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let G = window.__gui;
  for (let i = 0; i < 100 && !G; i++) { await sleep(50); G = window.__gui; }
  const waitFor = async (fn, ms = 8000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { try { const v = fn(); if (v) return v; } catch (e) {} await sleep(60); } return null; };
  const press = async (keys, wait = 500) => { G.send(keys); await sleep(wait); };
  const base = (f) => (f || '').split('/').pop();
  const ge = () => G.guiEdit();
  const cm = () => G.view.view;
  const doc = () => G.view.getText();
  const key = (k, extra = {}) => cm().contentDOM.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true, ...extra }));
  const btn = async (cmd) => { document.querySelector('#edit-tools [data-cmd="' + cmd + '"]').click(); await sleep(150); };
  const typeText = async (t) => { cm().focus(); document.execCommand('insertText', false, t); await sleep(200); };   // CodeMirror が入力を拾うのを待つ
  const endOfDoc = () => cm().dispatch({ selection: { anchor: cm().state.doc.length } });
  const R = {};
  await waitFor(() => G.state().file);
  await sleep(800);

  // 1. Vim で a.md を開く → GUI 編集へ（ボタン）
  await press(':e a.md\\r', 1200);
  R.vimFile = base(G.state().file);
  R.modeBefore = G.currentMode();
  document.querySelector('#modes [data-mode="gui"]').click();
  await waitFor(() => G.currentMode() === 'gui', 6000);
  await sleep(400);
  R.enter = { mode: G.currentMode(), editable: cm().contentDOM.getAttribute('contenteditable'), toolsHidden: document.getElementById('edit-tools').hidden,
              termHidden: getComputedStyle(document.getElementById('termwrap')).display, label: document.getElementById('mode').textContent,
              pressed: [...document.querySelectorAll('#modes button')].filter((b) => b.getAttribute('aria-pressed') === 'true').map((b) => b.dataset.mode),
              file: base(ge().state().file), docHasBody: doc().includes('最初の文。') };

  // 2. 入力 → 自動保存（Vim の :write 経由）。ディスクに入り、状態は「保存済み」になる
  endOfDoc();
  await typeText('\\n\\nGUIで書いた行');
  R.afterType = { dirty: ge().state().dirty, status: document.getElementById('save-state').textContent };
  await waitFor(() => !ge().state().dirty && !ge().state().saving, 8000);
  const onDisk = await window.gui.readNote(ge().state().file);
  R.saved = { dirty: ge().state().dirty, status: document.getElementById('save-state').textContent, diskHas: onDisk.text.includes('GUIで書いた行'), hashSame: onDisk.hash === ge().state().hash };

  // 3. 書式ボタン: 選択して太字 → 元に戻す → やり直す
  const at = doc().indexOf('最初の文');
  cm().dispatch({ selection: { anchor: at, head: at + 4 } });
  await btn('bold');
  R.bold = doc().includes('**最初の文**');
  await sleep(900);                       // 履歴の段を分ける（700ms より空ける）
  await btn('h2');
  R.h2 = /^## /m.test(doc().split('\\n').find((l) => l.includes('最初の文')) || '') ;
  await btn('undo');
  R.undoH2 = !(/^## /m.test(doc().split('\\n').find((l) => l.includes('最初の文')) || ''));
  await btn('undo');
  R.undoBold = !doc().includes('**最初の文**');
  await btn('redo');
  R.redoBold = doc().includes('**最初の文**');
  key('z', { ctrlKey: true });            // キー（Ctrl+Z）でも同じ
  R.keyUndo = !doc().includes('**最初の文**');

  // 4. Enter でリストを続ける・空の項目で抜ける
  const li = doc().indexOf('- 項目') + '- 項目'.length;
  cm().dispatch({ selection: { anchor: li } });
  key('Enter');
  R.listContinue = doc().includes('- 項目\\n- ');
  await typeText('二つ目');
  key('Enter');
  key('Enter');                           // 空の項目で Enter → 項目をやめる
  R.listExit = !/\\n- \\n/.test(doc()) && doc().includes('- 二つ目');
  await waitFor(() => !ge().state().dirty && !ge().state().saving, 8000);

  // 5. 競合: 外（Vim の :call writefile）がファイルを書き換えたあとに編集 → 上書きせず確認が出る
  const file = ge().state().file;
  await sleep(300);
  endOfDoc();
  await typeText('\\n私の追記');                                              // 先に編集（まだ保存されない）
  await press(':call writefile(["---", "title: 外", "---", "", "# 外の版", "外が書いた"], ' + JSON.stringify(file) + ')\\r', 100);   // 保存の前に外が書き換える
  await waitFor(() => !document.getElementById('conflict').hidden, 8000);
  R.conflict = { shown: !document.getElementById('conflict').hidden, paused: ge().state().paused, status: document.getElementById('save-state').textContent,
                 diskStillExternal: (await window.gui.readNote(file)).text.includes('外が書いた') };
  document.querySelector('#conflict [data-act="mine"]').click();                // 自分の版を残す（ディスクの版は退避）
  await waitFor(() => document.getElementById('conflict').hidden && !ge().state().dirty && !ge().state().saving, 8000);
  const after = await window.gui.readNote(file);
  R.mine = { hidden: document.getElementById('conflict').hidden, diskHasMine: after.text.includes('私の追記'), diskNoExternal: !after.text.includes('外が書いた') };

  // 6. 競合 → ディスクの版を読み込む（自分の版は退避）
  await sleep(300);
  endOfDoc();
  await typeText('\\n捨てる私の文');
  await press(':call writefile(["---", "title: また外", "---", "", "# また外", "二度目の外"], ' + JSON.stringify(file) + ')\\r', 100);
  await waitFor(() => !document.getElementById('conflict').hidden, 8000);
  R.step6Shown = !document.getElementById('conflict').hidden;
  document.querySelector('#conflict [data-act="theirs"]').click();
  await waitFor(() => document.getElementById('conflict').hidden, 4000);
  await sleep(300);
  R.theirs = { docHasExternal: doc().includes('二度目の外'), docNoMine: !doc().includes('捨てる私の文'), dirty: ge().state().dirty };

  // 6b. 編集していないときに外が書き換えたら、そのまま取り込む（競合にしない）
  await press(':call writefile(["---", "title: 三度目", "---", "", "# 三度目", "編集していない間の外の変更"], ' + JSON.stringify(file) + ')\\r', 300);
  await press(':checktime\\r', 300);
  await waitFor(() => doc().includes('編集していない間の外の変更'), 8000);
  R.pickup = { docHasExternal: doc().includes('編集していない間の外の変更'), conflictHidden: document.getElementById('conflict').hidden, dirty: ge().state().dirty };

  // 7. リンク: 描かれたリンクをクリックすると、そのノートが開く（GUI 編集のまま）
  const fileA = file;
  await press(':call writefile(["---", "title: ノートA", "---", "", "# ノートA", "", "[Bへ](b.md)"], ' + JSON.stringify(fileA) + ')\\r', 300);
  await press(':checktime\\r', 300);
  await waitFor(() => document.querySelector('[data-md-href="b.md"]'), 8000);
  cm().dispatch({ selection: { anchor: 0 } });
  await sleep(300);
  const link = document.querySelector('[data-md-href="b.md"]');
  R.linkFound = !!link;
  window.__md = 0; cm().contentDOM.addEventListener('mousedown', () => window.__md++);
  R.linkDbg = { connected: link && link.isConnected, inContent: link && cm().contentDOM.contains(link), tag: link && link.tagName };
  if (link) {
    const r = link.getBoundingClientRect();
    link.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, button: 0 }));
    await waitFor(() => base(ge().state().file) === 'b.md', 8000);
  }
  R.md = window.__md;
  R.afterLink = { file: base(ge().state().file), mode: G.currentMode(), docHasB: doc().includes('Bの本文'), err: document.getElementById('err').textContent, vimFile: base(G.state().file), st: ge().state().dirty + '/' + ge().state().paused, resolve: JSON.stringify(await window.gui.resolveLink(ge().state().file, 'b.md')) };

  // 8. Vim に戻る: Vim のバッファが今の内容と一致し、未保存の変更は無い
  document.querySelector('#modes [data-mode="vim"]').click();
  await waitFor(() => G.currentMode() === 'vim', 6000);
  await sleep(1200);
  R.back = { mode: G.currentMode(), vimFile: base(G.state().file), mod: G.state().mod, toolsHidden: document.getElementById('edit-tools').hidden,
             editable: cm().contentDOM.getAttribute('contenteditable'), termShown: getComputedStyle(document.getElementById('termwrap')).display !== 'none' };

  // 9. 閲覧専用 → GUI 編集 → 閲覧専用（キー Alt+E / Alt+V）: 閲覧では何も変わらない
  document.querySelector('#modes [data-mode="view"]').click();
  await sleep(400);
  R.view = { mode: G.currentMode(), pressed: [...document.querySelectorAll('#modes button')].filter((b) => b.getAttribute('aria-pressed') === 'true').map((b) => b.dataset.mode) };
  const t0 = doc();
  const ta = document.querySelector('.xterm-helper-textarea');
  for (const k of ['i', 'h', 'e', 'l', 'l', 'o', 'd', 'd']) ta.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));   // 本物のキー入力（閲覧専用では Vim に届かない）
  await sleep(700);
  R.viewNoChange = doc() === t0 && G.state().mod === 0;
  document.querySelector('#modes [data-mode="vim"]').click();
  await sleep(500);

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
  execFileSync("xvfb-run", ["-a", "-s", "-screen 0 1100x880x24", path.join(web, "node_modules/.bin/electron"), web, "--no-sandbox", "--disable-gpu", "--ozone-platform=x11"],
    { env, stdio: ["ignore", "ignore", "inherit"], timeout: 180000 });
  const R = JSON.parse(fs.readFileSync(outPath, "utf8"));
  console.log(JSON.stringify(R, null, 2));
  if (R.fatal) { console.error("fatal: " + R.fatal); process.exit(1); }
  const jsErrors = (R.__console || []).filter((l) => !/Electron Security Warning/.test(l));
  check(jsErrors.length === 0, "console errors in the app: " + JSON.stringify(jsErrors));
  check(R.vimFile === "a.md" && R.modeBefore === "vim", "start in Real Vim on a.md: " + JSON.stringify([R.vimFile, R.modeBefore]));
  const e = R.enter || {};
  check(e.mode === "gui" && e.editable === "true" && e.toolsHidden === false && e.termHidden === "none" && e.label === "EDIT" && e.docHasBody && e.file === "a.md" && JSON.stringify(e.pressed) === '["gui"]', "enter GUI edit: " + JSON.stringify(e));
  check(R.afterType?.dirty === true && R.afterType.status === "未保存", "typing makes it dirty: " + JSON.stringify(R.afterType));
  check(R.saved?.dirty === false && R.saved.status === "保存済み" && R.saved.diskHas && R.saved.hashSame, "autosave writes the note (via Vim :write): " + JSON.stringify(R.saved));
  check(R.bold && R.h2 && R.undoH2 && R.undoBold && R.redoBold && R.keyUndo, "format buttons, undo/redo and Ctrl+Z: " + JSON.stringify([R.bold, R.h2, R.undoH2, R.undoBold, R.redoBold, R.keyUndo]));
  check(R.listContinue && R.listExit, "Enter continues a list and an empty item leaves it: " + JSON.stringify([R.listContinue, R.listExit]));
  check(R.conflict?.shown && R.conflict.paused && R.conflict.diskStillExternal, "external change → conflict is shown, disk untouched: " + JSON.stringify(R.conflict));
  check(R.mine?.hidden && R.mine.diskHasMine && R.mine.diskNoExternal, "keep mine: " + JSON.stringify(R.mine));
  check(R.step6Shown && R.theirs?.docHasExternal && R.theirs.docNoMine && R.theirs.dirty === false, "take disk: " + JSON.stringify([R.step6Shown, R.theirs]));
  check(R.pickup?.docHasExternal && R.pickup.conflictHidden && R.pickup.dirty === false, "an external change while not editing is picked up without a conflict: " + JSON.stringify(R.pickup));
  const conflicts = path.join(vault, ".state", "conflicts");
  const saved = fs.existsSync(conflicts) ? fs.readdirSync(conflicts) : [];
  check(saved.some((f) => /-disk-/.test(f)) && saved.some((f) => /-mine-/.test(f)), "both losing sides were saved aside in .state/conflicts: " + JSON.stringify(saved));
  check(saved.some((f) => /-disk-/.test(f) && fs.readFileSync(path.join(conflicts, f), "utf8").includes("外が書いた")), "the overwritten disk version is recoverable");
  check(saved.some((f) => /-mine-/.test(f) && fs.readFileSync(path.join(conflicts, f), "utf8").includes("捨てる私の文")), "the discarded own version is recoverable");
  check(R.linkFound && R.afterLink?.file === "b.md" && R.afterLink.mode === "gui" && R.afterLink.docHasB, "clicking a link opens the note and stays in GUI edit: " + JSON.stringify(R.afterLink));
  check(R.back?.mode === "vim" && R.back.vimFile === "b.md" && R.back.mod === 0 && R.back.toolsHidden === true && R.back.editable === "false" && R.back.termShown, "back to Real Vim: " + JSON.stringify(R.back));
  check(R.view?.mode === "view" && JSON.stringify(R.view.pressed) === '["view"]' && R.viewNoChange, "view-only does not change the note: " + JSON.stringify([R.view, R.viewNoChange]));
  if (!failed) console.log("gui edit e2e: OK (Real Vim ⇄ GUI 編集 ⇄ 閲覧専用・自動保存・書式ボタン・元に戻す・リスト・競合・リンク)");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);
