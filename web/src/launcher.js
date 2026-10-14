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
let editing = null; // 配色の編集中: {target: "vim"|"app", name, colors, orig, key}。保存するまで設定は書き換えない

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
  if (editing) return renderEditor();
  const s = draft;
  const themeOptions = [h("option", { value: "builtin", selected: s.theme.kind === "builtin" }, t("settings.theme_builtin"))];
  for (const name of Object.keys(s.customThemes).sort()) {
    themeOptions.push(h("option", { value: "custom:" + name, selected: s.theme.kind === "custom" && s.theme.name === name }, t("settings.theme_custom", name)));
  }
  for (const th of st.themes) for (const cs of th.colorschemes) {
    const val = "plugin:" + th.repo + ":" + cs;
    themeOptions.push(h("option", { value: val, selected: s.theme.kind === "plugin" && s.theme.repo === th.repo && s.theme.colorscheme === cs }, cs + "  (" + th.repo + ")"));
  }
  const appOptions = [h("option", { value: "builtin", selected: s.appTheme.kind !== "custom" }, t("settings.theme_app_builtin"))];
  for (const name of Object.keys(s.appCustomThemes).sort()) {
    appOptions.push(h("option", { value: "custom:" + name, selected: s.appTheme.kind === "custom" && s.appTheme.name === name }, t("settings.theme_custom", name)));
  }
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
      h("fieldset", { class: "l-colors", id: "s-vim-colors" },
        h("legend", { text: t("settings.item.custom") }),
        h("div", { class: "l-row" },
          h("button", { type: "button", id: "s-vim-custom", onclick: () => startEdit("vim") }, t("web.edit_colors")),
          h("button", { type: "button", id: "s-vim-reset", onclick: () => { s.theme = { kind: "builtin" }; render(); } }, t("settings.item.theme_reset")))),
      h("fieldset", { class: "l-colors", id: "s-app-colors" },
        h("legend", { text: t("settings.item.app_theme") }),
        h("div", { class: "l-vpath", text: t("web.app_theme_note") }),
        field(t("settings.item.app_theme"), h("select", { id: "s-app-theme", onchange: (e) => { setAppTheme(e.target.value); render(); } }, appOptions)),
        h("div", { class: "l-row" },
          h("button", { type: "button", id: "s-app-custom", onclick: () => startEdit("app") }, t("web.edit_colors")),
          h("button", { type: "button", id: "s-app-reset", onclick: () => { s.appTheme = { kind: "builtin" }; render(); } }, t("settings.item.app_theme_reset")))),
      h("div", { class: "l-buttons" },
        h("button", { type: "submit", class: "l-primary", id: "s-save" }, t("web.save")))),
    h("div", { class: "l-hint", text: t("web.zoom_note") }));
}

// ---------------------------------------------------------------- 配色の編集（カラーパレット・ライブプレビュー）
// 色を変えると、保存する前でもすぐプレビューに反映される（<input type=color> を動かしている間も）。
// 保存（「保存して使う」）するまで設定は書き換えない。取り消せば元の配色のまま。ノートは一切変更しない。
const COLOR_KEYS = ["bg", "fg", "link", "heading", "selection", "cursorline"];
const HUES = [[-1, 0], [0, 0.62], [28, 0.72], [50, 0.78], [130, 0.45], [175, 0.5], [212, 0.62], [275, 0.45]];
const LIGHTS = [0.12, 0.22, 0.34, 0.46, 0.58, 0.70, 0.82, 0.92, 0.98];

