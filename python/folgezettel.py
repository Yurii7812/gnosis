#!/usr/bin/env python3
"""Digital note identifiers: alternating numeric and alphabetic components."""
from __future__ import annotations

import json
from datetime import datetime, timezone
import re
import sys
from pathlib import Path
from urllib.parse import unquote

import note_format_v2 as nf

# 紙の PKM のノートの番号は、先頭に `PA-` のような印を付けて、デジタルの番号と別の空間にする（2026-10-27）。
# 印は設定（vault の .gnosis/settings.json の paperIdPrefix。既定 PA）で変えられる。`PA-1a2` の親は `PA-1a`、`PA-1` に親は無い
PREFIX_RE = re.compile(r"^[A-Z]{1,4}$")
PAPER_PREFIX_DEFAULT = "PA"
# `PA-0` は紙の自動作成の索引（Paper-Zettelkasten-Index など）の番号。デジタルの 0 は無い
ID_RE = re.compile(r"^(?:[A-Z]{1,4}-0|(?:[A-Z]{1,4}-)?[1-9]\d*(?:[a-z]+[1-9]\d*)*[a-z]*)$")
_PREFIXED_RE = re.compile(r"^([A-Z]{1,4}-)(.+)$")
_PART_RE = re.compile(r"[A-Z]+-|\d+|[a-z]+")


def split_prefix(ident: str) -> tuple[str, str]:
    """`PA-1a2` → ('PA-', '1a2')。印の無い番号は ('', 番号)。"""
    m = _PREFIXED_RE.match(ident or '')
    return (m.group(1), m.group(2)) if m else ('', ident or '')


def paper_prefix(root: Path) -> str:
    """紙の番号の印（`PA-` の形。末尾の _ まで）。設定 paperIdPrefix（vault の .gnosis/settings.json。root は vault かその note/）。"""
    value = PAPER_PREFIX_DEFAULT
    for base in (Path(root), Path(root).parent):
        f = base / '.gnosis' / 'settings.json'
        try:
            v = json.loads(f.read_text(encoding='utf-8')).get('paperIdPrefix')
        except (OSError, ValueError, AttributeError):
            continue
        if isinstance(v, str) and PREFIX_RE.fullmatch(v.strip().upper()):
            value = v.strip().upper()
        break
    return value + '-'


def value(text: str) -> str:
    fm, _ = nf._split_front_matter(text.splitlines())
    for line in fm:
        m = re.match(r'^folgezettel\s*:\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^#]*?))\s*(?:#.*)?$', line)
        if m:
            return next((v.strip() for v in m.groups() if v is not None), '')
    return ''


def set_value(text: str, ident: str) -> str:
    lines = text.split('\n')
    fm, _ = nf._split_front_matter(lines)
    entry = f'folgezettel: "{ident}"'
    if not fm:
        if lines[0].strip() == '---':
            raise ValueError('Unclosed YAML front matter')
        return '---\n' + entry + '\n---\n\n' + text
    for i in range(1, len(fm) - 1):
        if re.match(r'^folgezettel\s*:', lines[i]):
            lines[i] = entry
            return '\n'.join(lines)
    lines.insert(len(fm) - 1, entry)
    return '\n'.join(lines)


def remove_value(text: str) -> str:
    """front matter の folgezettel: の行を消す（グループは ID を持たない）。"""
    lines = text.split('\n')
    fm, _ = nf._split_front_matter(lines)
    for i in range(1, max(len(fm) - 1, 1)):
        if re.match(r'^folgezettel\s*:', lines[i]):
            del lines[i]
            break
    return '\n'.join(lines)


def parent_id(ident: str) -> str:
    prefix, body = split_prefix(ident)
    parts = re.findall(r'\d+|[a-z]+', body)
    parent = ''.join(parts[:-1])
    return prefix + parent if parent else ''


def natural_key(ident: str) -> tuple:
    """デジタルの番号が先、紙の番号（PA-…）が後。それぞれの中は自然順。"""
    prefix, body = split_prefix(ident)
    return (prefix,) + tuple(int(p) if p.isdigit() else (len(p), p)
                             for p in re.findall(r'\d+|[a-z]+', body))


def letters(number: int) -> str:
    result = ''
    while number:
        number, digit = divmod(number - 1, 26)
        result = chr(97 + digit) + result
    return result


