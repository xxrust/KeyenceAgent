#!/usr/bin/env python3
"""Compatibility wrapper for querying the local KEYENCE LLM Wiki V2 database."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import subprocess
import sys
from pathlib import Path


DEFAULT_HTMLHELP_ROOT = None
DEFAULT_WIKI_DIR = None
DEFAULT_DB = None
DEFAULT_QUERY_SCRIPT = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Query the local KEYENCE LLM Wiki V2 database used for KV STUDIO work."
    )
    parser.add_argument("keywords", nargs="*", help="Keywords passed through to wiki_query.py.")
    parser.add_argument("--chunk-id", help="Read one exact Wiki V2 chunk, including its full body.")
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help="Optional KeyenceAgent VM config JSON. Defaults to KEYENCE_AGENT_CONFIG, KV_STUDIO_OPERATOR_CONFIG, or %%APPDATA%%\\Codex\\kv-studio-operator\\config.json.",
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
    parser.add_argument("--evidence", action="store_true", help="Print source identifiers, checked paths, and full chunk bodies.")
    parser.add_argument("--full", action="store_true", help="Include complete chunk bodies from the read-only Wiki V2 database.")
    parser.add_argument("--json", action="store_true", help="Emit structured results including full chunk bodies.")
    parser.add_argument("--profile", choices=["address", "generic", "module", "network", "programming", "ui"], default="generic")
    parser.add_argument("--source-type", action="append", default=[], help="Restrict retrieval source type; repeat for multiple types.")
    parser.add_argument("--strict", action="store_true", help="Return exit code 2 when a keyword query has no results.")
    args = parser.parse_args()
    if bool(args.keywords) == bool(args.chunk_id):
        parser.error("Supply keywords or --chunk-id, but not both.")
    return args


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
        with path.open("r", encoding="utf-8-sig") as handle:
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

    if DEFAULT_HTMLHELP_ROOT:
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

    if DEFAULT_QUERY_SCRIPT:
        candidates.append(DEFAULT_QUERY_SCRIPT)

    for root in candidate_roots(config):
        candidates.append(root / "scripts" / "wiki_query.py")
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

    if DEFAULT_WIKI_DIR:
        candidates.append(DEFAULT_WIKI_DIR / db_name)

    for root in candidate_roots(config):
        candidates.append(root / db_name)
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


def attach_chunk_bodies(payload: dict, db_path: Path) -> None:
    # Keep retrieval/ranking in wiki_query.py; only hydrate its exact result IDs.
    database = db_path.resolve()
    with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as conn:
        conn.row_factory = sqlite3.Row
        for result in payload["results"]:
            row = conn.execute(
                "SELECT chunk_id, title, source, source_anchor, source_type, path, checksum, chunk "
                "FROM wiki_chunks WHERE chunk_id = ?",
                (result["chunk_id"],),
            ).fetchone()
            if row is None or not str(row["chunk"] or "").strip():
                raise ValueError(f"KV_WIKI_CHUNK_BODY_MISSING: {result['chunk_id']}")
            result.update(dict(row))
            reported_path = str(result.get("resolved_path") or "")
            result["reported_resolved_path"] = reported_path or None
            path_exists = bool(reported_path) and Path(reported_path).is_file()
            result["resolved_path"] = reported_path if path_exists else None
            result["resolved_path_exists"] = path_exists
            result["content_origin"] = {
                "database": str(database),
                "table": "wiki_chunks",
                "chunk_id": row["chunk_id"],
                "read_only": True,
            }


def render_result(payload: dict, full: bool) -> None:
    print(f"database: {payload['database']}")
    if not payload["results"]:
        print("no results")
    for index, row in enumerate(payload["results"], start=1):
        print(f"\n[{index}] {row['title']}")
        for field in ("chunk_id", "source_type", "source", "source_anchor"):
            print(f"{field}: {row.get(field, '')}")
        if full:
            print(f"checksum: {row.get('checksum', '')}")
            print(f"resolved_path: {row.get('resolved_path') or '(no verified local file)'}")
            print(f"content_origin: wiki_chunks, chunk_id={row['chunk_id']} (read-only database above)")
            print(f"body:\n{row['chunk']}")
        else:
            print(f"snippet: {row.get('snippet', '')}")
    if payload.get("graph"):
        print("graph (experimental co-occurrence navigation, not semantic evidence):")
        print(json.dumps(payload["graph"], ensure_ascii=False, indent=2))


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    args = parse_args()
    config = load_config(args.config)

    query_script = args.query_script or resolve_existing_path(candidate_query_scripts(config))
    if query_script is None and not args.chunk_id:
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

    if args.chunk_id:
        payload = {"query": None, "database": str(db_path.resolve()), "results": [{"chunk_id": args.chunk_id}]}
    else:
        cmd = [
            sys.executable, str(query_script), *args.keywords,
            "--db", str(db_path), "--limit", str(args.limit),
            "--profile", args.profile, "--json",
        ]
        if args.graph:
            cmd.append("--graph")
        for source_type in args.source_type:
            cmd.extend(["--source-type", source_type])
        completed = subprocess.run(cmd, check=False, capture_output=True, encoding="utf-8", errors="replace")
        if completed.stderr:
            print(completed.stderr, file=sys.stderr, end="")
        if completed.returncode:
            return completed.returncode
        payload = json.loads(completed.stdout)

    full = bool(args.evidence or args.full or args.json or args.chunk_id)
    if full:
        try:
            attach_chunk_bodies(payload, db_path)
        except (sqlite3.Error, ValueError) as error:
            print(str(error), file=sys.stderr)
            return 2
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        render_result(payload, full)
    return 2 if args.strict and not payload["results"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
