# Asset ontology

`ontology.json` is the single source of truth for what the skill can capture and
restore, and it also maps published write routes to their target assets,
prerequisites and repeatable acceptance recipes. Before saying an asset is
"missing", check it here:

- `assets.<id>.snapshot_status`
  - `wired` — snapshot stage produces it
  - `wired_limited` — produced with a documented limitation
  - `not_wired` — capability exists but no snapshot stage yet
  - `missing_route` — no proven read route
- `assets.<id>.snapshot_stage` — must exist in `stages`
- `stages.<id>.producer` — must exist in `capabilities`
- `capabilities.<id>.script` + `evidence` — a capability without evidence is not available

`scripts/gates/assert_kv_asset_coverage.ps1` enforces these rules and runs from
`tests/test_system_layout.ps1` (therefore from `tests/run_all.ps1`).

Write routes live in `write_capabilities`. Their script paths and statuses are
cross-checked against `scripts/script_manifest.json`; targets and dependencies
must resolve, repository evidence must exist, and the dependency graph must be
acyclic. `write_acceptance_recipes` records reproducible end-to-end scenarios
and the evidence required to call them successful. Run
`tests/write-ontology/run.ps1` to verify the mapping and its cycle rejection.

Rule for agents: **a capability that is `not_wired` is not a missing capability.**
Wire the existing workflow/runner first; only use `missing_route` when no proven
route exists and record why.
