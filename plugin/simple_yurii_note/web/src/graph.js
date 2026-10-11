// ローカルグラフ: 今のノートを中心に、つながるノートを円状に並べて描く（Obsidian の局所グラフ相当）。
// neighbors(rel) → [rel] を受け取り、深さ 1〜2 のノードと辺だけを描く。
const SVG_NS = "http://www.w3.org/2000/svg";

export function buildLocal(center, depth, neighbors) {
  const nodes = new Map([[center, { rel: center, depth: 0 }]]);
  const ring1 = (neighbors(center) || []).filter((r) => r !== center);
  for (const r of ring1) if (!nodes.has(r)) nodes.set(r, { rel: r, depth: 1 });
  if (depth >= 2) {
    for (const r of ring1) {
      for (const r2 of neighbors(r) || []) {
        if (r2 === center || nodes.has(r2)) continue;
        nodes.set(r2, { rel: r2, depth: 2, via: r });
      }
    }
  }
  // 辺: 描いているノート同士のつながり（重複なし）
  const edges = [];
  const seen = new Set();
  for (const a of nodes.keys()) {
    for (const b of neighbors(a) || []) {
      if (!nodes.has(b) || a === b) continue;
      const k = a < b ? a + "|" + b : b + "|" + a;
      if (seen.has(k)) continue;
      seen.add(k);
      edges.push([a, b]);
    }
  }
  return { nodes: [...nodes.values()], edges };
}

// 円状レイアウト。深さ 1 は内側の円、深さ 2 は外側の円（親になるノートの角度の近くに置く）。
export function layout(model, width, height) {
  const cx = width / 2, cy = height / 2;
  const pos = new Map();
  pos.set(model.nodes.find((n) => n.depth === 0).rel, { x: cx, y: cy });
  const r1 = Math.min(width, height) * 0.30;
  const r2 = Math.min(width, height) * 0.46;
  const ones = model.nodes.filter((n) => n.depth === 1);
  ones.forEach((n, i) => {
    const a = (2 * Math.PI * i) / Math.max(1, ones.length) - Math.PI / 2;
    pos.set(n.rel, { x: cx + r1 * Math.cos(a), y: cy + r1 * Math.sin(a), a });
  });
  const twos = model.nodes.filter((n) => n.depth === 2);
  const byVia = new Map();
  for (const n of twos) {
    if (!byVia.has(n.via)) byVia.set(n.via, []);
    byVia.get(n.via).push(n);
  }
  for (const [via, group] of byVia) {
    const base = pos.get(via)?.a ?? 0;
    const spread = Math.min(0.5, 0.18 * group.length);
    group.forEach((n, i) => {
      const off = group.length === 1 ? 0 : (i / (group.length - 1) - 0.5) * 2 * spread;
      const a = base + off;
      pos.set(n.rel, { x: cx + r2 * Math.cos(a), y: cy + r2 * Math.sin(a) });
    });
  }
  return pos;
}

function el(name, attrs = {}) {
  const e = document.createElementNS(SVG_NS, name);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, String(v));
  return e;
}

// svg 要素を描き直す。label(rel) → 表示名、onOpen(rel) → クリック時、current は中心のノート。
export function drawLocal(svg, model, { width, height, label, onOpen }) {
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  svg.innerHTML = "";
  const pos = layout(model, width, height);
  const gEdges = el("g", { class: "lg-edges" });
  for (const [a, b] of model.edges) {
    const pa = pos.get(a), pb = pos.get(b);
    if (!pa || !pb) continue;
    gEdges.appendChild(el("line", { x1: pa.x, y1: pa.y, x2: pb.x, y2: pb.y, class: "lg-edge" }));
  }
  svg.appendChild(gEdges);
  const gNodes = el("g", { class: "lg-nodes" });
  for (const n of model.nodes) {
    const p = pos.get(n.rel);
    if (!p) continue;
    const g = el("g", { class: `lg-node d${n.depth}`, transform: `translate(${p.x},${p.y})` });
    const r = n.depth === 0 ? 7 : n.depth === 1 ? 5.5 : 4;
    g.appendChild(el("circle", { r }));
    const t = el("text", { x: 0, y: -r - 4, "text-anchor": "middle", class: "lg-label" });
    const name = label(n.rel);
    t.textContent = name.length > 14 ? name.slice(0, 13) + "…" : name;
    g.appendChild(t);
    g.addEventListener("click", () => onOpen(n.rel));
    const title = el("title");
    title.textContent = name;
    g.appendChild(title);
    gNodes.appendChild(g);
  }
  svg.appendChild(gNodes);
}

// ---------------------------------------------------------------- 全体グラフ
// 場所が動かないように: 位置は一度決めたら保存し、次回からはそのまま使う。
// 新しく増えたノートだけを、つながりの近くに置いて少し整える（既存の位置は動かさない）。

