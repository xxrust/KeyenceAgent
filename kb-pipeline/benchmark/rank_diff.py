"""List cases whose rank changed (default: got worse), with the new top-3 for inspection."""
import json
import sys
from pathlib import Path


def load(p):
    d = json.loads(Path(p).read_text(encoding="utf-8"))
    return d, {r["id"]: r for r in d["rows"]}


before, after = sys.argv[1], sys.argv[2]
want = sys.argv[3] if len(sys.argv) > 3 else "worse"
b, br = load(before)
a, ar = load(after)
print(f"before {b['summary']['ALL']}\nafter  {a['summary']['ALL']}")
for cid, row in ar.items():
    rb = br.get(cid)
    if not rb:
        continue
    r0, r1 = rb["rank"], row["rank"]
    worse = (r0 or 99) < (r1 or 99)
    if (want == "worse" and not worse) or (want == "better" and worse):
        continue
    if r0 == r1:
        continue
    print(f"\n{cid:14} {r0} -> {r1}   {row['q']}")
    for i, t in enumerate(row["top3"], 1):
        print(f"    {i}. {t[:120]}")
        if i == 1:
            print(f"    was: {rb['top3'][0][:120]}")
