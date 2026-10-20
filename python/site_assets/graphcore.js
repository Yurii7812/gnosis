// グラフ表示の核（DOM に触れない純関数）。ブラウザでは window.GraphCore、node では module.exports。
(function (root) {
  // 辺の種類（種類ごとに色と向きを持つ。潰さない）
  var KINDS = {
    parent_branch: { label: "親(ParentBranch)", color: "#2f7ed8" },
    branch_group: { label: "子(BranchGroup)", color: "#1aa085" },
    child_branch: { label: "子(ChildBranch)", color: "#16a085" },
    group: { label: "グループ", color: "#8e44ad" },
    context: { label: "文脈", color: "#e67e22" },
    related: { label: "関連", color: "#d35400" },
    link: { label: "本文リンク", color: "#7f8c8d" },
    backlink: { label: "バックリンク", color: "#bdc3c7" },
    folgezettel: { label: "番号の親子", color: "#c0392b" }
  };

  // 中心ノートから深さ depth 以内（辺の向きは無視）の部分グラフ。kinds が null / 未指定なら全種類、[] なら辺なし（中心だけ）。
  function subgraph(data, center, depth, kinds) {
    var allow = kinds ? new Set(kinds) : null;
    var edges = data.edges.filter(function (e) { return !allow || allow.has(e.k); });
    var adj = new Map();
    function add(a, b) { if (!adj.has(a)) adj.set(a, []); adj.get(a).push(b); }
    edges.forEach(function (e) { add(e.s, e.d); add(e.d, e.s); });
    var dist = new Map([[center, 0]]);
    var q = [center];
    for (var i = 0; i < q.length; i++) {
      var cur = q[i];
      if (dist.get(cur) >= depth) continue;
      (adj.get(cur) || []).forEach(function (n) {
        if (!dist.has(n)) { dist.set(n, dist.get(cur) + 1); q.push(n); }
      });
    }
    var byId = new Map(data.nodes.map(function (n) { return [n.id, n]; }));
    var nodes = [];
    dist.forEach(function (d, id) { if (byId.has(id)) nodes.push(Object.assign({ depth: d }, byId.get(id))); });
    var keep = new Set(nodes.map(function (n) { return n.id; }));
    return { nodes: nodes, edges: edges.filter(function (e) { return keep.has(e.s) && keep.has(e.d); }) };
  }

  // 全体（または部分）グラフの、辺で結ばれた孤立でない部分だけを残す（全体表示の見通し用）
  function withoutIsolated(g) {
    var used = new Set();
    g.edges.forEach(function (e) { used.add(e.s); used.add(e.d); });
    return { nodes: g.nodes.filter(function (n) { return used.has(n.id); }), edges: g.edges };
  }

  // 決まった乱数（同じ入力なら同じ配置）
  function rng(seed) { var s = seed >>> 0; return function () { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }

  // 力学配置。返り値: { id: [x, y] }（0..w, 0..h に収まる）
  function layout(nodes, edges, w, h, iters, centerId) {
    var rand = rng(12345);
    var P = nodes.map(function (n, i) {
      var a = (i / Math.max(nodes.length, 1)) * Math.PI * 2;
      return { id: n.id, x: w / 2 + Math.cos(a) * w / 4 + (rand() - 0.5), y: h / 2 + Math.sin(a) * h / 4 + (rand() - 0.5), vx: 0, vy: 0 };
    });
    var idx = new Map(P.map(function (p, i) { return [p.id, i]; }));
    var L = Math.sqrt((w * h) / Math.max(nodes.length, 1)) * 0.7;
    var E = edges.filter(function (e) { return idx.has(e.s) && idx.has(e.d) && e.s !== e.d; });
    for (var it = 0; it < iters; it++) {
      var t = 1 - it / iters;
      for (var i = 0; i < P.length; i++) {
        for (var j = i + 1; j < P.length; j++) {
          var dx = P[i].x - P[j].x, dy = P[i].y - P[j].y, d2 = dx * dx + dy * dy + 0.01;
          var f = (L * L) / d2;
          P[i].vx += dx * f; P[i].vy += dy * f; P[j].vx -= dx * f; P[j].vy -= dy * f;
        }
      }
      E.forEach(function (e) {
        var a = P[idx.get(e.s)], b = P[idx.get(e.d)];
        var dx = b.x - a.x, dy = b.y - a.y, d = Math.sqrt(dx * dx + dy * dy) + 0.01;
        var f = (d - L) * 0.05;
        a.vx += (dx / d) * f * d * 0.1; a.vy += (dy / d) * f * d * 0.1;
        b.vx -= (dx / d) * f * d * 0.1; b.vy -= (dy / d) * f * d * 0.1;
      });
      P.forEach(function (p) {
        p.vx += (w / 2 - p.x) * 0.08; p.vy += (h / 2 - p.y) * 0.08;   // 中心へ引く（端に張り付かせない）
        var sp = Math.sqrt(p.vx * p.vx + p.vy * p.vy) || 1, cap = Math.min(sp, 30 * t + 1);
        p.x += (p.vx / sp) * cap; p.y += (p.vy / sp) * cap; p.vx = 0; p.vy = 0;
        p.x = Math.min(w - 110, Math.max(25, p.x)); p.y = Math.min(h - 25, Math.max(25, p.y));   // 右はラベルの分を空ける
      });
    }
    var out = {};
    P.forEach(function (p) { out[p.id] = [p.x, p.y]; });
    if (centerId && out[centerId]) out[centerId] = [w / 2, h / 2];
    return out;
  }

  var api = { KINDS: KINDS, subgraph: subgraph, withoutIsolated: withoutIsolated, layout: layout };
  if (typeof module !== "undefined" && module.exports) module.exports = api; else root.GraphCore = api;
})(typeof window !== "undefined" ? window : globalThis);
