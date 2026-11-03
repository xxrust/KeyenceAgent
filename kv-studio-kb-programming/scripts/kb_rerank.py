"""Cross-encoder reranker for kb_search.py (optional; needs torch + transformers).

Model: BAAI/bge-reranker-v2-m3 (XLM-R large). Lookup order is the same as kb_vectors:
KB_MODEL_DIR/<repo> > H:/models/<repo> > H:/models/models/<org>--<name>/snapshots/master > HF id.

A cross-encoder reads the query and the passage together, so it can tell "this page is about the
same topic" from "this page answers the question" — which is exactly what the RRF fusion of
independent channels cannot do. It is expensive: ~N forwards per query (N = candidates reranked).
"""
from __future__ import annotations

import os
from pathlib import Path

MODELS = {"bge-reranker-v2-m3": "BAAI/bge-reranker-v2-m3",
          "bge-reranker-base": "BAAI/bge-reranker-base"}


def model_path(name: str) -> str:
    repo = MODELS.get(name, name)
    roots = [os.environ.get("KB_MODEL_DIR"), r"H:\models"]
    for root in roots:
        if not root:
            continue
        for cand in (Path(root) / repo,
                     Path(root) / repo.replace(".", "___"),
                     Path(root) / "models" / repo.replace("/", "--") / "snapshots" / "master",
                     Path(root) / "models" / repo.replace("/", "--") / "snapshots" / "v1.0.0"):
            if (cand / "config.json").exists():
                return str(cand)
    return repo


class Reranker:
    def __init__(self, name: str | None = None, max_length: int = 512):
        import torch
        from transformers import AutoModelForSequenceClassification, AutoTokenizer

        self.name = name or os.environ.get("KB_RERANK_MODEL") or "bge-reranker-v2-m3"
        self.max_length = max_length
        path = model_path(self.name)
        self.tokenizer = AutoTokenizer.from_pretrained(path)
        self.model = AutoModelForSequenceClassification.from_pretrained(path)
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.model.to(self.device).eval()
        if self.device == "cuda":
            self.model.half()
        self.torch = torch

    def score(self, query: str, passages: list[str], batch: int = 16) -> list[float]:
        """sigmoid relevance in [0,1] for each (query, passage) pair."""
        out: list[float] = []
        with self.torch.no_grad():
            for i in range(0, len(passages), batch):
                chunk = passages[i:i + batch]
                enc = self.tokenizer([query] * len(chunk), chunk, padding=True, truncation=True,
                                     max_length=self.max_length, return_tensors="pt").to(self.device)
                logits = self.model(**enc).logits.view(-1).float()
                out += self.torch.sigmoid(logits).tolist()
        return out
