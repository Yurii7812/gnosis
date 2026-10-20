import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
globalThis.FzNav = require("./site_assets/fznav-core.js");
const C = require("./site_assets/views2core.js");

const N = (id, title, fz = "", extra = {}) => ({ id, title, fz, href: id.replace(".md", ".html"), group: false, ...extra });
const E = (s, d, k) => ({ s, d, k });
const near = (a, b, eps = 1e-6) => assert.ok(Math.abs(a - b) <= eps, `${a} ≈ ${b}`);

// ---- 階層ツリー ----
{
  const g = {
    nodes: [N("1.md", "ハーブ", "1"), N("1a.md", "栽培", "1a"), N("1b.md", "利用", "1b"), N("1a1.md", "水", "1a1"), N("g.md", "索引", "", { group: true }), N("x.md", "孤立"), N("10.md", "十", "10"), N("2.md", "二", "2")],
    edges: [E("1a.md", "1.md", "parent_branch"), E("1.md", "1b.md", "branch_group"), E("1a1.md", "1a.md", "folgezettel"), E("1a1.md", "g.md", "group")],
  };
  const h = C.hierarchy(g);
  assert.deepEqual(h.roots.map((r) => r.id), ["1.md", "2.md", "10.md", "x.md", "g.md"]);   // 番号順(1<2<10)・番号なしは最後(題の五十音順)
  const one = h.roots[0];
  assert.deepEqual(one.children.map((c) => c.id), ["1a.md", "1b.md"]);                      // ParentBranch / BranchGroup の両方から子になる
  assert.deepEqual(one.children[0].children.map((c) => c.id), ["1a1.md"]);                   // 1a1 は folgezettel の親(1a)が Group(g)より優先
  assert.equal(C.countTree(one), 4);
  assert.equal(C.depthOf(one), 3);
  // 親は 1 つだけ: 1a1 が g の下にも出ることはない
  assert.equal(h.roots.find((r) => r.id === "g.md").children.length, 0);
  // 循環は切る: a→b→a でも終わる
  const cyc = { nodes: [N("a.md", "A"), N("b.md", "B"), N("c.md", "C")], edges: [E("a.md", "b.md", "parent_branch"), E("b.md", "a.md", "parent_branch"), E("c.md", "b.md", "parent_branch")] };
  const hc = C.hierarchy(cyc);
  const total = hc.roots.reduce((s, r) => s + C.countTree(r), 0);
  assert.equal(total, 3);                                                                      // どのノートもちょうど 1 回
  assert.ok(hc.roots.length >= 1);
  // 自分への辺・存在しない相手は無視
  const odd = { nodes: [N("a.md", "A")], edges: [E("a.md", "a.md", "parent_branch"), E("a.md", "zzz.md", "parent_branch")] };
  assert.equal(C.hierarchy(odd).roots.length, 1);
  assert.deepEqual(C.hierarchy({ nodes: [], edges: [] }).roots, []);
}

// ---- 孤立・未参照・未索引 ----
{
  const g = {
    nodes: [N("idx.md", "索引", "", { group: true }), N("a.md", "A"), N("b.md", "B"), N("c.md", "C"), N("d.md", "D"), N("e.md", "E")],
    edges: [E("idx.md", "a.md", "link"), E("a.md", "b.md", "link"), E("c.md", "idx.md", "group"), E("d.md", "d.md", "link"), E("e.md", "b.md", "backlink")],
  };
  const o = C.orphans(g);
  assert.deepEqual(o.isolated.map((x) => x.id), ["d.md", "e.md"]);                // 自己リンク・派生の backlink は数えない
  assert.deepEqual(o.unreferenced.map((x) => x.id), ["c.md"]);                    // 出るリンクだけ(所属の group)がある
  assert.deepEqual(o.unindexed.map((x) => x.id), ["b.md", "d.md", "e.md"]);       // 索引から挙げられた a と、Group で属する c は載っている。b は a からのリンクだけ=索引ではない
  assert.equal(o.total, 6);
  assert.deepEqual(C.orphans({ nodes: [], edges: [] }).isolated, []);
}

