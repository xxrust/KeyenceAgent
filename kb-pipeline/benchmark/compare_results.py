"""Compare two benchmark result files case by case: which queries were gained / lost.

Usage: python compare_results.py <before.json> <after.json> [--show-top]
"""
import json
import sys
from pathlib import Path


def load(p):
    d = json.loads(Path(p).read_text(encoding="utf-8"))
    return d, {r["id"]: r for r in d["rows"]}


def main():
    before, after = sys.argv[1], sys.argv[2]
    show_top = "--show-top" in sys.argv
    b, br = load(before)
    a, ar = load(after)
    print(f"before {b['label']}  {b['summary']['ALL']}")
    print(f"after  {a['label']}  {a['summary']['ALL']}")
    gained, lost = [], []
    for cid, row in ar.items():
        rb = br.get(cid)
        if not rb:
            continue
        okb = row and rb["rank"] and rb["rank"] <= 5
        oka = row["rank"] and row["rank"] <= 5
        if oka and not okb:
            gained.append((cid, rb["rank"], row["rank"], row["q"]))
        if okb and not oka:
            lost.append((cid, rb["rank"], row["rank"], row["q"]))
    print(f"\ngained {len(gained)}:")
    for cid, r0, r1, q in gained:
        print(f"   + {cid:14} {str(r0):>5} -> {str(r1):>4}  {q}")
    print(f"\nlost {len(lost)}:")
    for cid, r0, r1, q in lost:
        print(f"   - {cid:14} {str(r0):>5} -> {str(r1):>4}  {q}")
        if show_top:
            for t in ar[cid]["top3"]:
                print(f"        {t[:110]}")


if __name__ == "__main__":
    main()
