"""Export the KB's own vocabulary so synonyms are written against real terms.

Output: inventory.tsv  (kind, name, cn_name, aliases, evidence_n)
        pairs.tsv      (cn desc, identifier, df)   manual name<->desc pairs that survived pruning
"""
import os
import re
import sqlite3
from collections import Counter
from pathlib import Path

DB = os.environ.get("KB_DB") or str(Path(__file__).resolve().parent.parent / "dist" / "kb-v3m-2026-11-03" / "wiki.v3m.db")
OUT = Path(r"H:\KeyenceAgent\kb-pipeline\vocab")
OUT.mkdir(exist_ok=True)
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)


def seg_df(term: str) -> int:
    expr = '"' + " ".join(w for w in __import__("jieba").cut(term) if w.strip()) + '"'
    try:
        return c.execute("select count(*) from (select rowid from fts_seg where fts_seg match ? limit 5000)",
                         (expr,)).fetchone()[0]
    except sqlite3.OperationalError:
        return 0


rows = []
for cid, typ, name, cn, al, ev, conf in c.execute(
        "select card_id, type, name, cn_name, aliases, evidence, confidence from cards"):
    evn = len(__import__("json").loads(ev or "[]"))
    rows.append((typ, name, cn or "", " ".join(__import__("json").loads(al or "[]")), evn))
rows.sort(key=lambda r: (r[0], r[1].lower()))
(OUT / "inventory.tsv").write_text(
    "type\tname\tcn_name\taliases\tevidence_n\n" + "\n".join("\t".join(map(str, r)) for r in rows),
    encoding="utf-8")
print("cards by type:", Counter(r[0] for r in rows))
print("wrote", OUT / "inventory.tsv", len(rows), "rows")

# manual pairs still in the lexicon (kind=manual_pair) with document frequency
pairs = []
for term, target in c.execute("select term, target from lexicon where kind='manual_pair'"):
    pairs.append((term, target, seg_df(term)))
pairs.sort(key=lambda r: (-r[2], r[0]))
(OUT / "pairs.tsv").write_text("cn_desc\tidentifier\tdf\n" + "\n".join(
    "\t".join(map(str, r)) for r in pairs), encoding="utf-8")
print("manual pairs:", len(pairs), "->", OUT / "pairs.tsv")

# Chinese section titles, a proxy for how the manuals phrase things
titles = Counter()
for (t,) in c.execute("select title from chunks where source_type!='table'"):
    t = re.sub(r"\s*\((p?\d+[-\d]*)\)\s*$", "", t or "").strip()
    if t and re.search(r"[\u4e00-\u9fff]{2,}", t) and len(t) <= 24:
        titles[t] += 1
(OUT / "titles.tsv").write_text("\n".join(f"{t}\t{n}" for t, n in titles.most_common()),
                                encoding="utf-8")
print("titles:", len(titles), "->", OUT / "titles.tsv")