def next_child(parent: str, child_texts: list[str]) -> str:
    ids = [value(t) for t in child_texts]
    used = []
    for ident in ids:
        if ID_RE.fullmatch(ident) and parent_id(ident) == parent:
            suffix = ident[len(parent):]
            n = int(suffix) if suffix.isdigit() else 0
            if not suffix.isdigit():
                for c in suffix:
                    n = n * 26 + ord(c) - 96
            used.append(n)
    n = max(used, default=0) + 1
    return parent + (letters(n) if parent[-1].isdigit() else str(n))


def assign_child(parent_text: str, child_text: str, sibling_texts: list[str]) -> str:
    pid = value(parent_text)
    if value(child_text) or not ID_RE.fullmatch(pid):
        return child_text
    return set_value(child_text, next_child(pid, sibling_texts))


# 紙の PKM のノートの題（番号・番号-題・番号の一覧）。グループでも ID を外さない
PAPER_TITLE_RE = re.compile(r'^(?:(?:[A-Z]{1,4}-)?[1-9]\d{0,4}(?:[a-z]+\d{0,5})*(?:-.*)?)$')
DAILY_RE = re.compile(r'^\d{4}-\d{2}-\d{2}-(?:MO|TU|WE|TH|FR|SA|SU)(?:-|$)')


def is_group(note: dict) -> bool:
    return bool(nf._GROUP_ATTR_RE.search('\n'.join(note['fm'])))


def is_daily(note: dict) -> bool:
    """日記・時系列記録のその日のノート。"""
    return bool(DAILY_RE.match(note['title'])) or any(re.match(r'^record\s*:', ln) for ln in note['fm'])


def creation_key(path: Path, note: dict) -> tuple:
    """Prefer YAML creation time, then the timestamp filename; unknown dates last."""
    for line in note['fm']:
        match = re.match(r'^time\s*:\s*(.*?)\s*$', line)
        if match:
            raw = match.group(1).split(' #', 1)[0].strip().strip("\"'")
            try:
                date = datetime.fromisoformat(raw)
                if date.tzinfo is not None:
                    date = date.astimezone(timezone.utc).replace(tzinfo=None)
                return (date, str(path))
            except ValueError:
                pass
    if re.fullmatch(r'\d{12}', path.stem):
        try:
            return (datetime.strptime('20' + path.stem, '%Y%m%d%H%M%S'), str(path))
        except ValueError:
            pass
    return (datetime.max, str(path))


# 日付の題（年「2026」・月「2026-10」・日「2026-10-19-MO-…」、時系列記録の「2026-10-夢」など）。
# きょうだいの番号は、作った時刻ではなくこの日付の順に振る（あとから作った過去の日記も日付の位置に来る）
DATED_TITLE_RE = re.compile(r'^(\d{4}(?:-\d{2}(?:-\d{2})?)?)(?:-|$)')


PAPER_NUMBER_RE = re.compile(r'^(?:[A-Z]{1,4}-)?[1-9]\d{0,4}(?:[a-z]+\d{0,5})*$')


def scan_number(note: dict) -> str:
    """紙のスキャンノート（題が番号だけで、スキャンの印か、同じ名前の画像の参照がある）なら、その番号。そうでなければ ''。
    題は `PA-1a2`（印つき。新しい形）か `1a2`（印なし。旧い形）。印つきの題はそのまま返す（ノートごとに自分の印を持つ）。"""
    title = note['title']
    if not PAPER_NUMBER_RE.fullmatch(title) or is_group(note):
        return ''
    if any(ln.strip() == 'source: scan' for ln in note['fm']):
        return title
    stems = {re.escape(title), re.escape(split_prefix(title)[1])}   # 画像の名前は、題と同じか、印を除いた番号
    pat = re.compile(r'!\[[^\]]*\]\(<?(?:[^)>]*/)?(?:' + '|'.join(sorted(stems)) + r')\.[A-Za-z0-9]+>?\)')
    return title if any(pat.search(ln) for ln in note['body']) else ''


_PAPER_INFRA_RE = re.compile(r'^folgezettel-Index-\S+$')
# 印が複数あるときの生成物の題: `Paper-Zettelkasten-Index-PA`・`Index-write-PA`・`Folgezettel-Index-PA`（末尾が印）
_INFRA_SUFFIX_RE = re.compile(r'^(?:Paper-Zettelkasten-Index|Index-write|Folgezettel-Index)-([A-Z]{1,4})$')


def infra_prefix(note: dict) -> str:
    """紙の自動作成の索引の題の末尾が印（`...-PB`）なら、その印（`PB-`）。印なしの題なら ''。"""
    m = _INFRA_SUFFIX_RE.match(note['title'])
    if m:
        return m.group(1) + '-'
    m = re.match(r'^folgezettel-Index-([A-Z]{1,4})-\S+$', note['title'])
    return m.group(1) + '-' if m else ''



