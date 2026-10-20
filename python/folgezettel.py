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

ID_RE = re.compile(r"^[1-9]\d*(?:[a-z]+[1-9]\d*)*[a-z]*$")


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
    parts = re.findall(r'\d+|[a-z]+', ident)
    return ''.join(parts[:-1])


def natural_key(ident: str) -> tuple:
    return tuple(int(p) if p.isdigit() else (len(p), p)
                 for p in re.findall(r'\d+|[a-z]+', ident))


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
PAPER_TITLE_RE = re.compile(r'^(?:\d+[a-z0-9]*(?:-.*)?|[Ff]olgezettel-Index(?:-.*)?|Paper-Zettelkasten-Index)$')
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


def is_paper(note: dict) -> bool:
    """紙の PKM のノート（題が番号）。日付の題（2026-10-19-MO-… / 2026-10 / 2026）は紙の番号ではない。"""
    return bool(PAPER_TITLE_RE.match(note['title'])) and not DATED_TITLE_RE.match(note['title'])


def sibling_key(path: Path, note: dict) -> tuple:
    m = DATED_TITLE_RE.match(note['title'])
    if m:
        return (0, m.group(1), creation_key(path, note))
    return (1, '', creation_key(path, note))


def allocation(root: Path, notes: dict) -> dict[Path, str]:
    """Plan missing IDs using the same parsed snapshot as the normal sync.

    番号は Branch の形に合わせる（2026-10-20 決定）: 親が 1 つのノートの番号が親の番号の子でなくなったら
    （親を付け替えた・日記の年のノートができて月がその下に入った、など）、親の下の新しい番号に振り直す。
    その子孫も同じく振り直す。紙の PKM の番号（題が番号）は振り直さない。"""
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
    parents = {p: targets(n['pbranch'], p.parent) for p, n in notes.items()}
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
    plan = {}
    # グループは Folgezettel ID を持たない（2026-10-20 決定）。付いていれば外す（'' は「消す」）。
    # 紙の PKM の番号（題が番号）は別物なので触らない
    for p, n in notes.items():
        if ids[p] and is_group(n) and not is_paper(n) and not nf._editor_has_unsaved_changes(p):
            plan[p] = ''
            ids[p] = ''
    # Reserve IDs across the vault, including currently disconnected notes
    # （グループから外した番号も、取り違えないように使い回さない）.
    reserved = set(ids.values()) | {value('\n'.join(notes[p]['fm'])) for p in plan}
    index = root / 'index.md'
    top = targets(notes[index]['body'], root) if index in notes else []
    # 日記（YYYY-MM-DD-曜日）と時系列記録のその日のノート（front matter の record:）も最上位にする。
    # グループの中にあって Branch の親を持たないので、ここで番号を振らないと、日記から伸びたノートにも番号が付かない
    for p, n in notes.items():
        if p not in top and p.name != 'index.md' and not is_group(n) and is_daily(n):
            top.append(p)
    number = max((int(i) for i in ids.values() if i.isdigit()), default=0)
    for p in sorted(top, key=lambda p: creation_key(p, notes[p])):
        if parents[p] or is_group(notes[p]) or nf._editor_has_unsaved_changes(p):
            continue
        # 最上位なのに子の番号（51a など）を持っているもの（親を外した）は、最上位の番号に振り直す
        if ids[p] and (not ID_RE.fullmatch(ids[p]) or not parent_id(ids[p]) or is_paper(notes[p])):
            continue
        number += 1
        while str(number) in reserved:
            number += 1
        ids[p] = plan[p] = str(number)
        reserved.add(ids[p])
    queue = [p for p in notes if ID_RE.fullmatch(ids[p]) and not is_group(notes[p])]
    seen = set()
    for p in queue:
        if p in seen:
            continue
        seen.add(p)
        for c in sorted(children[p], key=lambda c: sibling_key(c, notes[c])):
            if len(parents[c]) != 1 or c == p or is_group(notes[c]) or nf._editor_has_unsaved_changes(c):
                continue
            stale = (ID_RE.fullmatch(ids[c]) and parent_id(ids[c]) != ids[p]
                     and not is_paper(notes[c]))
            if not ids[c] or stale:
                # All reserved IDs prevent collisions even outside this Branch.
                ident = next_child(ids[p], [f'---\nfolgezettel: "{i}"\n---' for i in reserved])
                ids[c] = plan[c] = ident
                reserved.add(ident)
                # 先に見終わっていても、新しい番号でその子をもう一度見る（子孫も同じ回で振り直す）
                seen.discard(c)
            if ID_RE.fullmatch(ids[c]):
                queue.append(c)
    return plan


def navigate(root: Path, current: Path, direction: str) -> dict:
    by_id = {}
    current = current.resolve()
    ident = ''
    for p in nf._iter_md(root):
        i = value(p.read_text(encoding='utf-8'))
        if p.resolve() == current:
            ident = i
        if ID_RE.fullmatch(i):
            by_id.setdefault(i, []).append(p.resolve())
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
