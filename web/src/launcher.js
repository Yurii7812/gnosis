// 起動画面（ノートを開く前）・vault の選択と管理・設定画面。
// 起動画面は白背景・黒文字。vault を開いたあとは、その vault の設定のテーマになる（app.js）。
// 文言は i18n/ja.json・i18n/en.json（Vim と共通）。設定は <vault>/.gnosis/settings.json（Vim と共通）。
const G = window.gnosis;
const $ = (id) => document.getElementById(id);
const h = (tag, attrs = {}, ...kids) => {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") el.className = v;
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else if (k === "text") el.textContent = v;
    else if (v !== false && v != null) el.setAttribute(k, v === true ? "" : v);
  }
  for (const c of kids.flat()) if (c != null) el.append(c);
  return el;
};

let st = null; // main から受け取った状態
let view = "start"; // start | vaults | settings
let sel = 0; // vault 一覧の選択
let message = "";
let onStart = null;
let draft = null; // 編集中の設定

function t(key, ...args) {
  let s = (st && st.msg && st.msg[key]) || key;
  for (const a of args) s = s.replace("%s", a);
  return s;
}

function errText(r) {
  return r.key ? t(r.key, r.detail) : r.detail;
}

function selected() {
  return st.vaults.find((v) => v.path === st.selected) || null;
}

async function refresh(selectedPath) {
  st = await G.state(selectedPath ?? (st && st.selected));
  document.documentElement.lang = st.lang;
  const i = st.vaults.findIndex((v) => v.path === st.selected);
  sel = i >= 0 ? i : 0;
  render();
}

// ---------------------------------------------------------------- 描画

function render() {
  const root = $("launcher");
  root.replaceChildren(view === "vaults" ? renderVaults() : view === "settings" ? renderSettings() : renderStart());
  if (view === "start") fitArt();
  const focus = root.querySelector("[data-autofocus]");
  if (focus) focus.focus();
}

function renderStart() {
  const v = selected();
  const canStart = !!(v && v.exists);
  return h("div", { class: "l-start", id: "l-start" },
    h("pre", { class: "l-art", id: "l-art", "aria-hidden": "true" }),
    h("div", { class: "l-title", text: "Gnosis" }),
    h("div", { class: "l-vault" },
      v ? [h("div", { class: "l-vname", text: t("start.vault_label") + " " + v.name }), h("div", { class: "l-vpath", text: v.path })]
        : h("div", { class: "l-vpath", text: t("start.no_vault") }),
      v && !v.exists ? h("div", { class: "l-warn", text: t("start.vault_missing") }) : null),
    h("div", { class: "l-buttons" },
      h("button", { class: "l-primary", id: "l-enter", disabled: !canStart, "data-autofocus": canStart, onclick: () => start() }, t("start.enter")),
      h("button", { id: "l-open-vaults", "data-autofocus": !canStart, onclick: () => go("vaults") }, t("web.vaults_button")),
      h("button", { id: "l-open-settings", disabled: !v || !v.exists, onclick: () => go("settings") }, t("web.settings_button"))),
    message ? h("div", { class: "l-msg", text: message }) : null,
    h("div", { class: "l-hint", text: t("web.start_keys") }));
}

// アートを画面に収まる大きさで出す（Unicode Braille の形はそのまま。色は黒）
function fitArt() {
  const pre = $("l-art");
  if (!pre || !st.art) return;
  const box = $("launcher").getBoundingClientRect();
  const reserve = 260; // 下の情報欄の高さ
  const availH = Math.max(0, box.height - reserve);
  const availW = box.width - 32;
  let best = null;
  for (const w of [80, 60, 44]) {
    const lines = st.art[w];
    if (!lines) continue;
    // 等幅で 1 文字 ≒ 0.6em、行の高さ 1.0em として、収まる文字の大きさ
    const size = Math.min(availW / (w * 0.6), availH / lines.length, 14);
    if (size >= 5 || w === 44) { best = { lines, size }; break; }
  }
  if (!best || best.size < 2.5) { pre.hidden = true; return; }
  pre.hidden = false;
  pre.textContent = best.lines.join("\n");
  pre.style.fontSize = best.size.toFixed(2) + "px";
}

