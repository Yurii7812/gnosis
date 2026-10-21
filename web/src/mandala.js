// 曼荼羅（タブ）。保存はふつうの Markdown ノート（front matter `mandala: true`）の 9×9 の表（python/mandala.py と同じ形）。
//   3×3: 中心のブロック（主題と 8 つの副題）から始め、副題の「広げる」でそのブロック（副題を中心に 8 マス）へ入る。
//   9×9: 全体を見ながら直す。
//   副題は中心のブロックと周りのブロックの真ん中の 2 か所にある。片方を直せばもう片方も同じにする（mandala.py の sync と同じ対応）。
//   マスの文字から「ノートにする」「曼荼羅にする」（Vim の gnosis#app_op → mandala.py link-cell）。
//   保存は Vim（:write）。読んだときの内容と違えば上書きせず読み直す。
import { h, button, toast } from "./ui.js";

const N = 9;
const RING = [[3, 3], [3, 4], [3, 5], [4, 5], [5, 5], [5, 4], [5, 3], [4, 3]];          // 上から時計回り
const BLOCK_CENTER = [[1, 1], [1, 4], [1, 7], [4, 7], [7, 7], [7, 4], [7, 1], [4, 1]];
const THEME = [4, 4];
const ROW_RE = /^\s*\|(.*)\|\s*$/;
const SEP_RE = /^\s*\|\s*:?-{2,}/;
const LINK_RE = /\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)\)/;
// 3×3 の表示での、ブロックの中の位置 → ブロック番号（0..8）。4 が中心。副題 i のブロックは BLOCK_OF_RING[i]
const BLOCK_OF_RING = [0, 1, 2, 5, 8, 7, 6, 3];

export function cellsOf(line) {
  const m = ROW_RE.exec(line);
  const inner = m ? m[1] : line;
  return inner.split(/(?<!\\)\|/).map((c) => c.trim().replace(/\\\|/g, "|"));
}

export function parseGrid(text) {
  const grid = Array.from({ length: N }, () => Array(N).fill(""));
  const lines = text.split("\n");
  const rows = [];
  let started = false;
  for (let i = 0; i < lines.length; i++) {
    const ln = lines[i];
    if (ROW_RE.test(ln)) {
      if (SEP_RE.test(ln)) { started = true; continue; }
      if (started) rows.push(cellsOf(ln));
    } else if (started && rows.length) break;
  }
  rows.slice(0, N).forEach((row, r) => row.slice(0, N).forEach((v, c) => { grid[r][c] = v; }));
  return grid;
}

export function renderTable(grid) {
  const esc = (v) => v.replace(/\|/g, "\\|").replace(/\n/g, " ");
  const out = ["| " + Array.from({ length: N }, (_, c) => String(c + 1)).join(" | ") + " |", "|" + "---|".repeat(N)];
  for (let r = 0; r < N; r++) out.push("| " + grid[r].map(esc).join(" | ") + " |");
  return out;
}

// 本文の表だけを差し替える（表の前後の本文は触らない）。表が無ければ H1 の下に置く
export function replaceTable(text, grid) {
  const lines = text.split("\n");
  const idx = lines.map((ln, i) => (ROW_RE.test(ln) ? i : -1)).filter((i) => i >= 0);
  const table = renderTable(grid);
  if (idx.length >= N + 2) {
    const first = idx[0];
    let n = 0;
    while (first + n < lines.length && ROW_RE.test(lines[first + n])) n++;
    lines.splice(first, n, ...table);
    return lines.join("\n");
  }
  const h1 = lines.findIndex((l) => /^#\s/.test(l));
  lines.splice(h1 + 1, 0, "", ...table);
  return lines.join("\n");
}

// マスごとの 3-way: base（前に読んだ・保存した版）から、こちら（ours）とファイル（disk）のどちらが変えたか。
// 両方が違う文字に変えたマスは、こちらの文字にして数を返す
export function mergeGrids(base, ours, disk) {
  let clashes = 0;
  const grid = ours.map((row, r) => row.map((v, c) => {
    const b = base[r][c], d = disk[r][c];
    if (v === b) return d;
    if (d === b || d === v) return v;
    clashes++;
    return v;
  }));
  return { grid, clashes };
}

// マス (r, c) の対になるマス（副題の 2 か所）。無ければ null
export function mirrorOf(r, c) {
  for (let i = 0; i < 8; i++) {
    if (RING[i][0] === r && RING[i][1] === c) return BLOCK_CENTER[i];
    if (BLOCK_CENTER[i][0] === r && BLOCK_CENTER[i][1] === c) return RING[i];
  }
  return null;
}

// ブロック b（0..8）の 3×3 のマスの位置（行, 列）
const blockCells = (b) => { const br = Math.floor(b / 3) * 3, bc = (b % 3) * 3; const out = []; for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) out.push([br + r, bc + c]); return out; };

