"""Check if document statistics changed between v3 and v3m, affecting BM25/scoring."""
import sqlite3
from kb_paths import control_db, runtime_db

c3 = sqlite3.connect(control_db())
c3m = sqlite3.connect(runtime_db())

print("=== Database statistics ===")
for db, name in [(c3, 'v3'), (c3m, 'v3m')]:
    total = db.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
    avg_len = db.execute("SELECT AVG(length(text)) FROM chunks").fetchone()[0]
    pdf_cnt = db.execute("SELECT COUNT(*) FROM chunks WHERE source_type='pdf'").fetchone()[0]
    mineru_cnt = db.execute("SELECT COUNT(*) FROM chunks WHERE extractor LIKE 'mineru%'").fetchone()[0] if name == 'v3m' else 0

    print(f"\n{name}:")
    print(f"  Total chunks: {total}")
    print(f"  Avg text length: {avg_len:.1f}")
    print(f"  PDF chunks: {pdf_cnt}")
    if name == 'v3m':
        print(f"  MinerU replaced: {mineru_cnt}")

# Check the specific chunk we're looking for
target = '03_32_FBFUN_Motion::chunk-038'
print(f"\n=== Target chunk: {target} ===")
for db, name in [(c3, 'v3'), (c3m, 'v3m')]:
    r = db.execute("SELECT source_type, length(text) FROM chunks WHERE chunk_id=?", (target,)).fetchone()
    if r:
        print(f"{name}: source_type={r[0]}, length={r[1]}")

# Check if there are new chunks in v3m that might be interfering
print(f"\n=== Chunks containing '运动' ===")
for db, name in [(c3, 'v3'), (c3m, 'v3m')]:
    cnt = db.execute("SELECT COUNT(*) FROM chunks WHERE text LIKE '%运动%'").fetchone()[0]
    print(f"{name}: {cnt} chunks")

# Check the top result in v3m that's beating our target
print(f"\n=== Top v3m result analysis ===")
top_v3m = '03_32_FBFUN_Motion::chunk-002#p3'
r = c3m.execute("SELECT title, length(text), substr(text,1,200) FROM chunks WHERE chunk_id=?", (top_v3m,)).fetchone()
if r:
    print(f"chunk_id: {top_v3m}")
    print(f"title: {r[0]}")
    print(f"length: {r[1]}")
    print(f"text preview: {r[2]}...")
