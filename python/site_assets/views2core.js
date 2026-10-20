// 追加ビューの核（DOM に触れない純関数）。階層ツリー・孤立ノート・隣接行列・Treemap・Sunburst・カンバン・成長・川・比較・マインドマップ・Sankey・地図・3D・ホワイトボード・ギャラリー。（スライドの分割は書き出し側の Python が行う）
// データ: window.GNOSIS_NOTES（ノート）, window.GNOSIS_GRAPH（節点と辺）, window.GNOSIS_TASKS（タスク）, window.GNOSIS_FILES（添付）, window.GNOSIS_SLIDES（スライド）。
(function (root) {
  var REAL = ["link", "context", "related", "parent_branch", "group", "branch_group", "child_branch"];
  function cmpStr(a, b) { return String(a || "").localeCompare(String(b || ""), "ja"); }
  function fzCmp(a, b) { return root.FzNav && root.FzNav.compare ? root.FzNav.compare(a, b) : cmpStr(a, b); }
  function byId(graph) { var m = {}; graph.nodes.forEach(function (n) { m[n.id] = n; }); return m; }
  function topFz(fz) { var m = /^\d+/.exec(fz || ""); return m ? m[0] : ""; }

  // ---- 階層ツリー（フォルダではなく、ブランチ・グループ・番号による関係の階層）----
  // 親は 1 つだけ選ぶ: ParentBranch（子→親）> BranchGroup/ChildBranch（親→子）> 番号の親子 > Group（所属）。循環は切る。
  var PARENT_RANK = { parent_branch: 0, branch_group: 1, child_branch: 1, folgezettel: 2, group: 3 };
  function hierarchy(graph) {
    var nodes = byId(graph), best = {};
    function offer(child, parent, rank) {
      if (child === parent || !nodes[child] || !nodes[parent]) return;
      if (!(child in best) || rank < best[child].rank) best[child] = { parent: parent, rank: rank };
    }
    graph.edges.forEach(function (e) {
      if (e.k === "parent_branch" || e.k === "folgezettel" || e.k === "group") offer(e.s, e.d, PARENT_RANK[e.k]);
      else if (e.k === "branch_group" || e.k === "child_branch") offer(e.d, e.s, PARENT_RANK[e.k]);
    });
    // 循環を切る: 親をたどって自分に戻るノートは、その親を外して根にする
    Object.keys(best).forEach(function (id) {
      var seen = {}, cur = id;
      seen[id] = true;
      while (cur in best) {
        cur = best[cur].parent;
        if (seen[cur]) { delete best[id]; break; }
        seen[cur] = true;
      }
    });
    var kids = {};
    Object.keys(best).forEach(function (c) { (kids[best[c].parent] = kids[best[c].parent] || []).push(c); });
    function build(id) {
      var n = nodes[id], list = (kids[id] || []).slice().sort(function (a, b) { return fzCmp(nodes[a].fz, nodes[b].fz) || cmpStr(nodes[a].title, nodes[b].title); });
      return { id: id, title: n.title, fz: n.fz || "", href: n.href, group: !!n.group, children: list.map(build) };
    }
    var roots = graph.nodes.filter(function (n) { return !(n.id in best); })
      .sort(function (a, b) { return (a.fz ? 0 : 1) - (b.fz ? 0 : 1) || fzCmp(a.fz, b.fz) || cmpStr(a.title, b.title); });
    return { roots: roots.map(function (n) { return build(n.id); }), count: graph.nodes.length };
  }
  function countTree(t) { return 1 + t.children.reduce(function (s, c) { return s + countTree(c); }, 0); }
  function depthOf(t) { return 1 + t.children.reduce(function (m, c) { return Math.max(m, depthOf(c)); }, 0); }

  // ---- 孤立・未参照・未索引 ----
  function orphans(graph) {
    var nodes = byId(graph), inn = {}, out = {}, member = {};
    graph.nodes.forEach(function (n) { inn[n.id] = 0; out[n.id] = 0; });
    graph.edges.forEach(function (e) {
      if (REAL.indexOf(e.k) < 0 || e.s === e.d || !nodes[e.s] || !nodes[e.d]) return;
      out[e.s]++; inn[e.d]++;
      if (e.k === "group") member[e.s] = true;
    });
    // 索引に載っている: Group で属する、またはグループ/索引ノートから（リンク・BranchGroup・ChildBranch で）挙げられている
    graph.edges.forEach(function (e) {
      if (nodes[e.s] && nodes[e.s].group && nodes[e.d] && (e.k === "link" || e.k === "branch_group" || e.k === "child_branch")) member[e.d] = true;
    });
    var isolated = [], unreferenced = [], unindexed = [];
    graph.nodes.forEach(function (n) {
      var row = { id: n.id, title: n.title, fz: n.fz || "", href: n.href, in: inn[n.id], out: out[n.id] };
      if (!inn[n.id] && !out[n.id]) isolated.push(row);
      else if (!inn[n.id]) unreferenced.push(row);
      if (!n.group && !member[n.id]) unindexed.push(row);
    });
    var srt = function (l) { return l.sort(function (a, b) { return cmpStr(a.title, b.title); }); };
    return { isolated: srt(isolated), unreferenced: srt(unreferenced), unindexed: srt(unindexed), total: graph.nodes.length };
  }

  // ---- 隣接行列（次数の大きい順に上位 N）----
  function matrix(graph, top) {
    var deg = {}, nodes = byId(graph);
    graph.nodes.forEach(function (n) { deg[n.id] = 0; });
    graph.edges.forEach(function (e) { if (e.s !== e.d && nodes[e.s] && nodes[e.d]) { deg[e.s]++; deg[e.d]++; } });
    var ids = graph.nodes.map(function (n) { return n.id; }).sort(function (a, b) { return deg[b] - deg[a] || cmpStr(nodes[a].title, nodes[b].title); }).slice(0, top || 40);
    var idx = {}; ids.forEach(function (id, i) { idx[id] = i; });
    var cells = ids.map(function () { return ids.map(function () { return { n: 0, kinds: {} }; }); });
    graph.edges.forEach(function (e) {
      if (e.s === e.d || !(e.s in idx) || !(e.d in idx)) return;
      var c = cells[idx[e.s]][idx[e.d]]; c.n++; c.kinds[e.k] = (c.kinds[e.k] || 0) + 1;
    });
    var max = 0; cells.forEach(function (r) { r.forEach(function (c) { if (c.n > max) max = c.n; }); });
    return { ids: ids, titles: ids.map(function (i) { return nodes[i].title; }), cells: cells, max: max, total: graph.nodes.length };
  }

  // ---- Treemap（squarified）----
  function worst(row, side) {
    var s = row.reduce(function (a, r) { return a + r.area; }, 0), mx = Math.max.apply(null, row.map(function (r) { return r.area; })), mn = Math.min.apply(null, row.map(function (r) { return r.area; }));
    return Math.max(side * side * mx / (s * s), (s * s) / (side * side * mn));
  }
  function squarify(items, x, y, w, h) {
    var total = items.reduce(function (s, i) { return s + i.value; }, 0), out = [];
    if (!items.length || total <= 0 || w <= 0 || h <= 0) return out;
    var scale = (w * h) / total, rest = items.filter(function (i) { return i.value > 0; })
      .map(function (i) { return { item: i, area: i.value * scale }; }).sort(function (a, b) { return b.area - a.area; });
    var cx = x, cy = y, cw = w, ch = h;
    while (rest.length) {
      var side = Math.min(cw, ch), row = [rest[0]], i = 1;
      while (i < rest.length && worst(row.concat([rest[i]]), side) <= worst(row, side)) { row.push(rest[i]); i++; }
      var rs = row.reduce(function (a, r) { return a + r.area; }, 0), horizontal = cw >= ch, thick = rs / side, off = 0;
      row.forEach(function (r) {
        var len = r.area / thick;
        out.push(horizontal ? { item: r.item, x: cx, y: cy + off, w: thick, h: len } : { item: r.item, x: cx + off, y: cy, w: len, h: thick });
        off += len;
      });
      if (horizontal) { cx += thick; cw -= thick; } else { cy += thick; ch -= thick; }
      rest = rest.slice(row.length);
    }
    return out;
  }
  // 番号の最上位（1, 2, 3…）ごとにまとめ、その中をノートごとに分ける。値はサイズ（バイト）。番号なしは 1 つにまとめる
  function treemap(notes, w, h) {
    var groups = {};
    notes.forEach(function (n) { var k = topFz(n.fz) || "（番号なし）"; (groups[k] = groups[k] || []).push(n); });
    var gi = Object.keys(groups).map(function (k) {
      var items = groups[k], title = (items.filter(function (n) { return n.fz === k; })[0] || {}).title;
      return { key: k, label: title ? k + " " + title : k, value: items.reduce(function (s, n) { return s + Math.max(1, n.size || 1); }, 0), notes: items };
    });
    var outer = squarify(gi, 0, 0, w, h), leaves = [], cells = [];
    outer.forEach(function (g) {
      cells.push({ type: "group", key: g.item.key, label: g.item.label, x: g.x, y: g.y, w: g.w, h: g.h, value: g.item.value });
      var pad = Math.min(3, g.w / 10, g.h / 10), head = g.h > 24 && g.w > 40 ? 14 : 0;
      var inner = g.item.notes.map(function (n) { return { id: n.id, label: n.title, value: Math.max(1, n.size || 1), href: n.href }; });
      squarify(inner, g.x + pad, g.y + pad + head, Math.max(0, g.w - 2 * pad), Math.max(0, g.h - 2 * pad - head)).forEach(function (r) {
        leaves.push({ type: "note", id: r.item.id, label: r.item.label, href: r.item.href, x: r.x, y: r.y, w: r.w, h: r.h, value: r.item.value, group: g.item.key });
      });
    });
    return { groups: cells, notes: leaves };
  }

  // ---- Sunburst / マインドマップ（木の放射状配置）----
  function leafCount(t) { return t.children.length ? t.children.reduce(function (s, c) { return s + leafCount(c); }, 0) : 1; }
  function limitDepth(t, d) { return { id: t.id, title: t.title, fz: t.fz, href: t.href, group: t.group, children: d <= 1 ? [] : t.children.map(function (c) { return limitDepth(c, d - 1); }), more: d <= 1 ? t.children.length : 0 }; }
  function sunburst(forest, maxDepth, rings) {
    var tree = { id: "", title: "", children: forest.roots.map(function (r) { return limitDepth(r, maxDepth || 4); }), fz: "" }, arcs = [];
    var total = leafCount(tree), R = rings || 1;
    (function place(t, depth, a0, a1) {
      if (depth > 0) arcs.push({ id: t.id, title: t.title, fz: t.fz, href: t.href, depth: depth, a0: a0, a1: a1, more: t.more || 0 });
      var span = a1 - a0, cur = a0;
      t.children.forEach(function (c) { var s = span * leafCount(c) / leafCount(t); place(c, depth + 1, cur, cur + s); cur += s; });
    })(tree, 0, 0, 2 * Math.PI);
    return { arcs: arcs, leaves: total, rings: R };
  }
  function polar(cx, cy, r, a) { return [cx + r * Math.sin(a), cy - r * Math.cos(a)]; }
  function arcPath(cx, cy, r0, r1, a0, a1) {
    if (a1 - a0 >= 2 * Math.PI - 1e-6) a1 = a0 + 2 * Math.PI - 1e-4;                 // 全周は描けないので少し欠く
    var p0 = polar(cx, cy, r1, a0), p1 = polar(cx, cy, r1, a1), p2 = polar(cx, cy, r0, a1), p3 = polar(cx, cy, r0, a0), large = a1 - a0 > Math.PI ? 1 : 0;
    function f(p) { return p[0].toFixed(2) + " " + p[1].toFixed(2); }
    return "M" + f(p0) + "A" + r1 + " " + r1 + " 0 " + large + " 1 " + f(p1) + "L" + f(p2) + "A" + r0 + " " + r0 + " 0 " + large + " 0 " + f(p3) + "Z";
  }
  // マインドマップ: 中心のノートから、ツリーの枝を放射状に。depth は中心から何段まで
  function findNode(t, id) {
    if (t.id === id) return t;
    for (var i = 0; i < t.children.length; i++) { var r = findNode(t.children[i], id); if (r) return r; }
    return null;
  }
  function mindmap(forest, centerId, depth, cx, cy, ringGap) {
    var center = null;
    for (var i = 0; i < forest.roots.length && !center; i++) center = findNode(forest.roots[i], centerId);
    if (!center) return null;
    var t = limitDepth(center, (depth || 3) + 1), nodes = [], edges = [], gap = ringGap || 110;      // 深さ = 中心から何段先まで(1 なら中心と直接の子)
    (function place(n, d, a0, a1, parent) {
      var mid = (a0 + a1) / 2, p = d === 0 ? [cx, cy] : polar(cx, cy, d * gap, mid);
      var rec = { id: n.id, title: n.title, fz: n.fz, href: n.href, x: p[0], y: p[1], depth: d, angle: mid, more: n.more || 0 };
      nodes.push(rec);
      if (parent) edges.push({ from: parent.id, to: n.id, x1: parent.x, y1: parent.y, x2: p[0], y2: p[1] });
      var cur = a0;
      n.children.forEach(function (c) { var s = (a1 - a0) * leafCount(c) / leafCount(n); place(c, d + 1, cur, cur + s, rec); cur += s; });
    })(t, 0, 0, 2 * Math.PI, null);
    return { nodes: nodes, edges: edges };
  }

  // ---- カンバン（Markdown タスクの列。表示専用）----
  function addDays(iso, n) { var d = new Date(iso + "T00:00:00Z"); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); }
  function kanban(tasks, today) {
    var soon = addDays(today, 7), cols = [["overdue", "期限切れ"], ["today", "今日"], ["soon", "7 日以内"], ["later", "それ以降"], ["undated", "期限なし"], ["done", "完了"]], by = {};
    cols.forEach(function (c) { by[c[0]] = []; });
    tasks.forEach(function (t) {
      if (t.done) { by.done.push(t); return; }
      if (t.start && t.start > today) return;                                         // 開始日前は出さない
      var d = t.due || t.scheduled || "";
      var k = !d ? "undated" : d < today ? "overdue" : d === today ? "today" : d <= soon ? "soon" : "later";
      by[k].push(t);
    });
    var rank = { high: 0, medium: 1, low: 2, "": 3 };
    Object.keys(by).forEach(function (k) {
      by[k].sort(function (a, b) { return (a.due || a.scheduled || "9999").localeCompare(b.due || b.scheduled || "9999") || (rank[a.priority || ""] - rank[b.priority || ""]) || cmpStr(a.text, b.text); });
    });
    by.done.sort(function (a, b) { return (b.done_date || "").localeCompare(a.done_date || ""); });
    by.done = by.done.slice(0, 30);                                                   // 完了は新しい 30 件まで
    return cols.map(function (c) { return { key: c[0], label: c[1], tasks: by[c[0]] }; });
  }

  // ---- 成長（月ごとの新規と累計）と、川（番号の枝ごとの積み上げ）----
  function monthOf(n) { return (n.time || "").slice(0, 7); }
  function monthsBetween(a, b) {
    var out = [], y = +a.slice(0, 4), m = +a.slice(5, 7), ey = +b.slice(0, 4), em = +b.slice(5, 7);
    while (y < ey || (y === ey && m <= em)) { out.push(y + "-" + ("0" + m).slice(-2)); m++; if (m > 12) { m = 1; y++; } }
    return out;
  }
  function growth(notes) {
    var dated = notes.filter(monthOf), count = {};
    dated.forEach(function (n) { count[monthOf(n)] = (count[monthOf(n)] || 0) + 1; });
    var keys = Object.keys(count).sort();
    if (!keys.length) return { months: [], undated: notes.length };
    var months = monthsBetween(keys[0], keys[keys.length - 1]), cum = 0;
    return { months: months.map(function (m) { cum += count[m] || 0; return { month: m, added: count[m] || 0, total: cum }; }), undated: notes.length - dated.length };
  }
  // 川: 月ごと × 番号の最上位ごとの本数を、中心線に対して対称に積む（ストリームグラフ）
  function river(notes) {
    var dated = notes.filter(monthOf);
    if (!dated.length) return { months: [], series: [] };
    var keys = dated.map(monthOf).sort(), months = monthsBetween(keys[0], keys[keys.length - 1]), by = {};
    dated.forEach(function (n) { var s = topFz(n.fz) || "（番号なし）"; by[s] = by[s] || {}; by[s][monthOf(n)] = (by[s][monthOf(n)] || 0) + 1; });
    var names = Object.keys(by).sort(function (a, b) { return a === "（番号なし）" ? 1 : b === "（番号なし）" ? -1 : fzCmp(a, b); });
    var totals = months.map(function (m) { return names.reduce(function (s, k) { return s + (by[k][m] || 0); }, 0); });
    var maxTotal = Math.max.apply(null, totals.concat([1]));
    var series = names.map(function (k) { return { name: k, points: [] }; });
    months.forEach(function (m, i) {
      var y = -totals[i] / 2;
      names.forEach(function (k, j) { var v = by[k][m] || 0; series[j].points.push({ month: m, v: v, y0: y, y1: y + v }); y += v; });
    });
    return { months: months, series: series, max: maxTotal };
  }

  // ---- 2 つのノートの比較 ----
  function compare(graph, a, b) {
    var nodes = byId(graph), nb = {}, direct = [];
    graph.nodes.forEach(function (n) { nb[n.id] = {}; });
    graph.edges.forEach(function (e) {
      if (REAL.indexOf(e.k) < 0 || e.s === e.d || !nodes[e.s] || !nodes[e.d]) return;
      nb[e.s][e.d] = true; nb[e.d][e.s] = true;
      if ((e.s === a && e.d === b) || (e.s === b && e.d === a)) direct.push(e.k);
    });
    if (!nodes[a] || !nodes[b]) return null;
    var A = Object.keys(nb[a]).filter(function (x) { return x !== b; }), B = Object.keys(nb[b]).filter(function (x) { return x !== a; });
    var setB = {}; B.forEach(function (x) { setB[x] = true; });
    var shared = A.filter(function (x) { return setB[x]; });
    var onlyA = A.filter(function (x) { return !setB[x]; }), setA = {}; A.forEach(function (x) { setA[x] = true; });
    var onlyB = B.filter(function (x) { return !setA[x]; });
    var union = A.length + B.length - shared.length;
    var t = function (ids) { return ids.map(function (i) { return { id: i, title: nodes[i].title, href: nodes[i].href }; }).sort(function (x, y) { return cmpStr(x.title, y.title); }); };
    return { a: nodes[a], b: nodes[b], direct: direct.filter(function (k, i) { return direct.indexOf(k) === i; }), shared: t(shared), onlyA: t(onlyA), onlyB: t(onlyB), jaccard: union ? shared.length / union : 0 };
  }

  // ---- Sankey（番号の枝から枝への関係の流れ）----
  function sankey(graph, w, h) {
    var nodes = byId(graph), key = function (id) { return topFz(nodes[id].fz) || "（番号なし）"; }, flow = {};
    graph.edges.forEach(function (e) {
      if (REAL.indexOf(e.k) < 0 || !nodes[e.s] || !nodes[e.d]) return;
      var a = key(e.s), b = key(e.d);
      if (a === b) return;                                                          // 同じ枝の中は流れに数えない
      flow[a + "\u0000" + b] = (flow[a + "\u0000" + b] || 0) + 1;
    });
    var links = Object.keys(flow).map(function (k) { var p = k.split("\u0000"); return { s: p[0], d: p[1], v: flow[k] }; });
    if (!links.length) return { left: [], right: [], links: [] };
    var out = {}, inn = {};
    links.forEach(function (l) { out[l.s] = (out[l.s] || 0) + l.v; inn[l.d] = (inn[l.d] || 0) + l.v; });
    var total = links.reduce(function (s, l) { return s + l.v; }, 0), pad = 8;
    function column(names, sizes, x) {
      names.sort(function (a, b) { return sizes[b] - sizes[a] || cmpStr(a, b); });
      var usable = h - pad * (names.length - 1), y = 0, res = {};
      names.forEach(function (n) { var hh = Math.max(2, usable * sizes[n] / total); res[n] = { name: n, x: x, y: y, h: hh, v: sizes[n], used: 0 }; y += hh + pad; });
      return res;
    }
    var L = column(Object.keys(out), out, 0), R = column(Object.keys(inn), inn, w - 12), scale = function (n, v, sizes) { return n.h * v / sizes[n.name]; };
    links.sort(function (a, b) { return b.v - a.v || cmpStr(a.s, b.s) || cmpStr(a.d, b.d); });
    var ribbons = links.map(function (l) {
      var s = L[l.s], d = R[l.d], hs = scale(s, l.v, out), hd = scale(d, l.v, inn), y0 = s.y + s.used, y1 = d.y + d.used;
      s.used += hs; d.used += hd;
      var x0 = s.x + 12, x1 = d.x, mx = (x0 + x1) / 2;
      return { s: l.s, d: l.d, v: l.v, w0: hs, w1: hd, path: "M" + x0 + " " + (y0 + hs / 2) + "C" + mx + " " + (y0 + hs / 2) + " " + mx + " " + (y1 + hd / 2) + " " + x1 + " " + (y1 + hd / 2), width: Math.max(1, (hs + hd) / 2) };
    });
    return { left: Object.keys(L).map(function (k) { return L[k]; }), right: Object.keys(R).map(function (k) { return R[k]; }), links: ribbons };
  }

  // ---- 地図（位置情報のあるノート。タイルは使わず、緯度経度を平面に置く）----
  function parseLoc(s) {
    var m = /^\s*(-?\d+(?:\.\d+)?)\s*[,\s]\s*(-?\d+(?:\.\d+)?)\s*$/.exec(s || "");
    if (!m) return null;
    var lat = +m[1], lon = +m[2];
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 ? { lat: lat, lon: lon } : null;
  }
  function mapPoints(notes, w, h, pad) {
    pad = pad == null ? 30 : pad;
    var pts = notes.map(function (n) { var p = parseLoc(n.location); return p ? { id: n.id, title: n.title, href: n.href, lat: p.lat, lon: p.lon } : null; }).filter(Boolean);
    if (!pts.length) return { points: [], bounds: null, invalid: notes.filter(function (n) { return n.location && !parseLoc(n.location); }).length };
    var minLat = Math.min.apply(null, pts.map(function (p) { return p.lat; })), maxLat = Math.max.apply(null, pts.map(function (p) { return p.lat; }));
    var minLon = Math.min.apply(null, pts.map(function (p) { return p.lon; })), maxLon = Math.max.apply(null, pts.map(function (p) { return p.lon; }));
    var dLat = Math.max(maxLat - minLat, 0.01), dLon = Math.max(maxLon - minLon, 0.01);
    var sx = (w - 2 * pad) / dLon, sy = (h - 2 * pad) / dLat, s = Math.min(sx, sy), ox = pad + ((w - 2 * pad) - dLon * s) / 2, oy = pad + ((h - 2 * pad) - dLat * s) / 2;
    return { points: pts.map(function (p) { return { id: p.id, title: p.title, href: p.href, lat: p.lat, lon: p.lon, x: ox + (p.lon - minLon) * s, y: oy + (maxLat - p.lat) * s }; }),
             bounds: { minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon }, invalid: notes.filter(function (n) { return n.location && !parseLoc(n.location); }).length };
  }

  // ---- 3D グラフ（任意。回転と投影だけ。配置は決定的）----
  function layout3d(graph, iterations) {
    var n = graph.nodes.length, pos = {}, ids = graph.nodes.map(function (x) { return x.id; });
    ids.forEach(function (id, i) {                                                       // フィボナッチ球で初期配置（乱数を使わない）
      var k = (i + 0.5) / n, phi = Math.acos(1 - 2 * k), th = Math.PI * (1 + Math.sqrt(5)) * i;
      pos[id] = [Math.cos(th) * Math.sin(phi), Math.sin(th) * Math.sin(phi), Math.cos(phi)];
    });
    var edges = graph.edges.filter(function (e) { return e.s !== e.d && pos[e.s] && pos[e.d] && REAL.indexOf(e.k) >= 0; });
    for (var it = 0; it < (iterations == null ? 60 : iterations); it++) {
      var f = {}; ids.forEach(function (id) { f[id] = [0, 0, 0]; });
      edges.forEach(function (e) {
        var a = pos[e.s], b = pos[e.d], d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], len = Math.sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]) || 1e-6, k = 0.02 * (len - 0.5) / len;
        for (var c = 0; c < 3; c++) { f[e.s][c] += d[c] * k; f[e.d][c] -= d[c] * k; }
      });
      if (n <= 400) for (var i = 0; i < n; i++) for (var j = i + 1; j < n; j++) {
        var a2 = pos[ids[i]], b2 = pos[ids[j]], dd = [a2[0] - b2[0], a2[1] - b2[1], a2[2] - b2[2]], d2 = dd[0] * dd[0] + dd[1] * dd[1] + dd[2] * dd[2] + 0.01, k2 = 0.004 / d2;
        for (var c2 = 0; c2 < 3; c2++) { f[ids[i]][c2] += dd[c2] * k2; f[ids[j]][c2] -= dd[c2] * k2; }
      }
      ids.forEach(function (id) { for (var c = 0; c < 3; c++) pos[id][c] += Math.max(-0.1, Math.min(0.1, f[id][c])); });
    }
    // 重心を原点に寄せ、いちばん遠いノートが半径 1 になるように拡縮する（枠からはみ出さず、手前のノートだけ極端に大きくならない）
    if (n) {
      var cen = [0, 0, 0]; ids.forEach(function (id) { for (var c = 0; c < 3; c++) cen[c] += pos[id][c] / n; });
      var far = 1e-9; ids.forEach(function (id) { for (var c = 0; c < 3; c++) pos[id][c] -= cen[c]; far = Math.max(far, Math.sqrt(pos[id][0] * pos[id][0] + pos[id][1] * pos[id][1] + pos[id][2] * pos[id][2])); });
      ids.forEach(function (id) { for (var c = 0; c < 3; c++) pos[id][c] /= far; });
    }
    return pos;
  }
  function project3d(pos, rotY, rotX, cx, cy, scale, dist) {
    var cyv = Math.cos(rotY), syv = Math.sin(rotY), cxv = Math.cos(rotX), sxv = Math.sin(rotX), out = {};
    Object.keys(pos).forEach(function (id) {
      var p = pos[id], x = p[0] * cyv + p[2] * syv, z = -p[0] * syv + p[2] * cyv, y = p[1] * cxv - z * sxv, z2 = p[1] * sxv + z * cxv, persp = (dist || 4) / ((dist || 4) + z2);
      out[id] = { x: cx + x * scale * persp, y: cy + y * scale * persp, z: z2, r: persp };
    });
    return out;
  }

  // ---- ホワイトボード（位置の保存用の純関数）----
  function snap(v, grid) { return grid > 0 ? Math.round(v / grid) * grid : v; }
  function clampPos(p, w, h, cw, ch) { return { x: Math.max(0, Math.min(w - cw, p.x)), y: Math.max(0, Math.min(h - ch, p.y)) }; }
  function autoPlace(ids, cols, cw, ch, gap) {
    var out = {}; ids.forEach(function (id, i) { out[id] = { x: (i % cols) * (cw + gap), y: Math.floor(i / cols) * (ch + gap) }; }); return out;
  }

  // ---- ギャラリー ----
  var TYPES = { image: /\.(png|jpe?g|gif|webp|svg|bmp)$/i, pdf: /\.pdf$/i, audio: /\.(mp3|wav|ogg|m4a|flac)$/i, video: /\.(mp4|webm|mov|mkv)$/i };
  function fileType(name) { for (var k in TYPES) if (TYPES[k].test(name)) return k; return "other"; }
  function gallery(files, type, q) {
    var terms = String(q || "").toLowerCase().split(/\s+/).filter(Boolean);
    return files.filter(function (f) {
      var t = f.type || fileType(f.name);
      return (!type || type === "all" || t === type) && terms.every(function (x) { return (f.name + " " + (f.notes || []).map(function (n) { return n.title; }).join(" ")).toLowerCase().indexOf(x) >= 0; });
    }).sort(function (a, b) { return cmpStr(a.name, b.name); });
  }

  var api = { hierarchy: hierarchy, countTree: countTree, depthOf: depthOf, orphans: orphans, matrix: matrix, squarify: squarify, treemap: treemap, sunburst: sunburst, arcPath: arcPath, polar: polar,
              mindmap: mindmap, kanban: kanban, addDays: addDays, growth: growth, river: river, compare: compare, sankey: sankey, parseLoc: parseLoc, mapPoints: mapPoints, layout3d: layout3d,
              project3d: project3d, snap: snap, clampPos: clampPos, autoPlace: autoPlace, fileType: fileType, gallery: gallery, topFz: topFz };
  if (typeof module !== "undefined" && module.exports) module.exports = api; else root.Views2Core = api;
})(typeof window !== "undefined" ? window : globalThis);
