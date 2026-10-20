// グラフ表示（SVG）。データは graph-data.js の window.GNOSIS_GRAPH。表示専用。
(function () {
  var C = window.GraphCore, data = window.GNOSIS_GRAPH || { nodes: [], edges: [] };
  var svg = document.getElementById("g"), W = 900, H = 640, NS = "http://www.w3.org/2000/svg";
  var state = { n: "", depth: 1, labels: false, kinds: Object.keys(C.KINDS).filter(function (k) { return k !== "backlink"; }) };
  function readHash() {
    var m;
    state.n = ""; state.depth = 1; state.labels = /[#&]labels=1/.test(location.hash);
    if ((m = /[#&]n=([^&]*)/.exec(location.hash))) { try { state.n = decodeURIComponent(m[1]); } catch (e) {} }
    if ((m = /[#&]depth=(\d+)/.exec(location.hash))) state.depth = Math.min(9, Math.max(1, +m[1]));
  }
  readHash();
  var MAX_ALL = 400;

  function el(tag, attrs, text) {
    var e = document.createElementNS(NS, tag);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (text != null) e.textContent = text;
    return e;
  }

  function controls() {
    var box = document.getElementById("kinds");
    box.textContent = "";
    Object.keys(C.KINDS).forEach(function (k) {
      var lab = document.createElement("label"), cb = document.createElement("input");
      cb.type = "checkbox"; cb.checked = state.kinds.indexOf(k) >= 0;
      cb.addEventListener("change", function () {
        state.kinds = state.kinds.filter(function (x) { return x !== k; });
        if (cb.checked) state.kinds.push(k);
        draw();
      });
      var sw = document.createElement("span"); sw.className = "sw"; sw.style.background = C.KINDS[k].color;
      lab.appendChild(cb); lab.appendChild(sw); lab.appendChild(document.createTextNode(C.KINDS[k].label));
      box.appendChild(lab);
    });
    var sel = document.getElementById("depth");
    sel.value = String(state.depth);
    sel.addEventListener("change", function () { state.depth = +sel.value; draw(); });
    var lb = document.getElementById("labels");
    if (lb) { lb.checked = state.labels; lb.addEventListener("change", function () { state.labels = lb.checked; draw(); }); }
    var ns = document.getElementById("note");
    data.nodes.slice().sort(function (a, b) { return a.title.localeCompare(b.title); }).forEach(function (n) {
      var o = document.createElement("option"); o.value = n.id; o.textContent = n.title; ns.appendChild(o);
    });
    ns.value = state.n;
    ns.addEventListener("change", function () { state.n = ns.value; draw(); });
  }

  function draw() {
    svg.textContent = "";
    var g = state.n ? C.subgraph(data, state.n, state.depth, state.kinds)
                    : C.withoutIsolated({ nodes: data.nodes, edges: data.edges.filter(function (e) { return state.kinds.indexOf(e.k) >= 0; }) });
    var info = document.getElementById("info");
    if (!state.n && g.nodes.length > MAX_ALL) {
      info.textContent = "ノートが多いので、上の「中心のノート」を選ぶとその周りのグラフを表示します（全体 " + g.nodes.length + " 件）";
      return;
    }
    info.textContent = g.nodes.length + " ノート・" + g.edges.length + " 本の関係" + (state.n ? "（深さ " + state.depth + "）" : "");
    var pos = C.layout(g.nodes, g.edges, W, H, g.nodes.length > 200 ? 120 : 300, state.n);
    var defs = el("defs", {});
    Object.keys(C.KINDS).forEach(function (k) {
      var mk = el("marker", { id: "a-" + k, viewBox: "0 0 10 10", refX: "17", refY: "5", markerWidth: "6", markerHeight: "6", orient: "auto-start-reverse" });
      mk.appendChild(el("path", { d: "M0 0L10 5L0 10z", fill: C.KINDS[k].color }));
      defs.appendChild(mk);
    });
    svg.appendChild(defs);
    g.edges.forEach(function (e) {
      var a = pos[e.s], b = pos[e.d];
      if (!a || !b || e.s === e.d) return;
      svg.appendChild(el("line", { x1: a[0], y1: a[1], x2: b[0], y2: b[1], stroke: C.KINDS[e.k].color, "stroke-width": "1.5", "marker-end": "url(#a-" + e.k + ")", opacity: "0.8" }));
    });
    // コンセプトマップとして読めるよう、関係の名前を線の上に出せる（線が多いと文字が重なるので 150 本まで）
    var labelOff = state.labels && g.edges.length > 150;
    if (state.labels && !labelOff) g.edges.forEach(function (e) {
      var a = pos[e.s], b = pos[e.d];
      if (!a || !b || e.s === e.d) return;
      svg.appendChild(el("text", { class: "elabel", x: ((a[0] + b[0]) / 2).toFixed(1), y: ((a[1] + b[1]) / 2 - 3).toFixed(1), "text-anchor": "middle", "font-size": "9", fill: C.KINDS[e.k].color }, C.KINDS[e.k].label));
    });
    if (labelOff) info.textContent += "（関係が多いので、名前の表示は 150 本までです。中心のノートを選んで絞ってください）";
    g.nodes.forEach(function (n) {
      var p = pos[n.id];
      var a = el("a", { href: n.href });
      a.appendChild(el("circle", { cx: p[0], cy: p[1], r: n.id === state.n ? 9 : 6, fill: n.id === state.n ? "#e0a800" : n.group ? "#8e44ad" : "#4a90d9", stroke: "#fff", "stroke-width": "1" }));
      var t = el("text", { x: p[0] + 9, y: p[1] + 4, "font-size": "11", fill: "currentColor" }, (n.fz ? n.fz + " " : "") + n.title);
      a.appendChild(t);
      svg.appendChild(a);
    });
  }
  controls();
  draw();
  // アドレスの #n= #depth= が書き換わったとき（戻る・進む・各ノートの「周りのグラフ」リンク）も追従する
  window.addEventListener("hashchange", function () {
    readHash();
    document.getElementById("note").value = state.n;
    document.getElementById("depth").value = String(state.depth);
    draw();
  });
})();
