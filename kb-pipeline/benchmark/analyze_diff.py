"""Find queries where v3 succeeds but v3m fails, and analyze why."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import search_v3

s3 = search_v3.Searcher(Path('H:/llm-wiki-v2-keyence/v3/wiki.v3.db'))
s3m = search_v3.Searcher(Path('H:/llm-wiki-v2-keyence/v3/wiki.v3m.db'))

cases = [json.loads(l) for l in open('cases_holdout.jsonl', encoding='utf-8')]

misses = []
for c in cases:
    q = c['q']
    expect = set(c.get('expect', []))

    r3 = s3.search(q, k=5)
    r3m = s3m.search(q, k=5)

    hit3 = any(any(e.lower() in (r.get('title','') + r.get('text','')).lower() for e in expect) for r in r3)
    hit3m = any(any(e.lower() in (r.get('title','') + r.get('text','')).lower() for e in expect) for r in r3m)

    if hit3 and not hit3m:
        misses.append({
            'query': q,
            'expect': list(expect),
            'v3_top_id': r3[0]['chunk_id'] if r3 else None,
            'v3_top_title': r3[0].get('title','')[:60] if r3 else None,
            'v3m_top_id': r3m[0]['chunk_id'] if r3m else None,
            'v3m_top_title': r3m[0].get('title','')[:60] if r3m else None,
        })

print(f"{len(misses)} queries where v3 hit but v3m missed (of {len(cases)} total)")
print()
for i, m in enumerate(misses[:5], 1):
    print(f"{i}. {m['query']}")
    print(f"   Expect: {m['expect']}")
    print(f"   v3  top: {m['v3_top_id']} - {m['v3_top_title']}")
    print(f"   v3m top: {m['v3m_top_id']} - {m['v3m_top_title']}")
    print()