// 決まった種から同じ乱数列を出す（同じ入力なら同じ配置になる）
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// nodes: [rel]、edges: [[a,b]]、stored: {rel:{x,y}}。戻り値は rel → {x,y} の全件。
export function layoutGlobal(nodes, edges, stored = {}) {
  const pos = new Map();
  const movable = [];
  for (const r of nodes) {
    const s = stored[r];
    if (s && Number.isFinite(s.x) && Number.isFinite(s.y)) pos.set(r, { x: s.x, y: s.y });
    else movable.push(r);
  }
  if (!movable.length) return pos;

  const adj = new Map();
  for (const [a, b] of edges) {
    if (!adj.has(a)) adj.set(a, []);
    if (!adj.has(b)) adj.set(b, []);
    adj.get(a).push(b);
    adj.get(b).push(a);
  }

  const rand = rng(7919 + nodes.length);
  const SPAN = 600;
  // 初期配置: 既に置いてあるつながりの近く、無ければ決まった乱数で広げる
  for (const r of movable) {
    const placed = (adj.get(r) || []).find((x) => pos.has(x));
    if (placed) {
      const p = pos.get(placed);
      pos.set(r, { x: p.x + (rand() - 0.5) * 60, y: p.y + (rand() - 0.5) * 60 });
    } else {
      pos.set(r, { x: (rand() - 0.5) * SPAN, y: (rand() - 0.5) * SPAN });
    }
  }
  const K = 46; // ノード同士の目安の間隔
  const CELL = K * 2;
  const iters = movable.length > 2000 ? 90 : 160;
  for (let it = 0; it < iters; it++) {
    const temp = K * 0.9 * (1 - it / iters) + 0.5;
    // 空間グリッド: 近いノードだけ斥力を計算する
    const grid = new Map();
    for (const r of pos.keys()) {
      const p = pos.get(r);
      const key = Math.floor(p.x / CELL) + "," + Math.floor(p.y / CELL);
      if (!grid.has(key)) grid.set(key, []);
      grid.get(key).push(r);
    }
    const disp = new Map();
    for (const r of movable) {
      const p = pos.get(r);
      let dx = 0, dy = 0;
      const cx = Math.floor(p.x / CELL), cy = Math.floor(p.y / CELL);
      for (let gx = cx - 1; gx <= cx + 1; gx++) {
        for (let gy = cy - 1; gy <= cy + 1; gy++) {
          for (const o of grid.get(gx + "," + gy) || []) {
            if (o === r) continue;
            const q = pos.get(o);
            let ex = p.x - q.x, ey = p.y - q.y;
            let d2 = ex * ex + ey * ey;
            if (d2 < 0.01) { ex = rand() - 0.5; ey = rand() - 0.5; d2 = 0.25; }
            const f = (K * K) / d2;
            dx += ex * f * 0.02;
            dy += ey * f * 0.02;
          }
        }
      }
      for (const o of adj.get(r) || []) {
        const q = pos.get(o);
        const ex = q.x - p.x, ey = q.y - p.y;
        const d = Math.sqrt(ex * ex + ey * ey) || 1;
        const f = (d - K) * 0.08;
        dx += (ex / d) * f;
        dy += (ey / d) * f;
      }
      const len = Math.sqrt(dx * dx + dy * dy) || 1;
      const s = Math.min(len, temp) / len;
      disp.set(r, { x: dx * s, y: dy * s });
    }
    for (const r of movable) {
      const p = pos.get(r), d = disp.get(r);
      p.x += d.x;
      p.y += d.y;
    }
  }
  return pos;
}

