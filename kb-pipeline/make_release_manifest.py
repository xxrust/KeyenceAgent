"""Build MANIFEST.json for the knowledge-base release package (run from the repo)."""
import datetime
import hashlib
import json
import os
import sqlite3
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
D = Path(os.environ.get("KB_RELEASE_DIR") or (REPO / "dist" / "kb-v3m-2026-11-03"))

files = []
for p in sorted(D.iterdir()):
    if p.suffix == ".zip" or p.name.startswith("MANIFEST"):
        continue
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    files.append({"name": p.name, "bytes": p.stat().st_size, "sha256": h.hexdigest()})

conn = sqlite3.connect(f"file:{D / 'wiki.v3m.db'}?mode=ro", uri=True)
by_type = dict(conn.execute("select source_type, count(*) from chunks group by 1 order by 2 desc"))
cards = dict(conn.execute("select type, count(*) from cards group by 1 order by 2 desc"))
vec = conn.execute("select model, n, dim from vectors").fetchall()
commit = subprocess.run(["git", "-C", str(REPO), "rev-parse", "HEAD"],
                        capture_output=True, text=True).stdout.strip()
man = {
    "name": "KEYENCE KV STUDIO 知识库 Wiki V3m",
    "version": "v3m-2026-11-03",
    "built_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "git_commit": commit,
    "chunks_total": sum(by_type.values()),
    "chunks_by_source_type": by_type,
    "cards_by_type": cards,
    "vectors": [{"model": m, "rows": n, "dim": dim} for m, n, dim in vec],
    "synonyms_pairs": 1683,
    "embedding_model": "BAAI/bge-m3 (1024 dim)",
    "benchmark_hit5": {"cases_holdout_50": 0.98, "blind_120": 0.90, "sealed_60": 0.833},
    "files": files,
}
(D / "MANIFEST.json").write_text(json.dumps(man, ensure_ascii=False, indent=1), encoding="utf-8")
print(json.dumps(man, ensure_ascii=False, indent=1)[:1200])
