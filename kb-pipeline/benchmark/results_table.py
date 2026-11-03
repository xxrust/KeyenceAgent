"""Print a markdown table from result JSONs: python results_table.py file1.json file2.json ..."""
import json
import sys
from pathlib import Path

rows = []
for p in sys.argv[1:]:
    d = json.loads(Path(p).read_text(encoding="utf-8"))
    s = d["summary"]["ALL"]
    rows.append((d["label"], s["n"], s["hit@1"], s["hit@5"], s["mrr@10"], d["ms_per_query"]))
print("| label | n | hit@1 | hit@5 | MRR | ms/q |")
print("|---|---|---|---|---|---|")
for r in rows:
    print(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} |")
