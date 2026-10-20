// layout.js（タブ・分割のレイアウト）の試験: node test/layout_test.mjs
import assert from "node:assert/strict";
import * as L from "../src/layout.js";

const ids = (lay) => L.panes(lay).map((p) => p.tabs.map((t) => t.kind + (t.params.n ? t.params.n : "")).join(","));

// 新しいレイアウト: Vim タブが 1 つだけ。閉じられない
let lay = L.newLayout();
const vim = L.vimTab(lay);
assert.equal(vim.kind, "vim");
assert.equal(L.closeTab(lay, vim.id, { force: true }).closed, null, "Vim タブは閉じられない");

// タブを開く。同じ種類・引数は重ねず前に出す。別の引数なら別のタブ
const paneId = L.panes(lay)[0].id;
lay = L.openTab(lay, paneId, L.newTab("cards"));
lay = L.openTab(lay, paneId, L.newTab("graph", { params: { n: 1 } }));
assert.deepEqual(ids(lay), ["vim,cards,graph1"]);
const active1 = L.findPane(lay, paneId).active;
lay = L.openTab(lay, paneId, L.newTab("cards"));
assert.equal(L.panes(lay)[0].tabs.length, 3, "同じ cards は重ねない");
assert.equal(L.findTab(lay, L.panes(lay)[0].active).tab.kind, "cards", "既存を前に出す");
lay = L.openTab(lay, paneId, L.newTab("graph", { params: { n: 2 } }));
assert.deepEqual(ids(lay), ["vim,cards,graph1,graph2"]);

// 閉じる: 隣のタブが前に出る。閉じたものは再開用に返る
const g2 = L.panes(lay)[0].tabs[3];
let r = L.closeTab(lay, g2.id);
assert.equal(r.closed.tab.id, g2.id);
assert.equal(r.closed.index, 3);
lay = r.layout;
assert.equal(L.findPane(lay, paneId).active, L.panes(lay)[0].tabs[2].id, "最後のタブを閉じると 1 つ前が前に出る");
const stack = L.createClosedStack();
stack.push(r.closed);
stack.push({ tab: vim });                                   // Vim は積まない
assert.equal(stack.size(), 1);
lay = L.reopen(lay, stack.pop(), paneId);
assert.deepEqual(ids(lay), ["vim,cards,graph1,graph2"], "閉じたタブを再開");
assert.notEqual(L.panes(lay)[0].tabs[3].id, g2.id, "再開すると新しい id");

// 固定: 閉じられない（force のときだけ）。並べ替えでは先頭側にまとまる
const cards = L.panes(lay)[0].tabs[1];
lay = L.setPinned(lay, cards.id, true);
assert.equal(L.closeTab(lay, cards.id).closed, null);
assert.ok(L.closeTab(lay, cards.id, { force: true }).closed);
lay = L.moveTab(lay, L.panes(lay)[0].tabs[3].id, paneId, 0);
assert.equal(L.panes(lay)[0].tabs[0].pinned, true, "固定のタブは先頭側");
assert.equal(L.panes(lay)[0].tabs.length, 4);

// 分割: 右へ。タブを新しいペインへ移す。空になった側は畳む
const gNode = L.panes(lay)[0].tabs.find((t) => t.kind === "graph" && t.params.n === 1);
lay = L.splitWithTab(lay, paneId, "row", gNode.id);
assert.equal(lay.type, "split");
assert.equal(lay.dir, "row");
assert.equal(lay.ratio, 0.5);
assert.equal(L.panes(lay).length, 2);
assert.equal(L.panes(lay)[1].tabs[0].id, gNode.id);
assert.equal(L.panes(lay)[0].tabs.some((t) => t.id === gNode.id), false);
// 2 つめを下へ分割（入れ子）
const g2n = L.panes(lay)[0].tabs.find((t) => t.kind === "graph" && t.params.n === 2);
lay = L.splitWithTab(lay, L.panes(lay)[1].id, "col", g2n.id);
assert.equal(L.panes(lay).length, 3);
assert.equal(lay.b.type, "split");
// 1 つしかないタブを自分自身と分割しても変わらない
const only = L.panes(lay)[2];
assert.equal(L.splitWithTab(lay, only.id, "row", only.tabs[0].id), lay);
// リサイズ（範囲に収める）
lay = L.setRatio(lay, lay.id, 0.3);
assert.equal(lay.ratio, 0.3);
assert.equal(L.setRatio(lay, lay.id, 5).ratio, 0.9);
assert.equal(L.setRatio(lay, lay.id, -1).ratio, 0.1);

