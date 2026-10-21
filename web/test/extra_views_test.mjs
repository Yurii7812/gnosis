// `\A` の追加ビュー(web/src/extra-views.js)が python/export_views2.py の VIEWS と一致していること、
// レイアウトの保存・復元で "v2" タブが残ること、知らないキーは壊さず扱えることの試験: node test/extra_views_test.mjs
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { EXTRA_VIEWS, EXTRA_KEYS, extraTitle } from "../src/extra-views.js";
import * as L from "../src/layout.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const py = fs.readFileSync(path.join(here, "..", "..", "python", "export_views2.py"), "utf-8");
const fromPy = [...py.matchAll(/^    \("([a-z0-9]+)", "([^"]+)", "/gm)].map((m) => [m[1], m[2]]);
assert.equal(fromPy.length, 23);
assert.deepEqual(EXTRA_VIEWS, fromPy, "extra-views.js と export_views2.py の VIEWS が食い違っている");
assert.equal(new Set(EXTRA_VIEWS.map((v) => v[0])).size, EXTRA_VIEWS.length, "キーの重複");
assert.ok(EXTRA_KEYS.has("hypotheses") && !EXTRA_KEYS.has("nope"));
assert.equal(extraTitle("tree"), "階層ツリー");
assert.equal(extraTitle("zzz"), "zzz");

let lay = L.newLayout();
const pane = L.panes(lay)[0].id;
lay = L.openTab(lay, pane, L.newTab("v2", { title: extraTitle("tree"), params: { key: "tree" } }));
lay = L.openTab(lay, pane, L.newTab("v2", { title: extraTitle("kanban"), params: { key: "kanban" } }));
const before = L.panes(lay)[0].tabs.length;
lay = L.openTab(lay, pane, L.newTab("v2", { title: extraTitle("tree"), params: { key: "tree" } }));
assert.equal(L.panes(lay)[0].tabs.length, before, "同じキーの追加ビューは重ねない");
const back = L.restore(L.serialize(lay));
assert.deepEqual(L.panes(back)[0].tabs.map((t) => [t.kind, t.params.key]), [["vim", undefined], ["v2", "tree"], ["v2", "kanban"]]);
console.log("extra-views OK");
