// 書き出した静的サイトのビュー（Folgezettel ナビ・グラフ・検索・曼荼羅）を、本物のブラウザ（Electron の Chromium、xvfb）で
// file:// から開き、ボタン・キー・クリックを実際に操作して確かめる。vault は一時フォルダ（本物には触らない）。
//   node test/site_views_e2e.mjs
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
const tmp = fs.mkdtempSync(path.join(base, "site-e2e-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
const electron = path.join(repo, "web", "node_modules", "electron", "dist", "electron");
if (!fs.existsSync(electron) || spawnSync("which", ["xvfb-run"]).status !== 0) { console.error("SKIP: electron か xvfb-run が無いので省略"); process.exit(0); }

// --- テスト用 vault ---
const v = path.join(tmp, "vault");
fs.mkdirSync(v);
const note = (name, title, body, fz = "", extra = "") => fs.writeFileSync(path.join(v, name),
  `---\ntime: 2026-01-01 00:00:00\ntitle: ${title}\n${fz ? `folgezettel: "${fz}"\n` : ""}${extra}---\n\n# ${title}\n\n${body}\n`);
note("n1.md", "ハーブ", "BranchGroup:\n[栽培](n1a.md)\n[利用](n1b.md)\n[保存](n1c.md)\n\n本文", "1");
note("n1a.md", "栽培", "ParentBranch:\n[ハーブ](n1.md)\n\nローズマリーは乾燥気味に", "1a");
note("n1a1.md", "水やり", "ParentBranch:\n[栽培](n1a.md)\n\n本文", "1a1");
note("n1a2.md", "土", "ParentBranch:\n[栽培](n1a.md)\n\n本文", "1a2");
note("n1b.md", "利用", "ParentBranch:\n[ハーブ](n1.md)\n\n本文", "1b");
note("n1c.md", "保存", "ParentBranch:\n[ハーブ](n1.md)\n\n本文", "1c");
note("n2.md", "料理", "[ハーブ](n1.md) を使う", "2");
note("n3a1.md", "孤児の枝", "親(3a, 3)のノートが無い", "3a1");
note("secret.md", "秘密", "TOPSECRET", "", "private: true\n");
fs.writeFileSync(path.join(v, "m.md"), execFileSync("python3", ["-I", "-c", `
import sys; sys.path.insert(0, ${JSON.stringify(path.join(repo, "python"))})
import mandala; print(mandala.new_text("主題", ["a", "[詳細](n1.md)"]), end="")`], { encoding: "utf8" }));
const site = path.join(tmp, "site");
execFileSync("python3", [path.join(repo, "python", "export_site.py"), v, site], { encoding: "utf8" });

function run(name, scenarioSrc) {
  const f = path.join(tmp, name + ".cjs");
  fs.writeFileSync(f, scenarioSrc);
  const r = spawnSync("xvfb-run", ["-a", electron, path.join(here, "site_views_main.cjs"), site, f],
    { encoding: "utf8", timeout: 120000, env: { ...process.env, ELECTRON_DISABLE_SANDBOX: "1" } });
  const line = (r.stdout || "").split("\n").find((l) => l.startsWith("RESULT "));
  assert.ok(line, `${name}: 結果が出ない\n${r.stdout}\n${r.stderr}`);
  const out = JSON.parse(line.slice(7));
  assert.ok(out.ok, `${name}: ${out.error}`);
  return out.result;
}
const text = (sel) => `document.querySelector(${JSON.stringify(sel)}).textContent`;

// 1. Folgezettel ナビ: 深掘り・兄弟・親・履歴・空き番号・プレビュー
const nav = run("fznav", `
module.exports = async (p) => {
  const cur = () => p.eval(${JSON.stringify(text("#cur"))});
  const out = {};
  await p.open("fznav.html#id=1");
  out.start = await cur();
  await p.key("Down");  out.down1 = await cur();        // 1 → 1a
  await p.key("Down");  out.down2 = await cur();        // 1a → 1a1
  await p.key("Right"); out.sib = await cur();          // 1a1 → 1a2（兄弟）
  await p.key("Up");    out.up = await cur();           // 1a2 → 1a（親）
  await p.key("Right"); out.sibOfParent = await cur();  // 1a → 1b（兄弟。子ではない）
  out.trail = await p.eval(${JSON.stringify(text("#trail"))});
  out.parentOf1b = await p.eval(${JSON.stringify(text("#parent"))});
  await p.key("Left", { alt: true }); out.back = await cur();   // 履歴を戻る → 1a
  await p.key("Right", { alt: true }); out.fwd = await cur();   // 進む → 1b
  await p.key("]");  out.onext = await cur();           // 番号順の次: 1b → 1c
  await p.key("[");  await p.key("[");  out.oprev = await cur();  // 1c → 1b → 1a2? （1b の前は 1a2）
  await p.click("#b-first"); out.first = await cur();
  await p.click("#b-last");  out.last = await cur();
  out.hash = await p.eval("location.hash");
  // プレビュー（iframe）と「ノートを開く」
  await p.open("fznav.html#id=1a");
  out.pv = await p.eval("document.getElementById('pv').getAttribute('src')");
  out.openHref = await p.eval("document.getElementById('open').getAttribute('href')");
  // 空き番号: 3a1 の祖先 3a・3 は存在しない番号として出る。選んでも勝手にノートは作らない
  await p.open("fznav.html#id=3a1");
  out.gapCrumbs = await p.eval("Array.from(document.querySelectorAll('#crumbs .chip')).map(e => e.textContent + (e.classList.contains('gap') ? '*' : ''))");
  await p.eval("Array.from(document.querySelectorAll('#crumbs .chip')).find(e => e.textContent.startsWith('3a')).click()");
  await new Promise(r => setTimeout(r, 150));
  out.gapCur = await cur();
  out.gapClass = await p.eval("document.getElementById('cur').className");
  out.gapPreview = await p.eval("document.getElementById('pv').hasAttribute('src')");
  // ツリーの開閉
  await p.open("fznav.html#id=2");
  await p.click("#b-allclose");
  out.closedRows = await p.eval("document.querySelectorAll('#tree .tr').length");
  await p.click("#b-allopen");
  out.openRows = await p.eval("document.querySelectorAll('#tree .tr').length");
  return out;
};`);
assert.match(nav.start, /^1  ハーブ/);
assert.match(nav.down1, /^1a  栽培/);
assert.match(nav.down2, /^1a1  水やり/);
assert.match(nav.sib, /^1a2  土/);
assert.match(nav.up, /^1a  栽培/);                       // 親へ
assert.match(nav.sibOfParent, /^1b  利用/);               // 1a → 1b は兄弟
assert.match(nav.trail, /1.*→.*1a.*→.*1a1.*→.*1a2.*→.*1a.*→.*1b/);   // たどった順（履歴）には実際の経路が残る
assert.match(nav.parentOf1b, /^1 ハーブ$/);               // 構造上の親は 1（履歴の直前の 1a ではない）
assert.match(nav.back, /^1a  栽培/);
assert.match(nav.fwd, /^1b  利用/);
assert.match(nav.onext, /^1c  保存/);
assert.match(nav.oprev, /^1a2  土/);
assert.match(nav.first, /^1  ハーブ/);
assert.match(nav.last, /^3a1  孤児の枝/);
assert.equal(nav.hash, "#id=3a1");
assert.equal(nav.pv, "n1a.html");
assert.equal(nav.openHref, "n1a.html");
assert.deepEqual(nav.gapCrumbs, ["3（空き）*", "3a（空き）*"]);   // 抜けた祖先は「空き」として、破線（gap）で区別される
assert.match(nav.gapCur, /^3a  \（この番号のノートはありません）/);
assert.equal(nav.gapClass, "gap");
assert.equal(nav.gapPreview, false);
assert.ok(nav.openRows > nav.closedRows, `ツリー開閉 ${nav.closedRows} → ${nav.openRows}`);
assert.ok(!JSON.stringify(nav).includes("秘密"));

// 2. グラフ: 全体・ローカル（深さ）・種類の絞り込み・非公開は出ない
const gr = run("graph", `
module.exports = async (p) => {
  const out = {};
  await p.open("graph.html");
  out.allNodes = await p.eval("document.querySelectorAll('svg#g circle').length");
  out.allEdges = await p.eval("document.querySelectorAll('svg#g line').length");
  out.info = await p.eval(${JSON.stringify(text("#info"))});
  await p.open("graph.html#n=n1a.md&depth=1");
  out.d1 = await p.eval("document.querySelectorAll('svg#g circle').length");
  await p.open("graph.html#n=n1a.md&depth=2");
  out.d2 = await p.eval("document.querySelectorAll('svg#g circle').length");
  out.center = await p.eval("document.querySelector('svg#g circle[fill=\\"#e0a800\\"]') ? 1 : 0");
  out.labels = await p.eval("Array.from(document.querySelectorAll('svg#g text')).map(t => t.textContent).join('|')");
  // 種類を全部外すと辺が 0
  await p.eval("Array.from(document.querySelectorAll('#kinds input')).forEach(c => { if (c.checked) c.click(); })");
  out.noKinds = await p.eval("document.querySelectorAll('svg#g line').length");
  if (process.env.GNOSIS_E2E_SHOT_DIR) await p.shot(process.env.GNOSIS_E2E_SHOT_DIR + "/graph.png");   // 目視確認用（指定したときだけ）
  return out;
};`);
assert.ok(gr.allNodes >= 8, "全体のノード数 " + gr.allNodes);
assert.ok(gr.allEdges > gr.allNodes / 2);
assert.ok(gr.d1 >= 2 && gr.d2 > gr.d1, `深さ 1→2 で広がる ${gr.d1} → ${gr.d2}`);
assert.equal(gr.center, 1);
assert.ok(!gr.labels.includes("秘密"), "非公開ノートがグラフに出ている");
assert.equal(gr.noKinds, 0);

// 3. 検索（file:// で動く）と、非公開が出ない
const se = run("search", `
module.exports = async (p) => {
  await p.open("search.html#q=" + encodeURIComponent("ローズ"));
  const hit = await p.eval("Array.from(document.querySelectorAll('#r a')).map(a => a.textContent + '>' + a.getAttribute('href'))");
  await p.open("search.html#q=" + encodeURIComponent("TOPSECRET"));
  const secret = await p.eval("document.querySelectorAll('#r li').length");
  return { hit, secret };
};`);
assert.deepEqual(se.hit, ["栽培>n1a.html"]);
assert.equal(se.secret, 0);

// 4. 曼荼羅: 81 マス・マスのリンク先が実ノート
const md = run("mandala", `
module.exports = async (p) => {
  await p.open("m.html");
  return { cells: await p.eval("document.querySelectorAll('table.mandala td').length"),
           rows: await p.eval("document.querySelectorAll('table.mandala tr').length"),
           links: await p.eval("Array.from(document.querySelectorAll('table.mandala a')).map(a => a.getAttribute('href'))"),
           theme: await p.eval("document.querySelector('td.theme').textContent") };
};`);
assert.equal(md.cells, 81);
assert.equal(md.rows, 9);
assert.deepEqual([...new Set(md.links)], ["n1.html"]);
assert.equal(md.theme, "主題");
// 5. カード・テーブル・タイムライン: 絞り込み・並べ替え・ピン留め（このブラウザだけ）・非公開は出ない
const cv = run("views", `
module.exports = async (p) => {
  const out = {};
  const titles = () => p.eval("Array.from(document.querySelectorAll('#cards h3')).map(e => e.textContent)");
  await p.open("cards.html");
  out.cards = await titles();
  out.count = await p.eval("document.getElementById('count').textContent");
  await p.eval("(function(){var q=document.getElementById('q');q.value='ローズ';q.dispatchEvent(new Event('input'))})()");
  out.filtered = await titles();
  await p.eval("(function(){var q=document.getElementById('q');q.value='-ローズ';q.dispatchEvent(new Event('input'))})()");
  out.excluded = await titles();
  await p.eval("(function(){var q=document.getElementById('q');q.value='';q.dispatchEvent(new Event('input'));var s=document.getElementById('sort');s.value='title';s.dispatchEvent(new Event('change'))})()");
  await p.click("#dir");            // 降順 → 昇順
  out.byTitleAsc = await titles();
  // ピン留め: 最後のカードを押すと先頭へ。ページを開き直しても覚えている
  await p.eval("(function(){var b=document.querySelectorAll('#cards .pin');b[b.length-1].click()})()");
  out.pinned = (await titles())[0];
  out.pinnedClass = await p.eval("document.querySelectorAll('#cards .card.pinned').length");
  await p.open("cards.html");
  out.afterReload = (await titles())[0];
  await p.open("table.html");
  const col = (i) => p.eval("Array.from(document.querySelectorAll('#tbl tbody tr')).map(r => r.children[" + i + "].textContent)");
  out.tableTitles = await col(1);
  await p.eval("Array.from(document.querySelectorAll('#tbl th button')).find(b => b.textContent.startsWith('番号')).click()");
  out.byFz = await col(0);
  await p.eval("Array.from(document.querySelectorAll('#tbl th button')).find(b => b.textContent.startsWith('番号')).click()");
  out.byFzDesc = await col(0);
  out.ariaSort = await p.eval("document.querySelector('#tbl th[aria-sort=descending]') ? 1 : 0");
  await p.open("timeline.html");
  out.groups = await p.eval("Array.from(document.querySelectorAll('#tl h2')).map(e => e.textContent)");
  out.tlLinks = await p.eval("document.querySelectorAll('#tl a').length");
  out.secretAnywhere = await p.eval("document.documentElement.innerHTML.includes('秘密')");
  return out;
};`);
assert.ok(!cv.cards.includes("秘密"));
assert.equal(cv.cards.length, 9);                       // 通常ノート 8 件 + 曼荼羅 1 件（非公開の「秘密」は含まない）
assert.match(cv.count, /^9 \/ 9/);
assert.deepEqual(cv.filtered, ["栽培"]);
assert.ok(!cv.excluded.includes("栽培") && cv.excluded.length === 8);
assert.deepEqual(cv.byTitleAsc, [...cv.byTitleAsc].sort((a, b) => a.localeCompare(b, "ja")));
assert.equal(cv.pinned, cv.byTitleAsc[cv.byTitleAsc.length - 1]);          // 最後のカードが先頭に来る
assert.equal(cv.pinnedClass, 1);
assert.equal(cv.afterReload, cv.pinned);                                   // 開き直しても覚えている（localStorage。このブラウザだけ）
assert.equal(cv.tableTitles.length, 9);
assert.deepEqual(cv.byFz.slice(0, 7), ["1", "1a", "1a1", "1a2", "1b", "1c", "2"]);   // 番号の自然順
assert.equal(cv.byFz[7], "3a1");
assert.equal(cv.byFz[8], "");                                              // 番号の無い曼荼羅は最後
assert.equal(cv.ariaSort, 1);
assert.equal(cv.byFzDesc[8], "");                                          // 降順でも番号なしは最後
assert.deepEqual(cv.byFzDesc.slice(0, 2), ["3a1", "2"]);
assert.ok(cv.groups.includes("2026-01-01"));
assert.equal(cv.tlLinks, 9);
assert.equal(cv.secretAnywhere, false);
// 6. ブリッジ（bridge.js）: `\A` に埋め込まれた iframe（name="gnosis:open"）の中で、ノートのページへのリンクは親へ知らせて移動を止める。
//    ビューどうしのリンク・読み取り専用（name="gnosis:read"）・単独で開いたときは、ふつうに移動する。
fs.writeFileSync(path.join(site, "wrap.html"), `<!doctype html><html><body>
<iframe id="o" name="gnosis:open" src="fznav.html#id=1a" width="800" height="500"></iframe>
<iframe id="r" name="gnosis:read" src="fznav.html#id=1a" width="800" height="500"></iframe>
<script>window.__msgs = []; window.addEventListener("message", function (e) { window.__msgs.push(e.data); });</script>
</body></html>`);
const br = run("bridge", `
module.exports = async (p) => {
  await p.open("wrap.html");
  // ページの中で実行する（この関数は文字列にして渡す。外の変数は使えない）
  const inPage = async () => {
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    await sleep(1200);
    const doc = (id) => document.getElementById(id).contentDocument;
    const out = {};
    doc("o").getElementById("open").click();                       // 埋め込み（open）: ノートのリンクは親へ。iframe は動かない
    await sleep(300);
    out.msgs = JSON.parse(JSON.stringify(window.__msgs));
    out.openStays = document.getElementById("o").contentWindow.location.pathname.endsWith("fznav.html");
    const viewLink = [...doc("o").querySelectorAll("a")].find((a) => a.getAttribute("href") === "index.html");
    viewLink.click();                                              // ビューどうしのリンクは普通に移動（親へは知らせない）
    await sleep(800);
    out.viewNavigated = document.getElementById("o").contentWindow.location.pathname.endsWith("index.html");
    out.msgsAfterView = window.__msgs.length;
    const before = window.__msgs.length;
    doc("r").getElementById("open").click();                       // 読み取り専用（read）: ノートのリンクも普通に移動
    await sleep(800);
    out.readNavigated = document.getElementById("r").contentWindow.location.pathname.endsWith("n1a.html");
    out.readNoMsg = window.__msgs.length === before;
    return out;
  };
  return await p.eval("(" + inPage.toString() + ")()");
};`);
assert.equal(br.msgs.length, 1);
assert.equal(br.msgs[0].gnosis, "open");
assert.match(br.msgs[0].url, /^file:\/\/.*\/n1a\.html$/);
assert.equal(br.openStays, true);
assert.equal(br.viewNavigated, true);
assert.equal(br.msgsAfterView, 1);
assert.equal(br.readNavigated, true);
assert.equal(br.readNoMsg, true);
console.log("site_views E2E OK (ナビ・グラフ・検索・曼荼羅・カード・テーブル・タイムライン・`\\A` 埋め込み用のブリッジを実ブラウザで操作)");
