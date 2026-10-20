// 追加ビュー（階層ツリー・孤立・隣接行列・Treemap・Sunburst・カンバン・マインドマップ・成長・川・比較・Sankey・地図・3D・スライド・ホワイトボード・ギャラリー）を、
// 書き出したサイトとして本物のブラウザ（Electron の Chromium、xvfb）で開き、実際に操作して確かめる。vault は一時フォルダ。
//   node test/views2_e2e.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "..", "..");
const base = process.env.TMPDIR || path.join(os.homedir(), "Desktop", "test");
fs.mkdirSync(base, { recursive: true });
const tmp = fs.mkdtempSync(path.join(base, "views2-e2e-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
const electron = path.join(repo, "web", "node_modules", "electron", "dist", "electron");
if (!fs.existsSync(electron) || spawnSync("which", ["xvfb-run"]).status !== 0) { console.error("SKIP: electron か xvfb-run が無いので省略"); process.exit(0); }

const v = path.join(tmp, "vault");
fs.mkdirSync(path.join(v, "img"), { recursive: true });
fs.writeFileSync(path.join(v, "img", "p.png"), Buffer.from("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082", "hex"));
fs.writeFileSync(path.join(v, "doc.pdf"), "%PDF-1.4\n");
const note = (name, title, body, fz = "", extra = "", time = "2026-01-10 09:00:00") => fs.writeFileSync(path.join(v, name),
  `---\ntime: ${time}\ntitle: ${title}\n${fz ? `folgezettel: "${fz}"\n` : ""}${extra}---\n\n# ${title}\n\n${body}\n`);
note("n1.md", "ハーブ", "BranchGroup:\n[栽培](n1a.md)\n[利用](n1b.md)\n\n![図](img/p.png) [資料](doc.pdf)\n- [ ] 水やり 📅 2026-10-19\n- [ ] 収穫 📅 2026-10-21 ⏫\n- [ ] 肥料 📅 2026-10-25\n- [ ] 来年 📅 2027-03-01\n- [ ] いつか\n- [x] 種まき ✅ 2026-10-20", "1", "location: 35.68, 139.76\n");
note("n1a.md", "栽培", "ParentBranch:\n[ハーブ](n1.md)\n\nBranchGroup:\n[水やり](n1a1.md)\n\n水やりは控えめに", "1a", "location: 34.69, 135.50\n", "2026-02-15 09:00:00");
note("n1a1.md", "水やり", "ParentBranch:\n[栽培](n1a.md)\n\n本文", "1a1", "", "2026-02-20 09:00:00");
note("n1b.md", "利用", "ParentBranch:\n[ハーブ](n1.md)\n\n[栽培](n1a.md) を参照", "1b", "location: どこか\n", "2026-04-01 09:00:00");
note("n2.md", "料理", "[ハーブ](n1.md) と [栽培](n1a.md) を使う", "2", "", "2026-05-01 09:00:00");
note("lone.md", "孤立したメモ", "だれともつながっていない", "", "", "");
note("talk.md", "発表", "# 表紙\n\n導入の文\n\n---\n\n## 第一章\n\n- a\n- b\n\n## 第二章\n\n終わり", "", "slides: true\n");
note("hyp.md", "仮説ノート", "仮説: 水やりは控えめがよい\n状態: 検証中\n+ 証拠: 乾燥に強い [図鑑](n1.md)\n- 反証: 枯れた\n\n仮説: 水は多いほどよい\n+ 証拠: [図鑑](n1.md)\n", "", "", "2026-06-01 09:00:00");
note("secret.md", "秘密", "TOPSECRET", "", "private: true\n");
const site = path.join(tmp, "site");
execFileSync("python3", [path.join(repo, "python", "export_site.py"), v, site], { encoding: "utf8" });

function run(name, src) {
  const f = path.join(tmp, name + ".cjs");
  // 失敗した式が分かるように、p.eval を包む(ページ内で例外が出たとき、どの式かを報告する)
  const wrapped = src.replace("module.exports = async (p) => {", `module.exports = async (p0) => {
  const p = Object.create(p0);
  p.eval = async (x) => { try { return await p0.eval(x); } catch (e) { throw new Error("EVAL FAILED: " + String(x).slice(0, 220) + " :: " + e.message); } };`);
  fs.writeFileSync(f, wrapped);
  const r = spawnSync("xvfb-run", ["-a", electron, path.join(here, "site_views_main.cjs"), site, f], { encoding: "utf8", timeout: 120000, env: { ...process.env, ELECTRON_DISABLE_SANDBOX: "1" } });
  const line = (r.stdout || "").split("\n").find((l) => l.startsWith("RESULT "));
  assert.ok(line, `${name}: 結果が出ない\n${r.stdout}\n${r.stderr}`);
  const out = JSON.parse(line.slice(7));
  assert.ok(out.ok, `${name}: ${out.error}`);
  return out.result;
}
const q = (sel, what = "textContent") => `document.querySelector(${JSON.stringify(sel)}).${what}`;
const qa = (sel) => JSON.stringify(`document.querySelectorAll(${JSON.stringify(sel)}).length`);   // p.eval に渡す式の文字列(JSON)

// 1. 階層ツリー / 孤立 / 隣接行列
const a = run("tree-orphans-matrix", `
module.exports = async (p) => {
  const o = {};
  await p.open("tree.html");
  o.treeCount = await p.eval(${JSON.stringify(q("#count"))});
  o.openAtStart = await p.eval(${qa("#tree2 details[open]")});
  await p.click("#t-close"); o.afterClose = await p.eval(${qa("#tree2 details[open]")});
  await p.click("#t-open"); o.afterOpen = await p.eval(${qa("#tree2 details[open]")});
  o.hasSecret = await p.eval("document.body.textContent.indexOf('秘密') >= 0");
  o.rootFirst = await p.eval("document.querySelector('#tree2 > details > summary a, #tree2 > .leaf a').textContent");
  await p.open("orphans.html");
  o.isolated = await p.eval(${JSON.stringify(q("#o-isolated"))});
  o.unindexed = await p.eval(${JSON.stringify(q("#o-unindexed"))});
  await p.open("matrix.html");
  o.mxRows = await p.eval(${qa("#mx tr")});
  o.mxMarked = await p.eval("document.querySelectorAll('#mx td.cell1, #mx td.cell2, #mx td.cell3').length");
  o.mxTitle = await p.eval("(document.querySelector('#mx td.cell1, #mx td.cell2, #mx td.cell3')||{getAttribute(){return ''}}).getAttribute('title')");
  return o;
};`);
assert.match(a.treeCount, /^\d+ 件$/);
assert.ok(a.openAtStart >= 1);
assert.equal(a.afterClose, 0, "すべて閉じる");
assert.ok(a.afterOpen >= a.openAtStart, "すべて開く");
assert.equal(a.hasSecret, false, "非公開ノートはツリーに出ない");
assert.match(a.rootFirst, /^1 ハーブ$/, "番号順で最初が根");
assert.match(a.isolated, /孤立したメモ/);
assert.match(a.isolated, /^孤立（出入りするリンクがない）：\d+ \/ \d+/);
assert.match(a.unindexed, /孤立したメモ/);
assert.ok(a.mxRows >= 2 && a.mxMarked >= 3, "行列にセルが載る");
assert.match(a.mxTitle, /→/);

// 2. Treemap / Sunburst / カンバン
const b = run("treemap-sunburst-kanban", `
module.exports = async (p) => {
  const o = {};
  await p.open("treemap.html");
  o.tmRects = await p.eval(${qa("#tm rect")});
  o.tmLinks = await p.eval(${qa("#tm a")});
  o.tmHref = await p.eval("document.querySelector('#tm a').getAttribute('href')");
  await p.open("sunburst.html");
  o.sbPaths = await p.eval(${qa("#sb path")});
  o.sbCenter = await p.eval("document.querySelector('#sb text').textContent");
  await p.open("sunburst.html#depth=2");
  o.sbDepth2 = await p.eval(${qa("#sb path")});
  await p.open("kanban.html#today=2026-10-21");
  const cols = {};
  for (const k of ["overdue","today","soon","later","undated","done"]) cols[k] = await p.eval("document.querySelector('#kb-" + k + " h2').textContent");
  o.cols = cols;
  o.prio = await p.eval("document.querySelectorAll('#kb-today .prio-high').length");
  return o;
};`);
assert.ok(b.tmRects >= 5, "Treemap の矩形");
assert.ok(b.tmLinks >= 4);
assert.match(b.tmHref, /\.html$/);
assert.ok(b.sbPaths >= 4);
assert.match(b.sbCenter, /葉$/);
assert.ok(b.sbDepth2 <= b.sbPaths, "深さを浅くすると弧が減る");
assert.match(b.cols.overdue, /期限切れ（1）/);
assert.match(b.cols.today, /今日（1）/);
assert.match(b.cols.soon, /7 日以内（1）/);
assert.match(b.cols.later, /それ以降（1）/);
assert.match(b.cols.undated, /期限なし（1）/);
assert.match(b.cols.done, /完了（1）/);
assert.equal(b.prio, 1, "優先度の高いタスクに印");

// 3. マインドマップ / 成長 / 川 / 比較
const c = run("mindmap-growth-compare", `
module.exports = async (p) => {
  const o = {};
  await p.open("mindmap.html#n=n1.md&depth=3");
  o.mmNodes = await p.eval(${qa("#mm g.node")});
  o.mmLines = await p.eval(${qa("#mm line")});
  await p.open("mindmap.html#n=n1.md&depth=1");
  o.mmDepth1 = await p.eval(${qa("#mm g.node")});
  await p.open("growth.html");
  o.grBars = await p.eval(${qa("#gr rect")});
  o.grInfo = await p.eval(${JSON.stringify(q("#gr-info"))});
  await p.open("river.html");
  o.rvPolys = await p.eval(${qa("#rv polygon")});
  o.rvLegend = await p.eval("document.querySelectorAll('.legend span').length");
  await p.open("compare.html#a=n1.md&b=n2.md");
  o.cmpSum = await p.eval(${JSON.stringify(q("#cmp-sum"))});
  o.cmpFull = await p.eval(${JSON.stringify(q("#cmp"))});
  await p.eval("(function(){var a=document.getElementById('cmp-a');a.value='n1a.md';a.dispatchEvent(new Event('change'))})()");
  o.cmpAfter = await p.eval(${JSON.stringify(q("#cmp"))});
  await p.eval("(function(){var a=document.getElementById('cmp-a'),b=document.getElementById('cmp-b');b.value=a.value;b.dispatchEvent(new Event('change'))})()");
  o.cmpSame = await p.eval(${JSON.stringify(q("#cmp"))});
  return o;
};`);
assert.equal(c.mmNodes, 4, "ハーブ+栽培+利用+水やり（深さ3）");
assert.equal(c.mmLines, 3);
assert.equal(c.mmDepth1, 3, "深さ1: 中心と直接の子 2");
assert.ok(c.grBars >= 4, "月ごとの棒");
assert.match(c.grInfo, /作成日がないもの \d+ 件は含めていません/);
assert.ok(c.rvPolys >= 2 && c.rvLegend === c.rvPolys);
assert.match(c.cmpSum, /共通 \d+・A だけ \d+・B だけ \d+/);
assert.notEqual(c.cmpAfter, c.cmpFull, "選び直すと結果が変わる(見出しに選んだノート名が入る)");
assert.match(c.cmpSame, /別々のノート/, "同じノートは比べない");

// 3b. グラフの「関係の名前を表示」(コンセプトマップ)
const g2 = run("graph-labels", `
module.exports = async (p) => {
  const o = {};
  await p.open("graph.html");
  o.edges = await p.eval("document.querySelectorAll('#g line').length");
  o.labels0 = await p.eval("document.querySelectorAll('#g text.elabel').length");
  await p.click("#labels");
  o.labels1 = await p.eval("document.querySelectorAll('#g text.elabel').length");
  o.sample = await p.eval("Array.from(document.querySelectorAll('#g text.elabel')).map(function(t){return t.textContent}).filter(function(x,i,a){return a.indexOf(x)===i}).sort().join('|')");
  await p.click("#labels");
  o.labels2 = await p.eval("document.querySelectorAll('#g text.elabel').length");
  await p.open("graph.html#labels=1");
  o.fromHash = await p.eval("document.querySelectorAll('#g text.elabel').length");
  return o;
};`);
assert.equal(g2.labels0, 0, "既定では名前を出さない");
assert.equal(g2.labels1, g2.edges, "線 1 本ごとに名前");
assert.match(g2.sample, /親\(ParentBranch\)/);
assert.equal(g2.labels2, 0, "もう一度で消える");
assert.equal(g2.fromHash, g2.edges, "#labels=1 で最初から表示");

// 4. Sankey / 地図 / 3D
const d = run("sankey-map-3d", `
module.exports = async (p) => {
  const o = {};
  await p.open("sankey.html");
  o.skPaths = await p.eval(${qa("#sk path")});
  o.skTitle = await p.eval("document.querySelector('#sk path title').textContent");
  await p.open("map.html");
  o.mpCircles = await p.eval(${qa("#mp circle")});
  o.mpInfo = await p.eval(${JSON.stringify(q("#mp-info"))});
  const xs = await p.eval("Array.from(document.querySelectorAll('#mp a')).map(function(a){return a.querySelector('title').textContent.split('（')[0] + ':' + a.querySelector('circle').getAttribute('cx')})");
  o.mpXs = xs;
  await p.open("graph3d.html");
  o.g3Nodes = await p.eval(${qa("#g3 a")});
  o.g3Ry0 = await p.eval("document.getElementById('g3').getAttribute('data-ry')");
  const before = await p.eval("document.querySelector('#g3 circle').getAttribute('cx')");
  await p.click("#g3-right");
  o.g3Ry1 = await p.eval("document.getElementById('g3').getAttribute('data-ry')");
  o.g3Moved = (await p.eval("document.querySelector('#g3 circle').getAttribute('cx')")) !== before;
  for (let i = 0; i < 4; i++) await p.click("#g3-up");
  o.g3Rx = await p.eval("document.getElementById('g3').getAttribute('data-ry')");
  return o;
};`);
assert.ok(d.skPaths >= 1);
assert.match(d.skTitle, /→.*本/);
assert.equal(d.mpCircles, 2, "位置が読める 2 件(読めない 1 件は除外)");
assert.match(d.mpInfo, /位置が読めなかったもの 1 件は除外/);
const east = Object.fromEntries(d.mpXs.map((s) => s.split(":")));
assert.ok(parseFloat(east["ハーブ"]) > parseFloat(east["栽培"]), "東京は大阪より東(右)");
assert.equal(d.g3Nodes, 8, "非公開を除く 8 ノート");
assert.equal(d.g3Ry0, "0.600");
assert.equal(d.g3Ry1, "0.900");
assert.ok(d.g3Moved, "回すと位置が動く");

// 5. スライド / ホワイトボード / ギャラリー
const e = run("slides-wb-gallery", `
module.exports = async (p) => {
  const o = {};
  await p.open("slides.html");
  o.slPos0 = await p.eval(${JSON.stringify(q("#sl-pos"))});
  o.slText0 = await p.eval(${JSON.stringify(q("#slide"))});
  await p.click("#sl-next");
  o.slPos1 = await p.eval(${JSON.stringify(q("#sl-pos"))});
  o.slText1 = await p.eval(${JSON.stringify(q("#slide"))});
  await p.key("Right"); o.slPos2 = await p.eval(${JSON.stringify(q("#sl-pos"))});
  await p.key("Right"); o.slPos3 = await p.eval(${JSON.stringify(q("#sl-pos"))});   // 最後で止まる
  o.nextDisabled = await p.eval("document.getElementById('sl-next').disabled");
  await p.key("Home"); o.slHome = await p.eval(${JSON.stringify(q("#sl-pos"))});
  o.slScripts = await p.eval("document.querySelectorAll('#slide script').length");
  await p.open("whiteboard.html");
  o.wbCards = await p.eval(${qa(".wcard")});
  o.wbX0 = await p.eval("document.querySelector('.wcard').getAttribute('data-x')");
  await p.eval("document.querySelector('.wcard').focus()");
  await p.key("Right"); await p.key("Down");
  o.wbX1 = await p.eval("document.querySelector('.wcard').getAttribute('data-x')");
  o.wbY1 = await p.eval("document.querySelector('.wcard').getAttribute('data-y')");
  o.wbStored = await p.eval("localStorage.getItem('gnosis-whiteboard')");
  await p.open("whiteboard.html");
  o.wbX2 = await p.eval("document.querySelector('.wcard').getAttribute('data-x')");     // 開き直しても位置を覚えている
  await p.click("#wb-reset");
  o.wbX3 = await p.eval("document.querySelector('.wcard').getAttribute('data-x')");
  await p.open("gallery.html");
  o.gaAll = await p.eval(${JSON.stringify(q("#count"))});
  o.gaImg = await p.eval(${qa("#ga img")});
  o.gaRef = await p.eval("document.querySelector('#ga .gitem .note a').textContent");
  await p.eval("(function(){var s=document.getElementById('ga-type');s.value='pdf';s.dispatchEvent(new Event('change'))})()");
  o.gaPdf = await p.eval(${JSON.stringify(q("#count"))});
  await p.eval("(function(){var s=document.getElementById('ga-type');s.value='all';s.dispatchEvent(new Event('change'));var q=document.getElementById('ga-q');q.value='存在しない';q.dispatchEvent(new Event('input'))})()");
  o.gaNone = await p.eval(${JSON.stringify(q("#count"))});
  return o;
};`);
assert.equal(e.slPos0, "1 / 3");
assert.match(e.slText0, /表紙/);
assert.equal(e.slPos1, "2 / 3");
assert.match(e.slText1, /第一章/);
assert.equal(e.slPos2, "3 / 3");
assert.equal(e.slPos3, "3 / 3", "最後で止まる");
assert.equal(e.nextDisabled, true);
assert.equal(e.slHome, "1 / 3");
assert.equal(e.slScripts, 0);
assert.equal(e.wbCards, 8);
assert.equal(Number(e.wbX1), Number(e.wbX0) + 8, "矢印キーで 8px 動く");
assert.equal(Number(e.wbY1), 8);
const wbSaved = JSON.parse(e.wbStored || "{}");
const wbKeys = Object.keys(wbSaved);
assert.equal(wbKeys.length, 1, "動かした 1 枚だけを保存");
assert.deepEqual(Object.keys(wbSaved[wbKeys[0]]).sort(), ["x", "y"]);
assert.equal(wbSaved[wbKeys[0]].x, Number(e.wbX1));
assert.equal(wbSaved[wbKeys[0]].y, Number(e.wbY1));
assert.equal(e.wbX2, e.wbX1, "開き直しても位置を覚えている");
assert.equal(e.wbX3, e.wbX0, "位置を忘れるで初期配置に戻る");
assert.equal(e.gaAll, "2 / 2 件");
assert.equal(e.gaImg, 1);
assert.match(e.gaRef, /ハーブ/);
assert.equal(e.gaPdf, "1 / 2 件");
assert.equal(e.gaNone, "0 / 2 件");

// 6. 博物館 / 記憶の宮殿 / 迷路
const f = run("museum-palace-maze", `
module.exports = async (p) => {
  const o = {};
  await p.open("museum.html");
  o.muPos0 = await p.eval(${JSON.stringify(q("#mu-pos"))});
  o.muPrevDisabled = await p.eval("document.getElementById('mu-prev').disabled");
  await p.click("#mu-next"); o.muPos1 = await p.eval(${JSON.stringify(q("#mu-pos"))});
  await p.key("Right"); o.muPos2 = await p.eval(${JSON.stringify(q("#mu-pos"))});
  o.muRoom = await p.eval("document.querySelector('#hall .note').textContent");
  await p.eval("(function(){var r=document.getElementById('mu-room');r.value=r.options[r.options.length-1].value;r.dispatchEvent(new Event('change'))})()");
  o.muRoomSel = await p.eval("document.querySelector('#hall .note').textContent");
  o.muRoomPos = await p.eval(${JSON.stringify(q("#mu-pos"))});
  for (let i = 0; i < 20; i++) await p.key("Right");
  o.muLast = await p.eval(${JSON.stringify(q("#mu-pos"))});
  o.muNextDisabled = await p.eval("document.getElementById('mu-next').disabled");
  // 記憶の宮殿: 2 枚のカードを別々の部屋へ(矢印キーで動かす)
  await p.open("palace.html");
  o.paChips = await p.eval(${qa(".wcard")});
  o.paRooms = await p.eval(${qa(".room")});
  const move = async (idx, dx, ups) => {
    await p.eval("document.querySelectorAll('.wcard')[" + idx + "].focus()");
    for (let i = 0; i < ups; i++) await p.key("Up");
    for (let i = 0; i < dx; i++) await p.key("Right", { shift: true });
  };
  await move(0, 0, 3);      // 1 つ目の部屋へ
  await move(1, 5, 3);      // 2 つ目の部屋へ(右へ 80px×5)
  o.paRoom0 = await p.eval("document.querySelectorAll('.wcard')[0].getAttribute('data-room')");
  o.paRoom1 = await p.eval("document.querySelectorAll('.wcard')[1].getAttribute('data-room')");
  o.paInfo = await p.eval(${JSON.stringify(q("#pa-info"))});
  const saved = await p.eval("localStorage.getItem('gnosis-palace')");
  o.paSaved = saved;
  await p.open("palace.html");
  o.paRoomAfterReload = await p.eval("document.querySelectorAll('.wcard')[0].getAttribute('data-room')");
  await p.click("#pa-quiz");
  o.qCount = await p.eval("document.querySelectorAll('#pa-q [data-q]').length");
  o.qOptions = await p.eval("document.querySelector('#pa-q [data-q]').querySelectorAll('button.opt').length");
  // 正解は「その部屋に置いたノート」。最初の問いの部屋から、置いたカード(data-id)を探して押す
  o.qRoomText = await p.eval("document.querySelector('#pa-q [data-q] div').textContent");
  o.qClickedOk = await p.eval("(function(){try{var card=document.querySelector('#pa-q [data-q]');var room=/部屋 (.+?) に/.exec(card.firstChild.textContent)[1];var chip=Array.from(document.querySelectorAll('.wcard')).filter(function(c){return c.getAttribute('data-room')===room})[0];var id=chip.getAttribute('data-id');var b=Array.from(card.querySelectorAll('button.opt')).filter(function(x){return x.getAttribute('data-id')===id})[0];b.click();return b.className}catch(e){return 'ERR '+e.message+' | rooms='+Array.from(document.querySelectorAll('.wcard')).map(function(c){return c.getAttribute('data-room')}).join(',')+' | q='+(document.querySelector('#pa-q [data-q]')||{textContent:'none'}).textContent.slice(0,60)}})()");
  o.qScore = await p.eval(${JSON.stringify(q("#pa-score"))});
  await p.click("#pa-reset");
  o.afterReset = await p.eval("document.querySelectorAll('.wcard')[0].getAttribute('data-room')");
  await p.click("#pa-quiz");
  o.qNone = await p.eval("!!document.getElementById('pa-none')");
  // 迷路: ハーブ → 栽培 → 水やり
  await p.open("maze.html#a=n1.md&b=n1a1.md");
  o.mzStatus = await p.eval(${JSON.stringify(q("#mz-status"))});
  o.mzChoices = await p.eval("Array.from(document.querySelectorAll('#mz-choices .step')).map(function(b){return b.textContent}).sort().join('|')");
  await p.eval("Array.from(document.querySelectorAll('#mz-choices .step')).filter(function(b){return /栽培/.test(b.textContent)})[0].click()");
  o.mzPath1 = await p.eval(${JSON.stringify(q("#mz-path"))});
  await p.eval("Array.from(document.querySelectorAll('#mz-choices .step')).filter(function(b){return /水やり/.test(b.textContent)})[0].click()");
  o.mzDone = await p.eval(${JSON.stringify(q("#mz-done"))});
  await p.open("maze.html");
  o.mzIntro = await p.eval("!!document.getElementById('mz-intro')");
  await p.click("#mz-rand");
  o.mzRand = await p.eval(${JSON.stringify(q("#mz-status"))});
  await p.eval("(function(){var a=document.getElementById('mz-a'),b=document.getElementById('mz-b');b.value=a.value})()");
  await p.click("#mz-go");
  o.mzSame = await p.eval("!!document.getElementById('mz-same')");
  return o;
};`);
assert.equal(f.muPos0.startsWith("1 / "), true);
assert.equal(f.muPrevDisabled, true);
assert.ok(f.muPos1.startsWith("2 / ") && f.muPos2.startsWith("3 / "), "ボタンと矢印キーで進む");
assert.match(f.muRoom, /展示室/);
assert.match(f.muRoomSel, /展示室 （番号なし）/, "部屋を選ぶとその部屋の展示へ移る");
assert.ok(Number(f.muRoomPos.split(" / ")[0]) > 3);
const [curN, allN] = f.muLast.split(" / ").map(Number);
assert.equal(curN, allN, "矢印キーで最後まで進める");
assert.equal(f.muNextDisabled, true, "最後の展示で次へは押せない");
assert.equal(f.paChips, 8);
assert.ok(f.paRooms >= 2);
assert.ok(f.paRoom0 && f.paRoom1 && f.paRoom0 !== f.paRoom1, "別々の部屋に置いた: " + f.paRoom0 + " / " + f.paRoom1);
assert.match(f.paInfo, /部屋に置いたノート 2 件/);
assert.ok(f.paSaved && f.paSaved.includes("room"));
assert.equal(f.paRoomAfterReload, f.paRoom0, "開き直しても置き場所を覚えている");
assert.equal(f.qCount, 2, "置いた 2 件から出題");
assert.equal(f.qOptions, 4);
assert.match(f.qRoomText, /部屋 .+ に置いたのは/);
assert.match(f.qClickedOk, /ok/, "その部屋に置いたノートを選ぶと正解");
assert.match(f.qScore, /^1 \/ 2/);
assert.equal(f.afterReset, "", "忘れると部屋から出る");
assert.equal(f.qNone, true, "置いていないと出題しない");
assert.match(f.mzStatus, /目標：水やり.*最短 2 手/);
assert.match(f.mzChoices, /栽培/);
assert.match(f.mzChoices, /利用/);
assert.ok(!/水やり/.test(f.mzChoices), "いまのノートから直接リンクの無い先へは進めない");
assert.match(f.mzPath1, /ハーブ → 栽培/);
assert.match(f.mzDone, /着きました！　2 手・得点 100 \/ 100/);
assert.equal(f.mzIntro, true);
assert.match(f.mzRand, /手数 0（最短 \d+ 手）/);
assert.equal(f.mzSame, true, "同じノートどうしでは始められない");

// 7. 成長アニメーション / アイデア合成器 / 仮説実験室 / 思考の対戦
const g3 = run("timelapse-ideas-hyp", `
module.exports = async (p) => {
  const o = {};
  await p.open("timelapse.html");
  o.tlMax = await p.eval("document.getElementById('tl-range').max");
  o.tlLabel0 = await p.eval(${JSON.stringify(q("#tl-label"))});
  o.tlNodes0 = await p.eval(${qa("#tlg a")});
  await p.eval("(function(){var r=document.getElementById('tl-range');r.value=r.max;r.dispatchEvent(new Event('input'))})()");
  o.tlLabelN = await p.eval(${JSON.stringify(q("#tl-label"))});
  o.tlNodesN = await p.eval(${qa("#tlg a")});
  o.tlLines = await p.eval(${qa("#tlg line")});
  o.tlNew = await p.eval("document.querySelectorAll('#tlg a circle[fill=\\"#e0a800\\"]').length");
  await p.click("#tl-play"); o.tlPlayLabel = await p.eval(${JSON.stringify(q("#tl-play"))});
  await p.click("#tl-play"); o.tlStopLabel = await p.eval(${JSON.stringify(q("#tl-play"))});
  await p.open("ideas.html#s=1");
  o.idA = await p.eval(${JSON.stringify(q("#id-a h2"))});
  o.idB = await p.eval(${JSON.stringify(q("#id-b h2"))});
  o.idPrompts = await p.eval(${qa("#id-prompts li")});
  o.idDist = await p.eval(${JSON.stringify(q("#id-dist"))});
  o.idP0 = await p.eval("document.querySelector('#id-prompts li').textContent");
  await p.click("#id-again");
  o.idHash = await p.eval("location.hash");
  await p.open("hypotheses.html");
  o.hyCount = await p.eval(${JSON.stringify(q("#count"))});
  o.hyCards = await p.eval(${qa("#hy .hyp")});
  o.hyText = await p.eval("document.getElementById('hy').textContent");
  await p.eval("(function(){var s=document.getElementById('hy-status');s.value='検証中';s.dispatchEvent(new Event('change'))})()");
  o.hyFiltered = await p.eval(${JSON.stringify(q("#count"))});
  await p.eval("(function(){var s=document.getElementById('hy-status');s.value='棄却';s.dispatchEvent(new Event('change'))})()");
  o.hyNone = await p.eval(${JSON.stringify(q("#count"))});
  o.hasSecret = await p.eval("document.body.textContent.indexOf('TOPSECRET') >= 0");
  await p.open("debate.html");
  o.dbRows = await p.eval(${qa("#db-table tr")});
  o.dbLead = await p.eval(${JSON.stringify(q("#db-lead"))});
  o.dbShared = await p.eval(${JSON.stringify(q("#db-shared"))});
  await p.eval("(function(){var a=document.getElementById('db-a'),b=document.getElementById('db-b');b.value=a.value;b.dispatchEvent(new Event('change'))})()");
  o.dbSame = await p.eval("!!document.getElementById('db-same')");
  return o;
};`);
assert.ok(Number(g3.tlMax) >= 3, "月ごとのコマ");
assert.match(g3.tlLabel0, /^2026-01（ノート 2 件/, "最初のコマは 1 月");
assert.ok(g3.tlNodesN > g3.tlNodes0, "時間が進むとノートが増える");
assert.match(g3.tlLabelN, /日付なし/, "最後のコマは日付のないノート");
assert.ok(g3.tlLines > 0);
assert.ok(g3.tlNew >= 1, "そのコマで増えたノートは目立つ色");
assert.match(g3.tlPlayLabel, /止める/);
assert.match(g3.tlStopLabel, /再生/);
assert.notEqual(g3.idA, g3.idB);
assert.equal(g3.idPrompts, 5);
assert.match(g3.idDist, /歩離れています|つながっていません/);
assert.ok(g3.idP0.includes(g3.idA) && g3.idP0.includes(g3.idB), "問いに 2 つの題が入る");
assert.match(g3.idHash, /s=2/);
assert.equal(g3.hyCount, "2 / 2 件");
assert.equal(g3.hyCards, 2);
assert.match(g3.hyText, /証拠 1・反証 1/);
assert.match(g3.hyText, /乾燥に強い 図鑑/);
assert.ok(!g3.hyText.includes("n1.md"), "リンク先のファイル名は出さない");
assert.equal(g3.hyFiltered, "1 / 2 件");
assert.equal(g3.hyNone, "0 / 2 件");
assert.equal(g3.hasSecret, false, "非公開ノートの仮説は出ない");
assert.equal(g3.dbRows, 5);
assert.match(g3.dbLead, /優勢：/);
assert.match(g3.dbShared, /共通の出典：ハーブ/);
assert.equal(g3.dbSame, true, "同じ仮説どうしは比べない");

console.log("views2 E2E OK（23 ページを実ブラウザで操作）");
