// `\A` の曼荼羅・キャンバスの保存形式の純関数の試験（Electron 不要）。
//   曼荼羅: 表の読み書きが python/mandala.py と同じ形・表の外の本文を変えない・副題の対・マスごとの 3-way
//   キャンバス: gnosis-canvas のブロックとその上のリンクの行だけを書き直す・相対パス
import assert from "node:assert/strict";
import { parseGrid, renderTable, replaceTable, mirrorOf, mergeGrids, cellsOf, relLink, cellLink, unlinkText } from "../src/mandala.js";
import { parseCanvas, writeCanvas } from "../src/canvas.js";
import { fold, rank, readings } from "../src/palette-core.js";

const empty = () => Array.from({ length: 9 }, () => Array(9).fill(""));

// ---- 曼荼羅 ----
{
  const g = empty();
  g[4][4] = "旅行"; g[3][3] = "準備"; g[1][1] = "準備"; g[0][0] = "a|b";
  const table = renderTable(g);
  assert.equal(table[0], "| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |");
  assert.equal(table[1], "|---|---|---|---|---|---|---|---|---|");
  assert.equal(table.length, 11);
  const text = "---\ntitle: 旅行\nmandala: true\n---\n\n# 旅行\n\n前の文。\n\n" + table.join("\n") + "\n\n後ろの文。\n";
  assert.deepEqual(parseGrid(text), g);                               // 往復で同じ（| のエスケープも）
  const g2 = parseGrid(text); g2[3][4] = "持ち物"; g2[1][4] = "持ち物";
  const t2 = replaceTable(text, g2);
  assert.ok(t2.startsWith("---\ntitle: 旅行\nmandala: true\n---\n\n# 旅行\n\n前の文。\n\n"));
  assert.ok(t2.endsWith("\n\n後ろの文。\n"));                          // 表の外は変えない
  assert.equal(parseGrid(t2)[3][4], "持ち物");
  // 表が無いノートには H1 の下に作る
  const t3 = replaceTable("---\ntitle: x\n---\n\n# x\n\n本文\n", g);
  assert.equal(parseGrid(t3)[4][4], "旅行");
  assert.ok(t3.includes("本文"));
  // 副題の対（中心のブロック ↔ 周りのブロックの真ん中）
  assert.deepEqual(mirrorOf(3, 3), [1, 1]);
  assert.deepEqual(mirrorOf(7, 4), [5, 4]);
  assert.equal(mirrorOf(4, 4), null);
  assert.equal(mirrorOf(0, 0), null);
  // 3-way: こちらだけ・ファイルだけ・両方同じ・両方違う
  const base = empty(), ours = empty(), disk = empty();
  ours[0][0] = "こちら"; disk[0][1] = "ファイル"; ours[0][2] = disk[0][2] = "同じ"; ours[0][3] = "A"; disk[0][3] = "B";
  const m = mergeGrids(base, ours, disk);
  assert.equal(m.grid[0][0], "こちら");
  assert.equal(m.grid[0][1], "ファイル");
  assert.equal(m.grid[0][2], "同じ");
  assert.equal(m.grid[0][3], "A");
  assert.equal(m.clashes, 1);
  assert.deepEqual(cellsOf("| a | b\\|c |"), ["a", "b|c"]);
}

