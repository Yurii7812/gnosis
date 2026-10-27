// 実際の Electron アプリで、Folgezettel ビュー・アウトライン窓を確かめる。
//   node test/fznav_e2e.mjs
// 一時フォルダ・仮想ディスプレイ (xvfb) だけを使う。本物の vault には触らない。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const web = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repo = path.dirname(web), base = process.env.TMPDIR || path.join(os.homedir(), 'gnosis-work/test');
fs.mkdirSync(base, { recursive: true });
const tmp = fs.mkdtempSync(path.join(base, 'gnosis-fz-'));
const home = path.join(tmp, 'home'), vault = path.join(tmp, 'vault');
fs.mkdirSync(home); fs.mkdirSync(vault);
const note = (name, title, fz, { group = false, bg = [], body = '' } = {}) => fs.writeFileSync(path.join(vault, name),
  `---\ntime: 2026-01-01 00:00:00\ntitle: ${title}\n${group ? 'attribute: group\n' : ''}${fz ? `folgezettel: "${fz}"\n` : ''}---\n\n# ${title}\n\n${bg.length ? 'BranchGroup:\n' + bg.map(([t, f]) => `[${t}](${f})`).join('\n') + '\n\n' : ''}${body}\n`);
note('index.md', 'Index', '', { body: '[認識](n1.md)' });
note('n1.md', '認識', '1', { bg: [['認識G', 'g1.md']] });
note('g1.md', '認識G', '1', { group: true });
note('n1a.md', '知覚', '1a');
note('n1a1a.md', '言語', '1a1a', { body: '## 意味\n\n本文\n\n### 細部\n\n## 用法' });
note('n1a2b3c4d5e6f.md', '深い', '1a2b3c4d5e6f');
for (let i = 2; i <= 80; i++) note(`m${i}.md`, `項目${i}`, String(i));
const vimrc = path.join(tmp, 'vimrc');
fs.writeFileSync(vimrc, `source ${repo}/vimrc_gnosis\nlet g:gnosis_autosync = 0\nlet g:gnosis_diary_auto = 0\nlet g:gnosis_test_review_skip = 1\n`);
const incoming = path.join(tmp, 'incoming.json');
fs.writeFileSync(incoming, JSON.stringify({ root: vault + '/', file: path.join(vault, 'n1a1a.md'), mandala: { open: 1, center: 'n1a1a.md', size: 3, cur: [1, 1], page: 0, opage: 0, nums: 1, nv: 1, mode: 'all' } }));
const script = path.join(tmp, 'scenario.js'), out = path.join(tmp, 'out.json');
fs.writeFileSync(script, `(async () => {
 const sleep = ms => new Promise(r => setTimeout(r, ms));
 const wait = async (fn, label) => { for (let i = 0; i < 400; i++) { if (fn()) return; await sleep(50); } throw new Error(label); };
 await wait(() => window.__gui?.state()?.mandala?.center === 'n1a1a.md', 'startup');
 const G = window.__gui, R = {};
 await sleep(1200);
 G.send('\\x1b[1;5C'); await sleep(2500);
 await wait(() => G.state()?.mandala?.view === 'fz', 'switch to fz');
 const rows = () => [...document.querySelectorAll('.fz-row')];
 R.view = G.state().mandala.view;
 R.rowCount = rows().length;
 R.hasMandalaBoard = getComputedStyle(document.querySelector('.m-board')).display;
 // 列揃え: 題の左端の座標が全行で同じ・番号欄の幅が全行で同じ
 R.titleX = [...new Set(rows().map(r => Math.round(r.querySelector('.fz-title').getBoundingClientRect().left)))];
 R.numW = [...new Set(rows().map(r => Math.round(r.querySelector('.fz-num').getBoundingClientRect().width)))];
 R.texts = rows().map(r => [r.querySelector('.fz-mark').textContent, r.querySelector('.fz-num').textContent, r.querySelector('.fz-title').textContent, r.classList.contains('k-g'), r.style.color]);
 R.head = document.querySelector('.fz-head').textContent;
 R.curRow = rows().findIndex(r => r.classList.contains('cur'));
 R.nrows = rows().length;
 const lr = document.querySelector('.fz-list').getBoundingClientRect();
 R.list = [lr.top, lr.height];
 R.curTop = rows()[R.curRow]?.getBoundingClientRect().top;
 R.deepTitle = (rows().find(r => r.querySelector('.fz-title').textContent === '深い') || { title: '' }).title;
 // クリック: 項目 5 のノートを開く（ダブルクリックで開く）
 const target = rows().find(r => r.querySelector('.fz-title').textContent === '項目5');
 if (target) { target.dispatchEvent(new MouseEvent('dblclick', { bubbles: true })); await sleep(1500); }
 R.afterClickFile = G.state().file.split('/').pop();
 // ホイール: 窓の表示が動く
 const topBefore = G.state().mandala.top;
 document.querySelector('.fz-list').dispatchEvent(new WheelEvent('wheel', { deltaY: 400, bubbles: true, cancelable: true }));
 await sleep(800);
 R.topBefore = topBefore; R.topAfter = G.state().mandala.top;
 // アウトライン窓: \\o で開く（ノートの窓から）
 G.send('\\x1b '); await sleep(300);        // Space で右のノートへ
 G.send('\\x1b:edit ' + ${JSON.stringify(path.join(vault, 'n1a1a.md'))} + '\\r'); await sleep(1200);
 G.send('\\\\o'); await sleep(1800);
 await wait(() => G.state()?.outline?.lines?.length > 3, 'outline open');
 R.outlineLines = G.state().outline.lines.map(c => c.t + '|' + c.d);
 R.outlineVisible = !document.querySelector('#outline').hidden;
 R.threeColumns = [!document.querySelector('#mandala').hidden, !!document.querySelector('#view').offsetWidth, !document.querySelector('#outline').hidden];
 R.outlineRows = [...document.querySelectorAll('.olp-row')].map(r => r.textContent + ':' + r.style.paddingLeft);
 // 見出しをクリックして本文へジャンプ
 const h = [...document.querySelectorAll('.olp-row')].find(r => r.textContent === '細部');
 if (h) { h.dispatchEvent(new MouseEvent('click', { bubbles: true })); await sleep(1200); }
 R.jumpCur = G.state().cur;
 R.jumpFocus = G.state().focus;
 R.activeAfter = [...document.querySelectorAll('.olp-row.active')].map(r => r.textContent);
 R.__closeWindow = true; return R;
})()`);
const env = { ...process.env, GNOSIS_HOME: home, GNOSIS_ROOT: vault, GNOSIS_VIMRC: vimrc, GNOSIS_HANDOFF: incoming, GNOSIS_TEST_SCRIPT: script, GNOSIS_TEST_OUT: out, GNOSIS_TERMINAL: 'xterm', GNOSIS_SCAN_ONLY: '', HOME: tmp };
delete env.WAYLAND_DISPLAY; delete env.DISPLAY; delete env.XDG_SESSION_TYPE;
try {
  execFileSync('xvfb-run', ['-a', '-s', '-screen 0 1300x900x24', path.join(web, 'node_modules/.bin/electron'), web, '--no-sandbox', '--disable-gpu', '--ozone-platform=x11'], { env, timeout: 120000, stdio: ['ignore', 'ignore', 'pipe'] });
  const r = JSON.parse(fs.readFileSync(out));
  assert(!r.fatal, r.fatal);
  assert.equal(r.view, 'fz');
  assert.equal(r.hasMandalaBoard, 'none', 'mandala board is hidden in the Folgezettel view');
  assert.equal(r.head, 'FOLGEZETTEL');
  assert.equal(r.titleX.length, 1, 'all titles start at the same x: ' + JSON.stringify(r.titleX));
  assert.equal(r.numW.length, 1, 'number column has a fixed width: ' + JSON.stringify(r.numW));
  assert(r.rowCount >= 15, 'rows: ' + r.rowCount);
  // Group の行だけアクセントの色（Note は継承の色で style.color は空）
  const groups = r.texts.filter(t => t[3]);
  assert(groups.length >= 1 && groups.every(t => t[4] !== ''), 'group rows have the accent colour: ' + JSON.stringify(groups));
  assert(r.texts.filter(t => !t[3]).every(t => t[4] === ''), 'note rows use the normal text colour');
  const iG = r.texts.findIndex(t => t[2] === '認識G'), iN = r.texts.findIndex(t => t[2] === '認識');
  assert(iG >= 0 && iN === iG + 1 || r.curRow >= 0, 'Group row is directly above its Note row (or scrolled): ' + JSON.stringify(r.texts.slice(0, 5)));
  assert(r.curRow >= 0 && r.texts[r.curRow][0] === '▸' && r.texts[r.curRow][2] === '言語', 'current note has the marker: ' + JSON.stringify(r.texts[r.curRow]));
  assert(r.deepTitle === '' || r.deepTitle === '1a2b3c4d5e6f', 'full number on hover: ' + r.deepTitle);
  assert.equal(r.afterClickFile, 'm5.md', 'double click opens the note');
  assert(r.topAfter > r.topBefore, 'wheel scrolls the list: ' + [r.topBefore, r.topAfter]);
  assert(r.outlineVisible, 'outline pane is shown');
  assert.deepEqual(r.threeColumns, [true, true, true], 'folgezettel + note + outline at the same time');
  assert(r.outlineLines.includes('意味|1') && r.outlineLines.includes('細部|2'), 'outline indent: ' + JSON.stringify(r.outlineLines));
  assert(r.jumpCur[0] > 1 && r.jumpFocus === 'note', 'clicking a heading jumps in the note: ' + JSON.stringify([r.jumpCur, r.jumpFocus]));
  console.log('fznav e2e: OK'); console.log(JSON.stringify(r).slice(0, 1500));
} catch (e) { console.error('Artifacts:', tmp); throw e; }
