"""Dense-vector channel for kb_search.py (optional; needs torch + sentence-transformers).

Model lookup order: KB_MODEL_DIR/<org>/<name> > H:/models/<org>/<name> (ModelScope layout)
> Hugging Face id (through HF_ENDPOINT). Vectors live next to the DB as
vectors.<db-stem>.<model>.npy (+ .ids.json), falling back to the legacy vectors.<model>.npy;
table `vectors` in the DB records which models exist.
"""
from __future__ import annotations

import json
import os
import sqlite3
from pathlib import Path

import numpy as np

MODELS = {"bge-m3": "BAAI/bge-m3", "bge-small": "BAAI/bge-small-zh-v1.5", "bge-base": "BAAI/bge-base-zh-v1.5"}
QUERY_PREFIX = {"bge-small": "为这个句子生成表示以用于检索相关文章：",
                "bge-base": "为这个句子生成表示以用于检索相关文章："}


def model_path(name: str) -> str:
    repo = MODELS[name]
    roots = [os.environ.get("KB_MODEL_DIR"), r"H:\models"]
    for root in roots:
        if not root:
            continue
        for cand in (Path(root) / repo, Path(root) / repo.replace(".", "___"),
                     Path(root) / "models" / repo.replace("/", "--") / "snapshots" / "master"):
            if (cand / "config.json").exists():
                return str(cand)
    return repo


def load_model(name: str):
    from sentence_transformers import SentenceTransformer
    import torch
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    m = SentenceTransformer(model_path(name), device=dev)
    if dev == "cuda":
        m.half()
    return m


def active_model(db: Path) -> str | None:
    conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        r = conn.execute("select model from vectors order by rowid desc limit 1").fetchone()
        return r[0] if r else None
    except sqlite3.OperationalError:
        return None
    finally:
        conn.close()


def find_base(db: Path, model: str) -> Path:
    """Vector artefacts are <dir>/vectors.<db-stem>.<model>; older builds used vectors.<model>."""
    for base in (db.parent / f"vectors.{db.stem}.{model}", db.parent / f"vectors.{model}"):
        if Path(f"{base}.npy").exists():
            return base
    raise FileNotFoundError(f"no vector file for {model} next to {db}")


class VectorIndex:
    def __init__(self, db: Path, model: str | None = None):
        self.name = model or active_model(db)
        base = find_base(db, self.name)
        self.mat = np.load(f"{base}.npy").astype(np.float32)
        self.ids = json.loads(Path(f"{base}.ids.json").read_text(encoding="utf-8"))  # chunk row ids
        self.model = load_model(self.name)

    def search(self, q: str, k: int = 200) -> list[int]:
        qv = self.model.encode([QUERY_PREFIX.get(self.name, "") + q], normalize_embeddings=True)[0]
        sims = self.mat @ qv.astype(np.float32)
        order = np.argsort(-sims)[: k * 2]
        out, seen = [], set()
        for i in order:
            cid = self.ids[i]
            if cid not in seen:
                seen.add(cid)
                out.append(cid)
            if len(out) >= k:
                break
        return out
