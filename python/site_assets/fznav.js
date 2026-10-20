// Folgezettel 番号ナビゲーター（表示専用）。データは fz-data.js の window.GNOSIS_FZ = [{id, files:[href…], title}]。
// 操作: ボタン／クリック／キー（↑ 親・↓ 最初の子・← → 兄弟・[ ] 番号順の前後・Home End 最初と最後・Alt+← → 履歴）。
(function () {
  var N = window.FzNav, items = window.GNOSIS_FZ || [];
  var nav = N.build(items), trail = N.Trail(), cur = "", open = new Set();
  var $ = function (id) { return document.getElementById(id); };
  function h(tag, attrs, text) { var e = document.createElement(tag); for (var k in attrs || {}) e.setAttribute(k, attrs[k]); if (text != null) e.textContent = text; return e; }
  function label(o) { return o.id + (o.exists ? " " + o.title : "（空き）"); }

  function chip(o, cls) {
    var b = h("button", { type: "button", class: "chip " + (cls || "") + (o.exists ? "" : " gap"), title: o.exists ? "" : "ノートの無い番号（空き）" }, label(o));
    b.addEventListener("click", function () { go(o.id); });
    return b;
  }
  function list(into, arr, cls) { into.textContent = ""; if (!arr.length) { into.appendChild(h("span", { class: "none" }, "なし")); return; } arr.forEach(function (o) { into.appendChild(chip(o, cls)); }); }

  function go(id, noTrail) {
    if (!id) return;
    cur = id;
    if (!noTrail) trail.visit(id);
    var info = nav.info(id);
    // 祖先の枝を開く
    var p = N.parentId(id); while (p) { open.add(p); p = N.parentId(p); }
    location.replace("#id=" + encodeURIComponent(id));
    $("cur").textContent = id + (info.exists ? "  " + (items.find(function (x) { return x.id === id; }) || {}).title : "  （この番号のノートはありません）");
    $("cur").className = info.exists ? "" : "gap";
    var set = function (btn, o) { var e = $(btn); e.disabled = !o; e.onclick = o ? function () { go(o.id); } : null; e.title = o ? label(o) : ""; };
    set("b-up", info.parent); set("b-down", info.first_child); set("b-prev", info.prev_sibling); set("b-next", info.next_sibling);
    set("b-oprev", info.prev_in_order); set("b-onext", info.next_in_order);
    set("b-first", nav.ids.length && nav.ids[0] !== id ? { id: nav.ids[0], exists: true, title: "" } : null);
    set("b-last", nav.ids.length && nav.ids[nav.ids.length - 1] !== id ? { id: nav.ids[nav.ids.length - 1], exists: true, title: "" } : null);
    var crumb = $("crumbs"); crumb.textContent = "";
    info.breadcrumbs.forEach(function (c) { crumb.appendChild(chip(c)); crumb.appendChild(document.createTextNode(" / ")); });
    crumb.appendChild(h("strong", {}, id));
    list($("parent"), info.parent ? [info.parent] : []);
    list($("siblings"), info.siblings.filter(function (s) { return s.id !== id; }));
    list($("children"), info.children);
    var tl = $("trail"); tl.textContent = "";
    trail.list().forEach(function (t, i) { if (i) tl.appendChild(document.createTextNode(" → ")); var b = h("button", { type: "button", class: "chip" + (t === trail.current() ? " now" : "") }, t); b.addEventListener("click", function () { go(t, true); trail.visit(t); }); tl.appendChild(b); });
    var it = items.find(function (x) { return x.id === id; });
    var pv = $("pv");
    if (it && it.files[0]) { pv.src = it.files[0]; $("open").href = it.files[0]; $("open").hidden = false; } else { pv.removeAttribute("src"); $("open").hidden = true; }
    drawTree();
  }

  function row(n, depth) {
    var li = h("li", {});
    var line = h("div", { class: "tr" + (n.id === cur ? " sel" : "") + (n.exists ? "" : " gap") });
    line.style.paddingLeft = depth * 1.1 + "rem";
    var tog = h("button", { type: "button", class: "tog", "aria-label": "枝を開閉" }, n.children.length ? (open.has(n.id) ? "▾" : "▸") : "·");
    tog.addEventListener("click", function () { if (open.has(n.id)) open.delete(n.id); else open.add(n.id); drawTree(); });
    var a = h("button", { type: "button", class: "lab" }, n.id + (n.exists ? " " + n.title : "（空き）"));
    a.addEventListener("click", function () { go(n.id); });
    line.appendChild(tog); line.appendChild(a); li.appendChild(line);
    if (n.children.length && open.has(n.id)) { var ul = h("ul", {}); n.children.forEach(function (c) { ul.appendChild(row(c, depth + 1)); }); li.appendChild(ul); }
    return li;
  }
  function drawTree() { var t = $("tree"); t.textContent = ""; var ul = h("ul", {}); nav.tree().forEach(function (n) { ul.appendChild(row(n, 0)); }); t.appendChild(ul); }

  function init() {
    $("b-allopen").addEventListener("click", function () { nav.tree(); (function walk(ns) { ns.forEach(function (n) { if (n.children.length) { open.add(n.id); walk(n.children); } }); })(nav.tree()); drawTree(); });
    $("b-allclose").addEventListener("click", function () { open.clear(); drawTree(); });
    $("b-back").addEventListener("click", function () { var t = trail.back(); if (t) go(t, true); });
    $("b-fwd").addEventListener("click", function () { var t = trail.forward(); if (t) go(t, true); });
    document.addEventListener("keydown", function (e) {
      if (e.target && /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)) return;
      var info = cur ? nav.info(cur) : null, to = null;
      if (e.altKey && e.key === "ArrowLeft") { var t = trail.back(); if (t) go(t, true); e.preventDefault(); return; }
      if (e.altKey && e.key === "ArrowRight") { var t2 = trail.forward(); if (t2) go(t2, true); e.preventDefault(); return; }
      if (e.ctrlKey || e.metaKey || e.altKey || !info) return;
      if (e.key === "ArrowUp") to = info.parent; else if (e.key === "ArrowDown") to = info.first_child;
      else if (e.key === "ArrowLeft") to = info.prev_sibling; else if (e.key === "ArrowRight") to = info.next_sibling;
      else if (e.key === "[") to = info.prev_in_order; else if (e.key === "]") to = info.next_in_order;
      else if (e.key === "Home") to = { id: nav.ids[0] }; else if (e.key === "End") to = { id: nav.ids[nav.ids.length - 1] };
      if (to) { e.preventDefault(); go(to.id); }
    });
    // ブラウザの「戻る」や手で書き換えたアドレスの #id= にも従う
    window.addEventListener("hashchange", function () {
      var hm = /[#&]id=([^&]*)/.exec(location.hash), want = "";
      if (hm) { try { want = decodeURIComponent(hm[1]); } catch (e) {} }
      if (want && want !== cur) go(want);
    });
    var m = /[#&]id=([^&]*)/.exec(location.hash), start = "";
    if (m) { try { start = decodeURIComponent(m[1]); } catch (e) {} }
    if (!start && nav.ids.length) start = nav.ids[0];
    if (start) go(start); else $("cur").textContent = "番号のついたノートがありません";
  }
  init();
})();
