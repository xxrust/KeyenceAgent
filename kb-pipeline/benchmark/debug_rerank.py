"""Debug the reranker: compare fusion order vs rerank order on one query, with scores."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "kv-studio-kb-programming" / "scripts"))
import kb_search  # noqa: E402
from kb_paths import runtime_db

DB = runtime_db()
q = sys.argv[1] if len(sys.argv) > 1 else "找零点 原点传感器"
s = kb_search.Searcher(DB)
kb_search.RERANK = True
res = s.search(q, 8, "hybrid")
print("expansions:", s.analyse(q)["expansions"][:12])
print("\n-- after rerank:")
for i, r in enumerate(res, 1):
    print(f"[{i}] {r['score']:>8} {r['title'][:60]} | {(r['source'] or '')[:50]}")

kb_search.RERANK = False
res2 = s.search(q, 8, "hybrid")
print("\n-- fusion only:")
for i, r in enumerate(res2, 1):
    print(f"[{i}] {r['score']:>8} {r['title'][:60]} | {(r['source'] or '')[:50]}")

# score the two lists' chunks side by side
kb_search.RERANK = True
a = s.analyse(q)
ids = list(dict.fromkeys([r["chunk_id"] for r in res2] + [r["chunk_id"] for r in res]))
rowids = [s.conn.execute("select id from chunks where chunk_id=?", (c,)).fetchone()[0] for c in ids]
meta = {r["id"]: r for r in s.conn.execute(
    f"select id, chunk_id, title, section, text from chunks where id in ({','.join('?'*len(rowids))})", rowids)}
passages = [f"{meta[i]['title']} | {meta[i]['section'] or ''} | {(meta[i]['text'] or '')[:900]}" for i in rowids]
from kb_rerank import Reranker
rr = Reranker()
sc = rr.score(q, passages)
print("\n-- raw reranker scores on both lists:")
for i, x in zip(rowids, sc):
    print(f"   {x:.4f}  {meta[i]['title'][:60]}")
