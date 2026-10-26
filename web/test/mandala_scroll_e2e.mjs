// 実際の Electron アプリで、曼荼羅を動かしてもノートの画面が動かず、曼荼羅の盤面ががたつかないことを確かめる。
//   node test/mandala_scroll_e2e.mjs
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
const tmp = fs.mkdtempSync(path.join(base, 'gnosis-mscroll-'));
const home = path.join(tmp, 'home'), vault = path.join(tmp, 'vault');
fs.mkdirSync(home); fs.mkdirSync(vault);
const longBody = n => Array.from({ length: 90 }, (_, i) => `${n} の ${i + 1} 行目。ここは長い本文の続きで、画面より長いノートを作るための行です。`).join('\n\n');
const titles = ['短い題', 'とても長い題のノートで、曼荼羅の下の説明の行を何行にも折り返させるための題です。さらに続けて長くします', '三番目', '四番目の少し長めの題です', '五番目', '六番目の題'];
fs.writeFileSync(path.join(vault, 'index.md'), `---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n${titles.map((t, i) => `[${t}](n${i}.md)`).join('\n')}\n`);
titles.forEach((t, i) => fs.writeFileSync(path.join(vault, `n${i}.md`), `---\ntime: 2026-01-01 00:00:00\ntitle: ${t}\n---\n\n# ${t}\n\n${longBody(t.slice(0, 4))}\n`));
const vimrc = path.join(tmp, 'vimrc');
fs.writeFileSync(vimrc, `source ${repo}/vimrc_gnosis\nlet g:gnosis_autosync = 0\nlet g:gnosis_diary_auto = 0\nlet g:gnosis_test_review_skip = 1\n`);
const incoming = path.join(tmp, 'incoming.json');
fs.writeFileSync(incoming, JSON.stringify({ root: vault + '/', file: path.join(vault, 'n0.md'), mandala: { open: 1, center: 'index.md', size: 3, cur: [1, 1], page: 0, opage: 0, nums: 1, nv: 1, mode: 'all' } }));
const script = path.join(tmp, 'scenario.js'), out = path.join(tmp, 'out.json');
fs.writeFileSync(script, `(async () => {
 const sleep = ms => new Promise(r => setTimeout(r, ms));
 const wait = async (fn, label) => { for (let i = 0; i < 400; i++) { if (fn()) return; await sleep(50); } throw new Error(label); };
 await wait(() => window.__gui?.state()?.mandala?.size === 3, 'startup');
 const G = window.__gui, R = { rects: [], tops: [], infos: [] };
 await sleep(1500);
 const board = () => { const r = document.querySelector('.m-board').getBoundingClientRect(); return [r.x, r.y, r.width, r.height].map(Math.round); };
 const top = () => Math.round(document.querySelector('.cm-scroller').scrollTop);
 R.focus = G.state().focus; R.top0 = top(); R.cursor0 = G.state().cur;
 // 曼荼羅にカーソルがあるまま、マスを動かす（右のノートが替わる）
 for (const k of ['\t', '\t', '\t', '\t', '\t', '\t', '\t', '\t']) {
   G.send(k); await sleep(700);
   R.files = (R.files || []).concat(G.state().file.split('/').pop()); R.rects.push(board()); R.tops.push(top()); R.infos.push(document.querySelector('.m-info').getBoundingClientRect().height);
 }
 R.vh = document.querySelector('.cm-scroller').clientHeight; R.lastCur = G.state().cur; R.lastFile = G.state().file;
 R.__closeWindow = true; return R;
})()`);
const env = { ...process.env, GNOSIS_HOME: home, GNOSIS_ROOT: vault, GNOSIS_VIMRC: vimrc, GNOSIS_HANDOFF: incoming, GNOSIS_TEST_SCRIPT: script, GNOSIS_TEST_OUT: out, GNOSIS_TERMINAL: 'xterm', GNOSIS_SCAN_ONLY: '', HOME: tmp };
delete env.WAYLAND_DISPLAY; delete env.DISPLAY; delete env.XDG_SESSION_TYPE;
try {
  execFileSync('xvfb-run', ['-a', '-s', '-screen 0 1100x880x24', path.join(web, 'node_modules/.bin/electron'), web, '--no-sandbox', '--disable-gpu', '--ozone-platform=x11'], { env, timeout: 90000, stdio: ['ignore', 'ignore', 'pipe'] });
  const r = JSON.parse(fs.readFileSync(out));
  assert(!r.fatal, r.fatal);
  assert.equal(r.focus, 'mandala');
  assert(r.vh > 100, 'note view has a height');
  assert.deepEqual(r.tops.filter(t => t !== 0), [], 'note view does not scroll while the cursor is in the mandala: ' + JSON.stringify(r.tops));
  const first = JSON.stringify(r.rects[0]);
  assert(r.rects.every(x => JSON.stringify(x) === first), 'mandala board does not move or resize: ' + JSON.stringify(r.rects));
  assert(new Set(r.infos).size === 1, 'info line keeps its height: ' + JSON.stringify(r.infos));
  console.log('mandala scroll e2e: OK'); console.log(JSON.stringify(r));
} catch (e) { console.error('Artifacts:', tmp); throw e; }
