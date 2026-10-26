// アプリ（\c）の曼荼羅。Vim の曼荼羅（autoload/gnosis/mview.vim）の盤面の状態を、色つきのマスで描く。
// 見た目だけ。キーは、Vim の曼荼羅の窓にそのまま届く（Space・hjkl・Enter・q など）。マウスのクリックは onCell で Vim に伝える。
const KINDS = [
  ["index", "索引", "Index"], ["group", "グループ", "Group"], ["parent", "親", "Parent"], ["context", "文脈", "Context"], ["cite", "引用", "Cite"],
  ["back", "BackLink", "BackLink"], ["child", "子", "Child"], ["related", "関連", "Related"], ["pred", "予測関連", "Predicted"], ["note", "ノート", "Note"], ["outline", "見出し", "Heading"],
];
const isEn = () => document.documentElement.lang === "en";
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
  const info = document.createElement("div");
  info.className = "m-info";
  root.append(head, board, legend, info);

  const light = () => document.documentElement.classList.contains("theme-light");
  const colors = () => (light() ? LIGHT : DARK);

  function drawLegend() {
    legend.textContent = "";
    const c = colors();
    for (const [k, ja, en] of KINDS) {
      const s = document.createElement("span");
      s.textContent = isEn() ? en : ja;
      s.style.color = c[k];
      legend.appendChild(s);
    }
  }

  let sig = "";
  let selected = null;
  let legendTheme = null;
  function render(m) {
    last = m;
    const n = m.size;
    if (head.textContent !== (m.status || "")) head.textContent = m.status || "";
    const description = m.info ? "▶ " + m.info : "";
    if (info.textContent !== description) info.textContent = description;
    // 種類の凡例（Vim の設定 mandalaLegend）。
    legend.hidden = m.legend === false || m.legend === 0;
    const legendKey = light() + ":" + isEn();
    if (legendTheme !== legendKey) { drawLegend(); legendTheme = legendKey; }
    // 盤面の中身（マス・色・番号）が前と同じなら、作り直さず、選んでいるマスの枠だけ動かす（ちらつかない）
    const key = JSON.stringify([n, m.nums, m.cells, light()]);
    if (key === sig && board.children.length === n * n) {
      select(m.cur, n);
      return;
    }
    sig = key;
    if (board.children.length !== n * n) {
      board.replaceChildren(...Array.from({ length: n * n }, () => document.createElement("div")));
      selected = null;
    }
    board.style.setProperty("--n", String(n));
    board.classList.toggle("n9", n === 9);
    const c = colors();
    const bgs = light() ? BG_LIGHT : BG_DARK;
    m.cells.forEach((row, r) => row.forEach((cell, col) => {
      const el = board.children[r * n + col];
      const cellKey = JSON.stringify([cell, m.nums, light()]);
      if (el.dataset.content === cellKey) return;
      el.dataset.content = cellKey;
      el.replaceChildren();
      el.removeAttribute("style");
      el.className = "m-cell role-" + cell.role;
      el.dataset.r = String(r);
      el.dataset.c = String(col);

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
      el.onclick = () => onCell(r, col, false);
      el.ondblclick = (e) => { e.preventDefault(); onCell(r, col, true); };

    }));
    select(m.cur, n);
  }

  function select(cur, n) {
    const next = cur && board.children[cur[0] * n + cur[1]];
    if (selected !== next) selected?.classList.remove("sel");
    next?.classList.add("sel");
    selected = next;
  }

  // 曼荼羅の窓にカーソルがあるときだけ、選んでいるマスをハイライトする（右のノートにカーソルがあるときは消す。CUI も同じ）
  function setFocus(on) { root.classList.toggle("unfocused", !on); }

  return { render, rerender: () => last && render(last), setFocus, el: root };
}