// ---- 隣接行列 ----
{
  const g = { nodes: [N("a.md", "A"), N("b.md", "B"), N("c.md", "C"), N("d.md", "D")], edges: [E("a.md", "b.md", "link"), E("a.md", "b.md", "related"), E("b.md", "c.md", "link"), E("a.md", "c.md", "link"), E("a.md", "a.md", "link")] };
  const m = C.matrix(g, 3);
  assert.deepEqual(m.ids, ["a.md", "b.md", "c.md"]);                              // 次数の大きい順の上位 3（d は次数 0 で落ちる）
  assert.equal(m.cells[0][1].n, 2);
  assert.deepEqual(m.cells[0][1].kinds, { link: 1, related: 1 });                  // 関係の種類を潰さない
  assert.equal(m.cells[1][0].n, 0);                                               // 向きがある(b→a は無い)
  assert.equal(m.cells[0][0].n, 0);                                               // 自己リンクは数えない
  assert.equal(m.max, 2);
  assert.equal(m.total, 4);
  assert.deepEqual(C.matrix({ nodes: [], edges: [] }).ids, []);
}

// ---- Treemap ----
{
  const items = [{ id: "a", value: 6 }, { id: "b", value: 6 }, { id: "c", value: 4 }, { id: "d", value: 3 }, { id: "e", value: 2 }, { id: "f", value: 2 }, { id: "g", value: 1 }];
  const rects = C.squarify(items, 0, 0, 600, 400);
  assert.equal(rects.length, 7);
  const area = rects.reduce((s, r) => s + r.w * r.h, 0);
  near(area, 600 * 400, 1e-3);                                                    // 面積の合計が全体に一致(隙間も重なりも無い)
  rects.forEach((r) => { assert.ok(r.x >= -1e-6 && r.y >= -1e-6 && r.x + r.w <= 600 + 1e-6 && r.y + r.h <= 400 + 1e-6); });
  const byId = Object.fromEntries(rects.map((r) => [r.item.id, r]));
  near(byId.a.w * byId.a.h / (600 * 400), 6 / 24, 1e-6);                          // 面積は値に比例
  for (let i = 0; i < rects.length; i++) for (let j = i + 1; j < rects.length; j++) {  // 重ならない
    const a = rects[i], b = rects[j];
    assert.ok(a.x + a.w <= b.x + 1e-6 || b.x + b.w <= a.x + 1e-6 || a.y + a.h <= b.y + 1e-6 || b.y + b.h <= a.y + 1e-6, `重なり ${a.item.id} ${b.item.id}`);
  }
  assert.deepEqual(C.squarify([], 0, 0, 10, 10), []);
  assert.deepEqual(C.squarify([{ id: "z", value: 0 }], 0, 0, 10, 10), []);        // 値 0 は描かない
  assert.equal(C.squarify([{ id: "one", value: 5 }], 0, 0, 10, 20)[0].h, 20);      // 1 件は全面
  const notes = [N("n1.md", "ハーブ", "1", { size: 500 }), N("n1a.md", "栽培", "1a", { size: 300 }), N("n2.md", "料理", "2", { size: 200 }), N("n.md", "番号なし", "", { size: 100 })];
  const tm = C.treemap(notes, 800, 500);
  assert.deepEqual(tm.groups.map((g) => g.key).sort(), ["1", "2", "（番号なし）"].sort());
  assert.equal(tm.notes.length, 4);
  assert.equal(tm.groups.find((g) => g.key === "1").label, "1 ハーブ");             // 最上位の番号のノートの題を見出しに
  const g1 = tm.groups.find((g) => g.key === "1");
  tm.notes.filter((n) => n.group === "1").forEach((n) => { assert.ok(n.x >= g1.x - 1e-6 && n.x + n.w <= g1.x + g1.w + 1e-6 && n.y >= g1.y - 1e-6 && n.y + n.h <= g1.y + g1.h + 1e-6); });   // 子は親の枠の中
  assert.equal(C.treemap([], 100, 100).notes.length, 0);
}

