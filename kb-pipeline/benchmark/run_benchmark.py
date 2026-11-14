"""Retrieval benchmark for the KEYENCE wiki.

A result "hits" a case when any expect term matches the result's title or source.
ASCII terms match as whole tokens (so "C" or "TP" do not match inside "KV-TP40");
CJK terms match as substrings. Metrics: hit@1, hit@5, MRR@10, per category.

Usage:
  python run_benchmark.py --retriever v2 [--db PATH]
  python run_benchmark.py --retriever v3 [--db PATH] [--mode fts|hybrid|...]
  python run_benchmark.py --oracle --db PATH     # check every case is answerable in the DB
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
import time
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
PIPELINE = HERE.parent
REPO_ROOT = PIPELINE.parent
DEFAULT_DB = REPO_ROOT / "dist" / "kb-v3m-2026-11-03" / "wiki.v3m.db"
V3_DB = DEFAULT_DB
K = 10


def load_cases(path: Path) -> list[dict]:
    return [json.loads(l) for l in path.read_text(encoding="utf-8-sig").splitlines() if l.strip()]


def term_regex(term: str) -> re.Pattern:
    if term.isascii():
        return re.compile(r"(?<![A-Za-z0-9_])" + re.escape(term) + r"(?![A-Za-z0-9_])", re.I)
    return re.compile(re.escape(term))


def is_hit(result: dict, patterns: list[re.Pattern], where: str = "doc") -> bool:
    """where=doc: only title/source count (the classic, conservative metric).
    where=content: the returned chunk text counts too, i.e. the answer is inside the context
    the agent would actually read. Both are reported because they answer different questions
    ("did we find the right document" vs "is the answer in front of the agent")."""
    if where == "content":
        hay = f"{result.get('title') or ''} {result.get('source') or ''} {result.get('text') or ''}"
    else:
        hay = f"{result.get('title') or ''} {result.get('source') or ''}"
    return any(p.search(hay) for p in patterns)


def v2_search(db: Path):
    sys.path.insert(0, str(WIKI_ROOT / "scripts"))
    import wiki_query  # type: ignore

    def search(q: str, k: int) -> list[dict]:
        return wiki_query.run_query(db, q, k)["results"]

    return search


def v3_search(db: Path, mode: str):
    sys.path.insert(0, str(PIPELINE))
    import search_v3  # type: ignore

    s = search_v3.Searcher(db)

    def search(q: str, k: int) -> list[dict]:
        return s.search(q, k, mode=mode)

    return search


def run(cases, search, label: str, where: str = "doc") -> dict:
    per_cat = defaultdict(lambda: {"n": 0, "h1": 0, "h5": 0, "mrr": 0.0})
    misses, rows = [], []
    t0 = time.time()
    for c in cases:
        pats = [term_regex(t) for t in c["expect"]]
        try:
            res = search(c["q"], K)
        except Exception as e:  # a crash counts as a miss
            res = []
            print(f"  ! {c['id']}: {e}", file=sys.stderr)
        rank = next((i + 1 for i, r in enumerate(res[:K]) if is_hit(r, pats, where)), None)
        for key in (c["cat"], "ALL"):
            d = per_cat[key]
            d["n"] += 1
            d["h1"] += rank == 1
            d["h5"] += bool(rank and rank <= 5)
            d["mrr"] += 1 / rank if rank else 0
        rows.append({"id": c["id"], "q": c["q"], "rank": rank,
                     "top3": [f"{r.get('title')} | {r.get('source')}" for r in res[:3]]})
        if not rank or rank > 5:
            misses.append(rows[-1])
    elapsed = time.time() - t0
    summary = {cat: {"n": d["n"], "hit@1": round(d["h1"] / d["n"], 3),
                     "hit@5": round(d["h5"] / d["n"], 3), "mrr@10": round(d["mrr"] / d["n"], 3)}
               for cat, d in per_cat.items()}
    return {"label": label, "elapsed_s": round(elapsed, 1),
            "ms_per_query": round(elapsed * 1000 / max(1, len(cases)), 1),
            "summary": summary, "misses": misses, "rows": rows}


def oracle(cases, db: Path):
    conn = sqlite3.connect(db)
    titles = conn.execute("select title, source from wiki_chunks").fetchall()
    bad = []
    for c in cases:
        pats = [term_regex(t) for t in c["expect"]]
        if not any(is_hit({"title": t, "source": s}, pats) for t, s in titles):
            bad.append(c["id"])
    print(json.dumps({"cases": len(cases), "unanswerable": bad}, ensure_ascii=False, indent=1))


def print_summary(rep: dict):
    print(f"== {rep['label']}  ({rep['ms_per_query']} ms/query)")
    order = ["ALL"] + sorted(k for k in rep["summary"] if k != "ALL")
    print(f"{'category':16}{'n':>4}{'hit@1':>8}{'hit@5':>8}{'mrr':>8}")
    for k in order:
        s = rep["summary"][k]
        print(f"{k:16}{s['n']:>4}{s['hit@1']:>8}{s['hit@5']:>8}{s['mrr@10']:>8}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--retriever", choices=["v2", "v3"], default="v2")
    ap.add_argument("--db", type=Path)
    ap.add_argument("--mode", default="hybrid")
    ap.add_argument("--cases", type=Path, default=HERE / "cases.jsonl")
    ap.add_argument("--oracle", action="store_true")
    ap.add_argument("--out", type=Path)
    ap.add_argument("--show-misses", action="store_true")
    ap.add_argument("--hit", choices=["doc", "content"], default="doc",
                    help="doc: hit only if the expected term is in title/source (classic); "
                         "content: also count a hit when the returned chunk text contains it")
    a = ap.parse_args()
    cases = load_cases(a.cases)
    # KB_DB is the supported override for local benchmark runs. The v2
    # retriever remains an explicit compatibility mode over the same shipped
    # database; no deleted external H: drive is consulted implicitly.
    if a.db:
        db = a.db
    elif os.environ.get("KB_DB"):
        db = Path(os.environ["KB_DB"])
    elif a.retriever == "v3":
        db = V3_DB
    else:
        raise SystemExit("--retriever v2 is legacy; pass --db explicitly")
    if a.oracle:
        return oracle(cases, db)
    search = v2_search(db) if a.retriever == "v2" else v3_search(db, a.mode)
    label = f"{a.retriever}:{a.mode if a.retriever == 'v3' else 'baseline'}:{db.name}"
    rep = run(cases, search, label, a.hit)
    print_summary(rep)
    if a.show_misses:
        for m in rep["misses"]:
            print(f"  MISS {m['id']:16} rank={m['rank']}  q={m['q']}  top: {m['top3'][:2]}")
    out = a.out or (HERE / "results" / f"{label.replace(':', '_')}.json")
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
