#!/usr/bin/env python3
"""思考法のノート（KM05〜KM16）: Cornell・Feynman・KJ 法・SCAMPER・Six Hats・SWOT・5W1H・MECE・TRIZ・IBIS・ADR・概念辞書。

どれも**ふつうの Markdown ノート**（front matter に `thinking: <種類>`）。雛形から作り、`check` で構造を確かめる。
検査は補助で、中身の正しさは断定しない（特に MECE は「重複・漏れの疑い」を示すだけ）。別の DB は持たず、
通常の Markdown ビューア・Vim でそのまま読み書きできる。節は `## 見出し` で、見出しの名前が構造。

CLI（JSON）:
  thinking.py kinds                          種類の一覧
  thinking.py new KIND FILE 題 [引数…]        雛形からノートを作る（既存は上書きしない）。引数は種類ごと（SCAMPER の対象など）
  thinking.py check FILE                      構造の検査（不足している節・空の節・種類ごとの注意）
  thinking.py summary FILE                    要点（節ごとの項目数など）を JSON で
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

H2 = re.compile(r"^##\s+(.+?)\s*$")


def _sections(text: str) -> dict[str, list[str]]:
    """本文の `## 見出し` ごとの行（コードブロックの中の見出しは見ない）。"""
    out: dict[str, list[str]] = {}
    cur = None
    fence = False
    for ln in text.split("\n"):
        if ln.strip().startswith(("```", "~~~")):
            fence = not fence
        m = None if fence else H2.match(ln)
        if m:
            cur = m.group(1)
            out[cur] = []
        elif cur is not None:
            out[cur].append(ln)
    return out


def _items(lines: list[str]) -> list[str]:
    """節の中の項目（箇条書き・番号つき・チェックボックスの本文）。空の項目は数えない。"""
    items = []
    for ln in lines:
        m = re.match(r"^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s*)?(.*)$", ln)
        if m and m.group(1).strip():
            items.append(m.group(1).strip())
    return items


def _body_text(lines: list[str]) -> str:
    return " ".join(x.strip() for x in lines if x.strip() and not x.strip().startswith(("<!--", "-->")))


# 種類ごと: 節（名前, 雛形の本文, 項目か文章か）と、追加の検査
SPECS: dict[str, dict] = {
    "cornell": {
        "label": "Cornell Notes", "sections": [
            ("ノート", "- ", "text"), ("キュー（質問・キーワード）", "- ", "items"), ("要約", "", "text")],
        "doc": "本文（ノート）・質問欄（キュー）・要約欄。要約は最後に自分の言葉で書く。"},
    "feynman": {
        "label": "Feynman", "sections": [
            ("題材", "", "text"), ("自分の言葉での説明", "", "text"), ("つまずいた所・分からない所", "- ", "items"),
            ("元の資料に戻って確かめたこと", "- ", "items"), ("言い直した説明", "", "text")],
        "doc": "説明を書き、つまずいた所（理解の抜け）を挙げ、資料に戻って言い直す。"},
    "kj": {
        "label": "KJ法", "sections": [
            ("カード", "- ", "items"), ("グループ（仮）", "### グループ名\n- \n", "text"), ("関係（仮置き）", "- ", "items"), ("名前を付けた結論", "", "text")],
        "doc": "カードを書き出し、近いものを仮にグルーピングして名前を付け、関係を仮置きする。グループは一時的なもので、ノートの分類にはしない。"},
    "scamper": {
        "label": "SCAMPER", "sections": [
            ("Substitute（置き換える）", "- ", "items"), ("Combine（組み合わせる）", "- ", "items"), ("Adapt（応用する）", "- ", "items"),
            ("Modify（修正・拡大・縮小）", "- ", "items"), ("Put to other uses（別の用途）", "- ", "items"),
            ("Eliminate（取り除く）", "- ", "items"), ("Reverse / Rearrange（逆・並べ替え）", "- ", "items")],
        "doc": "7 つの発想軸それぞれにアイデアを出す。"},
    "hats": {
        "label": "Six Thinking Hats", "sections": [
            ("白（事実・データ）", "- ", "items"), ("赤（感情・直感）", "- ", "items"), ("黒（慎重・リスク）", "- ", "items"),
            ("黄（利点・楽観）", "- ", "items"), ("緑（創造・代案）", "- ", "items"), ("青（整理・結論）", "", "text")],
        "doc": "6 つの観点を切り替えて考え、最後に青（整理）で結論を書く。"},
    "swot": {
        "label": "SWOT", "sections": [
            ("強み（内部・良い）", "- ", "items"), ("弱み（内部・悪い）", "- ", "items"), ("機会（外部・良い）", "- ", "items"),
            ("脅威（外部・悪い）", "- ", "items"), ("打ち手（強み×機会 / 弱み×脅威 など）", "- ", "items")],
        "doc": "内部要因（強み・弱み）と外部要因（機会・脅威）を分けて挙げる。"},
    "5w1h": {
        "label": "5W1H", "sections": [
            ("Why（なぜ）", "", "text"), ("What（何を）", "", "text"), ("Who（誰が）", "", "text"),
            ("When（いつ）", "", "text"), ("Where（どこで）", "", "text"), ("How（どうやって）", "", "text")],
        "doc": "問いを 6 つに分解して埋める。空欄は『まだ分からない』印。"},
    "mece": {
        "label": "MECE", "sections": [
            ("全体（切り出す対象）", "", "text"), ("切り口", "", "text"), ("区分", "- ", "items"),
            ("重複の疑い", "- ", "items"), ("漏れの疑い", "- ", "items")],
        "doc": "全体をある切り口で区分し、重複と漏れを点検する。`check` は同じ語が複数の区分に出ているかを示すだけで、正しさは断定しない。"},
    "triz": {
        "label": "TRIZ", "sections": [
            ("課題", "", "text"), ("改善したい特性", "", "text"), ("そのせいで悪化する特性（技術的矛盾）", "", "text"),
            ("理想の結果（理想解）", "", "text"), ("発明原理の候補", "- ", "items"), ("試す案", "- ", "items")],
        "doc": "改善したい点と、それで悪化する点（矛盾）を明示し、発明原理を当てはめて案を出す。"},
    "ibis": {
        "label": "IBIS", "sections": [
            ("Issue（問題）", "", "text"), ("Position（提案）", "- ", "items"), ("Argument（根拠）", "- ", "items")],
        "doc": "問題に対する提案と、それを支持／反論する根拠。提案は `P1:` `P2:`…、根拠は `+P1:`（支持）・`-P1:`（反論）で結ぶ。"},
    "adr": {
        "label": "ADR", "sections": [
            ("状態", "提案中", "text"), ("背景", "", "text"), ("選択肢", "- ", "items"), ("決定", "", "text"),
            ("根拠", "", "text"), ("結果・影響", "", "text"), ("変更履歴", "- ", "items")],
        "doc": "意思決定の記録。状態は 提案中／採用／却下／廃止／置き換え のどれか。変更履歴に日付と理由を足していく（書き換えて消さない）。"},
    "concept": {
        "label": "概念辞書", "sections": [
            ("定義", "", "text"), ("例", "- ", "items"), ("反例・混同しやすいもの", "- ", "items"),
            ("関連する概念", "- ", "items"), ("出典", "- ", "items")],
        "doc": "用語の定義・例・反例・関連概念・出典。関連する概念は `[用語](ノート.md)` でリンクする。"},
}

ADR_STATES = ("提案中", "採用", "却下", "廃止", "置き換え")


def kinds() -> list[dict]:
    return [{"kind": k, "label": v["label"], "sections": [s[0] for s in v["sections"]], "doc": v["doc"]} for k, v in SPECS.items()]


def new_text(kind: str, title: str, args: list[str] | None = None, now: dt.datetime | None = None) -> str:
    if kind not in SPECS:
        raise ValueError("種類が分かりません: " + kind + "（" + " / ".join(SPECS) + "）")
    spec = SPECS[kind]
    now = now or dt.datetime.now()
    out = ["---", f"time: {now:%Y-%m-%d %H:%M:%S}", f"title: {title}", f"thinking: {kind}", "---", "", f"# {title}", "",
           f"<!-- {spec['label']}: {spec['doc']} -->", ""]
    for name, body, _ in spec["sections"]:
        out += [f"## {name}", ""]
        if kind == "scamper" and args and name.startswith("Substitute"):
            body = "- "
        out += (body.split("\n") if body else []) + [""]
    if kind == "scamper" and args:
        out.insert(8, f"対象: {args[0]}")
        out.insert(9, "")
    return "\n".join(out)


def _front_kind(text: str) -> str:
    lines = text.split("\n")
    if lines and lines[0].strip() == "---":
        for ln in lines[1:]:
            if ln.strip() == "---":
                break
            m = re.match(r"^thinking:\s*(\S+)\s*$", ln)
            if m:
                return m.group(1)
    return ""


def check(text: str) -> dict:
    """{kind, ok, missing:[節], empty:[節], notes:[注意], counts:{節: 項目数}}。notes は疑いの指摘で、断定ではない。"""
    kind = _front_kind(text)
    if kind not in SPECS:
        return {"kind": kind, "ok": False, "missing": [], "empty": [], "notes": ["thinking: の種類が分かりません"], "counts": {}}
    spec = SPECS[kind]
    sec = _sections(text)
    missing = [n for n, _, _ in spec["sections"] if n not in sec]
    empty, counts = [], {}
    for name, _, mode in spec["sections"]:
        if name not in sec:
            continue
        lines = sec[name]
        counts[name] = len(_items(lines)) if mode == "items" else len(_body_text(lines))
        if counts[name] == 0:
            empty.append(name)
    notes: list[str] = []
    if kind == "adr":
        st = _body_text(sec.get("状態", []))
        if st and not any(st.startswith(x) for x in ADR_STATES):
            notes.append(f"状態は {' / '.join(ADR_STATES)} のどれかで始めてください（いま: {st[:20]}）")
        if st.startswith(("採用", "置き換え")) and not _body_text(sec.get("決定", [])):
            notes.append("採用なのに『決定』が空です")
        if st.startswith(("採用", "却下", "廃止", "置き換え")) and not _items(sec.get("変更履歴", [])):
            notes.append("状態を変えたら『変更履歴』に日付と理由を残してください")
    if kind == "ibis":
        pos = _items(sec.get("Position（提案）", []))
        ids = {m.group(1) for p in pos if (m := re.match(r"^(P\d+)\s*[:：]", p))}
        if pos and not ids:
            notes.append("提案には `P1:` のような名前を付けると、根拠を結べます")
        for a in _items(sec.get("Argument（根拠）", [])):
            m = re.match(r"^([+\-−])\s*(P\d+)\s*[:：]", a)
            if not m:
                notes.append(f"根拠の書き方は `+P1: …`（支持）か `-P1: …`（反論）です: {a[:30]}")
            elif m.group(2) not in ids:
                notes.append(f"根拠が存在しない提案 {m.group(2)} を指しています")
        for p in sorted(ids):
            has = any(re.match(rf"^[+\-−]\s*{p}\s*[:：]", a) for a in _items(sec.get("Argument（根拠）", [])))
            if not has:
                notes.append(f"提案 {p} に根拠がまだありません")
    if kind == "mece":
        parts = _items(sec.get("区分", []))
        seen: dict[str, list[int]] = {}
        for i, part in enumerate(parts):
            # 語の区切りはひらがな（助詞）と記号。漢字・カタカナ・英数の連なりを 1 語とみなす簡易な分かち書き
            for w in set(re.findall(r"[A-Za-z0-9ァ-ヶ一-龠ー]{2,}", part)):
                seen.setdefault(w, []).append(i)
        dup = sorted(w for w, idx in seen.items() if len(idx) > 1)
        if dup:
            notes.append("複数の区分に同じ語が出ています（重複の疑い。本当に重なるかは自分で判断）: " + "・".join(dup[:8]))
        if len(parts) < 2:
            notes.append("区分が 2 つ未満です")
    if kind == "5w1h":
        if len(empty) == len(spec["sections"]):
            notes.append("まだ何も書かれていません")
    if kind == "kj":
        if counts.get("カード", 0) and counts["カード"] < 5:
            notes.append("カードが少なめです（KJ 法は通常もっと多く出します）")
    if kind == "hats":
        blue = _body_text(sec.get("青（整理・結論）", []))
        if not blue and any(counts.get(n, 0) for n in counts if not n.startswith("青")):
            notes.append("他の帽子は書いてあるのに、青（整理・結論）がまだです")
    if kind == "swot":
        if counts.get("打ち手（強み×機会 / 弱み×脅威 など）", 0) == 0 and all(counts.get(n, 0) for n in list(counts)[:4]):
            notes.append("4 象限が埋まっています。次は『打ち手』を書きましょう")
    return {"kind": kind, "ok": not missing, "missing": missing, "empty": empty, "notes": notes, "counts": counts}


def summary(text: str) -> dict:
    c = check(text)
    kind = c["kind"]
    out = {"kind": kind, "label": SPECS[kind]["label"] if kind in SPECS else "", "counts": c["counts"], "empty": c["empty"]}
    if kind == "ibis":
        sec = _sections(text)
        pos = {m.group(1): p for p in _items(sec.get("Position（提案）", [])) if (m := re.match(r"^(P\d+)\s*[:：]", p))}
        arg = _items(sec.get("Argument（根拠）", []))
        out["positions"] = {k: {"pro": sum(1 for a in arg if re.match(rf"^\+\s*{k}\s*[:：]", a)),
                                "con": sum(1 for a in arg if re.match(rf"^[\-−]\s*{k}\s*[:：]", a))} for k in pos}
    if kind == "adr":
        out["state"] = _body_text(_sections(text).get("状態", []))
    return out


def _atomic_new(path: Path, text: str) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)   # 既存なら失敗（上書きしない）
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)


def main(argv: list[str]) -> int:
    try:
        if argv[:1] == ["kinds"]:
            print(json.dumps(kinds(), ensure_ascii=False))
        elif len(argv) >= 4 and argv[0] == "new":
            _atomic_new(Path(argv[2]), new_text(argv[1], argv[3], argv[4:]))
            print(json.dumps({"ok": True, "file": argv[2]}, ensure_ascii=False))
        elif len(argv) == 2 and argv[0] == "check":
            r = check(Path(argv[1]).read_text(encoding="utf-8"))
            print(json.dumps(r, ensure_ascii=False))
        elif len(argv) == 2 and argv[0] == "summary":
            print(json.dumps(summary(Path(argv[1]).read_text(encoding="utf-8")), ensure_ascii=False))
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (OSError, ValueError) as e:
        print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