// ---- Sunburst / マインドマップ ----
{
  const g = { nodes: [N("r.md", "根", "1"), N("a.md", "A", "1a"), N("b.md", "B", "1b"), N("a1.md", "A1", "1a1"), N("a2.md", "A2", "1a2")],
              edges: [E("a.md", "r.md", "parent_branch"), E("b.md", "r.md", "parent_branch"), E("a1.md", "a.md", "parent_branch"), E("a2.md", "a.md", "parent_branch")] };
  const h = C.hierarchy(g);
  const s = C.sunburst(h, 4);
  assert.equal(s.leaves, 3);                                                      // 葉 = a1, a2, b
  const arc = (id) => s.arcs.find((a) => a.id === id);
  near(arc("r.md").a1 - arc("r.md").a0, 2 * Math.PI);                              // 根は全周
  near(arc("a.md").a1 - arc("a.md").a0, 2 * Math.PI * 2 / 3);                      // a は葉 2/3
  near(arc("b.md").a1 - arc("b.md").a0, 2 * Math.PI / 3);
  assert.equal(arc("a1.md").depth, 3);
  assert.ok(arc("a1.md").a0 >= arc("a.md").a0 - 1e-9 && arc("a1.md").a1 <= arc("a.md").a1 + 1e-9);   // 子は親の角度の中
  const shallow = C.sunburst(h, 2);
  assert.equal(shallow.arcs.find((a) => a.id === "a.md").more, 2);                 // 深さで切ったら「あと 2」
  assert.ok(!shallow.arcs.find((a) => a.id === "a1.md"));
  const p = C.arcPath(100, 100, 20, 50, 0, Math.PI / 2);
  assert.match(p, /^M[\d. ]+A50 50 0 0 1 [\d. ]+L[\d. ]+A20 20 0 0 0 [\d. ]+Z$/);
  assert.match(C.arcPath(0, 0, 10, 20, 0, 2 * Math.PI), /A20 20 0 1 1/);            // 全周は欠かして large-arc
  const mm = C.mindmap(h, "a.md", 2, 400, 300, 100);
  assert.equal(mm.nodes.length, 3);                                               // 中心 a と a1, a2
  assert.deepEqual([mm.nodes[0].x, mm.nodes[0].y], [400, 300]);
  mm.nodes.slice(1).forEach((n) => near(Math.hypot(n.x - 400, n.y - 300), 100, 1e-6));   // 子は中心から ringGap の距離
  assert.equal(mm.edges.length, 2);
  const m1 = C.mindmap(h, "r.md", 1, 0, 0, 100);
  assert.equal(m1.nodes.length, 3);                                               // 深さ 1 = 中心と直接の子 2
  assert.equal(m1.nodes.find((n) => n.id === "a.md").more, 2);                    // その先に 2 件ある印
  assert.equal(C.mindmap(h, "r.md", 0, 0, 0, 100).nodes.length, 5);               // 0・未指定は既定の深さ 3 になり、全体(5 ノード)が出る
  assert.equal(C.mindmap(h, "nothing.md", 2, 0, 0), null);
}

// ---- カンバン ----
{
  const T = (text, extra) => ({ text, due: "", done: false, ...extra });
  const tasks = [T("遅れ", { due: "2026-10-19" }), T("今日1", { due: "2026-10-21", priority: "low" }), T("今日2", { due: "2026-10-21", priority: "high" }), T("来週", { due: "2026-10-28" }), T("7日目", { due: "2026-10-28" }),
                 T("ずっと先", { due: "2027-01-01" }), T("期限なし"), T("予定日", { scheduled: "2026-10-22" }), T("開始前", { due: "2026-10-30", start: "2026-10-25" }), T("終えた", { done: true, done_date: "2026-10-20" }), T("昨日終えた", { done: true, done_date: "2026-10-19" })];
  const col = Object.fromEntries(C.kanban(tasks, "2026-10-21").map((c) => [c.key, c.tasks.map((t) => t.text)]));
  assert.deepEqual(col.overdue, ["遅れ"]);
  assert.deepEqual(col.today, ["今日2", "今日1"]);                                  // 同じ日は優先度が高い順
  assert.deepEqual(col.soon, ["予定日", "7日目", "来週"].sort((a, b) => a.localeCompare(b, "ja")).sort((a, b) => (a === "予定日" ? -1 : b === "予定日" ? 1 : 0)));
  assert.deepEqual(col.later, ["ずっと先"]);
  assert.deepEqual(col.undated, ["期限なし"]);
  assert.ok(!Object.values(col).flat().includes("開始前"));                         // 開始日前は出さない
  assert.deepEqual(col.done, ["終えた", "昨日終えた"]);                              // 完了は新しい順
  assert.equal(C.kanban([], "2026-10-21").length, 6);
  assert.equal(C.addDays("2026-12-31", 1), "2027-01-01");                          // 年またぎ
  assert.equal(C.addDays("2028-02-28", 1), "2028-02-29");                          // うるう年
  const many = Array.from({ length: 50 }, (_, i) => T("d" + i, { done: true, done_date: "2026-01-" + String(i % 28 + 1).padStart(2, "0") }));
  assert.equal(C.kanban(many, "2026-10-21").find((c) => c.key === "done").tasks.length, 30);   // 完了は 30 件まで
}

