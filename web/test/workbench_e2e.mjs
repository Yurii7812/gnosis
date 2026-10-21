// `\A` の索引ナビ・索引ブラウザ・カレンダー・曼荼羅・キャンバスを、実際の Electron + 本物の Vim で確かめる E2E。
//   ダブルインデックス（Index → ハーブ → トピック索引 → ローズマリー → トピック索引 → 栽培）の試験用 vault を一時フォルダに作る。
//   画面のボタン・ダイアログを押して、書かれたファイルの中身まで確かめる（書くのは Vim）。
//   node test/workbench_e2e.mjs            （vault・HOME は一時フォルダ。本物には触らない）
//   GNOSIS_E2E_SHOTS=dir node test/workbench_e2e.mjs   … 途中の画面のスクリーンショットを dir に残す（目で確かめる用）
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
const tmp = fs.mkdtempSync(path.join(testBase(), "workbench-e2e-"));
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
const shots = process.env.GNOSIS_E2E_SHOTS || "";
if (shots) fs.mkdirSync(shots, { recursive: true });

const pad = (n) => String(n).padStart(2, "0");
const now = new Date();
const ym = `${now.getFullYear()}-${pad(now.getMonth() + 1)}`;
const dayA = `${ym}-01`;              // 日記のある日（タスクつき）
const dayB = `${ym}-02`;              // 日記の無い過去の日（今日が 1 日・2 日なら別の月の日にする）
const pastB = now.getDate() > 2 ? dayB : `${now.getFullYear() - 1}-01-02`;
const W = (name, text) => fs.writeFileSync(path.join(vault, name), text.replace(/^\n/, ""));
W("index.md", `
---
time: 2026-09-09 10:50:56
title: Index
attribute: group
---

# Index

[ハーブ](h.md)
[薬草](h.md)
[運動](u.md)
`);
W("h.md", `
---
time: 2026-09-12 08:23:55
title: ハーブ
---

# ハーブ

BranchGroup:
[ハーブ](gh.md)

ハーブについて最初に書いたノート。
`);
W("gh.md", `
---
time: 2026-09-20 10:00:00
title: ハーブ
attribute: group
---

# ハーブ

ParentBranch:
[ハーブ](h.md)

[まとめ](hm.md)
[ローズマリー](r.md)
[栽培](hs.md)
`);
W("r.md", `
---
time: 2026-10-01 09:00:00
title: ローズマリーを育ててみた
---

# ローズマリーを育ててみた

BranchGroup:
[ローズマリー](gr.md)

ベランダで育て始めた。
`);
W("gr.md", `
---
time: 2026-10-05 09:00:00
title: ローズマリー
attribute: group
---

# ローズマリー

ParentBranch:
[ローズマリーを育ててみた](r.md)

[栽培](rs.md)
[利用](ru.md)
`);
for (const [n, t] of [["hm.md", "ハーブのまとめ"], ["hs.md", "ハーブの栽培"], ["rs.md", "ローズマリーの栽培"], ["ru.md", "ローズマリーの利用"], ["u.md", "運動"]]) W(n, `---\ntime: 2026-10-10 12:00:00\ntitle: ${t}\n---\n\n# ${t}\n\n${t}の本文。\n`);
W("d1.md", `
---
time: ${dayA} 07:00:00
title: ${dayA}-XX
---

# ${dayA}-XX

07:00 起きた。
- [ ] 水やり 📅 ${dayA} 09:30
`);
// 日記の題の曜日を合わせる（Gnosis の日記の題は YYYY-MM-DD-曜日2文字）
{
  const wd = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][new Date(dayA + "T12:00:00").getDay()];
  const p = path.join(vault, "d1.md");
  fs.writeFileSync(p, fs.readFileSync(p, "utf8").replaceAll(`${dayA}-XX`, `${dayA}-${wd}`));
}