// ペインの最後のタブを閉じると、そのペインは畳まれて兄弟が広がる
const lastTab = L.panes(lay)[2].tabs[0];
r = L.closeTab(lay, lastTab.id);
assert.equal(L.panes(r.layout).length, 2);
assert.equal(r.layout.b.type, "tabs");

// 分割の解除: ペインのタブを隣へ寄せて畳む
const p1 = L.panes(lay)[1];
const un = L.unsplit(lay, p1.id);
assert.equal(L.panes(un).length, 2);
assert.equal(L.panes(un).flatMap((p) => p.tabs).length, L.panes(lay).flatMap((p) => p.tabs).length, "タブは失われない");
assert.equal(L.vimTab(un).kind, "vim");

// Vim タブを別のペインへ移せる（閉じられないだけ）。Vim が 1 つのまま
const lay2 = L.moveTab(lay, vim.id, L.panes(lay)[1].id);
assert.equal(L.panes(lay2).flatMap((p) => p.tabs).filter((t) => t.kind === "vim").length, 1);
assert.equal(L.findTab(lay2, vim.id).pane.id, L.panes(lay)[1].id);

// 元の木は変えない（不変）
const snap = JSON.stringify(lay);
L.openTab(lay, paneId, L.newTab("table")); L.closeTab(lay, gNode.id, { force: true }); L.setRatio(lay, lay.id, 0.7);
assert.equal(JSON.stringify(lay), snap);

// 保存・復元: 往復で同じ。壊れた入力・Vim タブが無い／複数の入力は正しく直す
const back = L.restore(L.serialize(lay));
assert.deepEqual(ids(back), ids(lay));
assert.equal(back.ratio, 0.3);
assert.equal(L.restore("{壊れた").type, "tabs");
assert.equal(L.vimTab(L.restore("{壊れた")).kind, "vim");
assert.equal(L.vimTab(L.restore({ type: "tabs", id: "p9", tabs: [{ id: "t9", kind: "cards" }], active: "t9" })).kind, "vim", "Vim タブが無ければ足す");
const dup = L.restore({ type: "split", dir: "row", ratio: 0.5, id: "s1",
  a: { type: "tabs", id: "p1", tabs: [{ id: "t1", kind: "vim" }], active: "t1" }, b: { type: "tabs", id: "p2", tabs: [{ id: "t2", kind: "vim" }, { id: "t3", kind: "cards" }], active: "t2" } });
assert.equal(L.panes(dup).flatMap((p) => p.tabs).filter((t) => t.kind === "vim").length, 1, "Vim タブは 1 つに");
const unknown = L.restore({ type: "tabs", id: "p1", tabs: [{ id: "t1", kind: "vim" }, { id: "t2", kind: "evil-kind" }], active: "t2" });
assert.deepEqual(unknown.tabs.map((t) => t.kind), ["vim"], "未知の種類は捨てる");
assert.equal(unknown.active, "t1");
const fresh = L.openTab(back, L.panes(back)[0].id, L.newTab("table"));
const allIds = L.panes(fresh).flatMap((p) => p.tabs.map((t) => t.id));
assert.equal(new Set(allIds).size, allIds.length, "復元後に作る id が重ならない");
// 閉じたタブの保存
const st2 = L.createClosedStack(2);
for (const k of ["cards", "graph", "table"]) st2.push({ tab: L.newTab(k) });
assert.equal(st2.size(), 2);
const st3 = L.createClosedStack();
st3.load(JSON.parse(JSON.stringify(st2.toJSON())));
assert.equal(st3.pop().tab.kind, "table");
console.log("layout OK");