// ---- 成長・川 ----
{
  const notes = [N("a", "A", "1", { time: "2026-01-05 10:00:00" }), N("b", "B", "1a", { time: "2026-01-20 10:00:00" }), N("c", "C", "2", { time: "2026-04-02 10:00:00" }), N("d", "D", "", { time: "" })];
  const gr = C.growth(notes);
  assert.deepEqual(gr.months.map((m) => m.month), ["2026-01", "2026-02", "2026-03", "2026-04"]);   // 間の月も 0 で埋める
  assert.deepEqual(gr.months.map((m) => m.added), [2, 0, 0, 1]);
  assert.deepEqual(gr.months.map((m) => m.total), [2, 2, 2, 3]);
  assert.equal(gr.undated, 1);
  assert.deepEqual(C.growth([N("x", "X")]).months, []);
  const y = C.growth([N("p", "P", "", { time: "2025-11-01 00:00:00" }), N("q", "Q", "", { time: "2026-02-01 00:00:00" })]);
  assert.deepEqual(y.months.map((m) => m.month), ["2025-11", "2025-12", "2026-01", "2026-02"]);   // 年またぎ
  const r = C.river(notes);
  assert.deepEqual(r.series.map((s) => s.name), ["1", "2"]);
  assert.deepEqual(r.series[0].points.map((p) => p.v), [2, 0, 0, 0]);
  r.months.forEach((_, i) => {                                                    // 各月、積み上げは 0 を中心に対称
    const lo = Math.min(...r.series.map((s) => s.points[i].y0)), hi = Math.max(...r.series.map((s) => s.points[i].y1));
    near(lo + hi, 0, 1e-9);
  });
  assert.deepEqual(C.river([]).series, []);
}

// ---- 比較 ----
{
  const g = { nodes: [N("a.md", "A"), N("b.md", "B"), N("x.md", "共通X"), N("y.md", "Aだけ"), N("z.md", "Bだけ"), N("q.md", "無関係")],
              edges: [E("a.md", "x.md", "link"), E("b.md", "x.md", "link"), E("a.md", "y.md", "link"), E("z.md", "b.md", "related"), E("a.md", "b.md", "context"), E("q.md", "q.md", "link")] };
  const c = C.compare(g, "a.md", "b.md");
  assert.deepEqual(c.shared.map((n) => n.id), ["x.md"]);
  assert.deepEqual(c.onlyA.map((n) => n.id), ["y.md"]);
  assert.deepEqual(c.onlyB.map((n) => n.id), ["z.md"]);                           // 向きは無視して近傍を比べる
  assert.deepEqual(c.direct, ["context"]);                                        // 2 つの間の直接の関係の種類
  near(c.jaccard, 1 / 3);
  assert.equal(C.compare(g, "a.md", "nothing.md"), null);
  assert.equal(C.compare(g, "q.md", "a.md").jaccard, 0);
}

