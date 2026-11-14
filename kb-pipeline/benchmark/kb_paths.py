"""Database paths shared by benchmark utilities.

The shipped runtime database is resolved from ``KB_DB`` or the repository's
``dist`` release. Historical v3 versus v3m comparisons require an explicit
``KB_CONTROL_DB`` because the archived control database is not a runtime
dependency.
"""
from __future__ import annotations

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO_ROOT / "dist" / "kb-v3m-2026-11-03" / "wiki.v3m.db"


def runtime_db() -> Path:
    return Path(os.environ.get("KB_DB") or DEFAULT_DB)


def control_db() -> Path:
    value = os.environ.get("KB_CONTROL_DB")
    if not value:
        raise SystemExit("KB_CONTROL_DB is required for archived v3 comparison utilities")
    return Path(value)
