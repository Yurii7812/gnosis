// アプリ（\c）のアウトライン窓。Vim のアウトライン窓（autoload/gnosis/outline.vim）の見出しの一覧を描く。
// 見出しの解析・折りたたみ・本文のカーソルがある見出し（強調）は Vim 側の結果。クリックで本文のその見出しへ。
const isEn = () => document.documentElement.lang === "en";

export function createOutlinePane(root, { onClick, onFold, onScroll }) {
  root.classList.add("olp");
  const head = document.createElement("div");
  head.className = "olp-head";
  head.textContent = "OUTLINE";
  const list = document.createElement("div");
  list.className = "olp-list";
  root.append(head, list);
  let wheel = 0;
  list.addEventListener("wheel", (e) => {
    e.preventDefault();
    wheel += e.deltaY / 40;
    const n = Math.trunc(wheel);
    if (n) { wheel -= n; onScroll(n); }
  }, { passive: false });
  let sig = "";
  function render(o) {
    root.classList.toggle("unfocused", !o.focus);
    const key = JSON.stringify([o.lines, o.top]);
    if (key === sig) return;
    sig = key;
    const rows = [];
    for (const c of o.lines) {
      if (c.n <= 2) continue;       // 先頭の見出し（OUTLINE と空行）は固定の見出しで出している
      const el = document.createElement("div");
      el.dataset.n = String(c.n);
      if (c.k === "h") { el.className = "olp-note"; el.textContent = c.t; rows.push(el); continue; }
      el.className = "olp-row" + (c.a ? " active" : "") + (c.sel ? " sel" : "");
      el.style.paddingLeft = (8 + (c.d || 0) * 14) + "px";
      el.textContent = c.t + (c.c || "");
      el.onclick = () => onClick(c.n, true);
      el.oncontextmenu = (e) => { e.preventDefault(); onFold(c.n); };
      el.title = isEn() ? "Click: jump / Right click: fold" : "クリック: 本文へ / 右クリック: 折りたたみ";
      rows.push(el);
    }
    list.replaceChildren(...rows);
  }
  return { render, el: root };
}
