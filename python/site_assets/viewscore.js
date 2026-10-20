// カード・テーブル・タイムラインの共通の核（DOM に触れない純関数）。データは window.GNOSIS_NOTES。
(function (root) {
  // フィルタ: 空白区切りの語がすべて（題・本文の抜粋・番号）に含まれる（大文字小文字を区別しない）。-語 は含まない。
  function matches(n, query) {
    var terms = (query || "").toLowerCase().split(/\s+/).filter(Boolean);
    var hay = ((n.title || "") + " " + (n.fz || "") + " " + (n.excerpt || "")).toLowerCase();
    return terms.every(function (t) { return t[0] === "-" && t.length > 1 ? hay.indexOf(t.slice(1)) < 0 : hay.indexOf(t) >= 0; });
  }
  function cmpStr(a, b) { return String(a || "").localeCompare(String(b || ""), "ja"); }
  var SORTS = {
    title: function (a, b) { return cmpStr(a.title, b.title); },
    created: function (a, b) { return cmpStr(a.time, b.time); },
    updated: function (a, b) { return (a.mtime || 0) - (b.mtime || 0); },
    links_out: function (a, b) { return (a.out || 0) - (b.out || 0); },
    links_in: function (a, b) { return (a["in"] || 0) - (b["in"] || 0); },
    size: function (a, b) { return (a.size || 0) - (b.size || 0); },
    fz: function (a, b) { return root.FzNav ? root.FzNav.compare(a.fz, b.fz) : cmpStr(a.fz, b.fz); }
  };
  // 並べ替え（安定。同じ値は題で）。dir: 1 昇順 / -1 降順。番号・作成日が無いノートは、昇順でも降順でも最後に置く
  var NEEDS = { fz: "fz", created: "time" };
  function sort(notes, key, dir) {
    var f = SORTS[key] || SORTS.title, need = NEEDS[key];
    var has = function (n) { return !need || !!n[need]; };
    var cmp = function (x, y) {
      var c = f(x[0], y[0]) * (dir || 1);
      return c || cmpStr(x[0].title, y[0].title) || x[1] - y[1];
    };
    var indexed = notes.map(function (n, i) { return [n, i]; });
    var withV = indexed.filter(function (p) { return has(p[0]); }).sort(cmp);
    var without = indexed.filter(function (p) { return !has(p[0]); }).sort(function (x, y) { return cmpStr(x[0].title, y[0].title) || x[1] - y[1]; });
    return withV.concat(without).map(function (p) { return p[0]; });
  }
  // タイムライン: 作成日（time: の日付）ごとにまとめ、新しい日が先。日付の無いノートは最後の「日付なし」
  function timeline(notes) {
    var by = new Map();
    notes.forEach(function (n) {
      var d = (n.time || "").slice(0, 10) || "";
      if (!by.has(d)) by.set(d, []);
      by.get(d).push(n);
    });
    return Array.from(by.keys()).sort(function (a, b) { return a === "" ? 1 : b === "" ? -1 : a < b ? 1 : a > b ? -1 : 0; })
      .map(function (d) { return { date: d, notes: by.get(d).sort(function (a, b) { return cmpStr(b.time, a.time); }) }; });
  }
  var api = { matches: matches, sort: sort, timeline: timeline, SORTS: SORTS };
  if (typeof module !== "undefined" && module.exports) module.exports = api; else root.ViewsCore = api;
})(typeof window !== "undefined" ? window : globalThis);