// 全体グラフを描く。pos は rel → {x,y}。パン（背景ドラッグ）・ズーム（ホイール）・
// ノードのドラッグで位置を変える（onMove で保存）・クリックで開く。
export function mountGlobal(svg, nodes, edges, pos, { label, onOpen, onMove }) {
  svg.innerHTML = "";
  let view = { x: 0, y: 0, w: 800, h: 600 };
  const fit = () => {
    let minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity;
    for (const p of pos.values()) {
      if (p.x < minx) minx = p.x; if (p.x > maxx) maxx = p.x;
      if (p.y < miny) miny = p.y; if (p.y > maxy) maxy = p.y;
    }
    if (!Number.isFinite(minx)) { minx = miny = -100; maxx = maxy = 100; }
    const pad = 40;
    // 1 単位 = 1 画面ピクセルを基本にし、入り切らないときだけ縮小する（文字の大きさを保つ）
    const cw = svg.clientWidth || 800, ch = svg.clientHeight || 600;
    const cW = Math.max(200, maxx - minx + pad * 2), cH = Math.max(200, maxy - miny + pad * 2);
    // 少ない件数は画面の 7 割まで広げて見せる（0.6 倍まで拡大）。多い件数は入る大きさに縮小。
    const k = Math.max(0.6, cW / (cw * 0.7), cH / (ch * 0.7));
    const w = cw * k, h = ch * k;
    const mx = (minx + maxx) / 2, my = (miny + maxy) / 2;
    view = { x: mx - w / 2, y: my - h / 2, w, h };
  };
  // 文字は画面のピクセルで一定の大きさにする（ズームしても読みやすさを保つ）
  const apply = () => {
    svg.setAttribute("viewBox", `${view.x} ${view.y} ${view.w} ${view.h}`);
    const cw = svg.clientWidth || 800;
    svg.style.setProperty("--lfs", (11 * view.w / cw).toFixed(2) + "px");
  };
  fit();
  apply();

  const gEdges = el("g", { class: "lg-edges" });
  const lines = [];
  for (const [a, b] of edges) {
    if (!pos.has(a) || !pos.has(b)) continue;
    const ln = el("line", { class: "lg-edge" });
    lines.push([ln, a, b]);
    gEdges.appendChild(ln);
  }
  svg.appendChild(gEdges);
  const gNodes = el("g", { class: "lg-nodes" });
  const nodeEls = new Map();
  for (const r of nodes) {
    const g = el("g", { class: "lg-node d2" });
    g.appendChild(el("circle", { r: 4 }));
    const t = el("text", { x: 7, y: 3.5, class: "lg-label" });
    t.textContent = label(r);
    g.appendChild(t);
    gNodes.appendChild(g);
    nodeEls.set(r, g);
  }
  svg.appendChild(gNodes);
  const syncPos = () => {
    for (const r of nodes) {
      const p = pos.get(r), g = nodeEls.get(r);
      if (p && g) g.setAttribute("transform", `translate(${p.x},${p.y})`);
    }
    for (const [ln, a, b] of lines) {
      const pa = pos.get(a), pb = pos.get(b);
      ln.setAttribute("x1", pa.x); ln.setAttribute("y1", pa.y);
      ln.setAttribute("x2", pb.x); ln.setAttribute("y2", pb.y);
    }
  };
  syncPos();

  const clientToSvg = (e) => {
    const pt = svg.createSVGPoint();
    pt.x = e.clientX; pt.y = e.clientY;
    return pt.matrixTransform(svg.getScreenCTM().inverse());
  };
  // ホイールでズーム（カーソルの位置を中心に）
  svg.addEventListener("wheel", (e) => {
    e.preventDefault();
    const m = clientToSvg(e);
    const k = e.deltaY > 0 ? 1.1 : 1 / 1.1;
    view = { x: m.x - (m.x - view.x) * k, y: m.y - (m.y - view.y) * k, w: view.w * k, h: view.h * k };
    apply();
  }, { passive: false });

  let drag = null;
  svg.addEventListener("pointerdown", (e) => {
    const g = e.target.closest?.(".lg-node");
    const rel = g ? [...nodeEls.entries()].find(([, v]) => v === g)?.[0] : null;
    const m = clientToSvg(e);
    drag = rel
      ? { kind: "node", rel, moved: false, sx: m.x, sy: m.y }
      : { kind: "pan", sx: m.x, sy: m.y, vx: view.x, vy: view.y, moved: false };
    svg.setPointerCapture(e.pointerId);
  });
  svg.addEventListener("pointermove", (e) => {
    if (!drag) return;
    const m = clientToSvg(e);
    const dx = m.x - drag.sx, dy = m.y - drag.sy;
    if (Math.abs(dx) + Math.abs(dy) > 2) drag.moved = true;
    if (drag.kind === "node") {
      if (!drag.moved) return;
      const p = pos.get(drag.rel);
      p.x += m.x - (drag.lx ?? drag.sx); p.y += m.y - (drag.ly ?? drag.sy);
      drag.lx = m.x; drag.ly = m.y;
      syncPos();
    } else {
      view.x = drag.vx - dx; view.y = drag.vy - dy;
      apply();
    }
  });
  const end = (e) => {
    if (!drag) return;
    const d = drag;
    drag = null;
    try { svg.releasePointerCapture(e.pointerId); } catch { /* ignore */ }
    if (d.kind === "node") {
      if (d.moved) onMove?.(d.rel, pos.get(d.rel));
      else onOpen?.(d.rel);
    }
  };
  svg.addEventListener("pointerup", end);
  svg.addEventListener("pointercancel", end);

  let curRel = null;
  return {
    reset() { fit(); apply(); },
    positions: () => pos,
    // 今開いているノートを強調する
    setCurrent(rel) {
      if (curRel && nodeEls.get(curRel)) nodeEls.get(curRel).classList.remove("cur");
      curRel = rel;
      if (rel && nodeEls.get(rel)) nodeEls.get(rel).classList.add("cur");
    },
  };
}
