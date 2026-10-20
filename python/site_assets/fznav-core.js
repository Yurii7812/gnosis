// Folgezettel 番号ナビの核（DOM に触れない純関数）。python/folgezettel.py の natural_key / parent_id と同じ規則。
// 番号は「数字」と「英字」が交互に並ぶ（1, 1a, 1a1, 1a2, 1b, 1c, 2, 10 …）。
(function (root) {
  function parts(id) { return id.match(/\d+|[a-z]+/g) || []; }
  function parentId(id) { return parts(id).slice(0, -1).join(""); }
  // 自然順: 数字は数として、英字は「長さ → 辞書順」（a < b < … < z < aa < ab）で比べる。短い方が先（1 < 1a < 1a1）
  function compare(a, b) {
    var pa = parts(a), pb = parts(b);
    for (var i = 0; i < Math.min(pa.length, pb.length); i++) {
      var x = pa[i], y = pb[i], dx = /^\d/.test(x), dy = /^\d/.test(y);
      if (dx !== dy) return dx ? -1 : 1;
      var c = dx ? Number(x) - Number(y) : (x.length - y.length || (x < y ? -1 : x > y ? 1 : 0));
      if (c) return c < 0 ? -1 : 1;
    }
    return pa.length - pb.length;
  }

  // items: [{id, files:[…], title}]。返り値の info(id) は、1 つの番号の見取り図。
  // 親子（1 → 1a → 1a1）と兄弟（1a → 1b）は別。履歴の経路とも混同しない（履歴は Trail が別に持つ）。
  function build(items) {
    var by = new Map(), ids = [];
    items.forEach(function (it) { if (!by.has(it.id)) { by.set(it.id, it); ids.push(it.id); } });
    ids.sort(compare);
    function one(id) { var it = by.get(id); return { id: id, files: it ? it.files : [], title: it ? it.title : "", exists: !!it }; }
    function info(id) {
      var pid = parentId(id);
      var sibs = ids.filter(function (x) { return parentId(x) === pid; });
      var kids = ids.filter(function (x) { return parentId(x) === id; });
      var pos = sibs.indexOf(id), at = ids.indexOf(id);
      var crumbs = [], cur = pid;
      while (cur) { crumbs.push(cur); cur = parentId(cur); }
      return {
        id: id, exists: by.has(id),
        parent: pid ? one(pid) : null,
        siblings: sibs.map(one),
        prev_sibling: pos > 0 ? one(sibs[pos - 1]) : null,
        next_sibling: pos >= 0 && pos < sibs.length - 1 ? one(sibs[pos + 1]) : null,
        children: kids.map(one),
        first_child: kids.length ? one(kids[0]) : null,
        breadcrumbs: crumbs.reverse().map(one),
        prev_in_order: at > 0 ? one(ids[at - 1]) : null,
        next_in_order: at >= 0 && at < ids.length - 1 ? one(ids[at + 1]) : null
      };
    }
    // 木（親が無い番号は最上位に置く。抜けた親の番号は「空き」として途中に出す）
    function tree() {
      var all = new Set(ids);
      ids.forEach(function (id) { var p = parentId(id); while (p && !all.has(p)) { all.add(p); p = parentId(p); } });
      var order = Array.from(all).sort(compare);
      function node(id) {
        return { id: id, exists: by.has(id), files: by.has(id) ? by.get(id).files : [], title: by.has(id) ? by.get(id).title : "",
                 children: order.filter(function (x) { return parentId(x) === id; }).map(node) };
      }
      return order.filter(function (id) { return !parentId(id); }).map(node);
    }
    return { ids: ids, info: info, tree: tree };
  }

  // 閲覧の履歴（思考のトレイル）。番号の親子とは別物で、実際の関係を書き換えない。
  function Trail() {
    var items = [], pos = -1;
    return {
      visit: function (id) { if (items[pos] === id) return; items = items.slice(0, pos + 1); items.push(id); pos = items.length - 1; },
      back: function () { if (pos > 0) pos--; return items[pos]; },
      forward: function () { if (pos < items.length - 1) pos++; return items[pos]; },
      list: function () { return items.slice(); },
      current: function () { return items[pos]; }
    };
  }

  var api = { parts: parts, parentId: parentId, compare: compare, build: build, Trail: Trail };
  if (typeof module !== "undefined" && module.exports) module.exports = api; else root.FzNav = api;
})(typeof window !== "undefined" ? window : globalThis);
