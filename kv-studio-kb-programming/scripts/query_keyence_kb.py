#!/usr/bin/env python3
"""Compatibility wrapper for querying the local KEYENCE LLM Wiki V2 database."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


DEFAULT_HTMLHELP_ROOT = Path(
    r"C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052\htmlhelp"
)
DEFAULT_WIKI_DIR = DEFAULT_HTMLHELP_ROOT / "llm-wiki-v2-keyence"
DEFAULT_DB = DEFAULT_WIKI_DIR / "wiki.v2.cleaned.db"
DEFAULT_QUERY_SCRIPT = DEFAULT_WIKI_DIR / "scripts" / "wiki_query.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Query the local KEYENCE LLM Wiki V2 database used for KV STUDIO work."
    )
    parser.add_argument("keywords", nargs="+", help="Keywords passed through to wiki_query.py.")
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help="Optional KeyenceAgent VM config JSON. Defaults to KEYENCE_AGENT_CONFIG, KV_STUDIO_OPERATOR_CONFIG, or %APPDATA%\\Codex\\kv-studio-operator\\config.json.",
    )
    parser.add_argument("--db", type=Path, default=None, help="Explicit path to an alternate Wiki V2 database.")
    parser.add_argument(
        "--query-script",
        type=Path,
        default=None,
        help="Explicit path to llm-wiki-v2-keyence/scripts/wiki_query.py.",
    )
    parser.add_argument("--limit", type=int, default=5, help="Maximum results to print.")
    parser.add_argument("--graph", action="store_true", help="Include graph-hop results.")
    parser.add_argument("--evidence", action="store_true", help="Print source/evidence oriented output.")
    return parser.parse_args()


def expand_path(value: str | None) -> Path | None:
    if not value:
        return None
    return Path(os.path.expandvars(value))


def candidate_config_paths(explicit_config: Path | None) -> list[Path]:
    candidates: list[Path] = []
    if explicit_config:
        candidates.append(explicit_config)

    for env_name in ["KEYENCE_AGENT_CONFIG", "KV_STUDIO_OPERATOR_CONFIG"]:
        env_path = os.environ.get(env_name)
        expanded = expand_path(env_path)
        if expanded:
            candidates.append(expanded)

    appdata = os.environ.get("APPDATA")
    if appdata:
        candidates.append(Path(appdata) / "Codex" / "kv-studio-operator" / "config.json")

    skill_root = Path(__file__).resolve().parents[2]
    candidates.append(skill_root / "kv-studio-operator" / "config" / "kv-studio-operator.local.json")
    return dedupe(candidates)


def load_config(explicit_config: Path | None) -> dict[str, str]:
    for path in candidate_config_paths(explicit_config):
        if not path.exists():
            continue
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
        return {str(key): str(value) for key, value in data.items() if value is not None}
    return {}


def candidate_roots(config: dict[str, str]) -> list[Path]:
    candidates: list[Path] = []
    env_root = os.environ.get("KEYENCE_WIKI_ROOT") or os.environ.get("KEYENCE_KB_ROOT")
    if env_root:
        root = Path(env_root)
        candidates.extend([root, root / "htmlhelp"])

    config_htmlhelp_root = expand_path(config.get("htmlhelp_root"))
    if config_htmlhelp_root:
        candidates.append(config_htmlhelp_root)

    config_wiki_root = expand_path(config.get("wiki_root"))
    if config_wiki_root:
        candidates.append(config_wiki_root.parent)

    candidates.append(DEFAULT_HTMLHELP_ROOT)

    cwd = Path.cwd().resolve()
    for base in [cwd, *cwd.parents]:
        candidates.append(base)
        candidates.append(base / "htmlhelp")

    return dedupe(candidates)


def candidate_query_scripts(config: dict[str, str]) -> list[Path]:
    candidates: list[Path] = []
    env_path = os.environ.get("KEYENCE_WIKI_QUERY_SCRIPT")
    if env_path:
        candidates.append(Path(env_path))

    config_query_script = expand_path(config.get("wiki_query_script"))
    if config_query_script:
        candidates.append(config_query_script)

    config_wiki_root = expand_path(config.get("wiki_root"))
    if config_wiki_root:
        candidates.append(config_wiki_root / "scripts" / "wiki_query.py")

    candidates.append(DEFAULT_QUERY_SCRIPT)

    for root in candidate_roots(config):
        candidates.append(root / "llm-wiki-v2-keyence" / "scripts" / "wiki_query.py")

    return dedupe(candidates)


def candidate_dbs(query_script: Path | None, config: dict[str, str]) -> list[Path]:
    db_name = "wiki.v2.cleaned.db"
    candidates: list[Path] = []

    env_db = os.environ.get("KEYENCE_WIKI_DB")
    if env_db:
        candidates.append(Path(env_db))

    config_db = expand_path(config.get("wiki_cleaned_db"))
    if config_db:
        candidates.append(config_db)

    config_wiki_root = expand_path(config.get("wiki_root"))
    if config_wiki_root:
        candidates.append(config_wiki_root / db_name)

    candidates.append(DEFAULT_WIKI_DIR / db_name)

    for root in candidate_roots(config):
        candidates.append(root / "llm-wiki-v2-keyence" / db_name)

    if query_script:
        wiki_root = query_script.resolve().parent.parent
        candidates.append(wiki_root / db_name)

    return dedupe(candidates)


def dedupe(paths: list[Path]) -> list[Path]:
    deduped: list[Path] = []
    seen: set[str] = set()
    for path in paths:
        key = str(path).lower()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(path)
    return deduped


def resolve_existing_path(candidates: list[Path]) -> Path | None:
    for path in candidates:
        if path.exists():
            return path
    return None


def main() -> int:
    args = parse_args()
    config = load_config(args.config)

    query_script = args.query_script or resolve_existing_path(candidate_query_scripts(config))
    if query_script is None:
        print(
            "Could not find llm-wiki-v2-keyence/scripts/wiki_query.py. "
            "Set KEYENCE_WIKI_QUERY_SCRIPT or pass --query-script.",
            file=sys.stderr,
        )
        return 1

    db_path = args.db or resolve_existing_path(candidate_dbs(query_script, config))
    if db_path is None:
        print(
            "Could not find wiki.v2.cleaned.db. Set KEYENCE_WIKI_DB or KEYENCE_WIKI_ROOT, "
            "or pass --db.",
            file=sys.stderr,
        )
        return 1

    cmd = [
        sys.executable,
        str(query_script),
        *args.keywords,
        "--db",
        str(db_path),
        "--limit",
        str(args.limit),
    ]
    if args.graph:
        cmd.append("--graph")
    if args.evidence:
        cmd.append("--evidence")

    return subprocess.run(cmd, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
