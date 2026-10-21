// 画面の小さな部品（索引ナビ・カレンダー・曼荼羅・キャンバスで共通）。
//   h()       … 要素を作る
//   form()    … 入力ダイアログ（文字・候補から選ぶ欄）。Enter で決定、Esc で取り消し。Promise で答え（取り消しは null）
//   toast()   … 右下に短い知らせ
// 日本語入力（IME）で変換中のキーか。変換の確定の Enter・候補を選ぶ矢印・変換を取り消す Esc は、画面の操作として扱わない
export const imeActive = (e) => !!(e && (e.isComposing || e.keyCode === 229));

export function h(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

export function button(label, onClick, cls = "", title = "") {
  const b = h("button", cls, label);
  b.type = "button";
  if (title) b.title = title;
  b.addEventListener("click", (e) => { e.stopPropagation(); onClick(e); });
  return b;
}

let toastTimer = null;
export function toast(text, kind = "") {
  let el = document.getElementById("gtoast");
  if (!el) { el = h("div", "gtoast"); el.id = "gtoast"; el.setAttribute("role", "status"); document.body.appendChild(el); }
  el.textContent = text;
  el.className = "gtoast show " + kind;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.className = "gtoast"; }, kind === "err" ? 7000 : 3500);
}

// fields: [{ key, label, value?, placeholder?, type?: "text"|"textarea"|"picker"|"date"|"time", load?: async (q) => [{label, sub?, value}], hint? }]
export function form({ title, fields, ok = "OK", note = "" }) {
  return new Promise((resolve) => {
    document.querySelectorAll(".gdlg-back").forEach((x) => x.remove());
    const back = h("div", "gdlg-back");
    const box = h("div", "gdlg"); box.setAttribute("role", "dialog"); box.setAttribute("aria-label", title);
    box.appendChild(h("div", "gdlg-title", title));
    if (note) box.appendChild(h("div", "gdlg-note", note));
    const vals = {};
    const inputs = [];
    for (const f of fields) {
      const row = h("label", "gdlg-row");
      row.appendChild(h("span", "gdlg-label", f.label));
      if (f.type === "picker") {
        const wrap = h("div", "gpick");
        const inp = h("input"); inp.type = "search"; inp.placeholder = f.placeholder || "探す…"; inp.autocomplete = "off"; inp.value = f.query || "";
        const chosen = h("div", "gpick-chosen", "");
        const list = h("div", "gpick-list");
        let items = [], sel = 0, timer = null;
        vals[f.key] = f.value ?? null;
        if (f.valueLabel) chosen.textContent = "選択中: " + f.valueLabel;
        const draw = () => {
          list.textContent = "";
          items.forEach((it, i) => {
            const li = h("div", "gpick-item" + (i === sel ? " sel" : "") + (vals[f.key] === it.value ? " chosen" : ""));
            li.appendChild(h("span", "gpick-main", it.label));
            if (it.sub) li.appendChild(h("span", "gpick-sub", it.sub));
            li.addEventListener("mousedown", (e) => { e.preventDefault(); pick(i); });
            list.appendChild(li);
          });
          const s = list.querySelector(".sel"); if (s) s.scrollIntoView({ block: "nearest" });
        };
        const pick = (i) => {
          const it = items[i]; if (!it) return;
          vals[f.key] = it.value; sel = i; chosen.textContent = "選択中: " + it.label + (it.sub ? "（" + it.sub + "）" : "");
          if (f.onPick) f.onPick(it, setField);
          draw();
        };
        const load = async () => { try { items = await f.load(inp.value.trim()); } catch { items = []; } sel = Math.min(sel, Math.max(0, items.length - 1)); draw(); };
        inp.addEventListener("input", () => { clearTimeout(timer); sel = 0; timer = setTimeout(load, 120); });
        inp.addEventListener("keydown", (e) => {
          if (imeActive(e)) return;
          if (e.key === "ArrowDown") { e.preventDefault(); sel = Math.min(sel + 1, items.length - 1); draw(); }
          else if (e.key === "ArrowUp") { e.preventDefault(); sel = Math.max(sel - 1, 0); draw(); }
          else if (e.key === "Enter" && items.length && vals[f.key] !== items[sel]?.value) { e.preventDefault(); e.stopPropagation(); pick(sel); }
        });
        wrap.append(inp, chosen, list);
        row.appendChild(wrap);
        inputs.push(inp);
        load();
      } else {
        const inp = f.type === "textarea" ? h("textarea") : h("input");
        if (f.type !== "textarea") inp.type = f.type === "date" || f.type === "time" ? f.type : "text";
        inp.value = f.value ?? "";
        if (f.placeholder) inp.placeholder = f.placeholder;
        inp.dataset.key = f.key;
        row.appendChild(inp);
        inputs.push(inp);
      }
      if (f.hint) row.appendChild(h("span", "gdlg-hint", f.hint));
      box.appendChild(row);
    }
    function setField(key, v) { const inp = inputs.find((x) => x.dataset && x.dataset.key === key); if (inp && !inp.dataset.touched) inp.value = v; }
    for (const inp of inputs) inp.addEventListener("input", () => { inp.dataset.touched = "1"; });
    const bar = h("div", "gdlg-bar");
    const err = h("span", "gdlg-err", "");
    const done = (v) => { back.remove(); resolve(v); };
    const submit = () => {
      for (const inp of inputs) if (inp.dataset && inp.dataset.key) vals[inp.dataset.key] = inp.value;
      for (const f of fields) if (f.required && !String(vals[f.key] ?? "").trim()) { err.textContent = f.label + " を入れてください"; return; }
      done(vals);
    };
    bar.append(err, button("やめる", () => done(null)), button(ok, submit, "primary"));
    box.appendChild(bar);
    back.appendChild(box);
    back.addEventListener("mousedown", (e) => { if (e.target === back) done(null); });
    const onKey = (e) => {
      if (imeActive(e)) return;
      if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); done(null); }
      else if (e.key === "Enter" && !e.shiftKey && e.target.tagName !== "TEXTAREA" && !e.defaultPrevented) { e.preventDefault(); e.stopPropagation(); submit(); }
    };
    box.addEventListener("keydown", onKey);   // 欄の中の処理（候補を選ぶ Enter）が先に走るよう、泡立ちで受ける
    document.body.appendChild(back);
    setTimeout(() => inputs[0] && inputs[0].focus(), 0);
  });
}

