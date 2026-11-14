"""List the missed holdout queries to understand what types of questions fail."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import search_v3
from kb_paths import runtime_db

s = search_v3.Searcher(runtime_db())
cases = [json.loads(l) for l in open('cases_holdout.jsonl', encoding='utf-8')]

misses = []
for c in cases:
    results = s.search(c['q'], k=5)
    expect = set(c.get('expect', []))
    hit = any(any(e.lower() in (r.get('title','') + r.get('text','')).lower()
                  for e in expect)
              for r in results)
    if not hit:
        misses.append({
            'id': c.get('id', ''),
            'query': c['q'],
            'expect': list(expect),
            'top_result': results[0]['chunk_id'][:60] if results else None,
        })

print(f"{len(misses)} of {len(cases)} holdout queries missed (hit@5={1-len(misses)/len(cases):.3f})")
print(f"Need to improve by {len(misses) - int(len(cases)*0.1)} misses to reach 0.9 target\n")

print("Missed queries:")
for i, m in enumerate(misses, 1):
    print(f"\n{i}. [{m['id']}] {m['query']}")
    print(f"   Expect: {', '.join(m['expect'])}")
    if m['top_result']:
        print(f"   Got instead: {m['top_result']}")