// ---- Sankey ----
{
  const g = { nodes: [N("a1.md", "", "1"), N("a2.md", "", "1a"), N("b1.md", "", "2"), N("c1.md", "", "3"), N("n.md", "")],
              edges: [E("a1.md", "b1.md", "link"), E("a2.md", "b1.md", "link"), E("a1.md", "c1.md", "link"), E("a1.md", "a2.md", "link"), E("n.md", "b1.md", "link"), E("b1.md", "c1.md", "backlink")] };
  const s = C.sankey(g, 600, 300);
  const ln = (a, b) => s.links.find((l) => l.s === a && l.d === b);
  assert.equal(ln("1", "2").v, 2);
  assert.equal(ln("1", "3").v, 1);
  assert.equal(ln("（番号なし）", "2").v, 1);
  assert.ok(!ln("1", "1"));                                                       // 同じ枝の中は流れに数えない
  assert.ok(!s.links.some((l) => l.s === "2" && l.d === "3"));                    // 派生の backlink は数えない
  s.left.forEach((n) => { assert.ok(n.y >= 0 && n.y + n.h <= 300 + 1e-6); });
  const lsum = s.links.filter((l) => l.s === "1").reduce((a, l) => a + l.w0, 0);
  near(lsum, s.left.find((n) => n.name === "1").h, 1e-6);                           // 出る帯の太さの合計 = 節の高さ
  assert.ok(s.links.every((l) => /^M[\d. ]+C/.test(l.path)));
  assert.deepEqual(C.sankey({ nodes: [N("a.md", "")], edges: [] }, 100, 100).links, []);
}

// ---- 地図 ----
{
  assert.deepEqual(C.parseLoc("35.68, 139.76"), { lat: 35.68, lon: 139.76 });
  assert.deepEqual(C.parseLoc("-33.9 151.2"), { lat: -33.9, lon: 151.2 });
  for (const bad of ["", "abc", "91, 0", "0, 181", "35.68", "1,2,3", null]) assert.equal(C.parseLoc(bad), null, String(bad));
  const notes = [N("t.md", "東京", "", { location: "35.68, 139.76" }), N("o.md", "大阪", "", { location: "34.69, 135.50" }), N("x.md", "不正", "", { location: "どこか" }), N("n.md", "無し")];
  const m = C.mapPoints(notes, 600, 400, 30);
  assert.equal(m.points.length, 2);
  assert.equal(m.invalid, 1);                                                     // 位置が読めないものの件数
  const t = m.points.find((p) => p.id === "t.md"), o = m.points.find((p) => p.id === "o.md");
  assert.ok(t.x > o.x, "東(経度が大きい)ほど右");
  assert.ok(t.y < o.y, "北(緯度が大きい)ほど上");
  m.points.forEach((p) => { assert.ok(p.x >= 30 - 1e-6 && p.x <= 570 + 1e-6 && p.y >= 30 - 1e-6 && p.y <= 370 + 1e-6); });
  assert.deepEqual(C.mapPoints([N("n.md", "無し")], 100, 100).points, []);
  assert.equal(C.mapPoints([N("one.md", "一点", "", { location: "10, 20" })], 200, 100).points.length, 1);   // 1 点だけでも落ちない
}

// ---- 3D ----
{
  const g = { nodes: ["a", "b", "c", "d"].map((x) => N(x + ".md", x)), edges: [E("a.md", "b.md", "link"), E("b.md", "c.md", "link"), E("c.md", "d.md", "link")] };
  const p1 = C.layout3d(g), p2 = C.layout3d(g);
  assert.deepEqual(p1, p2);                                                       // 乱数を使わず、同じ入力は同じ配置
  Object.values(p1).forEach((p) => p.forEach((v) => assert.ok(Number.isFinite(v))));
  const radii = Object.values(p1).map((p) => Math.hypot(p[0], p[1], p[2]));
  near(Math.max(...radii), 1, 1e-9);                                              // いちばん遠いノートが半径 1(枠に収まる)
  const cen = [0, 1, 2].map((c) => Object.values(p1).reduce((s, p) => s + p[c], 0) / 4);
  cen.forEach((v) => near(v, 0, 1e-9));                                           // 重心が原点
  const one = C.layout3d({ nodes: [N("only.md", "独り")], edges: [] });
  assert.deepEqual(Object.keys(one), ["only.md"]);                                // 1 ノートでも割り算で壊れない
  one["only.md"].forEach((v) => assert.ok(Number.isFinite(v)));
  const pr = C.project3d(p1, 0, 0, 450, 320, 200, 4);
  assert.equal(Object.keys(pr).length, 4);
  const back = C.project3d(p1, Math.PI, 0, 0, 0, 1, 4), front = C.project3d(p1, 0, 0, 0, 0, 1, 4);
  Object.keys(p1).forEach((id) => near(back[id].z, -front[id].z, 1e-9));           // 半回転で奥行きが反転
  const r360 = C.project3d(p1, 2 * Math.PI, 0, 0, 0, 1, 4);
  Object.keys(p1).forEach((id) => near(r360[id].x, front[id].x, 1e-9));            // 一周で元に戻る
  assert.deepEqual(C.layout3d({ nodes: [], edges: [] }), {});
}

