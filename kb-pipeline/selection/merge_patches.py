"""Merge verifier patches (patches/*.json) into the CSVs. Idempotent.

- status corrected/new -> write `new` into the field (field not a column -> appended to notes as "字段: 值")
- status confirmed     -> no value change
- status unreadable    -> value untouched; reason appended to notes once
- every row that got a confirmed/corrected/new patch gets one "✔PDF核实(<patch file>: <sources>)" marker in notes
  (the page counts rows carrying "✔PDF核实")
"""
import csv
import json
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
FILES = ["cpu.csv", "motion_units.csv", "io_units.csv", "special_units.csv"]


def load(name):
    rows = list(csv.DictReader(open(HERE / name, encoding="utf-8-sig")))
    return rows, list(rows[0].keys())


def save(name, rows, cols):
    with open(HERE / name, "w", encoding="utf-8-sig", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)


def main():
    data = {f: load(f) for f in FILES}
    index = {f: {r["model"]: r for r in data[f][0]} for f in FILES}
    stats = defaultdict(int)
    missing = []
    for pf in sorted((HERE / "patches").glob("*.json")):
        patches = json.loads(pf.read_text(encoding="utf-8"))
        sources = defaultdict(set)      # (file, model) -> {source}
        for p in patches:
            f, m = p.get("file"), p.get("model")
            if f not in index or m not in index[f]:
                missing.append((pf.name, f, m))
                continue
            row = index[f][m]
            cols = data[f][1]
            st = p.get("status")
            stats[st] += 1
            if st in ("corrected", "new") and p.get("new"):
                fld = p["field"]
                if fld in cols and fld not in ("model", "evidence"):
                    row[fld] = p["new"]
                else:
                    tag = f"{fld}: {p['new']}"
                    if tag not in row["notes"]:
                        row["notes"] = (row["notes"] + "; " if row["notes"] else "") + tag
            if st == "unreadable":
                tag = f"[待核实 {p.get('field')}: {p.get('note') or p.get('source','')}]"
                if tag not in row["notes"]:
                    row["notes"] = (row["notes"] + "; " if row["notes"] else "") + tag
            if st in ("confirmed", "corrected", "new"):
                sources[(f, m)].add(p.get("source", "").split("(")[0].strip() or pf.stem)
        for (f, m), srcs in sources.items():
            row = index[f][m]
            marker = f"✔PDF核实({pf.stem}: {', '.join(sorted(srcs))[:160]})"
            if f"✔PDF核实({pf.stem}:" not in row["notes"]:
                row["notes"] = (row["notes"] + "; " if row["notes"] else "") + marker
    # output-only units have no input polarity: that is "not applicable", not "not found"
    for r in data["io_units.csv"][0]:
        if not r["in_points"].strip() and "未找到" in r["input_type"]:
            r["input_type"] = "不适用(纯输出单元)"
    for f in FILES:
        save(f, *data[f])
    print(dict(stats), "unmatched:", missing[:10], len(missing))


if __name__ == "__main__":
    main()
