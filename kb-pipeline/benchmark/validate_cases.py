"""Validate a benchmark case file against the corpus.

Checks, per case:
  1. expect is literally present in the evidence chunk's title or source (the hit rule).
  2. expect is not itself a substring of the question (would make the case trivially lexical).
  3. how much the question overlaps the answering page title (copy-paste detector): shares
     a >=6-char substring with the title means the case was probably written by reading the
     title, which over-credits lexical retrieval.
  4. near-duplicates against another case file (same expected doc + very similar wording).

Usage: python validate_cases.py <cases.jsonl> [--db PATH] [--dup-of other.jsonl]
"""
from __future__ import annotations

import argparse
import json
import os
import re
from kb_paths import runtime_db
import sqlite3
from pathlib import Path

DB = runtime_db()


def cjk_runs(s: str) -> set[str]:
    return set(re.findall(r"[\u4e00-\u9fff]{6,}", s or ""))


def norm(s: str) -> str:
    return re.sub(r"[\s，。？?！!、,\.]+", "", (s or "").lower())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cases", type=Path)
    ap.add_argument("--db", type=Path, default=DB)
    ap.add_argument("--dup-of", type=Path)
    a = ap.parse_args()
    cases = [json.loads(l) for l in a.cases.read_text(encoding="utf-8").splitlines() if l.strip()]
    conn = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True)
    bad = []
    leak = []
    copyish = []
    for c in cases:
        ev = c.get("evidence_chunk_id")
        row = conn.execute("select title, source, length(text) from chunks where chunk_id=?",
                           (ev,)).fetchone() if ev else None
        if not row:
            bad.append((c["id"], "evidence chunk not found", ev))
            continue
        title, source, tlen = row
        hay = f"{title} {source}"
        missing = [t for t in c["expect"] if t not in hay]
        if missing:
            bad.append((c["id"], f"expect not in title/source: {missing}", hay[:80]))
        if not tlen:
            bad.append((c["id"], "evidence chunk has empty text", ""))
        if any(t in c["q"] for t in c["expect"] if not t.isascii()):
            leak.append((c["id"], c["q"], [t for t in c["expect"] if t in c["q"]]))
        shared = cjk_runs(c["q"]) & cjk_runs(title)
        if shared:
            copyish.append((c["id"], sorted(shared), title[:60], c["q"]))
    print(f"cases={len(cases)}  bad={len(bad)}  expect-in-query={len(leak)}  "
          f"shares-6char-run-with-title={len(copyish)}")
    for x in bad:
        print("   BAD ", x)
    for x in leak:
        print("   LEAK", x)
    for x in copyish[:12]:
        print("   COPY", x[0], x[1], "|", x[2], "|", x[3])

    if a.dup_of and a.dup_of.exists():
        other = [json.loads(l) for l in a.dup_of.read_text(encoding="utf-8").splitlines() if l.strip()]
        seen = {norm(c["q"]) for c in other}
        dups = [c["id"] for c in cases if norm(c["q"]) in seen]
        # also flag high word overlap
        close = []
        for c in cases:
            for o in other:
                if c["id"] == o["id"]:
                    continue
                a_, b_ = cjk_runs(c["q"]), cjk_runs(o["q"])
                if a_ and b_ and len(a_ & b_) / max(1, len(a_ | b_)) >= 0.5:
                    close.append((c["id"], o["id"], c["q"], o["q"]))
        print(f"exact duplicate questions vs {a.dup_of.name}: {len(dups)} {dups}")
        print(f"near-duplicate (6-char run jaccard>=0.5): {len(close)}")
        for x in close[:10]:
            print("   NEAR", x)


if __name__ == "__main__":
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    main()