// 項目の名前を「は: ハーブ 薬草」のように行（見出し・頭文字）ごとに分ける
export function byRow(entries) {
  const out = [];
  for (const e of entries) {
    const last = out[out.length - 1];
    if (last && last.row === (e.row || "")) last.items.push(e);
    else out.push({ row: e.row || "", items: [e] });
  }
  return out;
}

export const KIND_BADGE = { index: "Global Index", topic: "トピック索引", group: "索引", diary: "日記", mandala: "曼荼羅", canvas: "キャンバス", note: "" };

// ノートの候補の添え書き: 種類（トピック索引など）・Index からの道・日付。同じ題のノートを見分けられるように
export function noteSub(x) {
  return [KIND_BADGE[x.kind] || "", x.path || "", x.time ? x.time.slice(0, 10) : ""].filter(Boolean).join(" · ");
}

// 小さなメニュー（右クリック・「…」のボタン）。items: [{ label, run, disabled? } | "-"]
export function popupMenu(x, y, items) {
  document.querySelectorAll(".ctxmenu").forEach((m) => m.remove());
  const m = h("div", "ctxmenu"); m.style.left = x + "px"; m.style.top = y + "px";
  for (const it of items) {
    if (it === "-") { m.appendChild(h("div", "sep")); continue; }
    const b = h("button", "", it.label); b.type = "button"; b.disabled = !!it.disabled;
    b.addEventListener("click", () => { m.remove(); it.run(); });
    m.appendChild(b);
  }
  document.body.appendChild(m);
  m.style.maxHeight = (window.innerHeight - 16) + "px";
  const r = m.getBoundingClientRect();
  if (r.bottom > window.innerHeight - 8) m.style.top = Math.max(8, window.innerHeight - r.height - 8) + "px";
  if (r.right > window.innerWidth - 8) m.style.left = Math.max(8, window.innerWidth - r.width - 8) + "px";
  const away = (e) => { if (!m.contains(e.target)) { m.remove(); document.removeEventListener("mousedown", away, true); } };
  setTimeout(() => document.addEventListener("mousedown", away, true), 0);
  return m;
}
