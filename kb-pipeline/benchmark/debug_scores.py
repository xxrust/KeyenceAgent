"""Debug why the same chunk gets different search scores in v3 vs v3m."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import search_v3

s3 = search_v3.Searcher(Path('H:/llm-wiki-v2-keyence/v3/wiki.v3.db'))
s3m = search_v3.Searcher(Path('H:/llm-wiki-v2-keyence/v3/wiki.v3m.db'))

# Test the failing query
q = "运动中途改目标位置"
target = '03_32_FBFUN_Motion::chunk-038'

print(f"Query: {q}")
print(f"Expected: {target}\n")

for name, s in [('v3', s3), ('v3m', s3m)]:
    print(f"=== {name} ===")
    results = s.search(q, k=10)

    found_rank = None
    for i, r in enumerate(results, 1):
        if r['chunk_id'] == target:
            found_rank = i
            print(f"*** TARGET FOUND at rank {i} ***")
            print(f"  score: {r.get('score', 0):.3f}")
            print(f"  title: {r.get('title', '')}")
            if 'channel_scores' in r:
                print(f"  channel_scores: {r['channel_scores']}")
            break

    if not found_rank:
        print(f"*** TARGET NOT IN TOP 10 ***")
        print("Top 3 results:")
        for i, r in enumerate(results[:3], 1):
            print(f"  {i}. {r['chunk_id'][:50]:50s} score={r.get('score', 0):.3f}")
            print(f"     {r.get('title', '')[:60]}")
    print()