def is_paper_infra(note: dict) -> bool:
    """紙の PKM が自動で作る索引（Paper-Zettelkasten-Index・Folgezettel-Index・folgezettel-Index-N、紙の Index-write）。
    YAML の folgezettel はどれも `PA-0`（題・表示名は変えない）。"""
    title = note['title']
    if title in ('Paper-Zettelkasten-Index', 'Folgezettel-Index') or _PAPER_INFRA_RE.match(title) or _INFRA_SUFFIX_RE.match(title):
        return True
    return (title == 'Index-write' or title.startswith('Index-write-')) and any('Paper-Zettelkasten-Index' in ln for ln in note['body'])


def is_paper(note: dict) -> bool:
    """紙の PKM のノート（題が番号）。日付の題（2026-10-19-MO-… / 2026-10 / 2026）は紙の番号ではない。"""
    return bool(PAPER_TITLE_RE.match(note['title'])) and not DATED_TITLE_RE.match(note['title'])


def sibling_key(path: Path, note: dict) -> tuple:
    m = DATED_TITLE_RE.match(note['title'])
    if m:
        return (0, m.group(1), creation_key(path, note))
    return (1, '', creation_key(path, note))


# グループではないが、親ノートの BranchGroup: に入って親と同じ番号を持つ生成ノート（紙の PKM の Index-write。2026-10-27）
SHARED_ID_TITLES = ('Index-write',)


def _suffix(parent: str, n: int) -> str:
    return parent + (letters(n) if parent[-1].isdigit() else str(n))


