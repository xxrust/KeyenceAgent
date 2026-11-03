"""Test length penalty to suppress overly short chunks in v3m.

Strategy: Add a length multiplier to the final RRF score:
  score *= min(1.0, len(text) / MIN_LEN)

Where MIN_LEN is a threshold below which chunks are penalized.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import search_v3
import kb_search

# Load test cases
dev_cases = [json.loads(l) for l in open('cases.jsonl', encoding='utf-8')]
holdout_cases = [json.loads(l) for l in open('cases_holdout.jsonl', encoding='utf-8')]

def evaluate_with_length_penalty(searcher, cases, min_len, best_rrf_k=45):
    """Evaluate with length penalty applied."""
    # Apply best RRF_K from previous sweep
    original_k = kb_search.RRF_K
    kb_search.RRF_K = best_rrf_k

    hits1, hits5, rr_sum = 0, 0, 0
    for c in cases:
        results = searcher.search(c['q'], k=10)  # Get more candidates
        expect = set(c.get('expect', []))

        # Apply length penalty and re-rank
        for r in results:
            text_len = len(r.get('text', ''))
            penalty = min(1.0, text_len / min_len) if min_len > 0 else 1.0
            r['score'] = r.get('score', 0) * penalty

        # Re-sort after penalty
        results.sort(key=lambda x: x.get('score', 0), reverse=True)

        for rank, r in enumerate(results[:5], 1):
            text = (r.get('title', '') + r.get('text', '')).lower()
            if any(e.lower() in text for e in expect):
                if rank == 1:
                    hits1 += 1
                hits5 += 1
                rr_sum += 1.0 / rank
                break

    kb_search.RRF_K = original_k
    n = len(cases)
    return hits1 / n, hits5 / n, rr_sum / n

print("Testing length penalty on v3m with best RRF_K=45...")
print()

s = search_v3.Searcher(Path('H:/llm-wiki-v2-keyence/v3/wiki.v3m.db'))

# Test different MIN_LEN thresholds
min_len_values = [0, 300, 400, 500, 600, 800, 1000]

results = []
for min_len in min_len_values:
    dev_h1, dev_h5, dev_mrr = evaluate_with_length_penalty(s, dev_cases, min_len)
    hold_h1, hold_h5, hold_mrr = evaluate_with_length_penalty(s, holdout_cases, min_len)

    results.append({
        'min_len': min_len,
        'dev_h1': dev_h1,
        'dev_h5': dev_h5,
        'hold_h1': hold_h1,
        'hold_h5': hold_h5,
        'hold_mrr': hold_mrr,
    })

    print(f"MIN_LEN={min_len:4d}: dev h@5={dev_h5:.3f}, holdout h@1={hold_h1:.3f}, h@5={hold_h5:.3f}, MRR={hold_mrr:.3f}")

print("\n=== Best config ===")
best = max(results, key=lambda x: x['hold_h5'])
print(f"MIN_LEN={best['min_len']}")
print(f"  dev: h@1={best['dev_h1']:.3f}, h@5={best['dev_h5']:.3f}")
print(f"  holdout: h@1={best['hold_h1']:.3f}, h@5={best['hold_h5']:.3f}, MRR={best['hold_mrr']:.3f}")

if best['hold_h5'] >= 0.9:
    print("\n✓ Target achieved!")
else:
    print(f"\nGap to target: {0.9 - best['hold_h5']:.3f}")

# Save results
with open('length_penalty_results.json', 'w', encoding='utf-8') as f:
    json.dump(results, f, indent=2, ensure_ascii=False)
