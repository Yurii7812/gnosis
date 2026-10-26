// Real Electron and terminal Vim, isolated home/vault/display.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const web = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repo = path.dirname(web), base = process.env.TMPDIR || path.join(os.homedir(), 'gnosis-work/test');
fs.mkdirSync(base, { recursive: true });
const tmp = fs.mkdtempSync(path.join(base, 'gnosis-handoff-'));
const home = path.join(tmp, 'home'), vault = path.join(tmp, 'vault');
fs.mkdirSync(home); fs.mkdirSync(vault);
for (const [file, title, body] of [['index.md', 'Index', '[Topic](topic.md)'], ['topic.md', 'Topic', '[One](one.md)'], ['one.md', 'One', 'Text']])
 fs.writeFileSync(path.join(vault, file), `---\ntime: 2026-01-01 00:00:00\ntitle: ${title}\nattribute: group\n---\n\n# ${title}\n\n${body}\n`);
const command = path.join(tmp, 'command'), state = path.join(tmp, 'cui.json');
const vs = s => "'" + s.replaceAll("'", "''") + "'";
const vimrc = path.join(tmp, 'vimrc');
fs.writeFileSync(vimrc, `source ${repo}/vimrc_gnosis
let g:gnosis_autosync = 0
let g:gnosis_diary_auto = 0
let g:gnosis_test_review_skip = 1
function! Observe(t) abort
  if !empty($GNOSIS_GUI_PORT) | return | endif
  call writefile([json_encode({'mandala': gnosis#mview#handoff(), 'focus': &filetype, 'pid': getpid()})], ${vs(state)})
  if filereadable(${vs(command)})
    let l:cmd = readfile(${vs(command)})[0]
    call delete(${vs(command)})
    call feedkeys(l:cmd ==# 'gui' ? '\\c' : '\\x', 't')
  endif
endfunction
augroup observe_test
 autocmd!
 autocmd VimEnter * call timer_start(100, function('Observe'), {'repeat': -1})
augroup END
`);
const incoming = path.join(tmp, 'incoming.json');
fs.writeFileSync(incoming, JSON.stringify({root: vault+'/', file: path.join(vault,'one.md'), mandala: {
 open:1, center:'topic.md', size:9, cur:[3,5], page:0, opage:0, nums:0, nv:1, mode:'all', out_on:1, out_dir:'down', tenths:6, stretch:1.15, digit:'cursor', depth:2}}));