def allocation(root: Path, notes: dict) -> dict[Path, str]:
    """Plan the IDs so that they match the Branch tree exactly (2026-10-27).

    番号は Branch の木の形そのもの: 親の番号の子になり、きょうだいは 1, 2, 3 / a, b, c と欠番なしに続く。
    ParentBranch: を変えた・ノートを消した・親を外した、などで形が変わったら、その場で全体を振り直す
    （飛んだ番号は詰める）。きょうだいの順は、日付の題なら日付順、それ以外は今の番号の順、新しいものは作った順で最後。
    なので、何も変わっていなければ計画は空（何度回しても同じ）。1 回の走査で、ノートの数 n に対して n log n。
    振り直さないもの: 紙の PKM の番号（題が番号）・編集中で未保存のノート・Branch から外れていて番号を持つノート（その番号はそのまま、
    その子は下に続ける）。"""
    known = set(notes)
    def targets(lines, base):
        out = []
        for _, link in nf._links_from(lines):
            raw = link.split('#', 1)[0]
            for candidate in (raw, unquote(raw)):
                p = (base / candidate).resolve()
                if p in known and p.name != 'index.md':
                    if p not in out:
                        out.append(p)
                    break
        return out
    own_parents = {p: targets(n['pbranch'], p.parent) for p, n in notes.items()}
    parents = {p: list(ps) for p, ps in own_parents.items()}
    children = {p: targets(n['cbranch'], p.parent) for p, n in notes.items()}
    for p, kids in children.items():
        for c in kids:
            if p not in parents[c]:
                parents[c].append(p)
    for c, ps in parents.items():
        for p in ps:
            if c not in children[p]:
                children[p].append(c)
    ids = {p: value('\n'.join(n['fm'])) for p, n in notes.items()}
    stored = dict(ids)
    plan = {}
    unsaved = {p for p in notes if nf._editor_has_unsaved_changes(p)}
    # グループは Folgezettel ID を持たない。付いていれば外す（'' は「消す」）。
    # 例外（2026-10-20）: ブランチで作られたグループ（親ノートの BranchGroup: にあるグループ）は、親ノートと同じ ID を持つ（最後に振る）。
    # 紙の PKM の番号（題が番号）は別物なので触らない
    for p, n in notes.items():
        if ids[p] and (is_group(n) or n['title'] in SHARED_ID_TITLES) and not is_paper(n) and p not in unsaved:
            plan[p] = ''
            ids[p] = ''
    # 紙のスキャンノートの番号は、題の番号の前に印（PA-）を付けた形にそろえる（デジタルの番号とぶつからない別の空間）。
    # 印を設定で変えたら（PA → PB）、ここで全部付け直す
    prefix = paper_prefix(root)
    scan_prefixes = {split_prefix(scan_number(n))[0] for n in notes.values() if scan_number(n) and split_prefix(scan_number(n))[0]}
    # 印なしの旧い題のスキャンノートと、印なしの生成物は、印が 1 つだけならそれ（無ければ設定の印）に属する
    base_prefix = next(iter(scan_prefixes)) if len(scan_prefixes) == 1 else prefix
    for p, n in notes.items():
        num = scan_number(n)
        if num and p not in unsaved:
            ids[p] = num if split_prefix(num)[0] else base_prefix + num
            if ids[p] != stored[p]:
                plan[p] = ids[p]
    # 紙の自動作成の索引は、YAML の folgezettel を `PA-0` にそろえる（題は変えない。グループも同じ。印を変えたら付け直す）
    for p, n in notes.items():
        if is_paper_infra(n) and p not in unsaved:
            ids[p] = (infra_prefix(n) or base_prefix) + '0'
            if ids[p] != stored[p]:
                plan[p] = ids[p]
            else:
                plan.pop(p, None)
    index = root / 'index.md'
    top = targets(notes[index]['body'], root) if index in notes else []
    # 日記（YYYY-MM-DD-曜日）と時系列記録のその日のノート（front matter の record:）も最上位にする。
    # グループの中にあって Branch の親を持たないので、ここで番号を振らないと、日記から伸びたノートにも番号が付かない
    topset = set(top)
    for p, n in notes.items():
        if p not in topset and p.name != 'index.md' and not is_group(n) and is_daily(n):
            top.append(p)
            topset.add(p)

    def managed(p) -> bool:
        return p.name != 'index.md' and not is_group(notes[p]) and not is_paper(notes[p]) and p not in unsaved

    def primary(c):
        """親が複数あるノートの、番号の親にするもの: 今の番号の親 → ParentBranch: の最初 → 先頭。"""
        ps = [q for q in parents[c] if q != c]
        if len(ps) <= 1:
            return ps[0] if ps else None
        want = parent_id(ids[c]) if ID_RE.fullmatch(ids[c]) else ''
        for q in ps:
            if want and ids[q] == want:
                return q
        for q in own_parents[c]:
            if q in ps:
                return q
        return ps[0]

    primaries = {c: primary(c) for c in notes}
    kids = {}
    for c, q in primaries.items():
        if q is not None:
            kids.setdefault(q, []).append(c)
    old = dict(ids)
    roots = [p for p in top if managed(p) and not parents[p]]
    root_set = set(roots)
    # 番号を残すノート: 紙のノート・未保存の編集中のもの（これらの番号はそのまま。下に続くデジタルの子は、その番号の下に振る）
    def kept(p) -> bool:
        return p.name != 'index.md' and not is_group(notes[p]) and (is_paper(notes[p]) or p in unsaved)
    # 管理するノート（番号を決め直すもの）を、根から木をたどって集める
    managed_set = set(roots)
    stack = list(roots) + [p for p in notes if p not in managed_set and ID_RE.fullmatch(ids[p]) and kept(p)]
    seen = set(stack)
    while stack:
        p = stack.pop()
        for c in kids.get(p, ()):
            if c in seen or not managed(c) or c == p:
                continue
            seen.add(c)
            managed_set.add(c)
            stack.append(c)
    # 木に入れなかったのに番号を持つノート（Index の本文にも日記にもなく、親もない。親を外した・Index から外した、など）は、番号を外す。
    # 番号のないノートを親にしている子も、同じ理由で外れる。番号が無く親も無いノートは、\a（未所属）に出る
    for p, n in notes.items():
        if (ID_RE.fullmatch(ids[p]) and p not in managed_set and p.name != 'index.md' and not is_group(n)
                and not kept(p) and n['title'] not in SHARED_ID_TITLES and not is_paper_infra(n)):
            ids[p] = ''
            plan[p] = ''
    # 残した番号は、そのまま使われているものとして避ける
    fixed = {ids[p] for p in notes if p not in managed_set and ID_RE.fullmatch(ids[p])}

    def sibling_order(p, c):
        m = DATED_TITLE_RE.match(notes[c]['title'])
        if m:
            return (0, m.group(1), (), creation_key(c, notes[c]))
        if ID_RE.fullmatch(old[c]):
            # 今の番号の順（親がずれていても、その番号の並びで）。番号の無い新しいものは作った順で最後
            return (1, '', tuple((0, x, '') if isinstance(x, int) else (1, x[0], x[1]) if isinstance(x, tuple) else (2, 0, x) for x in natural_key(old[c])), creation_key(c, notes[c]))
        return (2, '', (), creation_key(c, notes[c]))

    def assign(p, ident):
        n = 0
        ordered = sorted((c for c in kids.get(p, ()) if c in managed_set and c not in done), key=lambda c: sibling_order(p, c))
        for c in ordered:
            n += 1
            while _suffix(ident, n) in fixed:
                n += 1
            done.add(c)
            new = _suffix(ident, n)
            ids[c] = new
            if new != stored[c]:
                plan[c] = new
            else:
                plan.pop(c, None)
            work.append(c)

    # 最上位: 今の最上位の番号の順（新しいものは作った順で最後）に、欠番なしで振る
    done = set()
    work = []
    def top_key(p):
        if ID_RE.fullmatch(old[p]) and old[p].isdigit():
            return (0, int(old[p]), creation_key(p, notes[p]))
        return (1, 0, creation_key(p, notes[p]))
    n = 0
    for p in sorted(roots, key=top_key):
        n += 1
        while str(n) in fixed:
            n += 1
        done.add(p)
        ids[p] = str(n)
        if ids[p] != stored[p]:
            plan[p] = ids[p]
        else:
            plan.pop(p, None)
        work.append(p)
    # 管理しないもの（紙のノート・編集中のもの）の子は、その番号の下に続ける
    for p in notes:
        if p not in managed_set and p not in done and ID_RE.fullmatch(ids[p]) and kept(p):
            work.append(p)
    while work:
        p = work.pop()
        if ID_RE.fullmatch(ids[p]):
            assign(p, ids[p])
    for p, n in notes.items():
        if p.name == 'index.md' or is_group(n) or not ID_RE.fullmatch(ids[p]):
            continue
        for g in targets(nf._take_branch_group_block(n['body'])[0], p.parent):
            if not (is_group(notes[g]) or notes[g]['title'] in SHARED_ID_TITLES) or is_paper(notes[g]) or g in unsaved:
                continue
            if stored[g] == ids[p]:
                plan.pop(g, None)
            else:
                plan[g] = ids[p]
    return plan


