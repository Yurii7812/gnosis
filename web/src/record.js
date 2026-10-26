// 時系列記録の「日付を指定して作る」（\D）と「上位の記録を選ぶ」（\E）の画面。
//   date   … カレンダー（日付の入力欄）と、記録の系列の検索・選択。Enter で作る（すでにあれば開く）。初期値は今日。
//   parent … 上位の記録の検索・選択（「上位なし」で解除）。Enter で決める。
// キーボードだけで使える。Tab で日付と検索を行き来、↑ ↓（Ctrl-N / Ctrl-P）で選ぶ、Enter で決める、Esc で閉じる。
export function createRecord(root, { onSubmit, onClose }) {
  root.className = "recordpick";
  root.innerHTML = `
    <div class="rp-box" role="dialog" aria-modal="true">
      <div class="rp-title"></div>
      <label class="rp-daterow"><span class="rp-dl"></span><input class="rp-date" type="date"></label>
      <input class="rp-search" type="text" autocomplete="off" spellcheck="false">
      <div class="rp-list" role="listbox"></div>
      <div class="rp-msg"></div>
      <div class="rp-keys"></div>
    </div>`;
  const $ = (s) => root.querySelector(s);
  const title = $(".rp-title"), dateRow = $(".rp-daterow"), dl = $(".rp-dl"), date = $(".rp-date");
  const search = $(".rp-search"), list = $(".rp-list"), msg = $(".rp-msg"), keys = $(".rp-keys");
  const en = document.documentElement.lang === "en";
  const T = en ? {
    dateTitle: "Create a chronological record for a date", parentTitle: "Parent of this record",
    date: "Date", search: "Search the records", none: "No matches.", bad: "Enter a real date.",
    dateKeys: "Tab: date ⇄ search   ↑ ↓: choose   Enter: create / open   Esc: close",
    parentKeys: "↑ ↓: choose   Enter: decide   Esc: close",
  } : {
    dateTitle: "日付を指定して時系列記録を作る", parentTitle: "この記録の上位の記録",
    date: "日付", search: "記録を検索", none: "該当する記録がありません。", bad: "実在する日付を入れてください。",
    dateKeys: "Tab: 日付 ⇄ 検索   ↑ ↓: 選ぶ   Enter: 作る・開く   Esc: 閉じる",
    parentKeys: "↑ ↓: 選ぶ   Enter: 決める   Esc: 閉じる",
  };
  let mode = "date", kinds = [], shown = [], sel = 0, opened = false;

  const realDate = (s) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
    const d = new Date(s + "T12:00:00");
    return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
  };

  function render() {
    const q = search.value.trim().toLowerCase();
    shown = kinds.filter((k) => !q || k.toLowerCase().includes(q));
    sel = Math.max(0, Math.min(sel, shown.length - 1));
    list.textContent = "";
    if (!shown.length) { const e = document.createElement("div"); e.className = "rp-empty"; e.textContent = T.none; list.appendChild(e); return; }
    shown.forEach((k, i) => {
      const row = document.createElement("div");
      row.className = "rp-item" + (i === sel ? " sel" : "");
      row.setAttribute("role", "option");
      row.textContent = k;
      row.onclick = () => { sel = i; submit(); };
      list.appendChild(row);
    });
    list.querySelector(".sel")?.scrollIntoView({ block: "nearest" });
  }

  function submit() {
    if (!shown.length) return;
    if (mode === "date") {
      if (!realDate(date.value)) { msg.textContent = T.bad; date.focus(); return; }
      const k = shown[sel];
      close();
      onSubmit("date", { kind: k, date: date.value });
    } else {
      const k = shown[sel];
      close();
      onSubmit("parent", { name: k });
    }
  }

  function close() {
    if (!opened) return;
    opened = false;
    root.hidden = true;
    onClose?.();
  }

  root.addEventListener("keydown", (e) => {
    if (!opened) return;
    if (e.key === "Escape") { e.preventDefault(); close(); return; }
    if (e.key === "Enter") { e.preventDefault(); submit(); return; }
    if (e.key === "ArrowDown" || (e.ctrlKey && e.key === "n")) { e.preventDefault(); sel = Math.min(shown.length - 1, sel + 1); render(); return; }
    if (e.key === "ArrowUp" || (e.ctrlKey && e.key === "p")) { e.preventDefault(); sel = Math.max(0, sel - 1); render(); return; }
    if (e.key === "Tab" && mode === "date") {
      e.preventDefault();
      (document.activeElement === date ? search : date).focus();
    }
  });
  search.addEventListener("input", () => { sel = 0; render(); });

  return {
    isOpen: () => opened,
    open(req) {
      mode = req.mode === "parent" ? "parent" : "date";
      kinds = Array.isArray(req.kinds) ? req.kinds.slice() : [];
      title.textContent = mode === "date" ? T.dateTitle : T.parentTitle + (req.kind ? ` — ${req.kind}` : "");
      dateRow.hidden = mode !== "date";
      dl.textContent = T.date;
      date.value = req.today || new Date().toISOString().slice(0, 10);
      search.placeholder = T.search;
      search.value = "";
      msg.textContent = "";
      keys.textContent = mode === "date" ? T.dateKeys : T.parentKeys;
      sel = 0;
      root.hidden = false;
      opened = true;
      render();
      (mode === "date" ? date : search).focus();
    },
    close,
  };
}