const script=path.join(tmp,'scenario.js'), out=path.join(tmp,'out.json');
fs.writeFileSync(script, `(async () => {
 const sleep=ms=>new Promise(r=>setTimeout(r,ms));
 const wait=async(fn,label)=>{for(let i=0;i<600;i++){if(fn())return;await sleep(50);}throw new Error(label + ' | ' + window.__gui.screen().join(' '));};
 await wait(()=>window.__gui?.state()?.mandala?.size===9,'startup handoff');
 const G=window.__gui,R={};
 const press=async k=>{G.send(k);await sleep(500);};
 const trigger=async action=>{await press(":call writefile(['"+action+"'], "+${JSON.stringify(vs(command))}+ ")"+String.fromCharCode(13));};
 R.initial={size:G.state().mandala.size,center:G.state().mandala.center,cur:G.state().mandala.cur,nums:G.state().mandala.nums,focus:G.state().focus,dir:G.state().mandala.flags.outDir,header:document.querySelector('.m-head').textContent};
 await press('D');
 await wait(()=>G.state().mandala.flags.outDir==='all','D returns to normal');
 R.normalHeader=document.querySelector('.m-head').textContent;
 await press('D');
 await wait(()=>G.state().mandala.flags.outDir==='down','D restores descendants');
 R.downHeader=document.querySelector('.m-head').textContent;
 // Put the original selection back after the direction toggle recenters it.
 await press(':call gnosis#mview#gui_click(3,5,0)'+String.fromCharCode(13));
 await press(String.fromCharCode(92)+'C'); await sleep(4000);
 await press('f'); await wait(()=>G.state().mandala.size===3,'GUI changed to 3');
 await trigger('gui'); await wait(()=>G.state().mandala.size===9,'CUI reuses GUI');
 R.reusedGui=G.state().mandala.cur;
 await press('f'); await press(String.fromCharCode(92)+'C'); await sleep(2000);
 await press('f'); await trigger('close');
 await wait(()=>G.state().mandala.size===3,'CUI close returns to GUI');
 R.returned={size:G.state().mandala.size,focus:G.state().focus};R.__closeWindow=true;return R;
})()`);
const env={...process.env,GNOSIS_HOME:home,GNOSIS_ROOT:vault,GNOSIS_VIMRC:vimrc,GNOSIS_HANDOFF:incoming,GNOSIS_TEST_SCRIPT:script,GNOSIS_TEST_OUT:out,GNOSIS_TERMINAL:'xterm',GNOSIS_SCAN_ONLY:'',HOME:tmp};
delete env.WAYLAND_DISPLAY;delete env.DISPLAY;delete env.XDG_SESSION_TYPE;
try {
 execFileSync('xvfb-run',['-a','-s','-screen 0 1100x880x24',path.join(web,'node_modules/.bin/electron'),web,'--no-sandbox','--disable-gpu','--ozone-platform=x11'],{env,timeout:65000,stdio:['ignore','ignore','pipe']});
 const r=JSON.parse(fs.readFileSync(out));assert(!r.fatal,r.fatal);assert.deepEqual((r.__console || []).filter(s => !s.includes('Electron Security Warning')), []);assert.deepEqual(r.__uncaught, []);
 assert.equal(r.initial.size,9);assert.equal(r.initial.center,'topic.md');assert.deepEqual(r.initial.cur,[3,5]);assert.equal(r.initial.nums,0);assert.equal(r.initial.focus,'mandala');assert.equal(r.initial.dir,'down');assert(r.initial.header.includes('配下'));
 assert(!r.normalHeader.includes('配下'));assert(r.downHeader.includes('配下・深さ2'));
 assert.deepEqual(r.reusedGui,[3,5]);assert.equal(r.returned.size,3);assert.equal(r.returned.focus,'mandala');
 const c=JSON.parse(fs.readFileSync(state));assert.equal(c.mandala.size,3);assert.equal(c.focus,'gnosis-mandala');
 assert.equal(fs.readdirSync(path.join(home,'run')).filter(n=>/^cui-.*json$/.test(n)).length,0);
 // Closing the GUI must preserve its latest state in the still-running CUI.
 fs.writeFileSync(script, `(async () => {
   const sleep=ms=>new Promise(r=>setTimeout(r,ms));
   while(!window.__gui?.state()?.mandala) await sleep(50);
   const G=window.__gui;
   await sleep(1000);
   G.send(String.fromCharCode(92)+'C'); await sleep(4000);
   if(G.state().mandala.size!==9) G.send('f');
   await sleep(500);
   G.send(String.fromCharCode(92)+'x');
   await new Promise(()=>{});
 })()`);
 // Keep Xvfb alive until the CUI has received the closing GUI's state.
 const checker=path.join(tmp,'after-close.cjs'), after=path.join(tmp,'after-close.json');
 fs.writeFileSync(checker, `const fs=require('node:fs');
 require('node:child_process').execFileSync(${JSON.stringify(path.join(web,'node_modules/.bin/electron'))},${JSON.stringify([web,'--no-sandbox','--disable-gpu','--ozone-platform=x11'])},{stdio:'ignore',timeout:20000});
 (async()=>{let state;
 for(let i=0;i<40;i++){try{state=JSON.parse(fs.readFileSync(${JSON.stringify(state)}));if(state.mandala.size===9)break;}catch{}await new Promise(r=>setTimeout(r,100));}
 const files=fs.readdirSync(${JSON.stringify(path.join(home,'run'))});
 fs.writeFileSync(${JSON.stringify(after)},JSON.stringify({state,cui:files.filter(n=>n.startsWith('cui-')).length,gui:files.filter(n=>n.startsWith('gui-')).length}));
 if(state)try{process.kill(state.pid,'SIGTERM');}catch{}
 })();`);
 execFileSync('xvfb-run',['-a','-s','-screen 0 1100x880x24',process.execPath,checker],{env:{...env,GNOSIS_HANDOFF:''},timeout:30000,stdio:['ignore','ignore','pipe']});
 const returned=JSON.parse(fs.readFileSync(after));
 assert.equal(returned.state?.mandala.size,9);assert.equal(returned.state?.focus,'gnosis-mandala');
 assert.equal(returned.gui,0);assert.equal(returned.cui,1);
 console.log('handoff e2e: OK (GUI -> new CUI -> existing GUI -> existing CUI -> close and return)');console.log(JSON.stringify(r));
} catch(e){console.error('Artifacts:',tmp);throw e;}
finally {
 const run=path.join(home,'run');
 if(fs.existsSync(run)) for(const file of fs.readdirSync(run)){const m=file.match(/^(cui|gui)-(\d+)\.json$/);if(m)try{process.kill(Number(m[2]),'SIGTERM');}catch{}}
}
