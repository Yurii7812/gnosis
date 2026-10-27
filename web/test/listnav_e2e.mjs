// リストビューを実Electronで操作する。ノート・HOME・表示はすべて試験用。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const web = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'), repo = path.dirname(web);
const base = process.env.TMPDIR || path.join(os.homedir(), 'gnosis-work/test');
fs.mkdirSync(base, { recursive: true });
const tmp = fs.mkdtempSync(path.join(base, 'gnosis-list-gui-'));
const home = path.join(tmp, 'home'), vault = path.join(tmp, 'vault');
fs.mkdirSync(home); fs.mkdirSync(vault);
function note(name, title, fz, body, group = false) {
  fs.writeFileSync(path.join(vault, name + '.md'), `---\ntime: 2026-01-01 00:00:00\nfolgezettel: "${fz}"\n${group ? 'attribute: group\n' : ''}---\n\n# ${title}\n\n${body}\n`);
}
note('index', 'Index', '', '[Alpha](a.md)', true);
note('a', 'Alpha', '1', 'Group:\n[Group](g.md)\n\nChildBranch:\n[Beta](b.md)\n\nOrigin body');
note('b', 'Beta', '1a', 'ParentBranch:\n[Alpha](a.md)\n\nNeedle body');
note('g', 'Group', '2', '[Unique alias](a.md)', true);
const vimrc = path.join(tmp, 'vimrc');
fs.writeFileSync(vimrc, `source ${repo}/vimrc_gnosis\nlet g:gnosis_autosync=0\nlet g:gnosis_diary_auto=0\nlet g:gnosis_test_review_skip=1\n`);
const incoming = path.join(tmp, 'incoming.json'), script = path.join(tmp, 'scenario.js'), out = path.join(tmp, 'out.json');
fs.writeFileSync(incoming, JSON.stringify({ root: vault + '/', file: path.join(vault, 'a.md'), mandala: { open: 1, center: 'a.md', size: 3, cur: [1, 1], page: 0, opage: 0, nums: 1, nv: 1, mode: 'all' } }));
fs.writeFileSync(script, `(async () => {
 const sleep = ms => new Promise(r => setTimeout(r, ms));
 const wait = async (fn, label) => { for(let n=0;n<200;n++){if(fn())return;await sleep(50);}throw new Error(label + JSON.stringify({view:window.__gui?.state()?.mandala?.view,focus:window.__gui?.state()?.focus,mode:window.__gui?.state()?.mode,why:window.__gui?.state()?.terminalReason,screen:window.__gui?.screen()?.slice(-5)})); };
 await wait(() => window.__gui?.state()?.mandala?.center === 'a.md', 'startup');
 const G=window.__gui, R={};
 await sleep(300);
 G.send('\\x1b[1;5C'); await wait(() => G.state()?.mandala?.view === 'fz', 'Folgezettel');
 await sleep(500); G.send('\\x1b[1;5C'); await wait(() => G.state()?.mandala?.view === 'list', 'List');
 await sleep(400);
 R.head=document.querySelector('.fz-head').textContent;
 R.board=getComputedStyle(document.querySelector('.m-board')).display;
 R.rows=[...document.querySelectorAll('.fz-row')].map(el=>el.textContent);
 const before=G.state().file;
 G.send('b');await sleep(300);R.filterFile=G.state().file;R.before=before;
 G.send('a');G.send('sUnique alias\\r');await sleep(1200);
 R.searchRows=[...document.querySelectorAll('.fz-row')].map(el=>el.textContent);
 const group=[...document.querySelectorAll('.fz-row')].find(el=>el.textContent.includes('Group'));
 if(group)group.dispatchEvent(new MouseEvent('click',{bubbles:true}));
 await sleep(500);R.preview=G.state().file;
 G.send('o');await sleep(300);R.origin=G.state().file;
 G.send('mUnique\\r');await sleep(700);
 R.hits=document.querySelectorAll('.fz-row.nav-hit').length;
 G.send('\\x1b[1;5D');await wait(()=>G.state()?.mandala?.view==='fz','reverse');
 R.reverse=G.state().mandala.view;
 R.__closeWindow=true;return R;
})()`);
const env = { ...process.env, GNOSIS_HOME: home, GNOSIS_ROOT: vault, GNOSIS_VIMRC: vimrc, GNOSIS_HANDOFF: incoming, GNOSIS_TEST_SCRIPT: script, GNOSIS_TEST_OUT: out, GNOSIS_TERMINAL: 'xterm', GNOSIS_SCAN_ONLY: '', HOME: tmp };
delete env.WAYLAND_DISPLAY; delete env.DISPLAY; delete env.XDG_SESSION_TYPE;
try {
  execFileSync('xvfb-run', ['-a', '-s', '-screen 0 1300x900x24', path.join(web,'node_modules/.bin/electron'), web, '--no-sandbox', '--disable-gpu', '--ozone-platform=x11'], {env,timeout:90000,stdio:['ignore','ignore','pipe']});
  const r=JSON.parse(fs.readFileSync(out));assert(!r.fatal,r.fatal);
  assert(r.head.startsWith('LIST'), r.head);assert.equal(r.board,'none');
  assert(r.rows.some(x=>x.includes('Beta')),JSON.stringify(r.rows));
  assert.equal(r.filterFile,r.before,'relationship filter keeps the preview');
  assert(r.searchRows.some(x=>x.includes('Unique alias')),JSON.stringify(r.searchRows));
  assert(r.preview.endsWith('/g.md'),r.preview);assert(r.origin.endsWith('/a.md'),r.origin);
  assert(r.hits>0,'highlight on GUI rows');assert.equal(r.reverse,'fz');
  console.log('listnav Electron: OK');
} catch(e) {console.error('Artifacts:',tmp);throw e;}
