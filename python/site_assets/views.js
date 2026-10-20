// カード / テーブル / タイムライン（表示専用）。data: window.GNOSIS_NOTES、核: ViewsCore。body[data-view] で切り替える。
(function () {
  var V = window.ViewsCore, all = window.GNOSIS_NOTES || [], view = document.body.getAttribute("data-view");
  var $ = function (id) { return document.getElementById(id); };
  function h(tag, attrs, text) { var e = document.createElement(tag); for (var k in attrs || {}) e.setAttribute(k, attrs[k]); if (text != null) e.textContent = text; return e; }
  var st = { q: "", key: view === "table" ? "title" : "updated", dir: view === "table" ? 1 : -1 };
  var pins = new Set();
  try { JSON.parse(localStorage.getItem("gnosis-pins") || "[]").forEach(function (x) { pins.add(x); }); } catch (e) {}
  function savePins() { try { localStorage.setItem("gnosis-pins", JSON.stringify(Array.from(pins))); } catch (e) {} }
  function day(ms) { if (!ms) return ""; var d = new Date(ms * 1000); return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2); }
  function visible() { return all.filter(function (n) { return V.matches(n, st.q); }); }

  function drawCards() {
    var list = V.sort(visible(), st.key, st.dir);
    list = list.filter(function (n) { return pins.has(n.id); }).concat(list.filter(function (n) { return !pins.has(n.id); }));   // ピン留めが先
    var box = $("cards"); box.textContent = "";
    list.forEach(function (n) {
      var c = h("article", { class: "card" + (pins.has(n.id) ? " pinned" : "") });
      if (n.image) { var im = h("img", { src: n.image, alt: "", loading: "lazy" }); c.appendChild(im); }
      var t = h("h3", {}); var a = h("a", { href: n.href }, n.title); t.appendChild(a); c.appendChild(t);
      if (n.fz) c.appendChild(h("span", { class: "chip" }, n.fz));
      if (n.excerpt) c.appendChild(h("p", {}, n.excerpt));
      var meta = h("div", { class: "meta" }, day(n.mtime) + " ・ → " + (n.out || 0) + " ・ ← " + (n["in"] || 0) + (n.tasks_open ? " ・ ☐ " + n.tasks_open : ""));
      var pin = h("button", { type: "button", class: "pin", title: "ピン留め（このブラウザだけに覚える）", "aria-pressed": String(pins.has(n.id)) }, pins.has(n.id) ? "★" : "☆");
      pin.addEventListener("click", function () { if (pins.has(n.id)) pins.delete(n.id); else pins.add(n.id); savePins(); draw(); });
      c.appendChild(meta); c.appendChild(pin); box.appendChild(c);
    });
    $("count").textContent = list.length + " / " + all.length + " 件";
  }

  var COLS = [["fz", "番号", "fz"], ["title", "題", "title"], ["created", "作成", "created"], ["updated", "更新", "updated"], ["links_out", "→リンク", "links_out"], ["links_in", "←被リンク", "links_in"], ["size", "サイズ", "size"]];
  function drawTable() {
    var list = V.sort(visible(), st.key, st.dir);
    var tb = $("tbl"); tb.textContent = "";
    var head = h("tr", {});
    COLS.forEach(function (c) {
      var th = h("th", { scope: "col", "aria-sort": st.key === c[2] ? (st.dir > 0 ? "ascending" : "descending") : "none" });
      var b = h("button", { type: "button", class: "sortb" }, c[1] + (st.key === c[2] ? (st.dir > 0 ? " ▲" : " ▼") : ""));
      b.addEventListener("click", function () { if (st.key === c[2]) st.dir = -st.dir; else { st.key = c[2]; st.dir = 1; } draw(); });
      th.appendChild(b); head.appendChild(th);
    });
    head.appendChild(h("th", {}, "タスク"));
    var thead = h("thead", {}); thead.appendChild(head); tb.appendChild(thead);
    var body = h("tbody", {});
    list.forEach(function (n) {
      var tr = h("tr", {});
      tr.appendChild(h("td", {}, n.fz || ""));
      var td = h("td", {}); td.appendChild(h("a", { href: n.href }, n.title)); tr.appendChild(td);
      tr.appendChild(h("td", {}, (n.time || "").slice(0, 10)));
      tr.appendChild(h("td", {}, day(n.mtime)));
      tr.appendChild(h("td", { class: "num" }, String(n.out || 0)));
      tr.appendChild(h("td", { class: "num" }, String(n["in"] || 0)));
      tr.appendChild(h("td", { class: "num" }, String(n.size || 0)));
      tr.appendChild(h("td", {}, n.tasks_open ? "☐ " + n.tasks_open : ""));
      body.appendChild(tr);
    });
    tb.appendChild(body);
    $("count").textContent = list.length + " / " + all.length + " 件";
  }

  function drawTimeline() {
    var groups = V.timeline(visible()), box = $("tl"); box.textContent = "";
    var n = 0;
    groups.forEach(function (g) {
      var sec = h("section", {}); sec.appendChild(h("h2", {}, g.date || "日付なし"));
      var ul = h("ul", {});
      g.notes.forEach(function (x) { n++; var li = h("li", {}); li.appendChild(h("span", { class: "tm" }, (x.time || "").slice(11, 16) + " ")); li.appendChild(h("a", { href: x.href }, (x.fz ? x.fz + " " : "") + x.title)); ul.appendChild(li); });
      sec.appendChild(ul); box.appendChild(sec);
    });
    $("count").textContent = n + " / " + all.length + " 件";
  }

  function draw() { (view === "cards" ? drawCards : view === "table" ? drawTable : drawTimeline)(); }
  var q = $("q");
  q.addEventListener("input", function () { st.q = q.value; draw(); });
  var m = /^#q=(.*)$/.exec(location.hash); if (m) { try { q.value = st.q = decodeURIComponent(m[1]); } catch (e) {} }
  var sel = $("sort");
  if (sel) { sel.value = st.key; sel.addEventListener("change", function () { st.key = sel.value; draw(); }); }
  var dirb = $("dir");
  if (dirb) dirb.addEventListener("click", function () { st.dir = -st.dir; dirb.textContent = st.dir > 0 ? "昇順 ▲" : "降順 ▼"; draw(); });
  draw();
})();
