"""Content-first similarity for Gnosis predicted relations and ranked views.

Only prose/title are signals. Index membership, Folgezettel numbering, front matter,
link-only lists and diary dates are not evidence of semantic relevance.
This is local lexical TF-IDF (no cloud/AI services), not embedding-based semantics.
"""
from __future__ import annotations

from collections import Counter
import math
from pathlib import PurePosixPath
import re

_CJK = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uff66-\uff9f]+")
_WORD = re.compile(r"[a-z][a-z0-9_-]{1,}", re.I)
_CYRILLIC = re.compile(r"[\u0400-\u052f]{2,}")
_DATE = re.compile(r"(?:^|[^0-9])(?:19|20)\d{2}[-_/]\d{1,2}(?:[-_/]\d{1,2})?(?:$|[^0-9])")
_LINK = re.compile(r"!?\[([^\]]*)\]\([^)]+\)")
_SECTIONS = re.compile(r"^(?:Group|BranchGroup|ParentBranch|ChildBranch|Context|Related|BackLink|ThisNoteGroup):\s*$", re.I)
_STOP = {"the", "and", "for", "with", "from", "that", "this", "index", "diary",
         "note", "notes", "group", "today", "日記", "索引", "目次", "今日", "ノート", "日時",
         "to", "of", "in", "on", "by", "an", "or", "as", "be", "is", "it", "at",
         "и", "на", "это", "для", "как", "или", "что", "из", "над", "про", "не", "по"}
_FRONT = re.compile(r"^---\s*$")
_ONLY_LINKS = re.compile(r"^(?:\s*(?:[-*+]\s*)?!?\[[^\]]*\]\([^)]+\)\s*)+$")


def organizational(path: str, title: str, is_group: bool = False) -> bool:
    """Navigation indexes and date-addressed journals are not predicted topics."""
    # A topical group is meaningful (e.g. 植物・言語). Only generic navigation
    # indexes and date-addressed journals must be excluded, not every Group.
    if PurePosixPath(path).name.lower() == "index.md":
        return True
    stem = PurePosixPath(path).stem
    if _DATE.search(stem) or _DATE.search(title):
        return True
    t = title.strip().casefold()
    return t in {"index", "索引", "目次", "日記", "diary", "daily", "daily note", "時系列記録"}


def _tokens(text: str):
    text = text.casefold()
    for w in _WORD.findall(text):
        if w not in _STOP and not w.isdigit():
            yield w
    for word in _CYRILLIC.findall(text):
        if word in _STOP:
            continue
        yield word
        # Suffix variation across Russian inflections otherwise loses all overlap.
        if len(word) >= 4:
            for i in range(len(word) - 2):
                yield word[i:i + 3]
    for run in _CJK.findall(text):
        if len(run) == 1:
            continue
        for i in range(len(run) - 1):
            token = run[i:i + 2]
            if token not in _STOP:
                yield token


def profile(raw: str, title: str, path: str = "", is_group: bool = False) -> dict[str, int]:
    """Count content terms; intentionally discard navigation structures and metadata."""
    if organizational(path, title, is_group):
        return {}
    lines = raw.splitlines()
    if lines and _FRONT.match(lines[0]):
        for i in range(1, len(lines)):
            if _FRONT.match(lines[i]):
                lines = lines[i + 1:]
                break
        else:
            lines = []  # malformed front matter must not become relevance evidence
    counts = Counter(_tokens(title))
    counts.update(_tokens(title))
    for line in lines:
        s = line.strip()
        if not s or _SECTIONS.fullmatch(s) or _ONLY_LINKS.fullmatch(s):
            continue
        if s.startswith("#"):
            s = s.lstrip("#").strip()
            if s.casefold() == title.casefold():
                continue
        if _DATE.fullmatch(s) or s in ("---", "***"):
            continue
        # Links that occur in real prose keep their display text.
        s = _LINK.sub(lambda m: m.group(1), s)
        counts.update(_tokens(s))
    # Avoid a huge diary / pasted document dominating cache size.
    return dict(counts.most_common(240))


def similarities(profiles: dict[str, dict[str, int]], source: str,
                 limit: int = 80, minimum: float = 0.06) -> list[tuple[str, float]]:
    """Return cosine-ranked substantive neighbors, without graph/number/date bonuses."""
    src = profiles.get(source, {})
    if not src:
        return []
    df: Counter = Counter()
    for counts in profiles.values():
        df.update(counts.keys())
    n = max(1, len(profiles))
    idf = {t: math.log(1 + (n + 1) / (c + 1)) for t, c in df.items()}

    def weight(p):
        v = {t: (1 + math.log(c)) * idf[t] for t, c in p.items() if c and df[t] <= max(2, n * 0.6)}
        norm = math.sqrt(sum(x * x for x in v.values()))
        return {t: a / norm for t, a in v.items()} if norm else {}

    sv = weight(src)
    if not sv:
        return []
    out = []
    for key, counts in profiles.items():
        if key == source or not counts:
            continue
        common = set(sv) & counts.keys()
        if not common:
            continue
        # Short notes often only have a 2-kanji heading, a single abbreviation
        # (AI/IT), or a short Russian topic. Permit one strong rare shared
        # concept, but not a single ubiquitous word.
        single = len(common) == 1
        if single:
            token = next(iter(common))
            rare = df[token] <= max(3, int(n * .25))
            title_weighted = src[token] >= 2 or counts[token] >= 2
            tiny_topics = len(src) <= 2 and len(counts) <= 2
            if not rare or not (title_weighted or tiny_topics):
                continue
        v = weight(counts)
        sim = sum(sv[t] * v.get(t, 0.) for t in common)
        if sim >= (max(minimum, .12) if single else minimum):
            out.append((key, sim))
    out.sort(key=lambda pair: (-pair[1], pair[0]))
    return out[:limit]
