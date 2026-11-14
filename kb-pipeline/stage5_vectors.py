"""Stage 5: dense vectors for non-table chunks and all cards.

- model: bge-m3 by default (multilingual, good Chinese); --model bge-small for a light one
- text embedded: "title | section | text" (chunks) or "name cn_name aliases summary" (cards),
  truncated to --max-len tokens
- stored: <db_dir>/vectors.<db-stem>.<model>.npy (float16, L2-normalised) + ...ids.json,
  and a marker table `vectors(model, n, dim)` so search_v3 knows the channel exists.
  The db stem is in the file name because v3 and v3m live in the same directory; without it
  building v3m would silently overwrite v3's float matrix (kb_vectors still reads the legacy
  vectors.<model>.npy name for databases built before this change).
- a card vector votes for its first evidence chunk (same idea as the card FTS channel)

Tables (address maps) are left to the lexical channels: exact numbers/names, not meaning.
Downloads go through HF_ENDPOINT (defaults to hf-mirror.com when huggingface.co is blocked).
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import time
from pathlib import Path

import numpy as np

DB = Path(os.environ.get("KB_DB") or (Path(__file__).resolve().parent.parent / "dist" / "kb-v3m-2026-11-03" / "wiki.v3m.db"))
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "kv-studio-kb-programming" / "scripts"))
from kb_vectors import MODELS, VectorIndex, load_model  # noqa: E402,F401
os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")


def build(db: Path, model_name: str, max_len: int, batch: int) -> dict:
    t0 = time.time()
    conn = sqlite3.connect(db)
    texts, ids = [], []
    for cid, title, section, text in conn.execute(
            "select id, title, section, text from chunks where source_type not in ('table','htmlnavi_meta')"):
        texts.append(f"{title} | {section} | {text}"[:2000])
        ids.append(cid)
    n_chunks = len(texts)
    chunk_id_to_row = {r[1]: r[0] for r in conn.execute("select id, chunk_id from chunks")}
    for name, cn, aliases, summary, evidence in conn.execute(
            "select name, cn_name, aliases, summary, evidence from cards"):
        ev = [chunk_id_to_row[e] for e in json.loads(evidence or "[]") if e in chunk_id_to_row]
        if not ev:
            continue
        texts.append(f"{name} {cn} {' '.join(json.loads(aliases or '[]'))} {summary}"[:1000])
        ids.append(ev[0])
    model = load_model(model_name)
    model.max_seq_length = max_len
    # sort by length for efficient batching, then restore order
    order = sorted(range(len(texts)), key=lambda i: len(texts[i]))
    vecs = model.encode([texts[i] for i in order], batch_size=batch, normalize_embeddings=True,
                        show_progress_bar=True, convert_to_numpy=True)
    mat = np.zeros_like(vecs)
    mat[order] = vecs
    base = db.parent / f"vectors.{db.stem}.{model_name}"
    np.save(f"{base}.npy", mat.astype(np.float16))
    Path(f"{base}.ids.json").write_text(json.dumps(ids), encoding="utf-8")
    conn.execute("create table if not exists vectors (model TEXT, n INTEGER, dim INTEGER, built TEXT)")
    conn.execute("delete from vectors where model=?", (model_name,))
    conn.execute("insert into vectors values (?,?,?,datetime('now'))", (model_name, len(ids), mat.shape[1]))
    stats = {"model": model_name, "chunks": n_chunks, "cards": len(ids) - n_chunks, "dim": int(mat.shape[1]),
             "max_len": max_len, "elapsed_s": round(time.time() - t0, 1)}
    conn.execute("insert or replace into build_meta values ('stage5_' || ?, ?)", (model_name, json.dumps(stats)))
    conn.commit()
    return stats


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", type=Path, default=DB)
    ap.add_argument("--model", default="bge-m3", choices=sorted(MODELS))
    ap.add_argument("--max-len", type=int, default=512)
    ap.add_argument("--batch", type=int, default=32)
    a = ap.parse_args()
    print(json.dumps(build(a.db, a.model, a.max_len, a.batch), indent=1))