const scenario = `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let G = window.__gui;
  for (let i = 0; i < 100 && !G; i++) { await sleep(50); G = window.__gui; }
  const waitFor = async (fn, ms = 12000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { try { const v = await fn(); if (v) return v; } catch (e) {} await sleep(100); } return null; };
  const read = async (rel) => { const r = await window.gui.readNote(${JSON.stringify(vault)} + '/' + rel); return r.ok ? r.text : ''; };
  const sideText = () => document.getElementById('sidebar').innerText;
  const shot = async (name) => { if (${JSON.stringify(shots)} && window.gui.testShot) { await sleep(400); await window.gui.testShot(name); } };
  const btn = (root, text) => [...(root || document).querySelectorAll('button')].find((b) => b.textContent.trim() === text);
  const dlg = () => document.querySelector('.gdlg');
  const typeIn = (el, v) => { el.value = v; el.dispatchEvent(new Event('input', { bubbles: true })); };
  const pick = async (fieldIdx, query, itemText) => {
    const inp = dlg().querySelectorAll('.gpick input')[fieldIdx];
    typeIn(inp, query);
    const it = await waitFor(() => [...dlg().querySelectorAll('.gpick-item')].find((x) => (typeof itemText === 'function' ? itemText(x) : x.textContent.includes(itemText))), 6000);
    if (!it) return false;
    it.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
    await sleep(100);
    return true;
  };
  const okDlg = async () => { dlg().querySelector('.gdlg-bar .primary').click(); await sleep(200); };
  const vimFile = () => (G.state().file || '').split('/').pop();
  const R = {};
  try {
  await waitFor(() => G.state().file);
  await sleep(1000);

  // 1. サイドバーは Vim の今のノートに付いていく: Index からの道・載っている索引（別名も）・トピック索引の中身
  await G.appCtx.open('h.md');
  await waitFor(() => G.nav().info() && G.nav().info().rel === 'h.md');
  await sleep(300);
  const t1 = sideText();
  R.side = { shown: !document.getElementById('sidebar').hidden, crumbs: [...document.querySelectorAll('#sidebar .nav-crumbs')[0]?.querySelectorAll('.nav-crumb') || []].map((b) => b.textContent),
    indexedHerb: t1.includes('ハーブ') && t1.includes('薬草'), topics: t1.includes('トピック索引（1）'), entries: ['まとめ', 'ローズマリー', '栽培'].every((x) => t1.includes(x)) };
  await shot('1-sidebar-herb');
  // ▸ でトピック索引の項目をその場に開ける（ローズマリーのトピック索引 → 栽培・利用）
  const tw = [...document.querySelectorAll('#sidebar .nav-entry')].find((e) => e.textContent.includes('ローズマリー'))?.querySelector('.nav-twisty');
  tw && tw.click();
  await waitFor(() => document.querySelector('#sidebar .nav-sub') && document.querySelector('#sidebar .nav-sub').textContent.includes('利用'));
  R.twisty = document.querySelector('#sidebar .nav-sub') ? document.querySelector('#sidebar .nav-sub').innerText.replace(/\\s+/g, ' ') : '';

  // 1b. 戻る・進む（ツールバー。Vim の ⌫ と \. と同じ履歴）: h.md → rs.md と開いて、戻ると h.md、進むと rs.md
  await G.appCtx.open('rs.md');
  await waitFor(() => vimFile() === 'rs.md');
  const hb = () => document.querySelector('#history-tools [data-hist="back"]'), hf = () => document.querySelector('#history-tools [data-hist="forward"]');
  await waitFor(() => !hb().disabled);
  R.hist = { backEnabled: !hb().disabled, fwdDisabledAtFirst: hf().disabled };
  hb().click();
  R.hist.afterBack = await waitFor(() => vimFile() === 'h.md' && vimFile(), 5000);
  await waitFor(() => !hf().disabled, 3000);
  R.hist.fwdEnabled = !hf().disabled;
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', code: 'ArrowRight', altKey: true, bubbles: true, cancelable: true }));
  R.hist.afterAltRight = await waitFor(() => vimFile() === 'rs.md' && vimFile(), 5000);
  window.dispatchEvent(new MouseEvent('mouseup', { button: 3, bubbles: true, cancelable: true }));
  R.hist.afterMouseBack = await waitFor(() => vimFile() === 'h.md' && vimFile(), 5000);

  // 1c. 日本語入力（IME）: 変換中の Enter・Esc・矢印は、画面の操作にしない。ひらがなで打ってもカタカナのラベルが見つかる
  const ime = (el, type, key) => el.dispatchEvent(new KeyboardEvent(type, { key, keyCode: 229, isComposing: true, bubbles: true, cancelable: true }));
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'P', code: 'KeyP', ctrlKey: true, shiftKey: true, bubbles: true, cancelable: true }));
  await waitFor(() => !document.getElementById('palette').hidden, 4000);
  const pin = document.getElementById('palette-input');
  pin.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
  typeIn(pin, 'ぐらふ');
  await sleep(250);
  R.ime = { first: document.querySelector('#palette-list li')?.textContent || '' };
  const tabsBefore = G.panes().getLayout() && JSON.stringify(G.panes().getLayout()).length;
  ime(pin, 'keydown', 'Enter'); ime(pin, 'keydown', 'ArrowDown'); ime(pin, 'keydown', 'Escape');
  await sleep(300);
  R.ime.openAfterComposingKeys = !document.getElementById('palette').hidden && JSON.stringify(G.panes().getLayout()).length === tabsBefore;
  pin.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true }));
  pin.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
  await sleep(500);
  R.ime.ranAfterRealEnter = document.getElementById('palette').hidden && JSON.stringify(G.panes().getLayout()).includes('"graph"');
  G.panes().showVim();
  // 入力ダイアログ: 変換中の Enter で決定されない・Esc で閉じない
  const pdlg = G.openMandala('new');
  await waitFor(() => dlg());
  const tin = dlg().querySelector('input[data-key="title"]');
  typeIn(tin, 'りょこう');
  ime(tin, 'keydown', 'Enter'); ime(tin, 'keydown', 'Escape');
  await sleep(300);
  R.ime.dialogKept = !!dlg() && !document.querySelector('.gdlg-err')?.textContent;
  tin.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
  await sleep(300);
  R.ime.dialogClosedByEsc = !dlg();
  await pdlg;
  // サイドバーの検索欄: 変換中の Enter で最初の候補を開かない
  const sin = document.querySelector('#sidebar .nav-search');
  typeIn(sin, '栽培');
  await waitFor(() => document.querySelectorAll('#sidebar .nav-hit').length >= 1);
  const beforeFile = vimFile();
  ime(sin, 'keydown', 'Enter');
  await sleep(500);
  R.ime.navKept = vimFile() === beforeFile;
  typeIn(sin, ''); await sleep(300);

  // 2. 深いノートの道（索引の名前で出る）
  await G.appCtx.open('rs.md');
  await waitFor(() => G.nav().info() && G.nav().info().rel === 'rs.md');
  await sleep(200);
  R.deep = [...document.querySelectorAll('#sidebar .nav-crumbs')[0].querySelectorAll('.nav-crumb')].map((b) => b.textContent);

  // 3. 索引語で探す: 同じ「栽培」が、どの索引の名前かと一緒に出る
  const s = document.querySelector('#sidebar .nav-search');
  typeIn(s, '栽培');
  await waitFor(() => document.querySelectorAll('#sidebar .nav-hit').length >= 2);
  R.search = [...document.querySelectorAll('#sidebar .nav-hit')].map((h) => h.innerText.replace(/\\s+/g, ' ')).slice(0, 4);
  await shot('2-search');
  typeIn(s, ''); await sleep(300);

  // 4. 索引に載せる（\\l の g と同じ）: 運動 → トピック索引「ハーブ」に「ハーブと運動」で
  await G.appCtx.open('u.md');
  await waitFor(() => G.nav().info() && G.nav().info().rel === 'u.md');
  await sleep(200);
  btn(document.getElementById('sidebar'), '＋ 載せる').click();
  await waitFor(() => dlg());
  R.pickedIndex = await pick(0, 'ハーブ', 'Index › ハーブ');
  typeIn(dlg().querySelector('input[data-key="name"]'), 'ハーブと運動');
  await shot('3-add-to-index');
  await okDlg();
  R.added = !!(await waitFor(async () => (await read('gh.md')).includes('[ハーブと運動](u.md)')));
  R.addedBack = await waitFor(() => vimFile() === 'u.md' && vimFile());
  await waitFor(() => G.nav().info() && G.nav().info().indexed.length === 2, 5000);
  R.addedSide = G.nav().info().indexed.map((x) => x.label);

  // 5. トピック索引を作る（zk → n と同じ）: ローズマリーの栽培 から
  await G.appCtx.open('rs.md');
  await waitFor(() => G.nav().info() && G.nav().info().rel === 'rs.md');
  await sleep(200);
  btn(document.getElementById('sidebar'), '＋ 作る').click();
  await waitFor(() => dlg());
  typeIn(dlg().querySelector('input[data-key="title"]'), '栽培の記録');
  await okDlg();
  const topicRel = await waitFor(async () => { const t = await read('rs.md'); const m = /BranchGroup:\\n\\[栽培の記録\\]\\(([^)]+)\\)/.exec(t); return m && m[1]; });
  R.topic = { rel: topicRel, text: topicRel ? await read(topicRel) : '', vim: vimFile() };
  await sleep(500);
  await G.send('\\x1b'); await sleep(300);

  // 6. 今の索引（いま Vim で開いているトピック索引）に新しいノート（zn → Enter と同じ）
  await waitFor(() => G.nav().info() && G.nav().info().rel === topicRel, 8000);
  await sleep(200);
  btn(document.getElementById('sidebar'), '＋ 新しいノート').click();
  await waitFor(() => dlg());
  typeIn(dlg().querySelector('input[data-key="name"]'), '水やり');
  await okDlg();
  const newRel = await waitFor(async () => { const t = await read(topicRel); const m = /\\[水やり\\]\\(([^)]+)\\)/.exec(t); return m && m[1]; });
  R.newInIndex = { rel: newRel, text: newRel ? await waitFor(async () => { const t = await read(newRel); return /ParentBranch:/.test(t) && t; }) : '', vim: vimFile() };
  await sleep(400);
  await G.send('\\x1b'); await sleep(300);
  await G.appCtx.open(newRel);
  await waitFor(() => G.nav().info() && G.nav().info().rel === newRel);
  await sleep(300);
  R.newCrumbs = [...document.querySelectorAll('#sidebar .nav-crumbs')[0]?.querySelectorAll('.nav-crumb') || []].map((b) => b.textContent);
  await shot('4-new-in-index');

  // 7. 索引ブラウザ: Index → ハーブ → ローズマリー → 栽培 を列で辿る
  G.openIndexBrowser();
  await waitFor(() => document.querySelector('.dibox .di-item'));
  const col = (i) => document.querySelectorAll('.dibox .di-col')[i];
  const clickItem = async (i, text) => { const b = await waitFor(() => [...(col(i)?.querySelectorAll('.di-item') || [])].find((x) => x.querySelector('.nav-kw').textContent === text)); if (b) b.click(); await sleep(500); return !!b; };
  R.browser = { c0: [...col(0).querySelectorAll('.di-item .nav-kw')].map((x) => x.textContent) };
  await clickItem(0, 'ハーブ');
  await waitFor(() => col(1) && col(1).querySelectorAll('.di-item').length);
  R.browser.c1 = [...col(1).querySelectorAll('.di-item .nav-kw')].map((x) => x.textContent);
  await clickItem(1, 'ローズマリー');
  await waitFor(() => col(2) && col(2).querySelectorAll('.di-item').length);
  R.browser.c2 = [...col(2).querySelectorAll('.di-item .nav-kw')].map((x) => x.textContent);
  R.browser.crumbs = document.querySelector('.di-crumbs').innerText.replace(/\\s+/g, ' ');
  await shot('5-index-browser');

  // 8. カレンダー: 日記・期限のタスク。チェックで完了（Vim が保存）・タスクの追加（今日の日記）・過去の日の日記を作る
  G.openCalendar();
  await waitFor(() => document.querySelector('.calbox .cal-cell:not(.blank)'));
  await sleep(500);
  const cellOf = (d) => [...document.querySelectorAll('.calbox .cal-cell:not(.blank)')].find((c) => c.querySelector('.cal-day').textContent === String(Number(d.slice(8))));
  const cA = cellOf(${JSON.stringify(dayA)});
  R.cal = { cellA: cA ? cA.innerText.replace(/\\s+/g, ' ') : '', today: !!document.querySelector('.calbox .cal-cell.today') };
  cA.click();
  await waitFor(() => document.querySelector('.cal-side .cal-trow input[type=checkbox]'));
  await shot('6-calendar');
  const cb = document.querySelector('.cal-side .cal-trow input[type=checkbox]');
  cb.checked = true; cb.dispatchEvent(new Event('change'));
  R.cal.completed = !!(await waitFor(async () => /- \\[x\\] 水やり 📅 ${dayA} 09:30 ✅ \\d{4}-\\d\\d-\\d\\d/.test(await read('d1.md'))));
  R.cal.vimAfterComplete = await waitFor(() => vimFile() !== 'd1.md' && vimFile(), 5000) || vimFile();
  btn(document.querySelector('.cal-bar'), '＋ タスク').click();
  await waitFor(() => dlg());
  typeIn(dlg().querySelector('input[data-key="text"]'), '剪定する');
  typeIn(dlg().querySelector('input[data-key="time"]'), '18:00');
  await okDlg();
  R.cal.added = await waitFor(async () => { const all = await window.gui.query('cal.day', { date: ${JSON.stringify(dayA)} }); return all.ok && all.result.due.find((t) => t.text === '剪定する'); });
  // 日記の無い過去の日 → 作って開く
  const r8 = await G.appCtx.op('diary_open', { date: ${JSON.stringify(pastB)} });
  R.cal.pastDiary = { ok: r8.ok, err: r8.error, vim: (G.state().file || '').split('/').pop() };
  R.cal.pastTitle = await waitFor(async () => { const r = await window.gui.query('cal.day', { date: ${JSON.stringify(pastB)} }); return r.ok && r.result.diary && r.result.diary.title; });
  const future = await G.appCtx.op('diary_open', { date: '2999-01-01' });
  R.cal.future = future;
  await G.send('\\x1b'); await sleep(300);

  // 9. 曼荼羅: 新しく作る → 3×3 で副題を打つ（2 か所が同じになる）→ 広げる → マスからノート
  const pm = G.openMandala('new');
  await waitFor(() => dlg());
  typeIn(dlg().querySelector('input[data-key="title"]'), '旅行');
  typeIn(dlg().querySelector('input[data-key="s0"]'), '準備');
  await okDlg();
  await pm;
  await waitFor(() => document.querySelector('.mdbox .md-cell textarea'), 10000);
  await sleep(600);
  const mdRel = G.panes().getLayout && (() => { let r = ''; (function w(x) { if (x.type === 'tabs') x.tabs.forEach((t) => { if (t.kind === 'mandala') r = t.params.rel; }); else { w(x.a); w(x.b); } })(G.panes().getLayout()); return r; })();
  const cell = (r, c) => document.querySelector('.mdbox [data-rc="' + r + ',' + c + '"] textarea');
  R.md = { rel: mdRel, theme: cell(4, 4)?.value, sub0: cell(3, 3)?.value };
  const sub = cell(3, 4);
  sub.focus(); typeIn(sub, '持ち物');
  R.md.saved = !!(await waitFor(async () => { const t = await read(mdRel); return (t.match(/持ち物/g) || []).length === 2; }));
  // 日本語入力: 変換の途中の文字は保存しない（確定したら保存する）
  const cm = cell(3, 5);
  cm.focus(); cm.value = 'りょこう';
  cm.dispatchEvent(new InputEvent('input', { bubbles: true, isComposing: true }));
  await sleep(1400);
  R.md.composingNotSaved = !(await read(mdRel)).includes('りょこう');
  cm.value = '旅行先';
  cm.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true }));
  R.md.committedSaved = !!(await waitFor(async () => (await read(mdRel)).includes('旅行先')));
  // 広げる: 副題「持ち物」のブロックへ
  const zoom = [...document.querySelector('.mdbox [data-rc="3,4"]').querySelectorAll('button')].find((b) => b.textContent.startsWith('広げる'));
  zoom.click(); await sleep(300);
  R.md.zoomed = document.querySelector('.mdbox .md-cell.mid textarea')?.value;
  const leaf = cell(0, 3);
  leaf.focus(); typeIn(leaf, '着替え');
  await waitFor(async () => (await read(mdRel)).includes('着替え'));
  await sleep(900);
  await shot('7-mandala');
  const toNote = await waitFor(() => [...document.querySelector('.mdbox [data-rc="0,3"]').querySelectorAll('button')].find((b) => b.textContent === 'ノートに'));
  toNote.click();
  R.md.linked = await waitFor(async () => /\\[着替え\\]\\(\\d+(?:-\\d+)?\\.md\\)/.test(await read(mdRel)));
  const b9 = btn(document.querySelector('.md-bar'), '9×9 全体'); b9.click(); await sleep(300);
  R.md.grid9 = document.querySelectorAll('.mdbox .md-grid9 .md-cell').length;
  await shot('8-mandala-9');

  // 10. キャンバス: 新しく作る → ノートを置く → 「索引を広げる」でトピック索引の項目が名前つきの矢印で並ぶ
  const pc = G.openCanvas('new');
  await waitFor(() => dlg());
  typeIn(dlg().querySelector('input[data-key="title"]'), 'ハーブの図');
  await okDlg();
  await pc;
  await waitFor(() => document.querySelector('.cvbox'), 10000);
  await sleep(600);
  btn(document.querySelector('.cv-bar'), '＋ ノート').click();
  await waitFor(() => dlg());
  R.cvPicked = await pick(0, 'ハーブ', (x) => x.querySelector('.gpick-main').textContent === 'ハーブ' && !x.textContent.includes('トピック索引'));
  await okDlg();
  await waitFor(() => document.querySelector('.cvbox .cv-card.note'));
  const card = [...document.querySelectorAll('.cvbox .cv-card.note')].find((c) => c.querySelector('.cv-ctitle').textContent === 'ハーブ');
  R.cv = { card: !!card, topicsQ: JSON.stringify((await window.gui.query('nav.topics', { file: 'h.md' })).result).slice(0, 200) };
  if (card) { btn(card, '索引を広げる').click(); }
  await waitFor(() => document.querySelectorAll('.cvbox .cv-card.note').length >= 4);
  await sleep(1200);
  let cvRel = ''; (function w(x) { if (x.type === 'tabs') x.tabs.forEach((t) => { if (t.kind === 'canvas') cvRel = t.params.rel; }); else { w(x.a); w(x.b); } })(G.panes().getLayout());
  R.cv.rel = cvRel;
  R.cv.cards = [...document.querySelectorAll('.cvbox .cv-card.note .cv-ctitle')].map((x) => x.textContent);
  R.cv.labels = [...document.querySelectorAll('.cvbox .cv-elabel')].map((x) => x.textContent);
  R.cv.toast = document.getElementById('gtoast') ? document.getElementById('gtoast').textContent : '';
  R.cv.file = await waitFor(async () => { const t = await read(cvRel); return t.includes('"label":"ローズマリー"') && t; });
  await shot('9-canvas');

  // 11. 索引ブラウザの「索引に無いノート」: 曼荼羅・キャンバスが出る → そこから Global Index に載せる
  G.openIndexBrowser();
  await sleep(400);
  btn(document.querySelector('.di-top'), '索引に無いノート').click();
  await waitFor(() => document.querySelectorAll('.di-unrow').length >= 2);
  R.un = { rows: [...document.querySelectorAll('.di-unrow .nav-label')].map((x) => x.textContent) };
  await shot('10-unindexed');
  const travel = [...document.querySelectorAll('.di-unrow')].find((r) => r.querySelector('.nav-label').textContent === '旅行');
  btn(travel, '＋ 載せる').click();
  await waitFor(() => dlg());
  R.un.pickedGlobal = await pick(0, '', (x) => x.querySelector('.gpick-main').textContent === 'Global Index');
  await okDlg();
  R.un.added = !!(await waitFor(async () => (await read('index.md')).includes('[旅行](' + R.md.rel + ')')));
  R.un.after = await waitFor(() => { const t = [...document.querySelectorAll('.di-unrow .nav-label')].map((x) => x.textContent); return !t.includes('旅行') && t; }, 6000);


  // 12. Obsidian のような枠: 左右のバー・リボン・クイックスイッチャー・Ctrl+P・リンク・アウトライン
  const D = G.docks();
  R.ob = { ribbon: [...document.querySelectorAll('#ribbon [data-ribbon]')].map((b) => b.dataset.ribbon), leftTabs: [...document.querySelectorAll('#leftdock .dock-tab')].map((b) => b.dataset.panel), rightTabs: [...document.querySelectorAll('#rightdock .dock-tab')].map((b) => b.dataset.panel) };
  document.querySelector('#ribbon .ribbon-toggle').click(); await sleep(200);
  R.ob.leftClosed = document.getElementById('leftdock').hidden;
  document.querySelector('#ribbon .ribbon-toggle').click(); await sleep(200);
  R.ob.leftReopened = !document.getElementById('leftdock').hidden;
  document.querySelector('#rightdock .dock-toggle').click(); await sleep(200);
  R.ob.rightClosed = document.getElementById('rightdock').hidden && !document.querySelector('.dock-float').hidden;
  document.querySelector('.dock-float').click(); await sleep(200);
  R.ob.rightReopened = !document.getElementById('rightdock').hidden;
  // クイックスイッチャー（Vim のノーマルモードで Ctrl+O）→ ローズマリーの栽培 を開く
  G.panes().showVim(); await sleep(200); G.term.focus();
  await G.send('\x1b'); await sleep(300);
  document.querySelector('#term textarea').dispatchEvent(new KeyboardEvent('keydown', { key: 'o', code: 'KeyO', ctrlKey: true, bubbles: true, cancelable: true }));
  await sleep(200);
  R.ob.switcherOpen = G.switcher().isOpen();
  typeIn(document.querySelector('.qs-input'), 'ローズマリーの栽培');
  await waitFor(() => [...document.querySelectorAll('.qs-item')].some((x) => x.textContent.includes('ローズマリーの栽培')));
  R.ob.qsItems = [...document.querySelectorAll('.qs-item')].map((x) => x.textContent).slice(0, 3);
  R.ob.qsOpenBeforeEnter = G.switcher().isOpen();
  document.querySelector('.qs-input').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
  R.ob.switched = await waitFor(() => vimFile() === 'rs.md' && 'rs.md');
  R.ob.tabTitle = await waitFor(() => { const t = [...document.querySelectorAll('.tab .tabtitle')].map((x) => x.textContent).find((x) => x.includes('ローズマリーの栽培')); return t; });
  // リンク（右のバー）: rs.md へは索引 gr.md の本文からリンクがある
  D.show('links');
  R.ob.back = await waitFor(() => { const t = document.querySelector('#rightdock .dock-panel[data-panel="links"]').innerText; return t.includes('バックリンク') && t.includes('ローズマリー') && t.replace(/\\s+/g, ' ').slice(0, 300); });
  if (!R.ob.back) { R.ob.backText = document.querySelector('#rightdock').innerText.slice(0, 300); R.ob.dock = JSON.stringify(D.state().right); R.ob.q = JSON.stringify(await window.gui.query('nav.links', { file: G.state().file })).slice(0, 300); }
  await shot('11-obsidian-links');
  // Ctrl+P（ノーマルモード）でコマンドパレット
  G.term.focus();
  document.querySelector('#term textarea').dispatchEvent(new KeyboardEvent('keydown', { key: 'p', code: 'KeyP', ctrlKey: true, bubbles: true, cancelable: true }));
  await sleep(200);
  R.ob.palette = !document.getElementById('palette').hidden;
  document.getElementById('palette-input').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  await sleep(200);
  // 挿入モードの Ctrl+P は Vim のまま（パレットを開かない）
  await G.send('o'); await waitFor(() => (G.state().mode || '')[0] === 'i', 3000);
  document.querySelector('#term textarea').dispatchEvent(new KeyboardEvent('keydown', { key: 'p', code: 'KeyP', ctrlKey: true, bubbles: true, cancelable: true }));
  await sleep(200);
  R.ob.paletteInInsert = !document.getElementById('palette').hidden;
  await G.send('\x1b'); await sleep(200); await G.send('u'); await sleep(300);
  // 機能（左のバー）: 探して押すと実行される
  D.show('features'); await sleep(300);
  const fs2 = document.querySelector('#leftdock .dock-panel[data-panel="features"] .pnl-search');
  typeIn(fs2, 'アウトライン');
  const fi = await waitFor(() => document.querySelector('#leftdock .dock-panel[data-panel="features"] .feat-item'));
  R.ob.featFirst = fi && fi.textContent;
  fi && fi.click(); await sleep(300);
  R.ob.outlineShown = D.isVisible('outline');
  R.ob.outline = await waitFor(() => [...document.querySelectorAll('#rightdock .outline-item')].map((x) => x.textContent).join('|'));
  D.show('index');

  // 13. 曼荼羅に既存のノートを入れる（「既存…」で選ぶ・ドラッグで落とす）・外す
  G.openMandala('pick');
  await waitFor(() => dlg());
  await pick(0, '旅行', '旅行');
  await okDlg();
  await waitFor(() => document.querySelector('.mdbox .md-cell textarea'), 8000);
  await sleep(500);
  const mdBox = [...document.querySelectorAll('.mdbox')].find((x) => x.offsetParent);
  const c3 = (r, c) => mdBox.querySelector('[data-rc="' + r + ',' + c + '"]');
  if (![...mdBox.querySelectorAll('.md-grid3')].length) btn(document.querySelector('.md-bar'), '3×3 で考える').click();
  await sleep(300);
  // 中心のブロックへ
  btn(mdBox.querySelector('.md-crumbs'), '旅行')?.click(); await sleep(300);
  const ex = await waitFor(() => [...c3(4, 3).querySelectorAll('button')].find((b) => b.textContent.startsWith('既存')));
  ex.click();
  await waitFor(() => dlg());
  R.mdx = { picked: await pick(0, 'ハーブの栽培', 'ハーブの栽培') };
  await okDlg();
  R.mdx.saved = await waitFor(async () => { const t = await read(R.md.rel); return (t.match(/\\[ハーブの栽培\\]\\(hs\\.md\\)/g) || []).length === 2; });
  if (!R.mdx.saved) R.mdx.text = (await read(R.md.rel)).split('\\n').filter((l) => l.startsWith('|')).join('\\n');
  // ドラッグで落とす（ノートのパネルの行と同じ text/gnosis-note）
  const dt = new DataTransfer(); dt.setData('text/gnosis-note', 'u.md');
  c3(5, 3).dispatchEvent(new DragEvent('dragover', { dataTransfer: dt, bubbles: true, cancelable: true }));
  c3(5, 3).dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true, cancelable: true }));
  R.mdx.dropped = await waitFor(async () => (await read(R.md.rel)).includes('[運動](u.md)'));
  await shot('12-mandala-existing');
  const un = await waitFor(() => [...c3(5, 3).querySelectorAll('button')].find((b) => b.textContent === '外す'));
  un.click();
  R.mdx.unlinked = await waitFor(async () => { const t = await read(R.md.rel); return !t.includes('(u.md)') && (t.match(/\\| 運動 \\|/g) || []).length >= 1; });
  } catch (e) { R.error = String(e && e.stack || e); R.errSide = sideText().slice(0, 400); R.errScreen = G.screen().filter((x) => x.trim()).slice(-3); await shot('error'); }
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
const env = { ...process.env, PATH: stubBin + path.delimiter + (process.env.PATH || ""), HOME: home, GNOSIS_HOME: gnosisHome, GNOSIS_VIMRC: path.join(web, "..", "vimrc_gnosis"), PKM_ROOT: vault, PKM_TEST_SCRIPT: scenarioPath, PKM_TEST_OUT: outPath, GNOSIS_TEST_SHOTS: shots };
delete env.WAYLAND_DISPLAY; delete env.XDG_SESSION_TYPE; delete env.DISPLAY;
let failed = 0;
const check = (ok, msg) => { if (!ok) { console.error("FAIL: " + msg); failed++; } };
try {
  execFileSync("xvfb-run", ["-a", "-s", "-screen 0 1440x900x24", path.join(web, "node_modules/.bin/electron"), web, "--no-sandbox", "--disable-gpu", "--ozone-platform=x11"],
    { env, stdio: ["ignore", "ignore", "inherit"], timeout: 300000 });
  const R = JSON.parse(fs.readFileSync(outPath, "utf8"));
  const show = { ...R }; if (show.cv) show.cv = { ...show.cv, file: show.cv.file ? "(ok)" : show.cv.file };
  console.log(JSON.stringify(show, null, 2));
  if (R.fatal) { console.error("fatal: " + R.fatal); process.exit(1); }
  check(!R.error, "scenario error: " + R.error);
  const jsErrors = (R.__console || []).filter((l) => !/Electron Security Warning/.test(l));
  check(jsErrors.length === 0, "console errors in the app: " + JSON.stringify(jsErrors));
  check(R.side?.shown && JSON.stringify(R.side.crumbs) === '["Index","ハーブ"]' && R.side.indexedHerb && R.side.topics && R.side.entries, "sidebar follows the note (path, indexes with aliases, topic index entries): " + JSON.stringify(R.side));
  check(R.hist?.backEnabled && R.hist.fwdDisabledAtFirst && R.hist.afterBack === "h.md" && R.hist.fwdEnabled && R.hist.afterAltRight === "rs.md" && R.hist.afterMouseBack === "h.md", "back/forward buttons, Alt+→ and the mouse back button follow Vim's history: " + JSON.stringify(R.hist));
  check(/栽培/.test(R.twisty) && /利用/.test(R.twisty), "▸ opens a nested topic index in place: " + R.twisty);
  check(JSON.stringify(R.deep) === '["Index","ハーブ","ローズマリー","栽培"]', "the path of a deep note uses the index names: " + JSON.stringify(R.deep));
  check(R.search?.some((x) => x.includes("Index › ハーブ ›") && x.includes("栽培")) && R.search.some((x) => x.includes("Index › ハーブ › ローズマリー ›")), "keyword search shows which index the keyword is in: " + JSON.stringify(R.search));
  check(R.pickedIndex && R.added && R.addedBack === "u.md" && R.addedSide?.includes("ハーブと運動"), "add to an index through the dialog (written by Vim, back on the note): " + JSON.stringify([R.pickedIndex, R.added, R.addedBack, R.addedSide]));
  check(R.topic?.rel && /attribute: group/.test(R.topic.text) && /title: 栽培の記録/.test(R.topic.text) && /ParentBranch:\n\[[^\]]+\]\(rs\.md\)/.test(R.topic.text), "a topic index is created from the note (zk → n): " + JSON.stringify(R.topic));
  check(R.newInIndex?.rel && /title: 水やり/.test(R.newInIndex.text) && /ParentBranch:\n\[[^\]]+\]\(rs\.md\)/.test(R.newInIndex.text), "a new note in the index gets the index's origin as its parent: " + JSON.stringify(R.newInIndex));
  check(JSON.stringify(R.newCrumbs) === '["Index","ハーブ","ローズマリー","栽培","水やり"]', "the new note is reachable from the Global Index: " + JSON.stringify(R.newCrumbs));
  check(JSON.stringify(R.browser?.c0?.slice(0, 3)) === '["ハーブ","薬草","運動"]' && R.browser.c1?.includes("ローズマリー") && R.browser.c1.includes("ハーブと運動") && JSON.stringify(R.browser.c2) === '["栽培","利用"]', "index browser columns: " + JSON.stringify(R.browser));
  check(/📔/.test(R.cal?.cellA) && /水やり/.test(R.cal.cellA) && R.cal.today, "calendar shows the diary and the due task: " + JSON.stringify(R.cal));
  check(R.cal?.completed && R.cal.vimAfterComplete !== "d1.md", "completing a task writes [x] ✅ through Vim and Vim goes back: " + JSON.stringify([R.cal?.completed, R.cal?.vimAfterComplete]));
  check(R.cal?.added && R.cal.added.time === "18:00", "add a task due on the selected day: " + JSON.stringify(R.cal?.added));
  check(R.cal?.pastDiary?.ok && /^\d{4}-\d\d-\d\d-[A-Z]{2}$/.test(R.cal.pastTitle || ""), "a past day's diary is created and opened: " + JSON.stringify([R.cal?.pastDiary, R.cal?.pastTitle]));
  check(R.cal?.future && !R.cal.future.ok, "no diary for a future day: " + JSON.stringify(R.cal?.future));
  check(R.md?.rel && R.md.theme === "旅行" && R.md.sub0 === "準備" && R.md.saved && R.md.zoomed === "持ち物" && R.md.linked && R.md.grid9 === 81, "mandala: create, type a sub theme (mirrored), zoom, cell → note, 9×9: " + JSON.stringify(R.md));
  check(/グラフ/.test(R.ime?.first || "") && R.ime.openAfterComposingKeys && R.ime.ranAfterRealEnter, "IME: hiragana finds a katakana label; Enter/arrows/Esc while composing do not run the palette: " + JSON.stringify(R.ime));
  check(R.ime?.dialogKept && R.ime.dialogClosedByEsc && R.ime.navKept, "IME: Enter/Esc while composing do not submit or close dialogs or open search hits: " + JSON.stringify(R.ime));
  check(R.md?.composingNotSaved && R.md.committedSaved, "IME: a mandala cell is not saved while composing, and is saved once confirmed: " + JSON.stringify(R.md));
  check(R.cv?.card && R.cv.cards.length >= 4 && ["まとめ", "ローズマリー", "栽培"].every((x) => R.cv.labels.includes(x)) && R.cv.file && /canvas: true/.test(R.cv.file) && /\[ハーブ\]\(h\.md\)/.test(R.cv.file), "canvas: place a note, expand its topic index as labelled arrows, saved as Markdown: " + JSON.stringify({ ...R.cv, file: !!R.cv?.file }));
  check(JSON.stringify(R.ob?.leftTabs) === '["index","notes","features"]' && JSON.stringify(R.ob.rightTabs) === '["links","outline"]' && R.ob.ribbon.includes("switcher") && R.ob.leftClosed && R.ob.leftReopened && R.ob.rightClosed && R.ob.rightReopened, "Obsidian-like frame: ribbon, left/right docks that hide and show: " + JSON.stringify(R.ob));
  check(R.ob?.switcherOpen && R.ob.switched === "rs.md" && R.ob.tabTitle, "Ctrl+O in Vim's normal mode opens the quick switcher, Enter opens the note and the tab shows its title: " + JSON.stringify(R.ob));
  check(/ローズマリー/.test(R.ob?.back || "") && R.ob.palette && !R.ob.paletteInInsert, "links panel shows backlinks; Ctrl+P opens the palette in normal mode but not in insert mode: " + JSON.stringify(R.ob));
  check(/アウトライン/.test(R.ob?.featFirst || "") && R.ob.outlineShown && /ローズマリーの栽培/.test(R.ob.outline || ""), "features panel runs a command; outline lists the headings: " + JSON.stringify(R.ob));
  check(R.mdx?.picked && R.mdx.saved && R.mdx.dropped && R.mdx.unlinked, "mandala: put an existing note into a cell (picker, mirrored), drop a note onto a cell, unlink: " + JSON.stringify(R.mdx));
  check(R.un?.rows?.includes("旅行") && R.un.rows.includes("ハーブの図") && R.un.pickedGlobal && R.un.added && R.un.after, "unindexed notes are listed and can be put on the Global Index from there: " + JSON.stringify(R.un));
  // ノートの原本: 試験で作ったもの以外のノートは、載せた索引（gh.md）・完了したタスク（d1.md）・トピック索引を足したノート（rs.md）だけが変わる
  const idx = fs.readFileSync(path.join(vault, "index.md"), "utf8");
  check(idx.includes("[ハーブ](h.md)") && !idx.includes("gh.md"), "the Global Index still points to the first note, never to the topic index");
  if (!failed) console.log("workbench e2e: OK (索引ナビ・索引語の検索・載せる・トピック索引・新しいノート・索引ブラウザ・カレンダー・曼荼羅・キャンバス)");
} finally {
  if (!process.env.GNOSIS_E2E_KEEP) fs.rmSync(tmp, { recursive: true, force: true });
  else console.log("kept: " + tmp);
}
process.exit(failed ? 1 : 0);
