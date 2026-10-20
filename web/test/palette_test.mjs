import assert from "node:assert/strict";
import { score, rank } from "../src/palette-core.js";

assert.equal(score("", "なんでも"), 0);
assert.equal(score("xyz", "abc"), -1);
assert.ok(score("graph", "グラフ graph") > 0);
assert.ok(score("cs", "Cards") > 0);                                           // 飛び飛びでも
assert.ok(score("car", "Cards") > score("crs", "Cards"), "連続のほうが高い");
assert.ok(score("g", "Graph") > score("g", "Big graph things"), "語頭・短いほうが高い");

const items = [
  { label: "カードを開く", keywords: "cards masonry", group: "ビュー" },
  { label: "グラフを開く", keywords: "graph", group: "ビュー" },
  { label: "GUI 編集モード", keywords: "edit gui", group: "モード" },
  { label: "閲覧専用モード", keywords: "view readonly", group: "モード" },
  { label: ":GnosisCaptureImport", keywords: "vim スマホ 取り込み", group: "Vim" },
  { label: ":GnosisExportSite", keywords: "vim html 書き出し", group: "Vim" },
  { label: "タブを閉じる", keywords: "close tab", group: "タブ" },
];
const names = (q) => rank(items, q).map((i) => i.label);
assert.equal(names("").length, 7, "空のクエリは全部（元の順）");
assert.equal(names("")[0], "カードを開く");
assert.deepEqual(names("graph"), ["グラフを開く"]);                              // キーワードにも当たる
assert.deepEqual(names("cards"), ["カードを開く"]);
assert.equal(names("export")[0], ":GnosisExportSite");
assert.equal(names("スマホ")[0], ":GnosisCaptureImport");                        // 日本語のキーワード
assert.deepEqual(names("モード").sort(), ["GUI 編集モード", "閲覧専用モード"].sort());
assert.deepEqual(names("vim export"), [":GnosisExportSite"], "空白区切りの語はすべて一致が必要");
assert.deepEqual(names("zzz"), []);
assert.ok(names("tab")[0] === "タブを閉じる");
assert.equal(rank(items, "", 3).length, 3, "件数の上限");
// ラベルに当たるものがキーワードだけに当たるものより先
const mixed = [{ label: "別の機能", keywords: "graph" }, { label: "graph view", keywords: "" }];
assert.equal(rank(mixed, "graph")[0].label, "graph view");
console.log("palette OK");
