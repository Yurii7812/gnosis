// クイックスイッチャー（Obsidian の Ctrl+O）: 題を打ってノートを開く。見つからなければ、その題で新しいノートを作る。
//   ↑↓ で選ぶ・Enter で開く・Shift+Enter（または「＋ 作る」の行）で新しいノート・Esc で閉じる。
import { h, KIND_BADGE, imeActive } from "./ui.js";

export function createSwitcher({ query, open, create, onClose }) {
  const back = h("div", "qs-back");
  back.hidden = true;
  const box = h("div", "qs");
  box.setAttribute("role", "dialog");
  box.setAttribute("aria-label", "ノートを開く");
  const input = h("input", "qs-input");
  input.type = "text"; input.placeholder = "ノートの題を打つ（Enter で開く・Shift+Enter で新しく作る）";
  input.autocomplete = "off"; input.spellcheck = false;
  const list = h("ul", "qs-list");
  list.setAttribute("role", "listbox");
  const foot = h("div", "qs-foot", "↑↓ 選ぶ　Enter 開く　Shift+Enter 新しく作る　Esc 閉じる");
  box.append(input, list, foot);
  back.appendChild(box);
  document.body.appendChild(back);
  let items = [], sel = 0, my = 0, timer = null, composing = false, loadedQ = null;

  async function load() {
    const q = input.value.trim();
    const n = ++my;
    const r = await query("nav.notes", { q, limit: 60 });
    if (n !== my) return;
    loadedQ = q;
    items = (r.ok ? r.result : []).map((x) => ({ ...x, act: "open" }));
    if (q && !items.some((x) => x.title === q)) items.push({ title: q, act: "create" });
    sel = Math.min(sel, Math.max(0, items.length - 1));
    draw();
  }
  function draw() {
    list.textContent = "";
    items.forEach((it, i) => {
      const li = h("li", "qs-item" + (i === sel ? " sel" : "") + (it.act === "create" ? " create" : ""));
      li.setAttribute("role", "option");
      if (it.act === "create") li.append(h("span", "qs-title", "＋ 新しいノート「" + it.title + "」を作る"));
      else {
        li.append(h("span", "qs-title", it.title));
        const sub = [KIND_BADGE[it.kind] || "", it.path || "", it.time ? it.time.slice(0, 10) : ""].filter(Boolean).join(" · ");
        if (sub) li.append(h("span", "qs-sub", sub));
      }
      li.addEventListener("mousedown", (e) => { e.preventDefault(); sel = i; run(e.shiftKey); });
      list.appendChild(li);
    });
    const s = list.querySelector(".sel"); if (s) s.scrollIntoView({ block: "nearest" });
  }
  async function run(forceCreate) {
    const q = input.value.trim();
    // 打ってすぐの Enter: 一覧がまだ前の文字のものなら、今の文字で探し直してから選ぶ
    if (loadedQ !== q) { clearTimeout(timer); sel = 0; await load(); }
    const it = items[sel];
    close(false);
    if (forceCreate || (it && it.act === "create")) { if (q) await create(q); return; }
    if (it) await open(it.rel);
  }
  function close(refocus = true) { back.hidden = true; if (refocus) onClose && onClose(); }

  input.addEventListener("input", () => { sel = 0; clearTimeout(timer); timer = setTimeout(load, 100); });
  input.addEventListener("compositionstart", () => { composing = true; });
  input.addEventListener("compositionend", () => { composing = false; });
  input.addEventListener("keydown", (e) => {
    if (imeActive(e)) return;
    if (e.key === "ArrowDown" || (e.ctrlKey && e.key === "n")) { e.preventDefault(); sel = Math.min(sel + 1, items.length - 1); draw(); }
    else if (e.key === "ArrowUp" || (e.ctrlKey && e.key === "p")) { e.preventDefault(); sel = Math.max(sel - 1, 0); draw(); }
    else if (e.key === "Enter") { e.preventDefault(); run(e.shiftKey); }
    else if (e.key === "Escape") { e.preventDefault(); close(); }
  });
  back.addEventListener("mousedown", (e) => { if (e.target === back) close(); });
  input.addEventListener("blur", () => setTimeout(() => { if (!composing && !back.hidden && document.activeElement !== input) close(false); }, 150));

  return {
    open() { back.hidden = false; input.value = ""; sel = 0; items = []; loadedQ = null; draw(); load(); setTimeout(() => input.focus(), 0); },
    close,
    isOpen: () => !back.hidden,
  };
}