export function normHex(text) {
  let v = String(text || "").trim().replace(/^#/, "");
  if (/^[0-9a-f]{3}$/i.test(v)) v = v.replace(/(.)/g, "$1$1");
  return /^[0-9a-f]{6}$/i.test(v) ? "#" + v.toLowerCase() : "";
}
const rgbOf = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
const toHex = (r, g, b) => "#" + [r, g, b].map((x) => Math.max(0, Math.min(255, Math.round(x))).toString(16).padStart(2, "0")).join("");
function hslToHex(h, s, l) {
  const f = (n) => {
    const k = (n + h / 30) % 12;
    return l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, 9 - k, 1));
  };
  return toHex(f(0) * 255, f(8) * 255, f(4) * 255);
}
function hexToHsl(hex) {
  const [r, g, b] = rgbOf(hex).map((x) => x / 255);
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2;
  if (mx === mn) return [0, 0, l];
  const d = mx - mn, s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
  const h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h * 60, s, l];
}
export function luminanceOf(hex) {
  const c = rgbOf(hex).map((x) => { const v = x / 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
export function contrastOf(a, b) {
  const x = luminanceOf(a), y = luminanceOf(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}
function mixHex(a, b, t) {
  const x = rgbOf(a), y = rgbOf(b);
  return toHex(x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t);
}
const paletteColor = (r, c) => hslToHex(HUES[r][0] < 0 ? 0 : HUES[r][0], HUES[r][1], LIGHTS[c]);

async function startEdit(target) {
  const app = target === "app";
  const th = app ? draft.appTheme : draft.theme;
  const store = (app ? draft.appCustomThemes : draft.customThemes) || {};
  const name = th && th.kind === "custom" ? th.name : "";
  const cur = store[name] || {};
  // 今のテーマの色から始める（アプリ用は白、Vim 用は選んでいるテーマの色）
  const pal = (app ? await G.appPalette(draft) : await G.palette(draft)) || {};
  const colors = {};
  for (const k of COLOR_KEYS) colors[k] = normHex(cur[k]) || normHex(pal[k]) || "#808080";
  editing = { target, name: name || (app ? "my-app-theme" : "my-theme"), colors, orig: { ...colors }, key: "bg" };
  message = "";
  render();
}

function cancelEdit() {
  editing = null;
  message = "";
  render();
}

async function saveEdit() {
  const name = (($("e-name") && $("e-name").value) || "").trim();
  if (!name) { message = t("theme_edit.need_name"); render(); return; }
  const theme = { ...editing.colors, base: luminanceOf(editing.colors.bg) < 0.4 ? "dark" : "light" };
  if (editing.target === "app") {
    draft.appCustomThemes[name] = theme;
    draft.appTheme = { kind: "custom", name };
  } else {
    draft.customThemes[name] = theme;
    draft.theme = { kind: "custom", name };
  }
  editing = null;
  await saveSettings();
}

// 色を 1 つ変える。画面は作り直さず、その場で更新する（カラーピッカーを閉じさせないため）。
function setColor(key, hex) {
  const c = normHex(hex);
  if (!c || !editing) return;
  editing.colors[key] = c;
  syncEditor(key);
}

function syncEditor(except) {
  if (!editing) return;
  for (const k of COLOR_KEYS) {
    const col = $("e-c-" + k), hx = $("e-h-" + k);
    if (col && col.value !== editing.colors[k]) col.value = editing.colors[k];
    if (hx && k !== except && hx.value !== editing.colors[k]) hx.value = editing.colors[k];
    const sw = $("e-sw-" + k);
    if (sw) sw.style.background = editing.colors[k];
  }
  updatePreview();
}

function updatePreview() {
  const pv = $("e-preview");
  if (!pv || !editing) return;
  const c = editing.colors;
  const dark = luminanceOf(c.bg) < 0.4;
  const vars = { bg: c.bg, fg: c.fg, link: c.link, heading: c.heading, sel: c.selection, cur: c.cursorline,
    dim: mixHex(c.fg, c.bg, 0.35), strong: mixHex(c.fg, dark ? "#ffffff" : "#000000", 0.6) };
  for (const [k, v] of Object.entries(vars)) pv.style.setProperty("--pv-" + k, v);
  const box = $("e-contrast");
  if (box) {
    box.replaceChildren(...[["fg", t("settings.color.fg")], ["link", t("settings.color.link")], ["heading", t("settings.color.heading")]].map(([k, label]) => {
      const r = contrastOf(c[k], c.bg);
      return h("div", { class: r >= 4.5 ? "e-ok" : "e-warn", text: `${label}  ${r.toFixed(1)} : 1  ${r >= 4.5 ? "✓" : t("theme_edit.low_contrast")}` });
    }));
  }
}

function nudge(dim, delta) {
  const k = editing.key;
  let [hh, ss, ll] = hexToHsl(editing.colors[k]);
  if (dim === "l") ll = Math.max(0, Math.min(1, ll + delta));
  else if (dim === "h") hh = (hh + delta * 360 + 360) % 360;
  else ss = Math.max(0, Math.min(1, ss + delta));
  setColor(k, hslToHex(hh, ss, ll));
}

function renderEditor() {
  const e = editing;
  const app = e.target === "app";
  const rows = COLOR_KEYS.map((k) => {
    const label = t("settings.color." + k);
    const row = h("div", { class: "e-row" + (e.key === k ? " sel" : ""), id: "e-row-" + k },
      h("label", { class: "e-label", for: "e-c-" + k, text: label }),
      h("input", { type: "color", id: "e-c-" + k, value: e.colors[k], "aria-label": label,
        onfocus: () => selectRow(k), oninput: (ev) => setColor(k, ev.target.value) }),
      h("input", { type: "text", id: "e-h-" + k, class: "e-hex", value: e.colors[k], maxlength: 7, spellcheck: false, "aria-label": label + " HEX",
        onfocus: () => selectRow(k),
        oninput: (ev) => { const n = normHex(ev.target.value); if (n) setColor(k, n); },
        onblur: (ev) => { ev.target.value = e.colors[k]; } }),
      h("span", { class: "e-swatch", id: "e-sw-" + k, style: "background:" + e.colors[k] }));
    return row;
  });
  const grid = h("div", { class: "e-grid", id: "e-grid", role: "grid", "aria-label": t("theme_edit.palette") },
    HUES.map((_, r) => h("div", { class: "e-grid-row", role: "row" }, LIGHTS.map((_l, c) => {
      const hex = paletteColor(r, c);
      return h("button", { type: "button", class: "e-sw", id: `e-pal-${r}-${c}`, title: hex.toUpperCase(), style: "background:" + hex, tabindex: r === 0 && c === 4 ? 0 : -1,
        "aria-label": hex.toUpperCase(), onclick: () => setColor(e.key, hex), onfocus: () => setColor(e.key, hex) });
    }))));
  grid.addEventListener("keydown", (ev) => {
    const m = /^e-pal-(\d+)-(\d+)$/.exec((ev.target && ev.target.id) || "");
    if (!m) return;
    let r = Number(m[1]), c = Number(m[2]);
    if (ev.key === "ArrowRight") c++; else if (ev.key === "ArrowLeft") c--; else if (ev.key === "ArrowDown") r++; else if (ev.key === "ArrowUp") r--; else return;
    ev.preventDefault();
    ev.stopPropagation();
    r = Math.max(0, Math.min(HUES.length - 1, r)); c = Math.max(0, Math.min(LIGHTS.length - 1, c));
    $(`e-pal-${r}-${c}`)?.focus();
  });
  const sample = h("div", { class: "e-preview", id: "e-preview", "aria-label": t("theme_edit.preview") },
    h("div", { class: "pv-h1 pv-h" }, h("span", { class: "pv-dim", text: "# " }), "植物について"),
    h("p", {}, "植物", h("span", { class: "pv-sel", text: "についての情報" }), "をまとめる。"),
    h("p", { text: "関連する情報：" }),
    h("div", { class: "pv-cur" }, h("a", { text: "ローズマリー" }), h("span", { class: "pv-dim", text: "  ← " + t("theme_edit.cursor_line") })),
    h("div", {}, h("a", { text: "レモンバーム" })),
    h("div", { class: "pv-h" }, h("span", { class: "pv-dim", text: "### " }), "Context"),
    h("div", {}, h("a", { text: "ハーブ" })),
    h("div", { class: "pv-h" }, h("span", { class: "pv-dim", text: "### " }), "ChildBranch"),
    h("div", {}, h("a", { text: "植物の栽培" })));
  const panel = h("div", { class: "l-panel l-editor" },
    h("div", { class: "l-head" }, h("button", { id: "e-cancel-top", onclick: cancelEdit }, "← " + t("web.cancel")), h("h2", { text: t(app ? "theme_edit.title_app" : "theme_edit.title_vim") })),
    h("div", { class: "l-vpath", text: t("settings.vault") + " " + st.selected }),
    message ? h("div", { class: "l-msg", text: message }) : null,
    h("div", { class: "e-cols" },
      h("div", { class: "e-left" },
        h("label", { class: "l-field" }, h("span", { text: t("theme_edit.name") }), h("input", { type: "text", id: "e-name", value: e.name, "data-autofocus": true })),
        h("div", { class: "e-rows", id: "e-rows" }, rows),
        h("div", { class: "e-sub", text: t("theme_edit.palette") }),
        grid,
        h("div", { class: "e-sub", text: t("web.editor_tune") }),
        h("div", { class: "l-row" },
          h("button", { type: "button", id: "e-darker", onclick: () => nudge("l", -0.04) }, t("web.darker")),
          h("button", { type: "button", id: "e-lighter", onclick: () => nudge("l", 0.04) }, t("web.lighter")),
          h("button", { type: "button", id: "e-reset", onclick: () => { setColor(e.key, e.orig[e.key]); } }, t("web.reset_color")))),
      h("div", { class: "e-right" },
        h("div", { class: "e-sub", text: t("theme_edit.preview") }),
        sample,
        h("div", { class: "e-contrast", id: "e-contrast" }))),
    h("div", { class: "l-buttons" },
      h("button", { type: "button", class: "l-primary", id: "e-save", onclick: saveEdit }, t("web.use_custom")),
      h("button", { type: "button", id: "e-cancel", onclick: cancelEdit }, t("web.cancel"))),
    h("div", { class: "l-hint", text: t("web.editor_keys") }));
  queueMicrotask(() => { syncEditor(); });
  return panel;
}

function selectRow(k) {
  if (!editing || editing.key === k) return;
  editing.key = k;
  for (const c of COLOR_KEYS) $("e-row-" + c)?.classList.toggle("sel", c === k);
}

function setAppTheme(val) {
  draft.appTheme = val.startsWith("custom:") ? { kind: "custom", name: val.slice(7) } : { kind: "builtin" };
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
  editing = null;
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

function start() {
  const v = selected();
  if (!v || !v.exists) { go("vaults"); return; }
  hide();
  onStart?.(v.path, st.settings);
}

// 画面の中の操作できる部品（ボタン・入力欄・選択）の順に、フォーカスを a:dir（1 / -1）だけ動かす
function moveFocus(dir) {
  const root = $("launcher");
  const items = [...root.querySelectorAll("button, input, select")].filter((el) => !el.disabled && el.tabIndex >= 0 && el.offsetParent !== null);
  if (!items.length) return false;
  const i = items.indexOf(document.activeElement);
  const next = items[i < 0 ? (dir > 0 ? 0 : items.length - 1) : Math.max(0, Math.min(items.length - 1, i + dir))];
  next.focus();
  return true;
}

export function hide() {
  $("launcher").hidden = true;
  document.body.classList.remove("launching");
}

function onKey(e) {
  if ($("launcher").hidden) return;
  const tag = (e.target && e.target.tagName) || "";
  const typing = tag === "INPUT" || tag === "SELECT" || tag === "TEXTAREA";
  if (e.key === "Escape") {
    if (editing) { e.preventDefault(); cancelEdit(); return; }
    if (view !== "start") { e.preventDefault(); go("start"); }
    return;
  }
  // ↑ ↓ で項目（ボタン・入力欄）を移動する。select と数字の入力欄は、矢印キー自体に意味があるので除く
  if ((e.key === "ArrowDown" || e.key === "ArrowUp") && (view === "settings" || view === "start" || (view === "vaults" && tag === "BUTTON"))) {
    const nativeArrow = tag === "SELECT" || (tag === "INPUT" && e.target.type === "number");
    if (!nativeArrow && !(view === "vaults")) { if (moveFocus(e.key === "ArrowDown" ? 1 : -1)) e.preventDefault(); return; }
  }
  if (view === "start" && (e.key === "ArrowRight" || e.key === "ArrowLeft") && tag === "BUTTON") { if (moveFocus(e.key === "ArrowRight" ? 1 : -1)) e.preventDefault(); return; }
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
