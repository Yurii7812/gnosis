// アプリ（\c）の曼荼羅。Vim の曼荼羅（autoload/gnosis/mview.vim）の盤面の状態を、色つきのマスで描く。
// 見た目だけ。キーは、Vim の曼荼羅の窓にそのまま届く（Space・hjkl・Enter・q など）。マウスのクリックは onCell で Vim に伝える。
const KINDS = [
  ["index", "索引"], ["group", "グループ"], ["parent", "親"], ["context", "文脈"], ["cite", "引用"],
  ["back", "BackLink"], ["child", "子"], ["related", "関連"], ["pred", "予測関連"], ["note", "ノート"], ["outline", "見出し"],
];
// 種類の色（Vim の曼荼羅と同じ。ライトは白い背景で読める濃さ）
const DARK = { index: "#ff8798", group: "#f2d13d", parent: "#65b1ef", context: "#d194e4", cite: "#ff9e4a", back: "#d8dee9", child: "#2ec4b6", related: "#8fd14f", pred: "#d2b48c", note: "#a6abb4", outline: "#7ee8fa" };
const LIGHT = { index: "#b81e52", group: "#8a5a00", parent: "#1864ab", context: "#862e9c", cite: "#a8400a", back: "#495057", child: "#08606f", related: "#1f6f30", pred: "#7a5530", note: "#5c6670", outline: "#0a6f8a" };
// 9×9 の、周りの 8 マスとそれぞれの曼荼羅の中心のマスの背景（全部同じごく薄い色）
const BG_DARK = Array(8).fill("#262b36");
const BG_LIGHT = Array(8).fill("#e9edf3");

export function createMandala(root, { onCell }) {
  let last = null;
  root.classList.add("mandala");
  const head = document.createElement("div");
  head.className = "m-head";
  const board = document.createElement("div");
  board.className = "m-board";
  const legend = document.createElement("div");
  legend.className = "m-legend";
  root.append(head, board, legend);

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

  let sig = "";
  function render(m) {
    last = m;
    const n = m.size;
    head.textContent = m.status || "";
    // 種類の凡例（Vim の設定 mandalaLegend）。選んでいるノートの題は出さない（右のノートに出ている）
    legend.hidden = m.legend === false;
    // 盤面の中身（マス・色・番号）が前と同じなら、作り直さず、選んでいるマスの枠だけ動かす（ちらつかない）
    const key = JSON.stringify([n, m.nums, m.cells, light()]);
    if (key === sig && board.children.length === n * n) {
      board.querySelectorAll(".m-cell.sel").forEach((e) => e.classList.remove("sel"));
      const el = m.cur && board.children[m.cur[0] * n + m.cur[1]];
      if (el) el.classList.add("sel");
      return;
    }
    sig = key;
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

  // 曼荼羅の窓にカーソルがあるときだけ、選んでいるマスをハイライトする（右のノートにカーソルがあるときは消す。CUI も同じ）
  function setFocus(on) { root.classList.toggle("unfocused", !on); }

  return { render, rerender: () => last && render(last), setFocus, el: root };
}