def navigate(root: Path, current: Path, direction: str) -> dict:
    by_id = {}
    groups = {}
    current = current.resolve()
    ident = ''
    for p in nf._iter_md(root):
        text = p.read_text(encoding='utf-8')
        i = value(text)
        if p.resolve() == current:
            ident = i
        if ID_RE.fullmatch(i):
            fm, _ = nf._split_front_matter(text.splitlines())
            shared = any(re.match(r'^title\s*:\s*(?:%s)\s*$' % '|'.join(map(re.escape, SHARED_ID_TITLES)), ln) for ln in fm)
            (groups if nf._GROUP_ATTR_RE.search('\n'.join(fm)) or shared else by_id).setdefault(i, []).append(p.resolve())
    # ブランチで作られたグループは親ノートと同じ ID を持つので、同じ ID のノートがあればそちらを優先する
    for i, ps in groups.items():
        by_id.setdefault(i, ps)
    if not ID_RE.fullmatch(ident):
        return {'ok': False, 'error': 'このノートにはfolgezettelがありません'}
    if direction == 'up':
        dest = parent_id(ident)
    elif direction == 'down':
        kids = sorted((i for i in by_id if parent_id(i) == ident), key=natural_key)
        dest = kids[0] if kids else ''
    else:
        siblings = sorted((i for i in by_id if parent_id(i) == parent_id(ident)), key=natural_key)
        pos = siblings.index(ident) + (-1 if direction == 'left' else 1)
        dest = siblings[pos] if 0 <= pos < len(siblings) else ''
    matches = by_id.get(dest, [])
    if not matches:
        return {'ok': False, 'error': '移動先のノートがありません'}
    if len(matches) != 1:
        return {'ok': False, 'error': f'folgezettel {dest} が重複しています'}
    return {'ok': True, 'path': str(matches[0]), 'id': dest}


def main() -> int:
    try:
        if len(sys.argv) == 5 and sys.argv[1] == 'move':
            result = navigate(Path(sys.argv[2]).resolve(), Path(sys.argv[3]), sys.argv[4])
        elif len(sys.argv) == 3 and sys.argv[1] == 'sync-index':
            result = {'ok': True, 'changed': nf.simple_sync(Path(sys.argv[2]))}
        else:
            raise ValueError('usage: folgezettel.py move ROOT FILE DIRECTION | sync-index ROOT')
    except (OSError, ValueError, RuntimeError) as e:
        result = {'ok': False, 'error': str(e)}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
