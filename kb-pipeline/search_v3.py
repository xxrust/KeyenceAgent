"""Shim: the runtime searcher lives in the skill (kv-studio-kb-programming/scripts/kb_search.py)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "kv-studio-kb-programming" / "scripts"))
from kb_search import *  # noqa: F401,F403
from kb_search import Searcher, main  # noqa: F401

if __name__ == "__main__":
    sys.exit(main())
