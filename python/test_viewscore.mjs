import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
globalThis.FzNav = require("./site_assets/fznav-core.js");
const V = require("./site_assets/viewscore.js");
const notes = [
  { id: "a.md", title: "ハーブ", fz: "1", excerpt: "ローズマリーとタイム", time: "2026-10-01 09:00:00", mtime: 300, out: 2, in: 0, size: 100 },
  { id: "b.md", title: "栽培", fz: "1a", excerpt: "水やりは控えめに", time: "2026-10-01 12:00:00", mtime: 100, out: 0, in: 3, size: 50 },
  { id: "c.md", title: "Apple", fz: "10", excerpt: "english text", time: "2026-09-20 00:00:00", mtime: 200, out: 1, in: 1, size: 10 },
  { id: "d.md", title: "日付なし", fz: "", excerpt: "", time: "", mtime: 50, out: 0, in: 0, size: 5 },
];
const ids = (l) => l.map((n) => n.id[0]).join("");
// フィルタ: 全語 AND・大文字小文字無視・除外語・番号・空は全部
assert.equal(ids(notes.filter((n) => V.matches(n, ""))), "abcd");
assert.equal(ids(notes.filter((n) => V.matches(n, "ローズ"))), "a");
assert.equal(ids(notes.filter((n) => V.matches(n, "APPLE"))), "c");
assert.equal(ids(notes.filter((n) => V.matches(n, "水やり 栽培"))), "b");
assert.equal(ids(notes.filter((n) => V.matches(n, "水やり ローズ"))), "");
assert.equal(ids(notes.filter((n) => V.matches(n, "1a"))), "b");
assert.equal(ids(notes.filter((n) => V.matches(n, "-ローズ"))), "bcd");
assert.equal(ids(notes.filter((n) => V.matches(n, "-"))), "");                 // 単独の - は語として扱う（何にも一致しない）
// 並べ替え
assert.equal(ids(V.sort(notes, "updated", -1)), "acbd");
assert.equal(ids(V.sort(notes, "updated", 1)), "dbca");
assert.equal(ids(V.sort(notes, "links_in", -1)), "bcad");                      // 同値(a,d)は題順で安定
assert.equal(ids(V.sort(notes, "fz", 1)), "abcd");                              // 番号の自然順（1 < 1a < 10）、番号なしは最後
assert.equal(ids(V.sort(notes, "fz", -1)), "cbad");                             // 降順でも番号なしは最後
assert.equal(ids(V.sort(notes, "created", -1)), "bacd");
assert.equal(ids(V.sort(notes, "created", 1)), "cabd");                         // 作成日なしは昇順でも最後
assert.equal(ids(V.sort(notes, "size", 1)), "dcba");
const before = ids(notes);
V.sort(notes, "title", 1);
assert.equal(ids(notes), before);                                               // 元の配列は変えない
// タイムライン
const tl = V.timeline(notes);
assert.deepEqual(tl.map((g) => g.date), ["2026-10-01", "2026-09-20", ""]);
assert.deepEqual(tl[0].notes.map((n) => n.id), ["b.md", "a.md"]);               // 同じ日は新しい時刻が先
console.log("viewscore OK");
