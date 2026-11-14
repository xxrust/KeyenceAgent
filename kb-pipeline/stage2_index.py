"""Stage 2: build hybrid indexes inside wiki.v3.db.

Tables created
- lexicon(term, target, kind, source, df)  manual-derived name<->Chinese description pairs
                                          + curated synonyms (synonyms.tsv); df = how many chunks
                                          contain the target, used to drop dead targets and to
                                          order expansions by specificity
- fts_tri    FTS5 trigram over chunks (external content) -> literal substring recall
- fts_seg    FTS5 contentless over jieba-segmented title/section/text -> word-level bm25
- jieba_userdict.txt next to the DB (domain words so jieba keeps them whole)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import time
from pathlib import Path

import jieba

HERE = Path(__file__).resolve().parent
DB = Path(os.environ.get("KB_DB") or (Path(__file__).resolve().parent.parent / "dist" / "kb-v3m-2026-11-03" / "wiki.v3m.db"))
SYN = HERE / "synonyms.tsv"

IDENT = r"[A-Za-z_*][A-Za-z0-9_.*+\-/&|^<>˜]*"
PAIR_RE = re.compile(r"^\|\s*(" + IDENT + r")\s*\|\s*([^|\n]{2,40}?)\s*\|", re.M)
CJK_RE = re.compile(r"[\u4e00-\u9fff]")
DATA_TYPES = {"BOOL", "INT", "UINT", "DINT", "UDINT", "REAL", "LREAL", "WORD", "DWORD", "STRING",
              "TIME", "BIN", "FUN/FB", "FUN", "FB", "IN", "OUT", "LD", "ST"}


def extract_lexicon(conn: sqlite3.Connection) -> list[tuple[str, str, str, str]]:
    """Identifier <-> short Chinese description pairs from htmlhelp/chm tables."""
    rows = []
    seen = set()
    for cid, text in conn.execute(
            "select chunk_id, text from chunks where source_type in ('htmlhelp','chm')"):
        for m in PAIR_RE.finditer(text):
            name, desc = m.group(1).strip(), m.group(2).strip()
            if name.endswith(".svg") or name.upper() in DATA_TYPES or len(name) < 2:
                continue
            if not CJK_RE.search(desc) or "。" in desc or len(desc) > 24:
                continue
            key = (desc, name)
            if key in seen:
                continue
            seen.add(key)
            rows.append((desc, name, "manual_pair", cid))
    return rows


def load_synonyms(path: Path) -> list[tuple[str, str, str, str]]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        term, targets = line.split("\t", 1)
        for t in targets.split("|"):
            if t.strip():
                rows.append((term.strip(), t.strip(), "curated", "synonyms.tsv"))
    return rows


def count_df(conn: sqlite3.Connection) -> int:
    """Fill lexicon.df and term_df(term, df) = number of chunks whose text contains the term.

    A plain substring scan, not FTS: targets shorter than 3 chars cannot be matched by the
    trigram tokenizer, and identifiers get split by jieba for the seg index. One pass over all
    chunks with all terms is ~30 s; it runs once per build and makes `df=0` (dead target)
    and `df` ordering available to the runtime.
    """
    terms = sorted({r[0] for r in conn.execute(
        "select term from lexicon union select target from lexicon")})
    df = dict.fromkeys(terms, 0)
    # title/section count too: identifier targets are often only in the page title (name_x channel)
    for (text,) in conn.execute("select title || ' ' || coalesce(section,'') || ' ' || text from chunks"):
        for t in terms:
            if t in text:
                df[t] += 1
    conn.executescript("drop table if exists term_df;"
                       "create table term_df (term TEXT PRIMARY KEY, df INTEGER NOT NULL);")
    conn.executemany("insert into term_df values (?,?)", [(t, n) for t, n in df.items()])
    conn.execute("update lexicon set df=(select df from term_df where term=lexicon.target)")
    return sum(1 for n in df.values() if n == 0)


def build_userdict(conn: sqlite3.Connection, lex, out: Path) -> int:
    words = set()
    for term, target, *_ in lex:
        for w in (term, target):
            if CJK_RE.search(w) and len(w) <= 12:
                words.add(w)
    for (t,) in conn.execute("select distinct title from chunks where source_type!='table'"):
        t = re.sub(r"\s*\((p?\d+[-\d]*)\)\s*$", "", t or "").strip()
        if CJK_RE.search(t) and 2 <= len(t) <= 10 and " " not in t:
            words.add(t)
    out.write_text("\n".join(f"{w} 2000" for w in sorted(words)), encoding="utf-8")
    return len(words)


def seg(text: str) -> str:
    return " ".join(w for w in jieba.cut_for_search(text or "") if w.strip())


GENERIC_DF = 0.02        # short (<=2 char) names found in >2% of chunks are everyday words
GENERIC_DF_ANY = 0.10    # any name found in >10% of chunks is too common to expand on


def prune_generic_terms(conn: sqlite3.Connection) -> int:
    """Drop manual pairs whose Chinese name is an everyday word (读取->MRD, 连接->CON, 脉冲->MPS).

    Such names expand almost every query and drag the instruction page to the top.
    Curated synonyms are kept: they were written as deliberate mappings.
    """
    total = conn.execute("select count(*) from chunks").fetchone()[0]
    limit = int(total * GENERIC_DF)
    cap = int(total * GENERIC_DF_ANY)
    pruned = 0
    for (term,) in conn.execute("select distinct term from lexicon where kind='manual_pair'").fetchall():
        expr = '"' + " ".join(w for w in jieba.cut(term) if w.strip()).replace('"', '""') + '"'
        try:
            df = conn.execute("select count(*) from (select rowid from fts_seg where fts_seg match ? limit ?)",
                              (expr, cap + 1)).fetchone()[0]
        except sqlite3.OperationalError:
            continue
        if (len(term) <= 2 and df > limit) or df > int(total * GENERIC_DF_ANY):
            conn.execute("delete from lexicon where kind='manual_pair' and term=?", (term,))
            pruned += 1
    return pruned


def build(db: Path) -> dict:
    t0 = time.time()
    conn = sqlite3.connect(db)
    conn.executescript("""
    drop table if exists lexicon;
    drop table if exists fts_tri;
    drop table if exists fts_seg;
    create table lexicon (term TEXT NOT NULL, target TEXT NOT NULL, kind TEXT NOT NULL, source TEXT,
                          df INTEGER);
    create index lexicon_term on lexicon(term);
    create index lexicon_target on lexicon(target);
    """)
    lex = extract_lexicon(conn) + load_synonyms(SYN)
    conn.executemany("insert into lexicon values (?,?,?,?,null)", lex)
    udict = db.parent / "jieba_userdict.txt"
    n_words = build_userdict(conn, lex, udict)
    jieba.load_userdict(str(udict))

    conn.execute("""create virtual table fts_tri using fts5(title, section, text,
                    content='chunks', content_rowid='id', tokenize='trigram')""")
    conn.execute("insert into fts_tri(rowid, title, section, text) select id, title, section, text from chunks")
    t1 = time.time()

    conn.execute("create virtual table fts_seg using fts5(title, section, text, content='', tokenize='unicode61')")
    batch = []
    for cid, title, section, text in conn.execute("select id, title, section, text from chunks").fetchall():
        batch.append((cid, seg(title), seg(section), seg(text)))
        if len(batch) >= 2000:
            conn.executemany("insert into fts_seg(rowid, title, section, text) values (?,?,?,?)", batch)
            batch = []
    if batch:
        conn.executemany("insert into fts_seg(rowid, title, section, text) values (?,?,?,?)", batch)
    conn.execute("insert into fts_tri(fts_tri) values('optimize')")
    conn.execute("insert into fts_seg(fts_seg) values('optimize')")
    stats_generic = prune_generic_terms(conn)
    stats_dead = count_df(conn)
    stats = {"lexicon_generic_pruned": stats_generic, "lexicon_dead_targets": stats_dead,
             "lexicon_manual_pairs": sum(1 for r in lex if r[2] == "manual_pair"),
             "lexicon_curated": sum(1 for r in lex if r[2] == "curated"),
             "userdict_words": n_words, "trigram_s": round(t1 - t0, 1),
             "total_s": round(time.time() - t0, 1)}
    conn.execute("insert or replace into build_meta values ('stage2', ?)", (json.dumps(stats),))
    conn.commit()
    conn.execute("vacuum")
    conn.close()
    return stats


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", type=Path, default=DB)
    print(json.dumps(build(ap.parse_args().db), ensure_ascii=False, indent=1))