// ---- キャンバス ----
{
  const t0 = "---\ntitle: 図\ncanvas: true\n---\n\n# 図\n\nメモの文。\n\n```gnosis-canvas\n{\"nodes\": [], \"edges\": []}\n```\n\nBackLink:\n[日記](d.md)\n";
  assert.deepEqual(parseCanvas(t0), { nodes: [], edges: [] });
  const data = { nodes: [{ id: "n1", type: "note", file: "sub/h.md", x: 0, y: 0, w: 220, h: 110 }, { id: "t1", type: "text", text: "考え", x: 10, y: 10, w: 100, h: 50 }], edges: [{ id: "e1", from: "n1", to: "t1", label: "栽培" }] };
  const t1 = writeCanvas(t0, data, { "sub/h.md": "ハーブ [1]" }, "c.md");
  assert.ok(t1.includes("メモの文。"));
  assert.ok(t1.includes("[ハーブ \\[1\\]](sub/h.md)\n```gnosis-canvas\n"));      // 置いたノートへのリンク（題の [] はエスケープ）
  assert.ok(t1.endsWith("```\n\nBackLink:\n[日記](d.md)\n"));                // 下の節はそのまま
  assert.deepEqual(parseCanvas(t1), data);
  // もう一度書いても、リンクの行は重ならない（前のリンクの行を書き直す）
  const t2 = writeCanvas(t1, { nodes: [data.nodes[1]], edges: [] }, {}, "c.md");
  assert.ok(!t2.includes("sub/h.md"));
  assert.equal((t2.match(/```gnosis-canvas/g) || []).length, 1);
  // サブフォルダのキャンバスからは相対パス
  const t3 = writeCanvas(t0, data, { "sub/h.md": "ハーブ" }, "other/c.md");
  assert.ok(t3.includes("[ハーブ](../sub/h.md)"));
  // ブロックが無いノートには末尾に足す
  const t4 = writeCanvas("# 図\n\n本文\n", data, {}, "c.md");
  assert.ok(t4.includes("本文\n\n[h](sub/h.md)\n```gnosis-canvas\n"));
  // 壊れた JSON は壊れたと分かる（空として扱い、保存で書き直す）
  assert.equal(parseCanvas("```gnosis-canvas\n{こわれ\n```\n").broken, true);
}
// ---- 検索（コマンドパレット・機能一覧）: ひらがな・カタカナ・全角半角の違いを越えて見つかる ----
{
  assert.equal(fold("グラフ"), "ぐらふ");
  assert.equal(fold("ＡＢＣ１２３ｶﾒﾗ"), "abc123かめら");
  const items = [{ label: "グラフを開く", keywords: "graph", group: "ビュー" }, { label: "カレンダーを開く", keywords: "calendar", group: "時間" }, { label: "索引ブラウザを開く", keywords: "", group: "索引" }];
  assert.equal(rank(items, "ぐらふ")[0].label, "グラフを開く");          // ひらがなで打っても
  assert.equal(rank(items, "かれんだー")[0].label, "カレンダーを開く");   // 長音も
  assert.equal(rank(items, "ｶﾚﾝﾀﾞｰ")[0].label, "カレンダーを開く");       // 半角カナでも
  // 漢字のラベルは、読み（palette-core の辞書）を足して、ひらがなでも見つかる
  const withRead = items.map((it) => ({ ...it, keywords: it.keywords + " " + readings(it.label + " " + it.group) }));
  assert.equal(rank(withRead, "さくいん")[0].label, "索引ブラウザを開く");
  assert.equal(rank(withRead, "ひらく")[0].label !== undefined, true);
  for (const w of ["きょう", "にっき", "ひらく"]) assert.ok(readings("今日の日記を開く").includes(w), w);
  assert.equal(rank(items, "GRAPH")[0].label, "グラフを開く");
}
// 曼荼羅のマスに既存のノートを入れる（リンク先は曼荼羅のフォルダから・表示名の [ ] は ( ) に・外すと文字だけ）
{
  assert.equal(relLink("", "abc.md"), "abc.md");
  assert.equal(relLink("sub/", "abc.md"), "../abc.md");
  assert.equal(relLink("sub/", "sub/abc.md"), "abc.md");
  assert.equal(relLink("a/b/", "a/c/x y.md"), "../c/x%20y.md");
  assert.equal(cellLink("ハーブ [仮]", "", "h.md"), "[ハーブ (仮)](h.md)");
  assert.equal(unlinkText("[ハーブ](h.md) と [運動](u.md)"), "ハーブ と 運動");
  // 入れたリンクは、表に書いて読み直しても同じ
  const g = parseGrid(renderTable(Array.from({ length: 9 }, (_, r) => Array.from({ length: 9 }, (_, c) => (r === 4 && c === 4 ? cellLink("主題", "", "t.md") : "")))).join("\n"));
  assert.equal(g[4][4], "[主題](t.md)");
}
console.log("workbench core: OK");