// ---- ホワイトボード・ギャラリー ----
{
  assert.equal(C.snap(47, 20), 40);
  assert.equal(C.snap(51, 20), 60);
  assert.equal(C.snap(47, 0), 47);
  assert.deepEqual(C.clampPos({ x: -5, y: 900 }, 800, 600, 100, 50), { x: 0, y: 550 });
  assert.deepEqual(C.clampPos({ x: 10, y: 10 }, 800, 600, 100, 50), { x: 10, y: 10 });
  assert.deepEqual(C.autoPlace(["a", "b", "c"], 2, 100, 50, 10), { a: { x: 0, y: 0 }, b: { x: 110, y: 0 }, c: { x: 0, y: 60 } });
  assert.equal(C.fileType("a.PNG"), "image");
  assert.equal(C.fileType("x.pdf"), "pdf");
  assert.equal(C.fileType("x.mp3"), "audio");
  assert.equal(C.fileType("x.docx"), "other");
  const files = [{ name: "b.png", notes: [{ title: "ハーブ" }] }, { name: "a.pdf", notes: [] }, { name: "c.png", notes: [{ title: "料理" }] }, { name: "d.zip", notes: [] }];
  assert.deepEqual(C.gallery(files, "image", "").map((f) => f.name), ["b.png", "c.png"]);
  assert.deepEqual(C.gallery(files, "all", "ハーブ").map((f) => f.name), ["b.png"]);   // 参照しているノートの題でも探せる
  assert.deepEqual(C.gallery(files, "other", "").map((f) => f.name), ["d.zip"]);
  assert.deepEqual(C.gallery(files, "all", "png 料理").map((f) => f.name), ["c.png"]);
}

// ---- 乱数 ----
{
  const a = C.rng(42), b = C.rng(42), c = C.rng(43);
  const sa = Array.from({ length: 5 }, a), sb = Array.from({ length: 5 }, b), sc = Array.from({ length: 5 }, c);
  assert.deepEqual(sa, sb);                                                       // 同じ種なら同じ列
  assert.notDeepEqual(sa, sc);
  sa.forEach((v) => assert.ok(v >= 0 && v < 1));
  assert.equal(C.seedOf("abc"), C.seedOf("abc"));
  assert.notEqual(C.seedOf("abc"), C.seedOf("abd"));
  assert.ok(Array.from({ length: 1000 }, C.rng(0)).every((v) => v >= 0 && v < 1));   // 種 0 でも落ちない
}

// ---- 博物館 ----
{
  const notes = [N("c.md", "料理", "2"), N("a1.md", "水", "1a1"), N("a.md", "栽培", "1a"), N("r.md", "ハーブ", "1"), N("x.md", "番号なし"), N("b.md", "二番", "10")];
  const m = C.museum(notes);
  assert.deepEqual(m.rooms.map((r) => r.key), ["1", "2", "10", "（番号なし）"]);       // 部屋は番号順(1<2<10)・番号なしは最後
  assert.equal(m.rooms[0].label, "1 ハーブ");                                       // 部屋の名前は最上位の番号のノートの題
  assert.deepEqual(m.rooms[0].exhibits.map((n) => n.id), ["r.md", "a.md", "a1.md"]);   // 部屋の中も番号順
  assert.equal(m.tour.length, 6);
  assert.deepEqual(m.tour.map((t) => t.note.id), ["r.md", "a.md", "a1.md", "c.md", "b.md", "x.md"]);   // 順路は部屋の順に 1 本
  assert.equal(m.tour[3].room, "2");
  assert.deepEqual(C.museum([]).tour, []);
}

