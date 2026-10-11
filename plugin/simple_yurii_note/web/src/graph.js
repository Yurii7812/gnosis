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
  const K = 110; // ノード同士の目安の間隔（長い日本語タイトルが並んでも読める広さ）
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
        const f = (d - K * 0.8) * 0.08;
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
// 点の大きさと文字は画面のピクセルで一定。つながりの多いノートほど大きく、
// 重なるタイトルは、つながりの多い順に残し、拡大すると他のタイトルも出る。
export function mountGlobal(svg, nodes, edges, pos, { label, onOpen, onMove }) {
  svg.innerHTML = "";
  const deg = new Map(nodes.map((r) => [r, 0]));
  for (const [a, b] of edges) {
    if (deg.has(a)) deg.set(a, deg.get(a) + 1);
    if (deg.has(b)) deg.set(b, deg.get(b) + 1);
  }
  // 優先順位: つながりの多い順（同じなら名前順）。重なったとき上位のタイトルを残す。
  const order = [...nodes].sort((x, y) => deg.get(y) - deg.get(x) || label(x).localeCompare(label(y), "ja"));

  let view = { x: 0, y: 0, w: 800, h: 600 };
  const size = () => ({ cw: svg.clientWidth || 800, ch: svg.clientHeight || 600 });
  const fit = () => {
    let minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity;
    for (const p of pos.values()) {
      if (p.x < minx) minx = p.x; if (p.x > maxx) maxx = p.x;
      if (p.y < miny) miny = p.y; if (p.y > maxy) maxy = p.y;
    }
    if (!Number.isFinite(minx)) { minx = miny = -100; maxx = maxy = 100; }
    const pad = 70;
    const { cw, ch } = size();
    const cW = Math.max(200, maxx - minx + pad * 2), cH = Math.max(200, maxy - miny + pad * 2);
    // 少ない件数でも画面いっぱいに広げ（最大 0.7 倍まで拡大）、多いときは入る大きさに縮小する
    const k = Math.max(0.7, cW / cw, cH / ch);
    const w = cw * k, h = ch * k;
    const mx = (minx + maxx) / 2, my = (miny + maxy) / 2;
    view = { x: mx - w / 2, y: my - h / 2, w, h };
  };

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
  const labelEls = new Map();
  const texts = new Map();
  for (const r of nodes) {
    const d = deg.get(r);
    const g = el("g", { class: "lg-node d2" });
    const c = el("circle", {});
    // 点の半径(px) = 3.5 + 1.5√つながり数（上限 10）。実寸への換算は CSS 変数で行う
    c.style.setProperty("--rr", Math.min(10, 3.5 + 1.5 * Math.sqrt(d)).toFixed(2));
    g.appendChild(c);
    const t = el("text", { x: 0, y: 0, class: "lg-label" });
    const name = label(r);
    t.textContent = name;
    g.appendChild(t);
    gNodes.appendChild(g);
    nodeEls.set(r, g);
    labelEls.set(r, t);
    texts.set(r, name);
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

  // 画面上の位置でタイトルの重なりを調べ、上位のものから残す（空間グリッドで高速化）
  let curRel = null;
  const cullLabels = () => {
    const { cw, ch } = size();
    const su = view.w / cw; // 1 画面ピクセルあたりの座標単位
    const grid = new Map();
    const CELL = 140;
    const fits = (x0, y0, x1, y1) => {
      for (let gx = Math.floor(x0 / CELL); gx <= Math.floor(x1 / CELL); gx++) {
        for (let gy = Math.floor(y0 / CELL); gy <= Math.floor(y1 / CELL); gy++) {
          for (const q of grid.get(gx + "," + gy) || []) {
            if (x0 < q[2] && q[0] < x1 && y0 < q[3] && q[1] < y1) return false;
          }
        }
      }
      return true;
    };
    const put = (x0, y0, x1, y1) => {
      for (let gx = Math.floor(x0 / CELL); gx <= Math.floor(x1 / CELL); gx++) {
        for (let gy = Math.floor(y0 / CELL); gy <= Math.floor(y1 / CELL); gy++) {
          const k = gx + "," + gy;
          if (!grid.has(k)) grid.set(k, []);
          grid.get(k).push([x0, y0, x1, y1]);
        }
      }
    };
    const FS = 12, H = FS + 3;
    const widthOf = (s) => {
      let w = 0;
      for (const ch2 of s) w += ch2.charCodeAt(0) > 0x2e80 ? FS : FS * 0.58;
      return w + 8;
    };
    // 今開いているノートは最優先で残す
    const seq = curRel ? [curRel, ...order.filter((r) => r !== curRel)] : order;
    for (const r of seq) {
      const p = pos.get(r), t = labelEls.get(r);
      if (!p || !t) continue;
      const sx = (p.x - view.x) / su, sy = (p.y - view.y) / su;
      // 画面外のタイトルは出さない
      if (sx < -200 || sx > cw + 200 || sy < -40 || sy > ch + 40) { t.style.display = "none"; continue; }
      const x0 = sx + 8, x1 = x0 + widthOf(texts.get(r)), y0 = sy - H / 2, y1 = sy + H / 2;
      if (fits(x0, y0, x1, y1)) { put(x0, y0, x1, y1); t.style.display = ""; }
      else t.style.display = "none";
    }
  };

  let raf = 0;
  const apply = () => {
    svg.setAttribute("viewBox", `${view.x} ${view.y} ${view.w} ${view.h}`);
    const { cw } = size();
    svg.style.setProperty("--su", (view.w / cw).toFixed(4));
    if (!raf) raf = requestAnimationFrame(() => { raf = 0; cullLabels(); });
  };
  fit();
  syncPos();
  apply();

  // 画面サイズが変わったら（境界のドラッグ・ウィンドウ変更・全画面）、拡大率と中心を保って描き直す
  let last = size();
  const ro = new ResizeObserver(() => {
    const n = size();
    if (!n.cw || !n.ch || (n.cw === last.cw && n.ch === last.ch)) return;
    const su = view.w / last.cw;
    const cx = view.x + view.w / 2, cy = view.y + view.h / 2;
    view.w = n.cw * su; view.h = n.ch * su;
    view.x = cx - view.w / 2; view.y = cy - view.h / 2;
    last = n;
    apply();
  });
  ro.observe(svg);

  const clientToSvg = (e) => {
    const pt = svg.createSVGPoint();
    pt.x = e.clientX; pt.y = e.clientY;
    return pt.matrixTransform(svg.getScreenCTM().inverse());
  };
  // ホイールでズーム（カーソルの位置を中心に）
  svg.addEventListener("wheel", (e) => {
    e.preventDefault();
    const m = clientToSvg(e);
    const k = e.deltaY > 0 ? 1.12 : 1 / 1.12;
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
      svg.setAttribute("viewBox", `${view.x} ${view.y} ${view.w} ${view.h}`);
    }
  });
  const end = (e) => {
    if (!drag) return;
    const d = drag;
    drag = null;
    try { svg.releasePointerCapture(e.pointerId); } catch { /* ignore */ }
    if (d.kind === "node") {
      if (d.moved) { onMove?.(d.rel, pos.get(d.rel)); apply(); }
      else onOpen?.(d.rel);
    } else if (d.moved) apply();
  };
  svg.addEventListener("pointerup", end);
  svg.addEventListener("pointercancel", end);

  return {
    reset() { fit(); apply(); },
    positions: () => pos,
    // 今開いているノートを強調し、そのタイトルを必ず出す
    setCurrent(rel) {
      if (curRel && nodeEls.get(curRel)) nodeEls.get(curRel).classList.remove("cur");
      curRel = rel;
      if (rel && nodeEls.get(rel)) nodeEls.get(rel).classList.add("cur");
      apply();
    },
  };
}
