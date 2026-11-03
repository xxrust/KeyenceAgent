"""Break a blind-set result down by case family and list the misses with their top hits."""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

rep = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
rows = {r["id"]: r for r in rep["rows"]}
fams = {"b_mo": "motion", "b_in": "instruction", "b_co": "comm", "b_md": "module/basic"}

per = defaultdict(lambda: {"n": 0, "h1": 0, "h5": 0, "mrr": 0.0})
for cid, r in rows.items():
    fam = fams.get(cid[:4], "other")
    d = per[fam]
    d["n"] += 1
    d["h1"] += r["rank"] == 1
    d["h5"] += bool(r["rank"] and r["rank"] <= 5)
    d["mrr"] += 1 / r["rank"] if r["rank"] else 0
print(f"{rep['summary']['ALL']}  {rep['ms_per_query']} ms/q")
print(f"{'family':14}{'n':>4}{'hit@1':>8}{'hit@5':>8}{'mrr':>8}")
for fam, d in sorted(per.items()):
    print(f"{fam:14}{d['n']:>4}{d['h1']/d['n']:>8.3f}{d['h5']/d['n']:>8.3f}{d['mrr']/d['n']:>8.3f}")
print("\nmisses (rank>5 or none):")
for cid, r in rows.items():
    if r["rank"] and r["rank"] <= 5:
        continue
    print(f"\n  {cid}  rank={r['rank']}  {r['q'][:70]}")
    for t in r["top3"][:2]:
        print(f"      {t[:120]}")
