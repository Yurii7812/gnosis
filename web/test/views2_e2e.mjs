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
note("n1a.md", "栽培", "ParentBranch:\n[ハーブ](n1.md)\n\n水やりは控えめに", "1a", "location: 34.69, 135.50\n", "2026-02-15 09:00:00");
note("n1a1.md", "水やり", "ParentBranch:\n[栽培](n1a.md)\n\n本文", "1a1", "", "2026-02-20 09:00:00");
note("n1b.md", "利用", "ParentBranch:\n[ハーブ](n1.md)\n\n[栽培](n1a.md) を参照", "1b", "location: どこか\n", "2026-04-01 09:00:00");
note("n2.md", "料理", "[ハーブ](n1.md) と [栽培](n1a.md) を使う", "2", "", "2026-05-01 09:00:00");
note("lone.md", "孤立したメモ", "だれともつながっていない", "", "", "");
note("talk.md", "発表", "# 表紙\n\n導入の文\n\n---\n\n## 第一章\n\n- a\n- b\n\n## 第二章\n\n終わり", "", "slides: true\n");
note("secret.md", "秘密", "TOPSECRET", "", "private: true\n");
const site = path.join(tmp, "site");
execFileSync("python3", [path.join(repo, "python", "export_site.py"), v, site], { encoding: "utf8" });

function run(name, src) {
  const f = path.join(tmp, name + ".cjs");
  fs.writeFileSync(f, src);
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
  await p.eval("(function(){var a=document.getElementById('cmp-a');a.value='n1a.md';a.dispatchEvent(new Event('change'))})()");
  o.cmpAfter = await p.eval(${JSON.stringify(q("#cmp-sum"))});
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
assert.notEqual(c.cmpAfter, c.cmpSum, "選び直すと結果が変わる");
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
assert.equal(d.g3Nodes, 7, "非公開を除く 7 ノート");
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
assert.equal(e.wbCards, 7);
assert.equal(Number(e.wbX1), Number(e.wbX0) + 8, "矢印キーで 8px 動く");
assert.equal(Number(e.wbY1), 8);
assert.ok(e.wbStored && e.wbStored.includes("n"), "位置を保存");
assert.equal(e.wbX2, e.wbX1, "開き直しても位置を覚えている");
assert.equal(e.wbX3, e.wbX0, "位置を忘れるで初期配置に戻る");
assert.equal(e.gaAll, "2 / 2 件");
assert.equal(e.gaImg, 1);
assert.match(e.gaRef, /ハーブ/);
assert.equal(e.gaPdf, "1 / 2 件");
assert.equal(e.gaNone, "0 / 2 件");

console.log("views2 E2E OK（16 ページを実ブラウザで操作）");
