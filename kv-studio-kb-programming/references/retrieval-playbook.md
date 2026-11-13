# Retrieval Playbook

Use this file when the first Wiki V2 query is weak, noisy, or ambiguous.

## Source Intent

- `htmlhelp` and `chm`: Prefer for instruction syntax, ST language rules, FB/FUN signatures, and editor-facing semantics.
- `table`: Prefer for `DeviceMap`, soft-device allocation, relay maps, buffer memory, and address lookup.
- `dockinghelp`: Prefer for motion parameter-help fragments and compact motion descriptions.
- `pdf`: Prefer for broader operational constraints, timing notes, examples, and hardware manuals.
- `htmlnavi_meta`: Use only as a pointer to manuals or navigation.

## Query Templates

### ST and syntax

- `assignment statement`
- `ST data type`
- exact token plus context, such as `TON timer`, `MOV ST`, `END ST`

For numeric ST, a concrete conversion such as `REAL_TO_LREAL` may be documented
under the generic `*_TO_**` conversion entry. Read that entry's supported source
and destination types before using the concrete spelling. For loop syntax,
`END_FOR` with source type `chm` distinguishes ST `FOR/END_FOR` from older
Script `FOR/NEXT` results. Do not treat a missing exact-name hit as proof that
the language lacks the operation.

MNM/ST import restrictions vary by KV STUDIO generation. Keep the manual's
version and CPU context when comparing KVS11 with current X-series documents;
an export description is not import evidence. Operator's maintained ST route
records the actual tested version/encoding and desktop acceptance.

### Ladder and instruction behavior

- exact instruction name first: `END`, `ENDH`, `OUT`, `SET`, `RST`
- then semantic follow-up: `scan end`, `interrupt program`, `execution condition`

### Device map and addresses

- module plus `DeviceMap`
- module plus `buffer memory`
- module plus `soft-device allocation`
- user wording plus `device map` or `register map`

Examples:

```powershell
python .\kv-studio-kb-programming\scripts\kb_search.py "KV-XH DeviceMap" -k 5
python .\kv-studio-kb-programming\scripts\kb_search.py "KV-XLE buffer memory" -k 5
python .\kv-studio-kb-programming\scripts\kb_search.py "register map" -k 5
```

There is exactly one runtime library (`dist/kb-v3m-*/wiki.v3m.db`); `kb_search.py` resolves it
without `--db`. If recall is weak, rewrite the query as exact identifiers plus short semantic
phrases and compare evidence by source type. Switching databases is no longer an option: the
Wiki V2 cleaned DB and `wiki.v3.db` were deleted on 2026-11-14.

### Motion and positioning

- use intent terms such as `action enable`, `target coordinate`, `origin return`, `deceleration stop`
- include module family when known: `KV-XH action enable`, `KV-ML_MC target coordinate`

### Communication

- `socket communication`
- exact FB/FUN names: `SocketTCP_ActiveOpen`, `SocketTCP_Send`
- protocol names with KEYENCE terms: `EtherNet/IP`, `Modbus`

## Query Discipline

Run multiple short queries instead of one long sentence.

Recommended order:

1. exact instruction or module token
2. user wording
3. mixed exact plus semantic term

If results still conflict:

1. narrow by module family
2. narrow by language mode
3. compare `htmlhelp/chm` against `pdf`

## Synthesis Rules

- Use at least one syntax-oriented source and one context-oriented source for non-trivial answers.
- For address questions, require a `table` result unless the KB clearly states the mapping elsewhere.
- For execution behavior, prefer direct manual wording from `htmlhelp`, `chm`, or `pdf`, not navigation entries.
- If the KB cannot disambiguate a CPU or module family, state the ambiguity explicitly.
