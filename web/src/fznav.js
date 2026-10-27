// アプリ（\c）の Folgezettel ビュー。Vim の Folgezettel ビュー（autoload/gnosis/fznav.vim）が決めた行を、そのまま描く。
// 番号の並び・Group と Note の順・省略（~）・折りたたみ・現在位置はすべて Vim（python/fznav.py）の結果で、ここでは計算しない。
// 窓に見えている行だけが届くので、大量のノートでも軽い。番号は固定幅の欄（ch 単位）、題は常に同じ桁から始まる。
const isEn = () => document.documentElement.lang === "en";
// Group だけアクセントの色（曼荼羅の Group と同じ。ライトは白い背景で読める濃さ）。Group ごとに色は変えない
const ACCENT = { dark: "#f2d13d", light: "#8a5a00" };

export function createFznav(root, { onClick, onScroll }) {
  root.classList.add("fz");
  const head = document.createElement("div");
  head.className = "fz-head";
  const list = document.createElement("div");
  list.className = "fz-list";
  const detail = document.createElement("div");
  detail.className = "fz-detail";
  root.append(head, list, detail);
  const light = () => document.documentElement.classList.contains("theme-light");
  let wheel = 0;
  list.addEventListener("wheel", (e) => {
    e.preventDefault();
    wheel += e.deltaY / 40;
    const n = Math.trunc(wheel);
    if (n) { wheel -= n; onScroll(n); }
  }, { passive: false });

  let sig = "";
  function render(m) {
    const title = m.view === "list" ? (m.title + " / " + m.status) : "FOLGEZETTEL" + (m.mode === "upper" ? " / " + (isEn() ? "Upper" : "上位表示") : "");
    if (head.textContent !== title) head.textContent = title;
    const key = JSON.stringify([m.lines, m.numw, m.top, light()]);
    if (m.detail !== detail.textContent) detail.textContent = m.detail || "";
    if (key === sig) return;
    sig = key;
    root.style.setProperty("--numw", String(m.numw || 8));
    const accent = light() ? ACCENT.light : ACCENT.dark;
    const rows = [];
    for (const c of m.lines) {
      // 先頭の見出し 2 行（FOLGEZETTEL と空行）は、上の固定の見出しで出しているので描かない
      if (c.ln <= 2 && c.k === "h") continue;
      const el = document.createElement("div");
      el.dataset.n = String(c.ln);
      if (c.k === "s") { el.className = c.t ? "fz-sep" : "fz-gap"; rows.push(el); continue; }
      if (c.k === "h") { el.className = "fz-note-line"; el.textContent = c.t; rows.push(el); continue; }
      el.className = "fz-row k-" + c.k + (c.sel ? " sel" : "") + (c.cur ? " cur" : "") + (c.hit ? " nav-hit" : "");
      const mark = document.createElement("span");
      mark.className = "fz-mark";
      mark.textContent = c.cur ? "▸" : "";
      const num = document.createElement("span");
      num.className = "fz-num";
      num.textContent = c.n || "";
      const t = document.createElement("span");
      t.className = "fz-title";
      t.textContent = c.t + (c.c || "");
      el.append(mark, num, t);
      if (c.k === "g") el.style.color = accent;
      if (c.id && c.id !== c.n) el.title = c.id;
      // 省かれた番号（~…）は、上にマウスを置くと全体が分かる（Vim の詳細表示と同じ内容）
      el.onclick = () => onClick(c.ln, false);
      el.ondblclick = (e) => { e.preventDefault(); onClick(c.ln, true); };
      rows.push(el);
    }
    list.replaceChildren(...rows);
  }
  return { render, rerender: () => {}, el: root, setFocus: (on) => root.classList.toggle("unfocused", !on) };
}
