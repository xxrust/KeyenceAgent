"""Debug why a query works in v3 but not v3m by tracing the full search path."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import search_v3
from kb_paths import control_db, runtime_db

s3 = search_v3.Searcher(control_db())
s3m = search_v3.Searcher(runtime_db())

q = "运动中途改目标位置"
print(f"Query: {q}\n")

for name, s in [('v3', s3), ('v3m', s3m)]:
    print(f"=== {name} ===")
    results = s.search(q, k=3)
    for i, r in enumerate(results, 1):
        print(f"{i}. {r['chunk_id'][:50]:50s} score={r.get('score', 0):.3f}")
        print(f"   {r.get('title', '')[:60]}")
        if 'channels' in r:
            print(f"   channels: {r['channels']}")
    print()

# Check if the expected chunk exists in both DBs
expected = '03_32_FBFUN_Motion::chunk-038'
print(f"Expected chunk: {expected}")
for name, s in [('v3', s3), ('v3m', s3m)]:
    r = s.db.execute("SELECT title, substr(text,1,200) FROM chunks WHERE chunk_id=?", (expected,)).fetchone()
    if r:
        print(f"{name}: EXISTS - {r[0]}")
        print(f"     Text: {r[1][:100]}...")
    else:
        print(f"{name}: NOT FOUND")