function renderVaults() {
  const list = st.vaults;
  return h("div", { class: "l-panel" },
    h("div", { class: "l-head" }, h("button", { onclick: () => go("start") }, "← " + t("web.back")), h("h2", { text: t("vaults.title") })),
    message ? h("div", { class: "l-msg", text: message }) : null,
    list.length ? h("ul", { class: "l-list", role: "listbox" }, list.map((v, i) =>
      h("li", { class: "l-item" + (i === sel ? " sel" : "") + (v.exists ? "" : " missing"), role: "option", "aria-selected": i === sel ? "true" : "false",
        onclick: () => { sel = i; render(); }, ondblclick: () => openVault(i) },
        h("div", { class: "l-vname", text: v.name + (v.exists ? "" : "  " + t("vaults.missing")) }), h("div", { class: "l-vpath", text: v.path }))))
      : h("p", { class: "l-vpath", text: t("vaults.empty") }),
    h("div", { class: "l-buttons" },
      h("button", { class: "l-primary", disabled: !list.length, "data-autofocus": !!list.length, onclick: () => openVault(sel) }, t("web.open")),
      h("button", { "data-autofocus": !list.length, onclick: addExisting }, t("web.add_existing")),
      h("button", { onclick: createNew }, t("web.create_new")),
      h("button", { disabled: !list.length, onclick: removeSelected }, t("web.remove"))),
    h("div", { class: "l-hint", text: t("web.vault_keys") }));
}

function field(label, control) {
  return h("label", { class: "l-field" }, h("span", { text: label }), control);
}

