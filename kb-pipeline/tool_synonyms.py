"""Validate synonyms.tsv against the corpus.

For every target: does it exist (df > 0)? For every surface form: how common is it (df)?
Dead targets are reported so they can be replaced with the name the manuals actually use; a
typical cause is a PLCopen / IEC / other-vendor name that KEYENCE never uses.

Usage:
  python tool_synonyms.py                 # report
  python tool_synonyms.py --df-term 定点 # show df for arbitrary terms
"""
import os
from __future__ import annotations

import argparse
import sqlite3
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
SYN = HERE / "synonyms.tsv"
DB = Path(os.environ.get("KB_DB") or (Path(__file__).resolve().parent.parent / "dist" / "kb-v3m-2026-11-03" / "wiki.v3m.db"))


def load(path: Path) -> list[tuple[int, str, str]]:
    rows = []
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        term, targets = line.split("\t", 1)
        for t in targets.split("|"):
            if t.strip():
                rows.append((i, term.strip(), t.strip()))
    return rows


def df_of(conn, cache: dict, term: str, total: int) -> int:
    """Document frequency of an arbitrary term: term_df first, then a direct corpus count."""
    if term in cache:
        return cache[term]
    n = 0
    if len(term) >= 3:
        try:
            n = conn.execute("select count(*) from fts_tri where fts_tri match ?",
                             ('"' + term.replace('"', '""') + '"',)).fetchone()[0]
        except Exception:
            n = 0
    if not n:
        n = conn.execute("select count(*) from chunks where title like ? or section like ? or text like ?",
                         (f"%{term}%", f"%{term}%", f"%{term}%")).fetchone()[0]
    cache[term] = n
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", type=Path, default=DB)
    ap.add_argument("--syn", type=Path, default=SYN)
    ap.add_argument("--df-term", nargs="*", default=[])
    ap.add_argument("--list-dead", action="store_true")
    ap.add_argument("--show-all", action="store_true", help="print df for every target")
    a = ap.parse_args()
    c = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True)
    try:
        df = dict(c.execute("select term, df from term_df"))
    except sqlite3.OperationalError:
        df = {}
    total = c.execute("select count(*) from chunks").fetchone()[0]

    if a.df_term:
        for t in a.df_term:
            n = df_of(c, df, t, total)
            print(f"  df({t!r}) = {n:,}  ({n/total:.2%} of chunks)")
        return

    rows = load(a.syn)
    dead = [(ln, term, t) for ln, term, t in rows if df_of(c, df, t, total) == 0]
    surfaces = {term for _, term, _ in rows}
    generic = [(term, df_of(c, df, term, total)) for term in sorted(surfaces)
               if df_of(c, df, term, total) > total * 0.10]
    print(f"pairs={len(rows)}  surfaces={len(surfaces)}  targets={len({t for _,_,t in rows})}")
    print(f"dead targets: {len(dead)}  (df=0, cannot be retrieved)")
    if a.list_dead:
        for ln, term, t in dead:
            print(f"   line {ln:4}  {term:14} -> {t}")
    print(f"surfaces that are everyday words (df>10%): {len(generic)}")
    for term, n in generic:
        print(f"   {term:14} df={n:6} ({n/total:.1%})")
    if a.show_all:
        for ln, term, t in rows:
            print(f"   line {ln:4}  {term:14} -> {t:34} df={df_of(c, df, t, total):6}")


if __name__ == "__main__":
    main()
