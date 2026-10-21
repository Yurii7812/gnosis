// カレンダー（タブ）。月の表に、日記・時系列記録（夢など）・その日に作ったノート・期限のタスクを出す。
//   日を選ぶと右にその日の中身。日記を開く／作る（\d と同じ。来ていない日は作らない）、タスクの完了、タスクの追加。
//   書くのは Vim（タスクの完了は本文を作って Vim に保存させる・追加と日記は gnosis#app_op）。
import { h, button, form, toast } from "./ui.js";

const WD = ["月", "火", "水", "木", "金", "土", "日"];
const pad = (n) => String(n).padStart(2, "0");
const iso = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const addMonths = (ym, k) => { const [y, m] = ym.split("-").map(Number); const d = new Date(y, m - 1 + k, 1); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`; };

export function createCalendar(ctx, params = {}) {
  const el = h("div", "viewbox calbox keepfocus");
  el.tabIndex = 0;
  const bar = h("div", "cal-bar");
  const title = h("div", "cal-title");
  const grid = h("div", "cal-grid");
  const side = h("div", "cal-side");
  const main = h("div", "cal-main"); main.append(grid, side);
  el.append(bar, main);
  let ym = params.ym || iso(new Date()).slice(0, 7);
  let sel = params.date || iso(new Date());
  let data = null;

  bar.append(button("‹", () => go(-1), "nav-btn", "前の月（PageUp）"), title, button("›", () => go(1), "nav-btn", "次の月（PageDown）"),
    button("今日", () => { sel = iso(new Date()); ym = sel.slice(0, 7); load(); }, "nav-btn", "今日（t）"),
    button("今日の日記（\\d）", () => openDiary(iso(new Date())), "nav-btn"),
    button("＋ タスク", () => addTask(sel), "nav-btn primary", "選んだ日が期限のタスクを今日の日記に書く（a）"),
    h("span", "cal-legend", "📔 日記　🌙 記録　📝 作ったノート　☐ 期限のタスク　✅ 終えた数"));

  function go(k) { ym = addMonths(ym, k); if (sel.slice(0, 7) !== ym) sel = ym + "-01"; load(); }

  async function load() {
    const r = await ctx.query("cal.month", { ym });
    if (!r.ok) { grid.textContent = r.error || "読めませんでした"; return; }
    data = r.result;
    drawMonth();
    drawDay();
  }

  function drawMonth() {
    const [y, m] = ym.split("-").map(Number);
    title.textContent = `${y}年 ${m}月`;
    grid.textContent = "";
    for (const w of WD) grid.appendChild(h("div", "cal-wd" + (w === "土" ? " sat" : w === "日" ? " sun" : ""), w));
    const first = new Date(y, m - 1, 1);
    const lead = (first.getDay() + 6) % 7;
    for (let i = 0; i < lead; i++) grid.appendChild(h("div", "cal-cell blank"));
    const last = new Date(y, m, 0).getDate();
    for (let d = 1; d <= last; d++) {
      const key = `${ym}-${pad(d)}`;
      const v = data.days[key];
      const wd = (lead + d - 1) % 7;
      const c = h("button", "cal-cell" + (key === data.today ? " today" : "") + (key === sel ? " sel" : "") + (wd === 5 ? " sat" : wd === 6 ? " sun" : "") + (key > data.today ? " future" : ""));
      c.type = "button";
      c.appendChild(h("div", "cal-day", String(d)));
      const marks = h("div", "cal-marks");
      if (v.diary) marks.appendChild(h("span", "cal-m diary", "📔"));
      for (const r of v.records) marks.appendChild(h("span", "cal-m rec", "🌙" + (r.record ? r.record.slice(0, 2) : "")));
      if (v.created) marks.appendChild(h("span", "cal-m", "📝" + v.created));
      if (v.done) marks.appendChild(h("span", "cal-m done", "✅" + v.done));
      c.appendChild(marks);
      if (v.diary && v.diary.preview) c.appendChild(h("div", "cal-prev", v.diary.preview));
      for (const t of v.due.slice(0, 3)) c.appendChild(h("div", "cal-task" + (key < data.today ? " over" : ""), "☐ " + (t.time ? t.time + " " : "") + t.text));
      if (v.due.length > 3) c.appendChild(h("div", "cal-more", `ほか ${v.due.length - 3} 件`));
      c.addEventListener("click", () => { sel = key; drawMonth(); drawDay(); });
      c.addEventListener("dblclick", () => openDiary(key));
      grid.appendChild(c);
    }
  }

  async function drawDay() {
    const r = await ctx.query("cal.day", { date: sel });
    side.textContent = "";
    if (!r.ok) { side.textContent = r.error || ""; return; }
    const d = r.result;
    const dt = new Date(sel + "T12:00:00");
    side.appendChild(h("div", "cal-sidetitle", `${sel}（${WD[(dt.getDay() + 6) % 7]}）`));
    const future = sel > d.today;
    // 日記
    const ds = h("div", "cal-sec");
    if (d.diary) {
      ds.append(button("📔 日記を開く", () => openDiary(sel), "nav-btn primary"));
      if (d.diary.preview) ds.appendChild(h("div", "cal-dprev", d.diary.preview));
    } else if (!future) ds.append(button("📔 この日の日記を作って開く", () => openDiary(sel), "nav-btn"), h("div", "nav-dim small", "日記・月・年の木は \\d と同じ形で作ります"));
    else ds.appendChild(h("div", "nav-dim", "まだ来ていない日です"));
    side.appendChild(ds);
    for (const rr of d.records) side.appendChild(button("🌙 " + rr.title, () => ctx.open(rr.rel), "nav-link block"));
    // タスク
    const ts = h("div", "cal-sec");
    ts.appendChild(h("div", "nav-sectitle", `期限のタスク（${d.due.length}）`));
    for (const t of d.due) ts.appendChild(taskRow(t));
    if (d.overdue && d.overdue.length) {
      ts.appendChild(h("div", "nav-sectitle over", `期限切れ（${d.overdue.length}）`));
      for (const t of d.overdue) ts.appendChild(taskRow(t, true));
    }
    ts.appendChild(button("＋ この日が期限のタスク", () => addTask(sel), "nav-btn"));
    if (d.done.length) {
      ts.appendChild(h("div", "nav-sectitle", `終えたタスク（${d.done.length}）`));
      for (const t of d.done) ts.appendChild(h("div", "cal-trow done", "✅ " + t.text));
    }
    side.appendChild(ts);
    // ノート
    if (d.created.length) {
      const ns = h("div", "cal-sec");
      ns.appendChild(h("div", "nav-sectitle", `この日に作ったノート（${d.created.length}）`));
      for (const n of d.created) {
        const b = button("", () => ctx.open(n.rel), "nav-link block");
        b.append(h("span", "cal-time", n.time), h("span", "", n.title));
        if (n.path) b.appendChild(h("span", "nav-dim small", " " + n.path));
        ns.appendChild(b);
      }
      side.appendChild(ns);
    }
  }

  function taskRow(t, showDue) {
    const row = h("div", "cal-trow");
    const cb = h("input"); cb.type = "checkbox"; cb.title = "完了にする（Vim が保存します）";
    cb.addEventListener("change", async () => {
      cb.disabled = true;
      const ok = await ctx.completeTask(t);
      if (ok) { toast("完了にしました: " + t.text); load(); } else cb.checked = false;
      cb.disabled = false;
    });
    row.append(cb, h("span", "cal-ttext", (t.time ? t.time + " " : "") + t.text));
    if (showDue) row.appendChild(h("span", "cal-tdue", t.due));
    if (t.repeat) row.appendChild(h("span", "nav-badge", "🔁 " + t.repeat));
    row.appendChild(button(t.note, () => ctx.open(t.file), "nav-link small", "タスクのあるノートを開く"));
    return row;
  }

  async function openDiary(date) {
    const r = await ctx.op("diary_open", { date });
    if (!r.ok) toast(r.error || "開けませんでした", "err");
    else { ctx.showVim && ctx.showVim(); setTimeout(load, 400); }
  }

  async function addTask(date) {
    const v = await form({
      title: `タスクを追加（期限 ${date}）`, ok: "追加",
      note: "今日の日記に `- [ ] … 📅 日付` の行で書きます（スマホの予定にも送られます）。",
      fields: [{ key: "text", label: "やること", required: true }, { key: "date", label: "期限の日", type: "date", value: date }, { key: "time", label: "時刻", type: "time", hint: "空なら終日" }],
    });
    if (!v) return;
    const r = await ctx.op("task_add", { text: v.text, date: v.date || "", time: v.time || "" });
    if (!r.ok) toast(r.error || "書けませんでした", "err"); else { toast("今日の日記に書きました"); setTimeout(load, 300); }
  }

  el.addEventListener("keydown", (e) => {
    if (e.target.tagName === "INPUT") return;
    const mv = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }[e.key];
    if (mv) {
      e.preventDefault();
      const d = new Date(sel + "T12:00:00"); d.setDate(d.getDate() + mv); sel = iso(d);
      if (sel.slice(0, 7) !== ym) { ym = sel.slice(0, 7); load(); } else { drawMonth(); drawDay(); }
    } else if (e.key === "PageUp") { e.preventDefault(); go(-1); }
    else if (e.key === "PageDown") { e.preventDefault(); go(1); }
    else if (e.key === "Enter") { e.preventDefault(); openDiary(sel); }
    else if (e.key === "t") { sel = iso(new Date()); ym = sel.slice(0, 7); load(); }
    else if (e.key === "a") { e.preventDefault(); addTask(sel); }
  });
  load();
  return { el, loaded: true, refresh: load };
}
