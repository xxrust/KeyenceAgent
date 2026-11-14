"""Check FTS index and lexicon differences between v3 and v3m."""
import sqlite3
from kb_paths import control_db, runtime_db

c3 = sqlite3.connect(control_db())
c3m = sqlite3.connect(runtime_db())

# Check FTS indexes
print("=== FTS indexes ===")
for db, name in [(c3, 'v3'), (c3m, 'v3m')]:
    print(f"\n{name}:")
    for row in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'fts_%' OR name='chunks'"):
        print(f"  {row[0]}")

# Test a specific query on both - fix column reference
q = "运动中途改目标位置"
print(f"\n=== Testing query: {q} ===")

for db, name in [(c3, 'v3'), (c3m, 'v3m')]:
    print(f"\n{name} FTS results:")
    try:
        # Use rowid instead of chunk_id for FTS virtual table
        results = db.execute("""
            SELECT c.chunk_id, c.title, fts.rank
            FROM fts_seg AS fts
            JOIN chunks AS c ON c.rowid = fts.rowid
            WHERE fts_seg MATCH ?
            ORDER BY rank
            LIMIT 5
        """, (q,)).fetchall()
        if results:
            for r in results[:3]:
                print(f"  {r[0][:50]:50s} {r[1][:40]:40s} rank={r[2]:.2f}")
        else:
            print(f"  No FTS matches")
    except Exception as e:
        print(f"  Error: {e}")

# Check lexicon differences
print(f"\n=== Lexicon ===")
for db, name in [(c3, 'v3'), (c3m, 'v3m')]:
    try:
        count = db.execute("SELECT COUNT(*) FROM lexicon").fetchone()[0]
        # Check actual columns in lexicon
        cols = [r[1] for r in db.execute("PRAGMA table_info(lexicon)")]
        print(f"{name}: {count} entries, columns: {cols}")
        sample = db.execute(f"SELECT * FROM lexicon LIMIT 3").fetchall()
        for s in sample:
            print(f"  {s}")
    except Exception as e:
        print(f"{name}: Error - {e}")
