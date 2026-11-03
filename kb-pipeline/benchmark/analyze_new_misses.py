"""Analyze which new cases fail and why, to guide synonym additions."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import search_v3

s3 = search_v3.Searcher(Path('H:/llm-wiki-v2-keyence/v3/wiki.v3.db'))

# Load only the new cases
new_cases = [json.loads(l) for l in open('cases_holdout_new.jsonl', encoding='utf-8')]

misses = []
for c in new_cases:
    results = s3.search(c['q'], k=5)
    expect = set(c.get('expect', []))
    hit = any(any(e.lower() in (r.get('title','') + r.get('text','')).lower()
                  for e in expect)
              for r in results)
    if not hit:
        misses.append({
            'id': c['id'],
            'query': c['q'],
            'expect': list(expect),
            'top_result': results[0].get('title', '')[:50] if results else None,
        })

print(f"{len(misses)} of {len(new_cases)} new cases missed in v3 (hit@5={1-len(misses)/len(new_cases):.3f})")
print(f"\nTop failure patterns:")

# Group by missing function type
from collections import Counter
missing_funcs = []
for m in misses:
    missing_funcs.extend(m['expect'])

func_counts = Counter(missing_funcs)
print("\nMost frequently missed functions:")
for func, count in func_counts.most_common(15):
    print(f"  {func}: {count} times")

print(f"\nFirst 20 missed queries:")
for i, m in enumerate(misses[:20], 1):
    print(f"\n{i}. [{m['id']}] {m['query']}")
    print(f"   Expect: {', '.join(m['expect'])}")
    if m['top_result']:
        print(f"   Got: {m['top_result']}")
