// 実際の Electron アプリで、時系列記録の「日付を指定して作る」（\D）と「上位の設定」（\E）の画面を確かめる。
//   node test/record_e2e.mjs      一時フォルダ・仮想ディスプレイ (xvfb) だけを使う。本物の vault には触らない。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const web = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repo = path.dirname(web), base = process.env.TMPDIR || path.join(os.homedir(), 'gnosis-work/test');
fs.mkdirSync(base, { recursive: true });
const tmp = fs.mkdtempSync(path.join(base, 'gnosis-record-'));
const home = path.join(tmp, 'home'), vault = path.join(tmp, 'vault');
fs.mkdirSync(home); fs.mkdirSync(vault);
fs.writeFileSync(path.join(vault, 'index.md'), '---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n');
const vimrc = path.join(tmp, 'vimrc');
fs.writeFileSync(vimrc, `source ${repo}/vimrc_gnosis\nlet g:gnosis_autosync = 0\nlet g:gnosis_diary_auto = 0\nlet g:gnosis_test_review_skip = 1\n`);
const incoming = path.join(tmp, 'incoming.json');
fs.writeFileSync(incoming, JSON.stringify({ root: vault + '/', file: path.join(vault, 'index.md'), mandala: { open: 0 } }));
const script = path.join(tmp, 'scenario.js'), out = path.join(tmp, 'out.json');
fs.writeFileSync(script, `(async () => {
 const sleep = ms => new Promise(r => setTimeout(r, ms));
 const wait = async (fn, label) => { for (let i = 0; i < 400; i++) { if (fn()) return; await sleep(50); } throw new Error(label + ' | ' + window.__gui.screen().join(' ')); };
 await wait(() => window.__gui?.state()?.file, 'startup');
 const G = window.__gui, R = {};
 const BS = String.fromCharCode(92), ESC = String.fromCharCode(27), CR = String.fromCharCode(13);
 const ex = async c => { G.send(ESC + ':' + c + CR); await sleep(900); };
 await ex('call gnosis#record_new("ビジネス")');
 await ex('call gnosis#record_new("せどり")');
 const panel = () => document.getElementById('recordpick');
 const open = () => panel() && !panel().hidden;
 // \\D: 日付指定の画面が開く。初期値は今日
 G.send(ESC + BS + 'D'); await wait(open, '\\\\D opens the date panel');
 R.dateOpen = open(); R.title = panel().querySelector('.rp-title').textContent;
 R.dateInitial = panel().querySelector('.rp-date').value;
 R.kinds = Array.from(panel().querySelectorAll('.rp-item')).map(e => e.textContent);
 // 検索で絞り込む
 const search = panel().querySelector('.rp-search');
 search.focus(); search.value = 'せど'; search.dispatchEvent(new Event('input'));
 R.filtered = Array.from(panel().querySelectorAll('.rp-item')).map(e => e.textContent);
 // 日付を入れて Enter
 const date = panel().querySelector('.rp-date'); date.value = '2026-10-20';
 search.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
 await wait(() => !open(), 'panel closes after Enter');
 await wait(() => (G.state().file || '').length && /\\.md$/.test(G.state().file) && !G.state().file.endsWith('index.md'), 'the record note opens');
 await sleep(500);
 R.openedFile = G.state().file;
 R.lines = (await window.gui.readFile?.(G.state().file)) || null;
 // 不正な日付は閉じない（エラーを出す）
 G.send(ESC + BS + 'D'); await wait(open, 'reopen');
 panel().querySelector('.rp-date').value = '';
 panel().querySelector('.rp-search').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
 await sleep(300);
 R.badStaysOpen = open(); R.badMsg = panel().querySelector('.rp-msg').textContent;
 panel().querySelector('.rp-search').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
 await sleep(200); R.escCloses = !open();
 // \\E: 上位の画面。ビジネスを選ぶ
 G.send(ESC + BS + 'E'); await wait(open, '\\\\E opens the parent panel');
 R.parentTitle = panel().querySelector('.rp-title').textContent;
 R.parentItems = Array.from(panel().querySelectorAll('.rp-item')).map(e => e.textContent);
 R.parentDateRowHidden = panel().querySelector('.rp-daterow').hidden;
 const s2 = panel().querySelector('.rp-search'); s2.value = 'ビジ'; s2.dispatchEvent(new Event('input'));
 s2.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
 await wait(() => !open(), 'parent panel closes');
 await sleep(1200);
 R.__closeWindow = true; return R;
})()`);
const env = { ...process.env, GNOSIS_HOME: home, GNOSIS_ROOT: vault, GNOSIS_VIMRC: vimrc, GNOSIS_HANDOFF: incoming, GNOSIS_TEST_SCRIPT: script, GNOSIS_TEST_OUT: out, GNOSIS_TERMINAL: 'xterm', GNOSIS_SCAN_ONLY: '', HOME: tmp };
delete env.WAYLAND_DISPLAY; delete env.DISPLAY; delete env.XDG_SESSION_TYPE;
try {
  execFileSync('xvfb-run', ['-a', '-s', '-screen 0 1100x880x24', path.join(web, 'node_modules/.bin/electron'), web, '--no-sandbox', '--disable-gpu', '--ozone-platform=x11'], { env, timeout: 110000, stdio: ['ignore', 'ignore', 'pipe'] });
  const r = JSON.parse(fs.readFileSync(out));
  assert(!r.fatal, r.fatal);
  assert.equal(r.dateOpen, true, '\\D opens the panel');
  assert.match(r.dateInitial, /^\d{4}-\d{2}-\d{2}$/, 'initial date is today');
  assert(r.kinds.includes('ビジネス') && r.kinds.includes('せどり'), 'kinds listed: ' + JSON.stringify(r.kinds));
  assert.deepEqual(r.filtered, ['せどり'], 'search filters the kinds');
  assert(r.openedFile.includes('/vault/') && !r.openedFile.endsWith('index.md'), 'a record note is opened: ' + r.openedFile);
  const files = fs.readdirSync(vault).filter(n => n.endsWith('.md'));
  const texts = files.map(n => fs.readFileSync(path.join(vault, n), 'utf8'));
  assert(texts.some(t => /record: "せどり"/.test(t) && /# 2026-10-20-TU-せどり/.test(t)), 'the せどり note for 2026-10-20 was created');
  assert.equal(r.badStaysOpen, true, 'an invalid date keeps the panel open');
  assert(r.badMsg.length > 0, 'an invalid date shows a message');
  assert.equal(r.escCloses, true, 'Esc closes the panel');
  assert.equal(r.parentDateRowHidden, true, 'the parent panel has no date row');
  assert(r.parentItems[0].length > 0 && r.parentItems.includes('ビジネス') && !r.parentItems.includes('せどり'), 'parent list: none + other kinds: ' + JSON.stringify(r.parentItems));
  assert(texts.some(t => /record: "せどり"/.test(t) && /parent_record: ビジネス/.test(t)), 'parent_record: ビジネス was written');
  console.log('record e2e: OK'); console.log(JSON.stringify(r));
} catch (e) { console.error('Artifacts:', tmp); throw e; }
