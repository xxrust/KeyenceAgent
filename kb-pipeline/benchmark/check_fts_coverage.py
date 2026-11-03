"""Check why the same chunk gets different scores in v3 vs v3m."""
import sqlite3

c3 = sqlite3.connect('H:/llm-wiki-v2-keyence/v3/wiki.v3.db')
c3m = sqlite3.connect('H:/llm-wiki-v2-keyence/v3/wiki.v3m.db')

chunk = '03_32_FBFUN_Motion::chunk-038'

print("=== Chunk content comparison ===")
for db, name in [(c3, 'v3'), (c3m, 'v3m')]:
    r = db.execute("SELECT title, length(text), substr(text,1,150) FROM chunks WHERE chunk_id=?", (chunk,)).fetchone()
    if r:
        print(f"{name}: title={r[0]}, len={r[1]}, text={r[2]}...")
    else:
        print(f"{name}: NOT FOUND")

print("\n=== FTS index check ===")
# Check if this chunk is indexed in FTS
for db, name in [(c3, 'v3'), (c3m, 'v3m')]:
    # Get rowid of this chunk
    rowid = db.execute("SELECT rowid FROM chunks WHERE chunk_id=?", (chunk,)).fetchone()
    if rowid:
        # Check if it's in FTS
        fts_seg = db.execute("SELECT COUNT(*) FROM fts_seg WHERE rowid=?", (rowid[0],)).fetchone()[0]
        fts_tri = db.execute("SELECT COUNT(*) FROM fts_tri WHERE rowid=?", (rowid[0],)).fetchone()[0]
        print(f"{name}: rowid={rowid[0]}, in fts_seg={fts_seg}, in fts_tri={fts_tri}")

print("\n=== Total chunk count ===")
for db, name in [(c3, 'v3'), (c3m, 'v3m')]:
    total = db.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
    fts_seg_cnt = db.execute("SELECT COUNT(*) FROM fts_seg").fetchone()[0]
    fts_tri_cnt = db.execute("SELECT COUNT(*) FROM fts_tri").fetchone()[0]
    print(f"{name}: chunks={total}, fts_seg_rows={fts_seg_cnt}, fts_tri_rows={fts_tri_cnt}")
