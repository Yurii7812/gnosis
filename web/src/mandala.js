// アプリ（\c）の曼荼羅。Vim の曼荼羅（autoload/gnosis/mview.vim）の盤面の状態を、色つきのマスで描く。
// 見た目だけ。キーは、Vim の曼荼羅の窓にそのまま届く（Space・hjkl・Enter・q など）。マウスのクリックは onCell で Vim に伝える。
const KINDS = [
  ["index", "索引"], ["group", "グループ"], ["parent", "親"], ["context", "文脈"], ["cite", "引用"],
  ["back", "BackLink"], ["child", "子"], ["related", "関連"], ["pred", "予測関連"], ["note", "ノート"],
];
// 種類の色（Vim の曼荼羅と同じ。ライトは白い背景で読める濃さ）
const DARK = { index: "#ff6b81", group: "#f2d13d", parent: "#61afef", context: "#c678dd", cite: "#ff9e4a", back: "#d8dee9", child: "#2ec4b6", related: "#8fd14f", pred: "#d2b48c", note: "#9aa0aa" };
const LIGHT = { index: "#d6336c", group: "#b8860b", parent: "#1c7ed6", context: "#9c36b6", cite: "#e8590c", back: "#495057", child: "#0b7285", related: "#2f9e44", pred: "#8a6d3b", note: "#6c757d" };
// 9×9 の、周りの 8 マスとそれぞれの曼荼羅の中心のマスの背景（8 色）
const BG_DARK = ["#2d3b52", "#43304f", "#2f4a3a", "#4f3f2b", "#4f2f36", "#2b4a4d", "#4a4a2b", "#3d3d4a"];
const BG_LIGHT = ["#e3edfb", "#f1e6f7", "#e4f3e8", "#f8eddc", "#f8e3e8", "#dff1f2", "#f3f1d6", "#e9e9ee"];

export function createMandala(root, { onCell }) {
  let last = null;
  root.classList.add("mandala");
  const head = document.createElement("div");
  head.className = "m-head";
  const board = document.createElement("div");
  board.className = "m-board";
  const foot = document.createElement("div");
  foot.className = "m-foot";
  const legend = document.createElement("div");
  legend.className = "m-legend";
  root.append(head, board, foot, legend);

  const light = () => document.documentElement.classList.contains("theme-light");
  const colors = () => (light() ? LIGHT : DARK);

  function drawLegend() {
    legend.textContent = "";
    const c = colors();
    for (const [k, label] of KINDS) {
      const s = document.createElement("span");
      s.textContent = label;
      s.style.color = c[k];
      legend.appendChild(s);
    }
  }

  function render(m) {
    last = m;
    const n = m.size;
    head.textContent = m.status || "";
    foot.textContent = m.info || "";
    board.textContent = "";
    board.style.setProperty("--n", String(n));
    board.classList.toggle("n9", n === 9);
    const c = colors();
    const bgs = light() ? BG_LIGHT : BG_DARK;
    m.cells.forEach((row, r) => row.forEach((cell, col) => {
      const el = document.createElement("div");
      el.className = "m-cell role-" + cell.role;
      el.dataset.r = String(r);
      el.dataset.c = String(col);
      // 3×3 の線は太く、9×9 は 3×3 のまとまりの境目を太く
      if (n === 9) { if (col % 3 === 0) el.classList.add("bl"); if (r % 3 === 0) el.classList.add("bt"); if (col === 8) el.classList.add("br"); if (r === 8) el.classList.add("bb"); }
      const sel = m.cur && m.cur[0] === r && m.cur[1] === col;
      if (sel) el.classList.add("sel");
      if (cell.role === "center") el.classList.add("ctr");
      if (cell.t) {
        const color = c[cell.k] || c.note;
        if (cell.dup) { el.style.background = color; el.style.color = light() ? "#fff" : "#1a1a1a"; el.classList.add("dup"); }
        else {
          el.style.color = color;
          if (cell.bgi >= 0) el.style.background = bgs[cell.bgi];
        }
        if (cell.pt && m.nums) { const p = document.createElement("div"); p.className = "m-pt"; p.textContent = cell.pt; el.appendChild(p); }
        const t = document.createElement("div");
        t.className = "m-t";
        t.textContent = (cell.n > 0 && m.nums ? cell.n + " " : "") + cell.t;
        el.appendChild(t);
      }
      el.addEventListener("click", () => onCell(r, col, false));
      el.addEventListener("dblclick", (e) => { e.preventDefault(); onCell(r, col, true); });
      board.appendChild(el);
    }));
    drawLegend();
  }

  return { render, rerender: () => last && render(last), el: root };
}