// ---- 迷路・探索ゲーム ----
{
  const g = { nodes: ["a", "b", "c", "d", "e", "iso"].map((x) => N(x + ".md", x)),
              edges: [E("a.md", "b.md", "link"), E("b.md", "c.md", "link"), E("c.md", "d.md", "link"), E("a.md", "d.md", "related"), E("d.md", "e.md", "link"), E("e.md", "a.md", "backlink"), E("b.md", "b.md", "link"), E("e.md", "iso.md", "folgezettel")] };
  const out = C.outLinks(g);
  assert.deepEqual(out["a.md"].sort(), ["b.md", "d.md"]);                          // ノートに書かれた関係だけ。backlink・番号の親子・自己リンクは辿れない
  assert.deepEqual(out["e.md"], []);
  assert.deepEqual(out["iso.md"], []);
  assert.deepEqual(C.shortest(out, "a.md", "e.md"), ["a.md", "d.md", "e.md"]);
  assert.equal(C.shortest(out, "e.md", "a.md"), null);                              // 向きがあるので戻れない
  assert.deepEqual(C.shortest(out, "a.md", "a.md"), ["a.md"]);
  let st = C.gameStart(g, "a.md", "e.md");
  assert.deepEqual([st.par, st.solvable, st.done, st.moves], [2, true, false, 0]);
  let r = C.gameMove(g, st, "c.md");
  assert.equal(r.ok, false, "リンクの無い先へは進めない");
  assert.equal(r.state, st);
  r = C.gameMove(g, st, "b.md"); assert.ok(r.ok); st = r.state;
  r = C.gameMove(g, st, "c.md"); st = r.state;
  r = C.gameMove(g, st, "d.md"); st = r.state;
  r = C.gameMove(g, st, "e.md"); st = r.state;
  assert.deepEqual([st.done, st.moves, st.path.join(">")], [true, 4, "a.md>b.md>c.md>d.md>e.md"]);
  near(C.gameScore(st), 0.5);                                                       // 最短 2 手のところ 4 手 → 0.5
  assert.equal(C.gameMove(g, st, "a.md").ok, false, "着いたあとは進めない");
  const direct = C.gameMove(g, C.gameMove(g, C.gameStart(g, "a.md", "e.md"), "d.md").state, "e.md").state;
  assert.equal(C.gameScore(direct), 1);                                             // 最短なら満点
  const unsolvable = C.gameStart(g, "e.md", "a.md");
  assert.equal(unsolvable.solvable, false);
  assert.equal(unsolvable.par, null);
  assert.equal(C.gameScore(C.gameStart(g, "a.md", "a.md")), 1);
  // 出発と目標を決める
  const p1 = C.mazePick(g, 7, 2), p2 = C.mazePick(g, 7, 2);
  assert.deepEqual(p1, p2);                                                         // 同じ種なら同じ問題
  assert.ok(p1.par >= 2);
  assert.equal(p1.path.length - 1, p1.par);
  assert.equal(C.mazePick(g, 1, 9), null);                                          // 長すぎる経路は無い
  assert.equal(C.mazePick({ nodes: [N("a.md", "a")], edges: [] }, 1, 1), null);
}

// ---- 記憶の宮殿 ----
{
  const placed = { "a": { room: "R1" }, "b": { room: "R1" }, "c": { room: "R2" }, "d": { room: "R2" }, "e": { room: "R3" } };
  const qs = C.recallQuiz(placed, 5, 3);
  assert.equal(qs.length, 3);
  qs.forEach((q) => {
    assert.equal(q.options.length, 4);
    assert.equal(new Set(q.options).size, 4);                                       // 選択肢は重複しない
    assert.ok(q.options.includes(q.answer));                                        // 正解が必ず入る
    assert.equal(q.room, placed[q.answer].room);
  });
  assert.deepEqual(C.recallQuiz(placed, 5, 3), qs);                                 // 同じ種なら同じ問題
  assert.equal(new Set(qs.map((q) => q.id)).size, 3);                               // 同じノートを 2 回出さない
  assert.deepEqual(C.recallQuiz({ a: { room: "x" } }, 1, 3), []);                   // 1 つだけでは出題しない
  assert.equal(C.recallQuiz({ a: {}, b: {} }, 1, 5)[0].options.length, 2);          // 置いたノートだけだと少ない選択肢
  const wide = C.recallQuiz({ a: { room: "x" }, b: { room: "y" } }, 1, 5, ["a", "b", "c", "d", "e", "f"]);
  assert.equal(wide.length, 2);                                                     // 問いの対象は置いたノートだけ
  wide.forEach((q) => { assert.equal(q.options.length, 4); assert.ok(q.options.includes(q.answer)); assert.equal(new Set(q.options).size, 4); });
  assert.ok(wide.some((q) => q.options.some((o) => !["a", "b"].includes(o))), "置いていないノートも選択肢に出る");
  const rr = C.roomRects(["a", "b", "c", "d", "e"], 600, 400);
  assert.equal(Object.keys(rr).length, 5);
  Object.values(rr).forEach((r) => assert.ok(r.x >= 0 && r.y >= 0 && r.x + r.w <= 600 + 1e-9 && r.y + r.h <= 400 + 1e-9));
  assert.deepEqual(C.roomRects([], 100, 100), {});
}

