// graphcore.js（グラフ表示の核）の試験。node で実行: node python/test_graphcore.mjs
import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const C = require("./site_assets/graphcore.js");

const nodes = ["a", "b", "c", "d", "e", "z"].map((id) => ({ id, title: id.toUpperCase() }));
const edges = [
  { s: "a", d: "b", k: "parent_branch" }, { s: "b", d: "c", k: "link" }, { s: "c", d: "d", k: "link" },
  { s: "d", d: "e", k: "context" }, { s: "a", d: "c", k: "related" },
];
const data = { nodes, edges };
const ids = (g) => g.nodes.map((n) => n.id).sort().join("");

// 深さ（辺の向きは無視）
assert.equal(ids(C.subgraph(data, "a", 0, [])), "a");
assert.equal(ids(C.subgraph(data, "a", 1, [])), "abc");
assert.equal(ids(C.subgraph(data, "a", 2, [])), "abcd");
assert.equal(ids(C.subgraph(data, "e", 1, [])), "de");          // 向きを無視して逆にも辿る
assert.equal(ids(C.subgraph(data, "a", 9, [])), "abcde");        // 孤立ノード z は含まない
assert.equal(C.subgraph(data, "a", 1, []).nodes.find((n) => n.id === "c").depth, 1);
// 種類で絞る（経路が切れるとそこまで）
assert.equal(ids(C.subgraph(data, "a", 9, ["parent_branch"])), "ab");
assert.equal(ids(C.subgraph(data, "a", 9, ["parent_branch", "link"])), "abcd");
// 種類を潰さない: a-c は related の辺として残る
assert.ok(C.subgraph(data, "a", 1, []).edges.some((e) => e.s === "a" && e.d === "c" && e.k === "related"));
assert.equal(C.subgraph(data, "a", 1, ["link"]).edges.length, 0);          // a から出る link は無い → a 1 ノードだけ
assert.equal(ids(C.subgraph(data, "a", 1, ["link"])), "a");
const lr = C.subgraph(data, "a", 1, ["link", "related"]);                  // related(a-c) だけが 1 本
assert.equal(ids(lr), "ac");
assert.deepEqual(lr.edges.map((e) => e.k), ["related"]);
// 存在しない中心
assert.equal(C.subgraph(data, "nope", 2, []).nodes.length, 0);
// 孤立を除く
assert.equal(ids(C.withoutIsolated(data)), "abcde");

// 配置: 決定的・範囲内・有限・重ならない
const p1 = C.layout(nodes, edges, 900, 640, 300, "a");
const p2 = C.layout(nodes, edges, 900, 640, 300, "a");
assert.deepEqual(p1, p2);
for (const id of Object.keys(p1)) {
  const [x, y] = p1[id];
  assert.ok(Number.isFinite(x) && Number.isFinite(y), id);
  assert.ok(x >= 0 && x <= 900 - 100 && y >= 0 && y <= 640, id);   // 右端はラベル用に空ける
}
assert.deepEqual(p1.a, [450, 320]);                                          // 中心ノートは真ん中
const keys = Object.keys(p1);
let minD = Infinity;
for (let i = 0; i < keys.length; i++) for (let j = i + 1; j < keys.length; j++) {
  minD = Math.min(minD, Math.hypot(p1[keys[i]][0] - p1[keys[j]][0], p1[keys[i]][1] - p1[keys[j]][1]));
}
assert.ok(minD > 15, "ノードが重なっている: " + minD);
// 大きめでも速い（1000 ノード・3000 辺・120 反復）
const big = Array.from({ length: 1000 }, (_, i) => ({ id: "n" + i, title: "t" + i }));
const bigE = Array.from({ length: 3000 }, (_, i) => ({ s: "n" + (i % 1000), d: "n" + ((i * 7 + 3) % 1000), k: "link" }));
const t0 = Date.now();
const pb = C.layout(big, bigE, 900, 640, 120);
const ms = Date.now() - t0;
assert.equal(Object.keys(pb).length, 1000);
console.log("graphcore OK (1000 ノード配置 " + ms + " ms)");
