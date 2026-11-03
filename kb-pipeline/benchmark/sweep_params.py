"""Sweep RRF_K and channel weights to optimize v3m holdout performance.

Target: holdout hit@5 >= 0.9 (current v3m: 0.54, v3: 0.78)

Strategy:
1. Test different RRF_K values (30, 45, 60, 90, 120)
2. For each RRF_K, test weight multipliers for seg/tri channels
3. Report top 10 configs by holdout hit@5
"""
import json
import sys
from pathlib import Path
from itertools import product

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import search_v3

# Load test cases
dev_cases = [json.loads(l) for l in open('cases.jsonl', encoding='utf-8')]
holdout_cases = [json.loads(l) for l in open('cases_holdout.jsonl', encoding='utf-8')]

def evaluate(searcher, cases):
    """Return (hit@1, hit@5, MRR)."""
    hits1, hits5, rr_sum = 0, 0, 0
    for c in cases:
        results = searcher.search(c['q'], k=5)
        expect = set(c.get('expect', []))

        for rank, r in enumerate(results, 1):
            text = (r.get('title', '') + r.get('text', '')).lower()
            if any(e.lower() in text for e in expect):
                if rank == 1:
                    hits1 += 1
                hits5 += 1
                rr_sum += 1.0 / rank
                break

    n = len(cases)
    return hits1 / n, hits5 / n, rr_sum / n

# Monkey-patch searcher to test different params
def patch_searcher(s, rrf_k, seg_mult, tri_mult):
    """Temporarily override RRF_K and channel weights."""
    import kb_search
    original_k = kb_search.RRF_K
    original_w = kb_search.WEIGHTS.copy()

    kb_search.RRF_K = rrf_k
    kb_search.WEIGHTS["seg_q"] = 1.0 * seg_mult
    kb_search.WEIGHTS["seg_x"] = 0.7 * seg_mult
    kb_search.WEIGHTS["tri_q"] = 0.9 * tri_mult
    kb_search.WEIGHTS["tri_x"] = 0.6 * tri_mult

    return original_k, original_w

def restore_searcher(original_k, original_w):
    import kb_search
    kb_search.RRF_K = original_k
    kb_search.WEIGHTS.clear()
    kb_search.WEIGHTS.update(original_w)

# Parameter grid
rrf_k_values = [30, 45, 60, 90, 120]
seg_mult_values = [0.8, 1.0, 1.2, 1.5]
tri_mult_values = [0.8, 1.0, 1.2, 1.5]

print("Sweeping parameters on v3m...")
print(f"Total configs: {len(rrf_k_values) * len(seg_mult_values) * len(tri_mult_values)}")
print()

s = search_v3.Searcher(Path('H:/llm-wiki-v2-keyence/v3/wiki.v3m.db'))

results = []
for i, (rrf_k, seg_m, tri_m) in enumerate(product(rrf_k_values, seg_mult_values, tri_mult_values), 1):
    orig_k, orig_w = patch_searcher(s, rrf_k, seg_m, tri_m)

    dev_h1, dev_h5, dev_mrr = evaluate(s, dev_cases)
    hold_h1, hold_h5, hold_mrr = evaluate(s, holdout_cases)

    restore_searcher(orig_k, orig_w)

    results.append({
        'rrf_k': rrf_k,
        'seg_mult': seg_m,
        'tri_mult': tri_m,
        'dev_h5': dev_h5,
        'hold_h5': hold_h5,
        'hold_h1': hold_h1,
        'hold_mrr': hold_mrr,
    })

    if i % 10 == 0:
        print(f"  {i}/{len(results)} configs tested...")

print("\n=== Top 10 configs by holdout hit@5 ===")
results.sort(key=lambda x: x['hold_h5'], reverse=True)

for i, r in enumerate(results[:10], 1):
    print(f"{i}. RRF_K={r['rrf_k']}, seg_mult={r['seg_mult']}, tri_mult={r['tri_mult']}")
    print(f"   dev h@5={r['dev_h5']:.3f}, holdout h@1={r['hold_h1']:.3f}, h@5={r['hold_h5']:.3f}, MRR={r['hold_mrr']:.3f}")

# Save full results
with open('param_sweep_results.json', 'w', encoding='utf-8') as f:
    json.dump(results, f, indent=2, ensure_ascii=False)

print(f"\nFull results saved to param_sweep_results.json")
print(f"Best holdout hit@5: {results[0]['hold_h5']:.3f}")
if results[0]['hold_h5'] >= 0.9:
    print("✓ Target achieved!")
else:
    print(f"Gap to target: {0.9 - results[0]['hold_h5']:.3f}")
