# Numeric ST FB fixture evidence

Wiki V2, H:/llm-wiki-v2-keyence/wiki.v2.cleaned.db, queried 2026-09-20.
Fixture is independently authored and unrelated to the fitting benchmark.

- `pdf::STUse::chunk-019`, STUse.pdf p46-52, checksum
  c79f33b8f3835ab6d3090d28ee5094f23ef1def93c8bbc21040e04a232aff103:
  FB may contain ST; calling an FB requires a declared variable of its type.
- `pdf::KVSHARDX5H::chunk-040`, p102-103: KV-X520 supports REAL and LREAL.
  Same-session wiki_x5_arrays evidence permits REAL array elements and
  INT-index access. The fixture only accesses indices 0..3.
- `chm::KVSST--chmfiles-NewLanguage_Script_06_01-FBSTRT.htm::chunk-001`:
  IN and IN-OUT named binding uses `:=`, OUT uses `=>`; directions are
  registered separately from executable ST. This fixture has no FBSTRT call.
- `pdf::STUse::chunk-133`, p302-304: reserved-name restrictions.

Samples is IN-OUT to transfer an array and is never written. Enable FALSE
clears Sum/Mean/Valid; TRUE computes gain-scaled sum and mean. Exact source,
argument direction/type/name, locals and native compile are acceptance targets.
Standalone FB conversion does not establish caller invocation or PLC runtime.
