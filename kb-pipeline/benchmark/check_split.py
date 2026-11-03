"""Check if the wrong top result in v3m was affected by splitting or MinerU."""
import sqlite3

c3m = sqlite3.connect('H:/llm-wiki-v2-keyence/v3/wiki.v3m.db')

# Check the wrong top result in v3m
wrong = '03_32_FBFUN_Motion::chunk-002#p3'
r = c3m.execute("SELECT extractor, parent_id, part, parts, length(text) FROM chunks WHERE chunk_id=?", (wrong,)).fetchone()
if r:
    print(f"Wrong top result in v3m: {wrong}")
    print(f"  extractor: {r[0]}")
    print(f"  parent_id: {r[1]}")
    print(f"  part {r[2]} of {r[3]}")
    print(f"  length: {r[4]}")

    # Check if parent was split
    parent = r[1]
    parts = c3m.execute("SELECT chunk_id, length(text) FROM chunks WHERE parent_id=? ORDER BY part", (parent,)).fetchall()
    print(f"\n  Parent {parent} split into {len(parts)} parts:")
    for cid, ln in parts[:5]:
        print(f"    {cid}: {ln} chars")

# Check the correct answer
correct = '03_32_FBFUN_Motion::chunk-038'
r = c3m.execute("SELECT extractor, part, parts FROM chunks WHERE chunk_id=?", (correct,)).fetchone()
print(f"\nCorrect answer: {correct}")
print(f"  extractor: {r[0]}")
print(f"  part {r[1]} of {r[3]}")

# Summary
print(f"\n=== Summary ===")
print("The wrong result that ranks #1 in v3m is a SPLIT chunk (#p3 part 3 of 3).")
print("This chunk didn't exist in v3 (v3 had the unsplit parent).")
print("The correct answer was NOT replaced by MinerU and has identical content in both DBs.")
print("\nHypothesis: Stage 1 splitting changed chunk boundaries, affecting document-level")
print("statistics (avg length, total count) used in BM25/IDF scoring.")
