// 追加ビュー（表示専用）。body[data-view2] で切り替える。核: Views2Core、データ: GNOSIS_NOTES / GNOSIS_GRAPH / GNOSIS_TASKS / GNOSIS_FILES / GNOSIS_SLIDES。
(function () {
  var C = window.Views2Core, notes = window.GNOSIS_NOTES || [], graph = window.GNOSIS_GRAPH || { nodes: [], edges: [] };
  var view = document.body.getAttribute("data-view2"), box = document.getElementById("v2");
  var SVGNS = "http://www.w3.org/2000/svg";
  function h(tag, attrs, text) { var e = document.createElement(tag); for (var k in attrs || {}) e.setAttribute(k, attrs[k]); if (text != null) e.textContent = text; return e; }
  function s(tag, attrs, text) { var e = document.createElementNS(SVGNS, tag); for (var k in attrs || {}) e.setAttribute(k, attrs[k]); if (text != null) e.textContent = text; return e; }
  function link(href, text, attrs) { var a = h("a", Object.assign({ href: href }, attrs || {}), text); return a; }
  function clip(t, n) { t = String(t || ""); return t.length > n ? t.slice(0, Math.max(1, n - 1)) + "…" : t; }
  var PAL = ["#4a90d9", "#e0a800", "#5cb85c", "#d9534f", "#9b59b6", "#16a085", "#e67e22", "#7f8c8d", "#c0392b", "#2c3e50"];
  function color(i) { return PAL[i % PAL.length]; }
  function hashParam(name) { var m = new RegExp("[#&]" + name + "=([^&]*)").exec(location.hash); try { return m ? decodeURIComponent(m[1]) : ""; } catch (e) { return ""; } }
  function setHash(obj) { var parts = []; for (var k in obj) if (obj[k] !== "" && obj[k] != null) parts.push(k + "=" + encodeURIComponent(obj[k])); location.hash = parts.join("&"); }
  function empty(msg) { box.appendChild(h("p", { class: "note" }, msg)); }
  var forest = C.hierarchy(graph);

  // ---- 階層ツリー ----
  function drawTree() {
    var bar = h("div", { class: "bar" }), open = h("button", { type: "button", class: "chip", id: "t-open" }, "すべて開く"), close = h("button", { type: "button", class: "chip", id: "t-close" }, "すべて閉じる");
    bar.appendChild(open); bar.appendChild(close); bar.appendChild(h("span", { id: "count" }, forest.roots.reduce(function (s0, r) { return s0 + C.countTree(r); }, 0) + " 件"));
    box.appendChild(bar);
    var root = h("div", { id: "tree2" });
    function node(t, depth) {
      if (!t.children.length) { var d = h("div", { class: "leaf" }); d.appendChild(link(t.href, (t.fz ? t.fz + " " : "") + t.title)); return d; }
      var det = h("details", {}); if (depth < 1) det.setAttribute("open", "");
      var sm = h("summary", {}); sm.appendChild(link(t.href, (t.fz ? t.fz + " " : "") + t.title)); sm.appendChild(h("span", { class: "chip" }, String(C.countTree(t) - 1)));
      det.appendChild(sm); t.children.forEach(function (c) { det.appendChild(node(c, depth + 1)); }); return det;
    }
    forest.roots.forEach(function (r) { root.appendChild(node(r, 0)); });
    box.appendChild(root);
    open.addEventListener("click", function () { root.querySelectorAll("details").forEach(function (d) { d.setAttribute("open", ""); }); });
    close.addEventListener("click", function () { root.querySelectorAll("details").forEach(function (d) { d.removeAttribute("open"); }); });
    if (!forest.roots.length) empty("ノートがありません。");
  }

  // ---- 孤立・未参照・未索引 ----
  function drawOrphans() {
    var o = C.orphans(graph), wrap = h("div", { class: "lists" });
    [["isolated", "孤立（出入りするリンクがない）", o.isolated], ["unreferenced", "未参照（どこからも参照されない）", o.unreferenced], ["unindexed", "未索引（どの索引・グループにも載っていない）", o.unindexed]].forEach(function (c) {
      var sec = h("section", { id: "o-" + c[0] }); sec.appendChild(h("h2", {}, c[1] + "：" + c[2].length + " / " + o.total));
      var ul = h("ul", {}); c[2].forEach(function (n) { var li = h("li", {}); li.appendChild(link(n.href, (n.fz ? n.fz + " " : "") + n.title)); ul.appendChild(li); });
      if (!c[2].length) ul.appendChild(h("li", { class: "note" }, "なし"));
      sec.appendChild(ul); wrap.appendChild(sec);
    });
    box.appendChild(wrap);
  }

  // ---- 隣接行列 ----
  function drawMatrix() {
    var topN = parseInt(hashParam("top"), 10) || 40, m = C.matrix(graph, topN);
    box.appendChild(h("p", { class: "note", id: "mx-info" }, "つながりの多い上位 " + m.ids.length + " 件 / 全 " + m.total + " 件。行 → 列の向き。セルの上にカーソルを置くと関係の種類。"));
    var tb = h("table", { class: "mx", id: "mx" }), head = h("tr", {}); head.appendChild(h("th", {}));
    m.titles.forEach(function (t, j) { var th = h("th", { class: "cl", scope: "col", title: t }, clip(t, 12)); head.appendChild(th); });
    tb.appendChild(head);
    m.ids.forEach(function (id, i) {
      var tr = h("tr", {}), th = h("th", { scope: "row", title: m.titles[i] }, clip(m.titles[i], 12)); tr.appendChild(th);
      m.cells[i].forEach(function (c, j) {
        var td = h("td", { class: c.n ? "cell" + Math.min(3, c.n) : "" }, c.n ? String(c.n) : "");
        if (c.n) td.setAttribute("title", m.titles[i] + " → " + m.titles[j] + "：" + Object.keys(c.kinds).map(function (k) { return k + " ×" + c.kinds[k]; }).join("、"));
        tr.appendChild(td);
      });
      tb.appendChild(tr);
    });
    box.appendChild(tb);
    if (!m.ids.length) empty("ノートがありません。");
  }

  // ---- Treemap ----
  function drawTreemap() {
    var W = 900, H = 560, t = C.treemap(notes, W, H), svg = s("svg", { viewBox: "0 0 " + W + " " + H, role: "img", "aria-label": "Treemap", id: "tm" });
    var gi = {}; t.groups.forEach(function (g, i) { gi[g.key] = i; });
    t.groups.forEach(function (g, i) {
      svg.appendChild(s("rect", { x: g.x, y: g.y, width: Math.max(0, g.w), height: Math.max(0, g.h), fill: color(i), "fill-opacity": "0.18", stroke: color(i) }));
      if (g.h > 24 && g.w > 40) svg.appendChild(s("text", { x: g.x + 4, y: g.y + 11, "font-size": "10", fill: "currentColor" }, clip(g.label, Math.floor(g.w / 7))));
    });
    t.notes.forEach(function (n) {
      var a = s("a", { href: n.href, class: "node" }), r = s("rect", { x: n.x, y: n.y, width: Math.max(0, n.w), height: Math.max(0, n.h), fill: color(gi[n.group]), "fill-opacity": "0.55", stroke: "#fff6" });
      r.appendChild(s("title", {}, n.label + "（" + n.value + " バイト）")); a.appendChild(r);
      if (n.w > 46 && n.h > 14) a.appendChild(s("text", { x: n.x + 3, y: n.y + 12, "font-size": "10", fill: "currentColor" }, clip(n.label, Math.floor(n.w / 7))));
      svg.appendChild(a);
    });
    box.appendChild(svg);
    if (!t.notes.length) empty("ノートがありません。");
  }

  // ---- Sunburst ----
  function drawSunburst() {
    var depth = parseInt(hashParam("depth"), 10) || 4, W = 640, cx = W / 2, cy = W / 2, ring = (W / 2 - 10) / (depth + 1);
    var bar = h("div", { class: "bar" }); bar.appendChild(h("label", {}, "深さ ")); var sel = h("select", { id: "sb-depth" });
    [2, 3, 4, 5, 6].forEach(function (d) { var o = h("option", { value: String(d) }, String(d)); if (d === depth) o.setAttribute("selected", ""); sel.appendChild(o); });
    bar.lastChild.appendChild(sel); box.appendChild(bar);
    var sb = C.sunburst(forest, depth), svg = s("svg", { viewBox: "0 0 " + W + " " + W, role: "img", "aria-label": "Sunburst", id: "sb" });
    var topIdx = {}, ti = 0;
    sb.arcs.forEach(function (a) { if (a.depth === 1) topIdx[a.id] = ti++; });
    var parentTop = {};
    forest.roots.forEach(function (r) { (function walk(t, top) { parentTop[t.id] = top; t.children.forEach(function (c) { walk(c, top); }); })(r, topIdx[r.id]); });
    sb.arcs.forEach(function (a) {
      var an = s("a", { href: a.href, class: "node" }), p = s("path", { d: C.arcPath(cx, cy, a.depth * ring, (a.depth + 1) * ring - 1, a.a0, a.a1), fill: color(parentTop[a.id] || 0), "fill-opacity": String(Math.max(0.3, 0.85 - a.depth * 0.12)), stroke: "#fff6" });
      p.appendChild(s("title", {}, (a.fz ? a.fz + " " : "") + a.title + (a.more ? "（このさき " + a.more + " 件）" : ""))); an.appendChild(p); svg.appendChild(an);
    });
    svg.appendChild(s("text", { x: cx, y: cy + 4, "text-anchor": "middle", "font-size": "12", fill: "currentColor" }, sb.leaves + " 葉"));
    box.appendChild(svg);
    sel.addEventListener("change", function () { setHash({ depth: sel.value }); location.reload(); });
    if (!sb.arcs.length) empty("ノートがありません。");
  }

  // ---- カンバン ----
  function todayIso() { var t = hashParam("today"); if (/^\d{4}-\d{2}-\d{2}$/.test(t)) return t; var d = new Date(); return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2); }
  function drawKanban() {
    var today = todayIso(), cols = C.kanban(window.GNOSIS_TASKS || [], today), wrap = h("div", { class: "cols", id: "kb" });
    box.appendChild(h("p", { class: "note" }, "基準日 " + today + "。タスクの完了・期日の変更は Gnosis（Vim の :GnosisAgenda）で行います。ここは表示だけです。"));
    cols.forEach(function (c) {
      var col = h("section", { class: "col", id: "kb-" + c.key }); col.appendChild(h("h2", {}, c.label + "（" + c.tasks.length + "）"));
      c.tasks.forEach(function (t) {
        var card = h("div", { class: "kcard" + (t.priority ? " prio-" + t.priority : "") }); card.appendChild(h("div", {}, t.text));
        var meta = h("div", { class: "meta" }, (t.due ? "期限 " + t.due + " ・ " : "") + (t.done_date ? "完了 " + t.done_date + " ・ " : "")); meta.appendChild(link(t.href, t.title)); card.appendChild(meta); col.appendChild(card);
      });
      if (!c.tasks.length) col.appendChild(h("p", { class: "note" }, "なし"));
      wrap.appendChild(col);
    });
    box.appendChild(wrap);
  }

  // ---- マインドマップ ----
  function drawMindmap() {
    var withKids = []; forest.roots.forEach(function (r) { (function w(t) { if (t.children.length) withKids.push(t); t.children.forEach(w); })(r); });
    var center = hashParam("n") || (withKids[0] && withKids[0].id) || (forest.roots[0] && forest.roots[0].id) || "", depth = parseInt(hashParam("depth"), 10) || 3;
    var bar = h("div", { class: "bar" }), sel = h("select", { id: "mm-center" }), ds = h("select", { id: "mm-depth" });
    forest.roots.forEach(function (r) { (function a(t) { var o = h("option", { value: t.id }, (t.fz ? t.fz + " " : "") + t.title); if (t.id === center) o.setAttribute("selected", ""); sel.appendChild(o); t.children.forEach(a); })(r); });
    [1, 2, 3, 4, 5].forEach(function (d) { var o = h("option", { value: String(d) }, String(d)); if (d === depth) o.setAttribute("selected", ""); ds.appendChild(o); });
    bar.appendChild(h("label", {}, "中心 ")); bar.lastChild.appendChild(sel); bar.appendChild(h("label", {}, "深さ ")); bar.lastChild.appendChild(ds); box.appendChild(bar);
    var W = 900, H = 640, mm = center ? C.mindmap(forest, center, depth, W / 2, H / 2, Math.min(W, H) / 2 / (depth + 0.6)) : null;
    if (!mm) { empty("ノートがありません。"); return; }
    var svg = s("svg", { viewBox: "0 0 " + W + " " + H, role: "img", "aria-label": "マインドマップ", id: "mm" });
    mm.edges.forEach(function (e) { svg.appendChild(s("line", { x1: e.x1, y1: e.y1, x2: e.x2, y2: e.y2, stroke: "#8888", "stroke-width": "1.5" })); });
    mm.nodes.forEach(function (n, i) {
      var g = s("g", { class: "node", "data-id": n.id, transform: "translate(" + n.x.toFixed(1) + "," + n.y.toFixed(1) + ")" }), a = s("a", { href: n.href });
      var rr = n.depth === 0 ? 9 : 6; a.appendChild(s("circle", { r: String(rr), fill: color(n.depth), stroke: "#fff" }));
      var t = s("text", { x: n.depth === 0 ? 0 : (Math.sin(n.angle) >= 0 ? 10 : -10), y: n.depth === 0 ? -14 : 4, "text-anchor": n.depth === 0 ? "middle" : (Math.sin(n.angle) >= 0 ? "start" : "end"), "font-size": "11", fill: "currentColor" }, clip(n.title, 14) + (n.more ? " ＋" + n.more : ""));
      a.appendChild(t); g.appendChild(a);
      var re = s("circle", { r: "3", fill: "none" }); g.appendChild(re); svg.appendChild(g);
    });
    box.appendChild(svg);
    function go() { setHash({ n: sel.value, depth: ds.value }); location.reload(); }
    sel.addEventListener("change", go); ds.addEventListener("change", go);
  }

  // ---- 成長 ----
  function drawGrowth() {
    var gr = C.growth(notes), W = 900, H = 320, pad = 40;
    if (!gr.months.length) { empty("作成日（time:）のあるノートがありません。"); return; }
    var svg = s("svg", { viewBox: "0 0 " + W + " " + H, role: "img", "aria-label": "成長", id: "gr" }), n = gr.months.length, bw = (W - 2 * pad) / n;
    var maxAdd = Math.max.apply(null, gr.months.map(function (m) { return m.added; }).concat([1])), maxTot = gr.months[n - 1].total || 1;
    svg.appendChild(s("line", { x1: pad, y1: H - pad, x2: W - pad, y2: H - pad, stroke: "#8888" }));
    gr.months.forEach(function (m, i) {
      var bh = (H - 2 * pad) * m.added / maxAdd, r = s("rect", { x: pad + i * bw + 1, y: H - pad - bh, width: Math.max(1, bw - 2), height: bh, fill: "#4a90d9", "fill-opacity": "0.7" });
      r.appendChild(s("title", {}, m.month + "：新しい " + m.added + " 件・累計 " + m.total + " 件")); svg.appendChild(r);
      if (n <= 24 || i % Math.ceil(n / 24) === 0) svg.appendChild(s("text", { x: pad + i * bw + bw / 2, y: H - pad + 12, "text-anchor": "middle", "font-size": "9", fill: "currentColor" }, m.month.slice(2)));
    });
    var pts = gr.months.map(function (m, i) { return (pad + i * bw + bw / 2).toFixed(1) + "," + (H - pad - (H - 2 * pad) * m.total / maxTot).toFixed(1); }).join(" ");
    svg.appendChild(s("polyline", { points: pts, fill: "none", stroke: "#e0a800", "stroke-width": "2" }));
    svg.appendChild(s("text", { x: pad, y: 14, "font-size": "11", fill: "currentColor" }, "棒：月ごとの新しいノート（最大 " + maxAdd + "）／線：累計（最大 " + maxTot + "）"));
    box.appendChild(svg);
    box.appendChild(h("p", { class: "note", id: "gr-info" }, "全 " + notes.length + " 件のうち、作成日がないもの " + gr.undated + " 件は含めていません。"));
  }

  // ---- 川（ストーリーリバー）----
  function drawRiver() {
    var r = C.river(notes), W = 900, H = 360, pad = 30;
    if (!r.months.length) { empty("作成日（time:）のあるノートがありません。"); return; }
    var svg = s("svg", { viewBox: "0 0 " + W + " " + H, role: "img", "aria-label": "ストーリーリバー", id: "rv" }), n = r.months.length, step = n > 1 ? (W - 2 * pad) / (n - 1) : 0, sc = (H - 2 * pad) / (r.max || 1), mid = H / 2;
    var legend = h("div", { class: "legend" });
    r.series.forEach(function (ser, k) {
      var top = ser.points.map(function (p, i) { return (pad + i * step).toFixed(1) + "," + (mid + p.y0 * sc).toFixed(1); });
      var bottom = ser.points.slice().reverse().map(function (p, i) { return (pad + (n - 1 - i) * step).toFixed(1) + "," + (mid + p.y1 * sc).toFixed(1); });
      var poly = s("polygon", { points: top.concat(bottom).join(" "), fill: color(k), "fill-opacity": "0.7", stroke: "#fff6" }); poly.appendChild(s("title", {}, ser.name + "：" + ser.points.reduce(function (a, p) { return a + p.v; }, 0) + " 件")); svg.appendChild(poly);
      var sp = h("span", {}); var sw = h("i", {}); sw.setAttribute("data-c", color(k)); sp.appendChild(sw); sp.appendChild(document.createTextNode(ser.name)); legend.appendChild(sp);
    });
    r.months.forEach(function (m, i) { if (n <= 12 || i % Math.ceil(n / 12) === 0) svg.appendChild(s("text", { x: pad + i * step, y: H - 8, "text-anchor": "middle", "font-size": "9", fill: "currentColor" }, m.slice(2))); });
    box.appendChild(svg); box.appendChild(legend);
    legend.querySelectorAll("i").forEach(function (i) { i.style.background = i.getAttribute("data-c"); });
  }

  // ---- 比較 ----
  function drawCompare() {
    var bar = h("div", { class: "bar" }), a = h("select", { id: "cmp-a" }), b = h("select", { id: "cmp-b" });
    var sorted = graph.nodes.slice().sort(function (x, y) { return String(x.title).localeCompare(String(y.title), "ja"); });
    var A = hashParam("a") || (sorted[0] && sorted[0].id) || "", B = hashParam("b") || (sorted[1] && sorted[1].id) || "";
    sorted.forEach(function (n) { [a, b].forEach(function (sel, i) { var o = h("option", { value: n.id }, (n.fz ? n.fz + " " : "") + n.title); if (n.id === (i ? B : A)) o.setAttribute("selected", ""); sel.appendChild(o); }); });
    bar.appendChild(h("label", {}, "A ")); bar.lastChild.appendChild(a); bar.appendChild(h("label", {}, "B ")); bar.lastChild.appendChild(b); box.appendChild(bar);
    var out = h("div", { id: "cmp" }); box.appendChild(out);
    function render() {
      out.textContent = ""; var c = C.compare(graph, a.value, b.value);
      if (!c || a.value === b.value) { out.appendChild(h("p", { class: "note" }, a.value === b.value ? "別々のノートを選んでください。" : "ノートがありません。")); return; }
      out.appendChild(h("p", { id: "cmp-sum" }, "共通 " + c.shared.length + "・A だけ " + c.onlyA.length + "・B だけ " + c.onlyB.length + "・近さ（Jaccard）" + c.jaccard.toFixed(2) + (c.direct.length ? "・直接の関係：" + c.direct.join("、") : "・直接の関係なし")));
      var wrap = h("div", { class: "lists" });
      [["共通のつながり", c.shared], ["A だけ（" + c.a.title + "）", c.onlyA], ["B だけ（" + c.b.title + "）", c.onlyB]].forEach(function (x) {
        var sec = h("section", {}); sec.appendChild(h("h2", {}, x[0] + "：" + x[1].length)); var ul = h("ul", {});
        x[1].forEach(function (n) { var li = h("li", {}); li.appendChild(link(n.href, n.title)); ul.appendChild(li); }); if (!x[1].length) ul.appendChild(h("li", { class: "note" }, "なし")); sec.appendChild(ul); wrap.appendChild(sec);
      });
      out.appendChild(wrap);
    }
    a.addEventListener("change", render); b.addEventListener("change", render); render();
  }

  // ---- Sankey ----
  function drawSankey() {
    var W = 800, H = 480, sk = C.sankey(graph, W, H);
    if (!sk.links.length) { empty("番号の違う枝どうしのつながりがありません。"); return; }
    var svg = s("svg", { viewBox: "0 0 " + (W + 120) + " " + H, role: "img", "aria-label": "Sankey", id: "sk" }), g = s("g", { transform: "translate(60,0)" });
    var idx = {}; sk.left.concat(sk.right).forEach(function (n) { if (!(n.name in idx)) idx[n.name] = Object.keys(idx).length; });
    sk.links.forEach(function (l) { var p = s("path", { d: l.path, fill: "none", stroke: color(idx[l.s]), "stroke-opacity": "0.45", "stroke-width": String(l.width) }); p.appendChild(s("title", {}, l.s + " → " + l.d + "：" + l.v + " 本")); g.appendChild(p); });
    [sk.left, sk.right].forEach(function (col, side) { col.forEach(function (n) {
      g.appendChild(s("rect", { x: n.x, y: n.y, width: 12, height: n.h, fill: color(idx[n.name]) }));
      g.appendChild(s("text", { x: side ? n.x - 4 : n.x + 16, y: n.y + Math.min(n.h, 14) - 3, "text-anchor": side ? "end" : "start", "font-size": "11", fill: "currentColor" }, "枝 " + n.name + "（" + n.v + "）"));
    }); });
    svg.appendChild(g); box.appendChild(svg);
    box.appendChild(h("p", { class: "note" }, "左が出るリンク、右が入るリンク。同じ番号の枝の中のリンクは数えません。"));
  }

  // ---- 地図 ----
  function drawMap() {
    var W = 900, H = 520, m = C.mapPoints(notes, W, H, 40);
    if (!m.points.length) { empty("location: 緯度, 経度 を書いたノートがありません。" + (m.invalid ? "（読めなかった位置 " + m.invalid + " 件）" : "")); return; }
    var svg = s("svg", { viewBox: "0 0 " + W + " " + H, role: "img", "aria-label": "地図", id: "mp" });
    svg.appendChild(s("rect", { x: 0, y: 0, width: W, height: H, fill: "#4a90d90f" }));
    for (var i = 1; i < 6; i++) { svg.appendChild(s("line", { x1: i * W / 6, y1: 0, x2: i * W / 6, y2: H, stroke: "#8883" })); svg.appendChild(s("line", { x1: 0, y1: i * H / 6, x2: W, y2: i * H / 6, stroke: "#8883" })); }
    m.points.forEach(function (p) {
      var a = s("a", { href: p.href, class: "node" }); a.appendChild(s("circle", { cx: p.x, cy: p.y, r: "6", fill: "#d9534f", stroke: "#fff" })); a.lastChild.appendChild(s("title", {}, p.title + "（" + p.lat + ", " + p.lon + "）"));
      a.appendChild(s("text", { x: p.x + 9, y: p.y + 4, "font-size": "11", fill: "currentColor" }, clip(p.title, 16))); svg.appendChild(a);
    });
    var b = m.bounds; svg.appendChild(s("text", { x: 6, y: H - 6, "font-size": "10", fill: "currentColor" }, "緯度 " + b.minLat + "〜" + b.maxLat + "・経度 " + b.minLon + "〜" + b.maxLon));
    box.appendChild(svg);
    box.appendChild(h("p", { class: "note", id: "mp-info" }, m.points.length + " 件" + (m.invalid ? "（位置が読めなかったもの " + m.invalid + " 件は除外）" : "") + "。地図の画像は使わず、位置関係だけを描いています。"));
  }

  // ---- 3D グラフ ----
  function draw3d() {
    var W = 800, H = 560, pos = C.layout3d(graph, 60), st = { ry: 0.6, rx: 0.3 }, ids = graph.nodes.map(function (n) { return n.id; }), byId = {}; graph.nodes.forEach(function (n) { byId[n.id] = n; });
    var bar = h("div", { class: "bar" });
    [["g3-left", "◀", function () { st.ry -= 0.3; }], ["g3-right", "▶", function () { st.ry += 0.3; }], ["g3-up", "▲", function () { st.rx -= 0.3; }], ["g3-down", "▼", function () { st.rx += 0.3; }]].forEach(function (b) {
      var bt = h("button", { type: "button", class: "chip", id: b[0] }, b[1]); bt.addEventListener("click", function () { b[2](); draw(); }); bar.appendChild(bt);
    });
    bar.appendChild(h("span", { class: "note" }, "ドラッグでも回せます。ノートの名前を押すと開きます。")); box.appendChild(bar);
    var svg = s("svg", { viewBox: "0 0 " + W + " " + H, role: "img", "aria-label": "3D グラフ", id: "g3" }); box.appendChild(svg);
    var edges = graph.edges.filter(function (e) { return e.s !== e.d && pos[e.s] && pos[e.d] && ["link", "context", "related", "parent_branch", "group", "branch_group", "child_branch"].indexOf(e.k) >= 0; });
    function draw() {
      var p = C.project3d(pos, st.ry, st.rx, W / 2, H / 2, 230, 6); svg.textContent = "";
      edges.forEach(function (e) { svg.appendChild(s("line", { x1: p[e.s].x.toFixed(1), y1: p[e.s].y.toFixed(1), x2: p[e.d].x.toFixed(1), y2: p[e.d].y.toFixed(1), stroke: "#8886" })); });
      ids.slice().sort(function (a, b) { return p[b].z - p[a].z; }).forEach(function (id) {
        var n = byId[id], a = s("a", { href: n.href, class: "node", "data-id": id });
        a.appendChild(s("circle", { cx: p[id].x.toFixed(1), cy: p[id].y.toFixed(1), r: (5 * p[id].r).toFixed(1), fill: n.group ? "#e0a800" : "#4a90d9", "fill-opacity": String(Math.max(0.35, Math.min(1, p[id].r)) ) }));
        a.appendChild(s("text", { x: (p[id].x + 8).toFixed(1), y: (p[id].y + 4).toFixed(1), "font-size": String(Math.round(10 * p[id].r)), fill: "currentColor" }, clip(n.title, 12))); svg.appendChild(a);
      });
      svg.setAttribute("data-ry", st.ry.toFixed(3));
    }
    var drag = null;
    svg.addEventListener("pointerdown", function (e) { drag = { x: e.clientX, y: e.clientY, ry: st.ry, rx: st.rx }; });
    window.addEventListener("pointermove", function (e) { if (!drag) return; st.ry = drag.ry + (e.clientX - drag.x) / 150; st.rx = drag.rx + (e.clientY - drag.y) / 150; draw(); });
    window.addEventListener("pointerup", function () { drag = null; });
    draw();
    if (!ids.length) empty("ノートがありません。");
  }

  // ---- スライド ----
  function drawSlides() {
    var decks = window.GNOSIS_SLIDES || [];
    if (!decks.length) { empty("front matter に slides: true を書いたノートがありません。"); return; }
    var cur = hashParam("n") || decks[0].id, deck = decks.filter(function (d) { return d.id === cur; })[0] || decks[0], i = Math.max(0, parseInt(hashParam("p"), 10) || 0);
    var bar = h("div", { class: "bar" }), sel = h("select", { id: "sl-deck" });
    decks.forEach(function (d) { var o = h("option", { value: d.id }, d.title); if (d.id === deck.id) o.setAttribute("selected", ""); sel.appendChild(o); });
    var prev = h("button", { type: "button", class: "chip", id: "sl-prev" }, "◀ 前"), next = h("button", { type: "button", class: "chip", id: "sl-next" }, "次 ▶"), full = h("button", { type: "button", class: "chip", id: "sl-full" }, "全画面"), pos = h("span", { id: "sl-pos" });
    [sel, prev, next, full, pos].forEach(function (e) { bar.appendChild(e); }); box.appendChild(bar);
    var stage = h("div", { id: "slide", tabindex: "0", "aria-live": "polite" }); box.appendChild(stage);
    function show() {
      i = Math.max(0, Math.min(deck.slides.length - 1, i)); stage.textContent = "";
      var doc = new DOMParser().parseFromString("<body>" + (deck.slides[i] || "") + "</body>", "text/html");
      Array.prototype.slice.call(doc.body.childNodes).forEach(function (n) { stage.appendChild(document.importNode(n, true)); });
      pos.textContent = (deck.slides.length ? i + 1 : 0) + " / " + deck.slides.length; prev.disabled = i <= 0; next.disabled = i >= deck.slides.length - 1;
    }
    prev.addEventListener("click", function () { i--; show(); }); next.addEventListener("click", function () { i++; show(); });
    full.addEventListener("click", function () { stage.classList.toggle("full"); stage.focus(); });
    sel.addEventListener("change", function () { setHash({ n: sel.value }); location.reload(); });
    document.addEventListener("keydown", function (e) {
      if (e.target && e.target.tagName === "SELECT") return;
      if (e.key === "ArrowRight" || e.key === "PageDown" || e.key === " ") { i++; show(); e.preventDefault(); }
      else if (e.key === "ArrowLeft" || e.key === "PageUp") { i--; show(); e.preventDefault(); }
      else if (e.key === "Home") { i = 0; show(); } else if (e.key === "End") { i = deck.slides.length - 1; show(); }
      else if (e.key === "Escape") stage.classList.remove("full");
    });
    show();
  }

  // ---- ホワイトボード ----
  function drawWhiteboard() {
    var W = 1200, H = 800, CW = 176, CH = 54, KEY = "gnosis-whiteboard";
    var saved = {}; try { saved = JSON.parse(localStorage.getItem(KEY) || "{}") || {}; } catch (e) {}
    var bar = h("div", { class: "bar" }), auto = h("button", { type: "button", class: "chip", id: "wb-auto" }, "整列"), reset = h("button", { type: "button", class: "chip", id: "wb-reset" }, "位置を忘れる");
    bar.appendChild(auto); bar.appendChild(reset); bar.appendChild(h("span", { class: "note" }, "カードをドラッグ。位置はこのブラウザだけに覚えます（ノートには書きません）。")); box.appendChild(bar);
    var stage = h("div", { id: "stage" }); box.appendChild(stage);
    var ids = notes.map(function (n) { return n.id; }), base = C.autoPlace(ids, 5, CW + 12, CH + 12, 8), cards = {};
    function save() { try { localStorage.setItem(KEY, JSON.stringify(saved)); } catch (e) {} }
    function place(id) { var p = saved[id] || base[id]; cards[id].style.left = p.x + "px"; cards[id].style.top = p.y + "px"; cards[id].setAttribute("data-x", String(p.x)); cards[id].setAttribute("data-y", String(p.y)); }
    notes.forEach(function (n) {
      var c = h("div", { class: "wcard", "data-id": n.id, tabindex: "0" }); c.appendChild(h("div", {}, (n.fz ? n.fz + " " : "") + n.title)); c.appendChild(link(n.href, "開く", { draggable: "false" })); stage.appendChild(c); cards[n.id] = c; place(n.id);
      var drag = null;
      c.addEventListener("pointerdown", function (e) { if (e.target.tagName === "A") return; var p = saved[n.id] || base[n.id]; drag = { x: e.clientX, y: e.clientY, px: p.x, py: p.y }; c.classList.add("drag"); c.setPointerCapture(e.pointerId); });
      c.addEventListener("pointermove", function (e) { if (!drag) return; var np = C.clampPos({ x: C.snap(drag.px + e.clientX - drag.x, 8), y: C.snap(drag.py + e.clientY - drag.y, 8) }, stage.clientWidth || W, stage.clientHeight || H, CW, CH); saved[n.id] = np; place(n.id); });
      c.addEventListener("pointerup", function () { if (drag) { drag = null; c.classList.remove("drag"); save(); } });
      c.addEventListener("keydown", function (e) {   // キーボードでも動かせる（矢印で 8px、Shift で 40px）
        var d = e.shiftKey ? 40 : 8, p = saved[n.id] || base[n.id], np = null;
        if (e.key === "ArrowLeft") np = { x: p.x - d, y: p.y }; else if (e.key === "ArrowRight") np = { x: p.x + d, y: p.y }; else if (e.key === "ArrowUp") np = { x: p.x, y: p.y - d }; else if (e.key === "ArrowDown") np = { x: p.x, y: p.y + d };
        if (np) { saved[n.id] = C.clampPos(np, stage.clientWidth || W, stage.clientHeight || H, CW, CH); place(n.id); save(); e.preventDefault(); }
      });
    });
    auto.addEventListener("click", function () { saved = {}; ids.forEach(place); save(); });
    reset.addEventListener("click", function () { saved = {}; try { localStorage.removeItem(KEY); } catch (e) {} ids.forEach(place); });
    if (!notes.length) empty("ノートがありません。");
  }

  // ---- ギャラリー ----
  function drawGallery() {
    var files = window.GNOSIS_FILES || [], st = { type: "all", q: "" }, bar = h("div", { class: "bar" }), sel = h("select", { id: "ga-type" }), q = h("input", { type: "search", id: "ga-q", placeholder: "ファイル名・ノートの題" });
    [["all", "すべて"], ["image", "画像"], ["pdf", "PDF"], ["audio", "音声"], ["video", "動画"], ["other", "その他"]].forEach(function (t) { sel.appendChild(h("option", { value: t[0] }, t[1])); });
    bar.appendChild(sel); bar.appendChild(q); var cnt = h("span", { id: "count" }); bar.appendChild(cnt); box.appendChild(bar);
    var grid = h("div", { class: "gal", id: "ga" }); box.appendChild(grid);
    var ICON = { pdf: "📄", audio: "🎵", video: "🎞", other: "📎" };
    function render() {
      grid.textContent = ""; var list = C.gallery(files, st.type, st.q);
      list.forEach(function (f) {
        var t = f.type || C.fileType(f.name), it = h("div", { class: "gitem" });
        if (t === "image") { var a = h("a", { href: f.name }); a.appendChild(h("img", { src: f.name, alt: f.name, loading: "lazy" })); it.appendChild(a); }
        else { var a2 = h("a", { href: f.name }); a2.appendChild(h("div", { class: "ico" }, ICON[t] || "📎")); it.appendChild(a2); }
        it.appendChild(h("div", {}, clip(f.name, 28)));
        (f.notes || []).forEach(function (n) { var d = h("div", { class: "note" }); d.appendChild(link(n.href, "↩ " + n.title)); it.appendChild(d); });
        if (!(f.notes || []).length) it.appendChild(h("div", { class: "note" }, "どのノートからも参照されていません"));
        grid.appendChild(it);
      });
      cnt.textContent = list.length + " / " + files.length + " 件";
    }
    sel.addEventListener("change", function () { st.type = sel.value; render(); });
    q.addEventListener("input", function () { st.q = q.value; render(); });
    render();
    if (!files.length) empty("コピーされた添付がありません。");
  }

  var VIEWS = { tree: drawTree, orphans: drawOrphans, matrix: drawMatrix, treemap: drawTreemap, sunburst: drawSunburst, kanban: drawKanban, mindmap: drawMindmap, growth: drawGrowth, river: drawRiver,
                compare: drawCompare, sankey: drawSankey, map: drawMap, graph3d: draw3d, slides: drawSlides, whiteboard: drawWhiteboard, gallery: drawGallery };
  if (VIEWS[view] && box) VIEWS[view]();
})();
