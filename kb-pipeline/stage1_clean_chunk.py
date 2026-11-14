"""Stage 1: clean + re-chunk wiki.v2.cleaned.db into wiki.v3.db (table `chunks`).

What it does
- drops chunks that v2's own quality audit marked action='drop'
- strips markdown noise (image tags, link targets, escapes, empty table cells)
- de-duplicates identical normalised text across documents; keeps the copy from the
  most authoritative source type and records the others in `also_in`
- splits oversized chunks on line boundaries (tables repeat their heading; prose gets
  a small overlap) and leaves small self-contained help fragments alone
- adds metadata: doc, section (page_title), series (CPU/unit family derived from the
  document name), parent_id (v2 chunk the piece came from)

The source DB is opened read-only and never modified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = Path(os.environ.get("KB_SOURCE_DB") or (HERE.parent / "dist" / "kb-v2.cleaned.db"))
DST = Path(os.environ.get("KB_DB") or (HERE.parent / "dist" / "kb-v3m-2026-11-03" / "wiki.v3m.db"))

TARGET = 1600       # preferred piece size (chars)
HARD_MAX = 2600     # pieces never exceed this unless a single line does
OVERLAP = 160       # prose overlap between consecutive pieces

SOURCE_PRIORITY = {"htmlhelp": 0, "chm": 1, "t_language_example": 2, "dockinghelp": 3,
                   "table": 4, "pdf": 5, "htmlnavi_meta": 9}

# document name -> product family. Order matters: first match wins.
SERIES_RULES = [
    (r"X5H|X3H", "KV-X"),                 # KVSHARDX5H / KVSHARDX3H = KV-X500 / KV-X300 hardware manuals
    (r"KV-?XH|XHEC|ParameterHelpX", "KV-XH"),
    (r"KV-?X(?!L)|KV-X_|KVX", "KV-X"),
    (r"8000", "KV-8000"),
    (r"NanoC", "KV-NanoC"),
    (r"Nano", "KV-Nano"),
    (r"G4|KVSHARD5|5000", "KV-5000/3000"),
    (r"KV-?ML|MLS", "KV-ML"),
    (r"SV3", "SV3"), (r"SV2", "SV2"), (r"SVHARD", "SV"),
]

IMG_RE = re.compile(r"!\[[^\]]*\]\([^)]*\)")
LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")
EMPTY_ROW_RE = re.compile(r"^\s*(\|\s*)+\|?\s*$")
SEP_ROW_RE = re.compile(r"^\s*\|?(\s*:?-{2,}:?\s*\|)+\s*:?-*:?\s*$")
MULTI_BLANK_RE = re.compile(r"\n{3,}")


def clean_text(text: str) -> str:
    text = IMG_RE.sub("", text)
    text = LINK_RE.sub(r"\1", text)
    text = text.replace("\\*", "*").replace("\\_", "_").replace("\u00a0", " ")
    lines = []
    for line in text.splitlines():
        if EMPTY_ROW_RE.match(line) or SEP_ROW_RE.match(line):
            continue
        if line.startswith("|"):
            line = re.sub(r"\|\s*\|", "|", line)  # collapse empty cells
            line = re.sub(r"\s{2,}", " ", line)
        lines.append(line.rstrip())
    return MULTI_BLANK_RE.sub("\n\n", "\n".join(lines)).strip()


def norm_key(text: str) -> str:
    return hashlib.sha1(re.sub(r"\s+", "", text).encode("utf-8")).hexdigest()


def series_of(doc: str, title: str) -> str:
    hay = f"{doc} {title}"
    for pat, name in SERIES_RULES:
        if re.search(pat, hay, re.I):
            return name
    return ""


def split_lines(text: str, heading: str, is_table: bool) -> list[str]:
    if len(text) <= HARD_MAX:
        return [text]
    lines = text.split("\n")
    pieces, cur, size = [], [], 0
    for line in lines:
        # a single monster line (rare) is cut hard
        while len(line) > HARD_MAX:
            pieces.append("\n".join(cur + [line[:TARGET]])) if cur else pieces.append(line[:TARGET])
            cur, size = [], 0
            line = line[TARGET:]
        if size + len(line) > TARGET and cur:
            pieces.append("\n".join(cur))
            if is_table:
                cur, size = [], 0
            else:  # carry a little context forward
                tail, tsize = [], 0
                for l in reversed(cur):
                    if tsize + len(l) > OVERLAP:
                        break
                    tail.insert(0, l)
                    tsize += len(l)
                cur, size = tail, tsize
        cur.append(line)
        size += len(line) + 1
    if cur:
        pieces.append("\n".join(cur))
    if is_table and heading:
        pieces = [p if p.lstrip().startswith("#") else f"# {heading}\n{p}" for p in pieces]
    return pieces


def build(src: Path, dst: Path, use_mineru: bool = False) -> dict:
    t0 = time.time()
    mpages = {}
    if use_mineru:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import mineru_pages
        mpages = mineru_pages.load()
    s = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
    drop_ids = {r[0] for r in s.execute("select chunk_id from quality_flags where action='drop'")}
    rows = s.execute("""select chunk_id, doc_id, title, chunk, source, source_anchor, page_title,
                               source_type, keywords, aliases, sort_key
                        from wiki_chunks""").fetchall()
    stats = {"v2_chunks": len(rows), "dropped_flagged": 0, "dropped_empty": 0,
             "dedup_merged": 0, "split_parents": 0, "mineru_replaced": 0}

    # pass 1: clean + dedup on whole v2 chunks
    best: dict[str, dict] = {}
    for (cid, doc_id, title, chunk, source, anchor, page_title, stype, kw, al, sort_key) in rows:
        if cid in drop_ids:
            stats["dropped_flagged"] += 1
            continue
        extractor = "text"
        text = None
        m = re.search(r"\(p(\d+)-(\d+)\)\s*$", title or "")
        if mpages and stype == "pdf" and m:
            got = mineru_pages.range_text(mpages, (source or "").split("#", 1)[0], int(m.group(1)), int(m.group(2)))
            if got:
                text, extractor = got[0], "mineru-" + got[1]
                stats["mineru_replaced"] += 1
        if text is None:
            text = clean_text(chunk or "")
        if len(re.sub(r"\s", "", text)) < 8:
            stats["dropped_empty"] += 1
            continue
        doc = (source or "").split("#", 1)[0]
        rec = {"parent_id": cid, "doc_id": doc_id, "title": (title or "").strip(), "text": text,
               "source": source, "anchor": anchor or "", "section": (page_title or "").strip(),
               "source_type": stype, "doc": doc, "keywords": kw or "", "aliases": al or "",
               "sort_key": sort_key or "", "also_in": [], "extractor": extractor}
        key = norm_key(text)
        if key in best:
            stats["dedup_merged"] += 1
            keep, other = best[key], rec
            if SOURCE_PRIORITY.get(rec["source_type"], 8) < SOURCE_PRIORITY.get(keep["source_type"], 8):
                keep, other = rec, keep
                rec["also_in"] = best[key]["also_in"]
            keep["also_in"].append(other["source"])
            best[key] = keep
        else:
            best[key] = rec

    # pass 2: split + write
    if dst.exists():
        dst.unlink()
    d = sqlite3.connect(dst)
    d.executescript("""
    create table chunks (
        id INTEGER PRIMARY KEY,
        chunk_id TEXT UNIQUE NOT NULL,
        parent_id TEXT NOT NULL,
        part INTEGER NOT NULL,
        parts INTEGER NOT NULL,
        title TEXT NOT NULL,
        section TEXT,
        doc TEXT,
        source TEXT,
        source_type TEXT,
        series TEXT,
        text TEXT NOT NULL,
        keywords TEXT,
        also_in TEXT,
        sort_key TEXT,
        extractor TEXT
    );
    create index chunks_parent on chunks(parent_id);
    create index chunks_title on chunks(title);
    create table build_meta (k TEXT PRIMARY KEY, v TEXT);
    """)
    out = 0
    for rec in best.values():
        pieces = split_lines(rec["text"], rec["title"], rec["source_type"] == "table")
        if len(pieces) > 1:
            stats["split_parents"] += 1
        series = series_of(rec["doc"], rec["title"])
        for i, p in enumerate(pieces, 1):
            cid = rec["parent_id"] if len(pieces) == 1 else f"{rec['parent_id']}#p{i}"
            d.execute("""insert into chunks (chunk_id,parent_id,part,parts,title,section,doc,source,
                         source_type,series,text,keywords,also_in,sort_key,extractor)
                         values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                      (cid, rec["parent_id"], i, len(pieces), rec["title"], rec["section"], rec["doc"],
                       rec["source"], rec["source_type"], series, p, rec["keywords"],
                       json.dumps(rec["also_in"], ensure_ascii=False) if rec["also_in"] else "",
                       rec["sort_key"], rec["extractor"]))
            out += 1
    stats["v3_chunks"] = out
    stats["elapsed_s"] = round(time.time() - t0, 1)
    lens = [r[0] for r in d.execute("select length(text) from chunks")]
    lens.sort()
    stats["len_p50"] = lens[len(lens) // 2]
    stats["len_p95"] = lens[int(len(lens) * 0.95)]
    stats["len_max"] = lens[-1]
    stats["base64_chunks"] = d.execute("select count(*) from chunks where text like '%base64,%'").fetchone()[0]
    assert stats["base64_chunks"] == 0, "inline image data leaked into chunks"
    d.execute("insert into build_meta values ('stage1', ?)", (json.dumps(stats),))
    d.commit()
    d.close()
    return stats


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=Path, default=SRC)
    ap.add_argument("--dst", type=Path, default=DST)
    ap.add_argument("--mineru", action="store_true", help="replace garbled/spec PDF chunks with MinerU page text")
    a = ap.parse_args()
    print(json.dumps(build(a.src, a.dst, a.mineru), indent=1))
