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
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "KV-XH DeviceMap" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "KV-XLE buffer memory" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "register map" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
```

If the cleaned database has weak recall, rerun the same query with `wiki.v2.fixed.db`:

```powershell
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "KV-XH DeviceMap" --db .\llm-wiki-v2-keyence\wiki.v2.fixed.db --limit 5 --evidence
```

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