// ---- 成長アニメーション ----
{
  const notes = [N("a", "A", "", { time: "2026-01-05 10:00:00" }), N("b", "B", "", { time: "2026-03-02 10:00:00" }), N("c", "C", "", { time: "" }), N("d", "D", "", { time: "2026-03-20 10:00:00" })];
  const g = { nodes: notes.map((n) => ({ id: n.id, title: n.title, href: n.href })), edges: [E("a", "b", "link"), E("b", "d", "link"), E("a", "c", "link"), E("b", "b", "link")] };
  const tl = C.timelapse(notes, g);
  assert.deepEqual(tl.months, ["2026-01", "2026-02", "2026-03", "日付なし"]);          // 空の月も 1 コマ・日付なしは最後
  assert.equal(tl.frames, 4);
  assert.deepEqual([tl.appear.a, tl.appear.b, tl.appear.d, tl.appear.c], [0, 2, 2, 3]);
  const f0 = C.visibleAt(tl, g, 0);
  assert.deepEqual(f0.nodes.map((n) => n.id), ["a"]);
  assert.equal(f0.edges.length, 0);
  const f2 = C.visibleAt(tl, g, 2);
  assert.deepEqual(f2.nodes.map((n) => n.id).sort(), ["a", "b", "d"]);
  assert.equal(f2.edges.length, 2);                                                 // a-b と b-d。c は未登場、自己リンクは数えない
  assert.equal(C.visibleAt(tl, g, 3).edges.length, 3);
  assert.equal(C.timelapse([N("x", "X")], { nodes: [], edges: [] }).frames, 1);       // 日付なしだけでも 1 コマ
  assert.equal(C.timelapse([], { nodes: [], edges: [] }).frames, 0);
}

// ---- アイデア合成器 ----
{
  const g = { nodes: ["a", "b", "c", "d", "far", "iso"].map((x) => N(x + ".md", x)),
              edges: [E("a.md", "b.md", "link"), E("b.md", "c.md", "link"), E("c.md", "d.md", "link"), E("d.md", "far.md", "link")] };
  const d = C.distances(g, "a.md");
  assert.deepEqual([d["b.md"], d["d.md"], d["far.md"], "iso.md" in d], [1, 3, 4, false]);   // 向きは無視・つながっていないものは入らない
  const p = C.ideaPair(g, 3, 3), p2 = C.ideaPair(g, 3, 3);
  assert.deepEqual(p, p2);
  assert.notEqual(p.a, p.b);
  const dd = C.distances(g, p.a);
  assert.ok(!(p.b in dd) || dd[p.b] >= 3, "選ばれた組は遠い(または無関係)");
  assert.equal(p.distance, p.b in dd ? dd[p.b] : null);
  const tiny = { nodes: [N("a.md", "a"), N("b.md", "b")], edges: [E("a.md", "b.md", "link")] };
  assert.equal(C.ideaPair(tiny, 1, 3), null);                                       // 近い組しか無ければ出さない
  assert.notEqual(C.ideaPair(tiny, 1, 1), null);
  assert.equal(C.ideaPair({ nodes: [N("a.md", "a")], edges: [] }, 1), null);
  const prompts = C.ideaPrompts("栽培", "料理");
  assert.equal(prompts.length, 5);
  assert.ok(prompts[0].includes("栽培") && prompts[0].includes("料理"));
}

console.log("views2core OK");