export function createMandala(ctx, params) {
  const rel = params.rel;
  const el = h("div", "viewbox mdbox keepfocus");
  const bar = h("div", "md-bar");
  const crumbs = h("div", "md-crumbs");
  const state = h("span", "md-state", "");
  const body = h("div", "md-body");
  el.append(bar, body);
  let text = "", hash = "", grid = null, base = null, mode = params.mode || "3", block = 4, dirty = false, saving = false, timer = null;
  const copyGrid = (g) => g.map((row) => row.slice());

  const b3 = button("3×3 で考える", () => { mode = "3"; draw(); }, "nav-btn");
  const b9 = button("9×9 全体", () => { mode = "9"; draw(); }, "nav-btn");
  bar.append(crumbs, b3, b9, button("Vim で開く", () => ctx.open(rel), "nav-btn"), state);

  async function load() {
    const r = await ctx.readNote(rel);
    if (!r.ok) { body.textContent = r.error || "読めませんでした"; return; }
    text = r.text; hash = r.hash; grid = parseGrid(text); base = copyGrid(grid); dirty = false;
    if (!/^mandala:\s*true\s*$/m.test(text.split(/\n---\s*\n/)[0] || "")) toast("曼荼羅ノート（mandala: true）ではありません。表の形だけ使います");
    draw();
  }

  function setState(t, cls = "") { state.textContent = t; state.className = "md-state " + cls; }

  function schedule() { dirty = true; setState("未保存", "dirty"); clearTimeout(timer); timer = setTimeout(save, 700); }
  async function save() {
    if (saving) { schedule(); return; }
    if (!dirty) return;
    saving = true;
    dirty = false;
    let clashes = 0;
    let r = null;
    // 保存のあとの自動同期や Vim がファイルを書き換えていることがある。そのときはマスごとに 3-way で合わせて保存し直す
    for (let tries = 0; tries < 3; tries++) {
      const saved = copyGrid(grid);
      const next = replaceTable(text, saved);
      r = await ctx.commit(rel, next, hash);
      if (r.ok) { text = r.text ?? next; hash = r.hash; base = saved; break; }
      if (!r.conflict) break;
      const disk = await ctx.readNote(rel);
      if (!disk.ok) break;
      const dg = parseGrid(disk.text);
      const m = mergeGrids(base, grid, dg);
      clashes += m.clashes;
      grid = m.grid; base = dg; text = disk.text; hash = disk.hash;
      refreshValues();
    }
    saving = false;
    if (r && r.ok) setState(clashes ? `保存しました（${clashes} マスはほかでも直されていたので、こちらの文字にしました）` : "保存しました", clashes ? "dirty" : "");
    else { dirty = true; setState((r && r.error) || "保存できませんでした", "err"); }
  }
  // 打っている最中のマスはそのままにして、ほかのマスの表示を今の grid に合わせる
  function refreshValues() {
    for (const ta of body.querySelectorAll(".md-cell textarea")) {
      const [rr, cc] = ta.closest(".md-cell").dataset.rc.split(",").map(Number);
      if (ta !== document.activeElement && ta.value !== grid[rr][cc]) { ta.value = grid[rr][cc]; ta.dispatchEvent(new Event("blur")); }
    }
  }

  function setCell(r, c, v) {
    grid[r][c] = v;
    const m = mirrorOf(r, c);
    if (m) {
      grid[m[0]][m[1]] = v;
      const other = body.querySelector(`[data-rc="${m[0]},${m[1]}"] textarea`);
      if (other && other !== document.activeElement) other.value = v;
    }
    schedule();
  }

  function cellEl(r, c, opts = {}) {
    const v = grid[r][c];
    const isTheme = r === THEME[0] && c === THEME[1];
    const ring = RING.findIndex(([a, b]) => a === r && b === c);
    const center = BLOCK_CENTER.findIndex(([a, b]) => a === r && b === c);
    const cell = h("div", "md-cell" + (isTheme ? " theme" : ring >= 0 ? " sub" : center >= 0 ? " sub2" : "") + (opts.mid ? " mid" : ""));
    cell.dataset.rc = `${r},${c}`;
    const ta = h("textarea"); ta.value = v; ta.rows = 2; ta.spellcheck = false;
    ta.placeholder = isTheme ? "主題" : ring >= 0 ? `副題 ${ring + 1}` : center >= 0 ? "（副題）" : "";
    ta.addEventListener("input", () => { setCell(r, c, ta.value.replace(/\n/g, " ")); drawTools(); });
    ta.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); moveFocus(cell, 1); }
      else if (e.key === "Tab") { e.preventDefault(); moveFocus(cell, e.shiftKey ? -1 : 1); }
      else if (e.key === "Escape") { ta.blur(); }
      else if (e.altKey && e.key === "ArrowDown" && opts.zoom) { e.preventDefault(); opts.zoom(); }
      else if (e.altKey && e.key === "ArrowUp" && mode === "3" && block !== 4) { e.preventDefault(); block = 4; draw(); }
    });
    // リンクのあるマスは、ふだんは名前だけを見せる（押すと中身を直せる）
    const disp = h("div", "md-disp");
    disp.addEventListener("mousedown", (e) => { e.preventDefault(); cell.classList.add("editing"); ta.focus(); });
    ta.addEventListener("focus", () => cell.classList.add("editing"));
    ta.addEventListener("blur", () => { cell.classList.remove("editing"); drawDisp(); });
    function drawDisp() {
      const cur = grid[r][c];
      disp.textContent = "";
      let last = 0;
      const re = new RegExp(LINK_RE.source, "g");
      let m;
      while ((m = re.exec(cur))) {
        if (m.index > last) disp.appendChild(document.createTextNode(cur.slice(last, m.index)));
        disp.appendChild(h("span", "md-linktext", m[1].replace(/\\(.)/g, "$1")));
        last = m.index + m[0].length;
      }
      if (last < cur.length) disp.appendChild(document.createTextNode(cur.slice(last)));
    }
    drawDisp();
    cell.append(disp, ta);
    const tools = h("div", "md-tools");
    // マスの道具: リンクがあれば「開く」、文字だけなら「ノートに」「曼荼羅に」。打つたびに作り直す
    let toolsKey = null;
    function drawTools() {
      const cur = grid[r][c];
      const lk = LINK_RE.exec(cur);
      const key = lk ? "L" + lk[2] : cur.trim() ? "T" : "";
      if (key === toolsKey) return;
      toolsKey = key;
      tools.textContent = "";
      cell.classList.toggle("linked", !!lk);
      if (lk) tools.appendChild(button("開く", () => openLink(lk[2]), "md-tool", "リンク先を Vim で開く"));
      else if (cur.trim()) {
        tools.appendChild(button("ノートに", () => linkCell(r, c, "note"), "md-tool", "このマスの文字で新しいノートを作り、マスをリンクにする"));
        tools.appendChild(button("曼荼羅に", () => linkCell(r, c, "mandala"), "md-tool", "このマスの文字を主題にした別の曼荼羅を作る"));
      }
      if (opts.zoom) tools.appendChild(button("広げる ▸", opts.zoom, "md-tool zoom", "このマスを中心に 8 マスで広げる（Alt+↓）"));
    }
    drawTools();
    cell.appendChild(tools);
    return cell;
  }

  function moveFocus(cell, k) {
    const all = [...body.querySelectorAll(".md-cell textarea")];
    const i = all.indexOf(cell.querySelector("textarea"));
    const n = all[(i + k + all.length) % all.length];
    if (n) n.focus();
  }

  function openLink(target) {
    const dir = rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/") + 1) : "";
    ctx.open(decodeURIComponent((dir + target).split("#")[0]));
  }

  async function linkCell(r, c, kind) {
    if (dirty) await save();
    const res = await ctx.op("mandala_link", { file: rel, row: r, col: c, kind });
    if (!res.ok) { toast(res.error || "作れませんでした", "err"); return; }
    toast(kind === "mandala" ? "曼荼羅を作りました（今日の日記にも載ります）" : "ノートを作りました（今日の日記にも載ります）");
    await load();
  }

  function draw() {
    if (!grid) return;
    b3.setAttribute("aria-pressed", String(mode === "3"));
    b9.setAttribute("aria-pressed", String(mode === "9"));
    body.textContent = "";
    crumbs.textContent = "";
    const theme = grid[THEME[0]][THEME[1]] || "（主題）";
    if (mode === "9") {
      crumbs.appendChild(h("span", "md-crumb", theme));
      const g = h("div", "md-grid9");
      for (let b = 0; b < 9; b++) {
        const blk = h("div", "md-block" + (b === 4 ? " center" : ""));
        for (const [r, c] of blockCells(b)) blk.appendChild(cellEl(r, c));
        g.appendChild(blk);
      }
      body.appendChild(g);
      return;
    }
    // 3×3
    crumbs.appendChild(button(theme, () => { block = 4; draw(); }, "md-crumb"));
    if (block !== 4) { crumbs.appendChild(h("span", "nav-sep", "›")); const i = BLOCK_OF_RING.indexOf(block); crumbs.appendChild(h("span", "md-crumb cur", grid[RING[i][0]][RING[i][1]] || `副題 ${i + 1}`)); }
    const g = h("div", "md-grid3");
    const cells = blockCells(block);
    cells.forEach(([r, c], k) => {
      const opts = { mid: k === 4 };
      if (block === 4) {
        const i = RING.findIndex(([a, b]) => a === r && b === c);
        if (i >= 0) opts.zoom = () => { block = BLOCK_OF_RING[i]; draw(); setTimeout(() => body.querySelector(".md-cell:not(.mid) textarea")?.focus(), 0); };
      }
      g.appendChild(cellEl(r, c, opts));
    });
    body.appendChild(g);
    // まわりのブロックの埋まり具合（押すとそこへ）
    const mini = h("div", "md-mini");
    for (let b = 0; b < 9; b++) {
      const filled = blockCells(b).filter(([r, c]) => grid[r][c].trim()).length;
      const label = b === 4 ? theme : (grid[BLOCK_CENTER[BLOCK_OF_RING.indexOf(b)][0]][BLOCK_CENTER[BLOCK_OF_RING.indexOf(b)][1]] || "—");
      const mb = button("", () => { block = b; draw(); }, "md-minib" + (b === block ? " cur" : ""), `${label}（${filled}/9）`);
      mb.append(h("span", "md-minil", label), h("span", "md-minic", `${filled}/9`));
      mini.appendChild(mb);
    }
    body.appendChild(mini);
    body.appendChild(h("div", "nav-dim small md-help", "Enter/Tab で次のマス・Shift+Tab で前・副題の「広げる ▸」（Alt+↓）でそのブロックへ・Alt+↑ で中心へ戻る。打ち終わって少しすると Vim が保存します。"));
  }

  load();
  return { el, loaded: true, onShow: () => { if (!dirty) load(); } };
}