function renderSettings() {
  const s = draft;
  const themeOptions = [h("option", { value: "builtin", selected: s.theme.kind === "builtin" }, t("settings.theme_builtin"))];
  for (const name of Object.keys(s.customThemes).sort()) {
    themeOptions.push(h("option", { value: "custom:" + name, selected: s.theme.kind === "custom" && s.theme.name === name }, t("settings.theme_custom", name)));
  }
  for (const th of st.themes) for (const cs of th.colorschemes) {
    const val = "plugin:" + th.repo + ":" + cs;
    themeOptions.push(h("option", { value: val, selected: s.theme.kind === "plugin" && s.theme.repo === th.repo && s.theme.colorscheme === cs }, cs + "  (" + th.repo + ")"));
  }
  const custom = s.theme.kind === "custom" ? s.customThemes[s.theme.name] : null;
  const base = st.palettes[(custom && custom.base) || s.appearance] || st.palettes.light;
  const colors = ["bg", "fg", "link", "heading", "selection", "cursorline"];
  return h("div", { class: "l-panel l-settings" },
    h("div", { class: "l-head" }, h("button", { onclick: () => go("start") }, "← " + t("web.back")), h("h2", { text: t("settings.title") })),
    h("div", { class: "l-vpath", text: t("settings.vault") + " " + st.selected }),
    message ? h("div", { class: "l-msg", text: message }) : null,
    h("form", { class: "l-form", onsubmit: (e) => { e.preventDefault(); saveSettings(); } },
      field(t("settings.item.language"), h("select", { id: "s-lang", "data-autofocus": true, onchange: (e) => { s.language = e.target.value; } },
        h("option", { value: "ja", selected: s.language === "ja" }, "日本語"), h("option", { value: "en", selected: s.language === "en" }, "English"))),
      field(t("settings.item.maximized"), h("input", { type: "checkbox", id: "s-max", checked: s.window.maximized, onchange: (e) => { s.window.maximized = e.target.checked; } })),
      field(t("settings.item.window"), h("span", { class: "l-row" },
        h("input", { type: "number", id: "s-w", min: 480, max: 10000, value: s.window.width, onchange: (e) => { s.window.width = Number(e.target.value); } }), " × ",
        h("input", { type: "number", id: "s-h", min: 360, max: 10000, value: s.window.height, onchange: (e) => { s.window.height = Number(e.target.value); } }))),
      field(t("settings.item.fontSize"), h("input", { type: "number", id: "s-font", min: 8, max: 48, value: s.fontSize, onchange: (e) => { s.fontSize = Number(e.target.value); } })),
      field(t("settings.item.appearance"), h("select", { id: "s-appearance", onchange: (e) => { s.appearance = e.target.value; render(); } },
        h("option", { value: "light", selected: s.appearance === "light" }, t("settings.light")), h("option", { value: "dark", selected: s.appearance === "dark" }, t("settings.dark")))),
      field(t("settings.item.theme"), h("select", { id: "s-theme", onchange: (e) => { setTheme(e.target.value); render(); } }, themeOptions)),
      field(t("settings.item.theme_add"), h("span", { class: "l-row" },
        h("input", { type: "text", id: "s-plug", placeholder: "Plug 'cocopon/iceberg.vim'" }),
        h("button", { type: "button", id: "s-plug-add", onclick: addTheme }, t("web.add")))),
      h("fieldset", { class: "l-colors" },
        h("legend", { text: t("settings.item.custom") }),
        field(t("settings.prompt_custom_name").replace(/[:：]\s*$/, ""), h("input", { type: "text", id: "s-cname", value: s.theme.kind === "custom" ? s.theme.name : "my-theme" })),
        colors.map((k) => field(t("settings.color." + k), h("input", { type: "color", id: "s-c-" + k, value: (custom && custom[k]) || base[k] }))),
        h("button", { type: "button", id: "s-custom-save", onclick: saveCustom }, t("web.use_custom"))),
      h("div", { class: "l-buttons" },
        h("button", { type: "submit", class: "l-primary", id: "s-save" }, t("web.save")),
        h("button", { type: "button", onclick: () => { s.theme = { kind: "builtin" }; render(); } }, t("settings.item.theme_reset")))),
    h("div", { class: "l-hint", text: t("web.zoom_note") }));
}

function setTheme(val) {
  if (val === "builtin") draft.theme = { kind: "builtin" };
  else if (val.startsWith("custom:")) draft.theme = { kind: "custom", name: val.slice(7) };
  else {
    const [, rest] = val.split(/^plugin:/);
    const i = rest.lastIndexOf(":");
    draft.theme = { kind: "plugin", repo: rest.slice(0, i), colorscheme: rest.slice(i + 1) };
  }
}

// ---------------------------------------------------------------- 操作

function go(v) {
  message = "";
  view = v;
  if (v === "settings") draft = JSON.parse(JSON.stringify(st.settings));
  render();
}

async function openVault(i) {
  const v = st.vaults[i];
  if (!v) return;
  if (!v.exists) { message = t("start.missing_choose", v.path); render(); return; }
  const r = await G.selectVault(v.path);
  if (!r.ok) { message = errText(r); render(); return; }
  view = "start";
  await refresh(r.value);
  start();
}

async function addExisting() {
  const p = await G.pickFolder(t("vaults.prompt_add"));
  if (!p) return;
  const r = await G.addVault(p);
  message = r.ok ? t("vaults.added", r.value) : errText(r);
  await refresh(r.ok ? r.value : undefined);
}

async function createNew() {
  const p = await G.pickFolder(t("vaults.prompt_new"));
  if (!p) return;
  const r = await G.createVault(p, st.lang);
  message = r.ok ? t("vaults.created", r.value) : errText(r);
  await refresh(r.ok ? r.value : undefined);
}

async function removeSelected() {
  const v = st.vaults[sel];
  if (!v) return;
  if (!window.confirm(t("vaults.confirm_remove", v.name, v.path))) return;
  await G.removeVault(v.path);
  message = t("vaults.removed", v.path);
  await refresh("");
}

