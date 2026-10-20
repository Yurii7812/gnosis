// fznav-core.js の試験。Python（folgezettel.py / gnosis_graph.py）と同じ結果になることを言語間で照合する。
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const N = require("./site_assets/fznav-core.js");
const here = path.dirname(fileURLToPath(import.meta.url));

const IDS = ["1", "1a", "1a1", "1a2", "1b", "1c", "2", "10", "2a", "11a1", "1aa", "1z", "1aa1", "3a1", "9", "1a10", "1a9", "10a", "1ab"];
const py = JSON.parse(execFileSync("python3", ["-I", "-c", `
import json, sys
sys.path.insert(0, ${JSON.stringify(here)})
import folgezettel as fz
ids = json.loads(sys.argv[1])
print(json.dumps({"sorted": sorted(ids, key=fz.natural_key), "parents": {i: fz.parent_id(i) for i in ids}}))
`, JSON.stringify(IDS)], { encoding: "utf8" }));

// 1. 自然順と親の番号が Python と一致
assert.deepEqual([...IDS].sort(N.compare), py.sorted);
for (const id of IDS) assert.equal(N.parentId(id), py.parents[id], id);
// 順序の性質（反対称・推移）
for (const a of IDS) for (const b of IDS) assert.equal(Math.sign(N.compare(a, b)) + Math.sign(N.compare(b, a)), 0);

// 2. ナビの意味
const items = ["1", "1a", "1a1", "1a2", "1b", "1c", "2", "3a1"].map((id) => ({ id, files: [id + ".md"], title: "T" + id }));
const nav = N.build(items);
const i1a = nav.info("1a");
assert.equal(i1a.parent.id, "1");
assert.deepEqual(i1a.siblings.map((s) => s.id), ["1a", "1b", "1c"]);
assert.equal(i1a.next_sibling.id, "1b");                    // 1a → 1b は兄弟（親子ではない）
assert.equal(i1a.prev_sibling, null);
assert.deepEqual(i1a.children.map((c) => c.id), ["1a1", "1a2"]);
assert.equal(i1a.first_child.id, "1a1");
assert.equal(i1a.next_in_order.id, "1a1");                  // 自然順の次は子（1a → 1a1 → 1a2 → 1b）
assert.equal(nav.info("1a2").next_in_order.id, "1b");
assert.equal(nav.info("1b").prev_in_order.id, "1a2");
assert.equal(nav.info("1c").next_in_order.id, "2");
assert.equal(nav.info("1").next_sibling.id, "2");               // 最上位どうしの兄弟
assert.equal(nav.info("2").next_sibling, null);                // 3 は無い（3a1 の祖先は「空き」で、兄弟には数えない）
// 空き番号: 存在しない番号は exists=false（勝手に作らない）。抜けた祖先（3a, 3）は存在しない親として出る
const gone = nav.info("9");
assert.equal(gone.exists, false);
const b = nav.info("3a1");
assert.deepEqual(b.breadcrumbs.map((c) => [c.id, c.exists]), [["3", false], ["3a", false]]);
assert.equal(b.parent.exists, false);
// 木: 抜けた祖先も「空き」の節として出し、枝を落とさない
const tree = nav.tree();
assert.deepEqual(tree.map((t) => t.id), ["1", "2", "3"]);
const t3 = tree[2];
assert.equal(t3.exists, false);
assert.equal(t3.children[0].id, "3a");
assert.equal(t3.children[0].children[0].id, "3a1");
assert.equal(t3.children[0].children[0].exists, true);
assert.deepEqual(tree[0].children.map((c) => c.id), ["1a", "1b", "1c"]);

// 3. トレイル（閲覧の履歴）は番号の親子と別物
const tr = N.Trail();
["1", "1a", "1b"].forEach((x) => tr.visit(x));               // 1 → 1a → 1b（枝に入ってから兄弟へ）
assert.deepEqual(tr.list(), ["1", "1a", "1b"]);
assert.equal(nav.info("1b").parent.id, "1");                // 履歴では 1a の次だが、構造上の親は 1
assert.equal(tr.back(), "1a");
assert.equal(tr.back(), "1");
assert.equal(tr.back(), "1");
assert.equal(tr.forward(), "1a");
tr.visit("2");                                              // 戻ってから別へ行くと先の履歴は捨てる
assert.deepEqual(tr.list(), ["1", "1a", "2"]);
console.log("fznav OK (" + IDS.length + " 件の番号を Python と照合)");