async function saveSettings() {
  const r = await G.saveSettings(st.selected, draft);
  if (!r.ok) { message = errText(r); render(); return; }
  await refresh(st.selected);
  draft = JSON.parse(JSON.stringify(st.settings));
  message = t("web.saved");
  render();
}

async function addTheme() {
  const spec = $("s-plug").value;
  message = t("settings.installing");
  render();
  const r = await G.installTheme(spec);
  if (!r.ok) { message = t(r.error, r.detail); render(); return; }
  st = await G.state(st.selected);
  draft.theme = { kind: "plugin", repo: r.repo, colorscheme: r.colorschemes[0] };
  message = t("theme.installed", r.repo);
  render();
}

function saveCustom() {
  const name = ($("s-cname").value || "").trim();
  if (!name) return;
  const c = { base: draft.appearance };
  for (const k of ["bg", "fg", "link", "heading", "selection", "cursorline"]) c[k] = $("s-c-" + k).value;
  draft.customThemes[name] = c;
  draft.theme = { kind: "custom", name };
  saveSettings();
}

function start() {
  const v = selected();
  if (!v || !v.exists) { go("vaults"); return; }
  hide();
  onStart?.(v.path, st.settings);
}

export function hide() {
  $("launcher").hidden = true;
  document.body.classList.remove("launching");
}

function onKey(e) {
  if ($("launcher").hidden) return;
  const tag = (e.target && e.target.tagName) || "";
  const typing = tag === "INPUT" || tag === "SELECT" || tag === "TEXTAREA";
  if (e.key === "Escape") { if (view !== "start") { e.preventDefault(); go("start"); } return; }
  if (typing) return;
  if (view === "start") {
    if (e.key === "Enter" && e.target.tagName !== "BUTTON") { e.preventDefault(); start(); }
    else if (e.key === "v") { e.preventDefault(); go("vaults"); }
    else if (e.key === "s" && selected() && selected().exists) { e.preventDefault(); go("settings"); }
    else if (e.key === "q") { e.preventDefault(); window.gui.quit(); }
  } else if (view === "vaults") {
    const n = st.vaults.length;
    if (e.key === "ArrowDown" || e.key === "j") { e.preventDefault(); sel = Math.min(sel + 1, Math.max(0, n - 1)); render(); }
    else if (e.key === "ArrowUp" || e.key === "k") { e.preventDefault(); sel = Math.max(sel - 1, 0); render(); }
    else if (e.key === "Enter" && e.target.tagName !== "BUTTON") { e.preventDefault(); openVault(sel); }
    else if (e.key === "a") { e.preventDefault(); addExisting(); }
    else if (e.key === "n") { e.preventDefault(); createNew(); }
    else if (e.key === "d") { e.preventDefault(); removeSelected(); }
  }
}

// 起動画面を出す。a:startCb(vaultPath, settings) は Enter で呼ばれる。
// GNOSIS_ROOT（Vim の \A から）で vault が決まっているときは、起動画面を出さずにすぐ呼ぶ。
export async function showLauncher(startCb) {
  onStart = startCb;
  st = await G.state("");
  window.__launcher = { state: () => st, view: () => view, go, refresh, start, setDraft: (f) => { f(draft); }, saveSettings, openVault, removeSelected, message: () => message };
  if (st.explicitRoot) {
    hide();
    startCb("", st.settings);
    return;
  }
  document.body.classList.add("launching");
  $("launcher").hidden = false;
  const i = st.vaults.findIndex((v) => v.path === st.selected);
  sel = i >= 0 ? i : 0;
  if (!st.vaults.length) { view = "vaults"; message = t("start.first_run"); }
  document.addEventListener("keydown", onKey, true);
  window.addEventListener("resize", () => { if (view === "start" && !$("launcher").hidden) fitArt(); });
  render();
}

export function translate(key, ...args) { return t(key, ...args); }
