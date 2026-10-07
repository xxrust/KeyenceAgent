# Numeric ST fixture evidence

Wiki V2, H:/llm-wiki-v2-keyence/wiki.v2.cleaned.db, queried 2026-09-20.
Fixture is independently authored and unrelated to the fitting benchmark.

- Query `程序语言`, pdf::KVSUSE::chunk-129, KVSUSE.pdf p432-434:
  domain ST executes on every scan without ladder conditions; executable
  assignments use `:=`; declarations remain in the variable editor.
- Existing same-session evidence wiki_x5_types.json / pdf::KVSHARDX5H::chunk-040,
  p102-103 explicitly lists KV-X520 REAL32 and LREAL64 variable formats.
- Existing same-session wiki_x5_arrays.json / KVSHARDX5H.pdf p104-106:
  arrays support REAL/LREAL elements and integer-index element access;
  read and write every index only within the declared 0..3 range.
- Query `名称不可使用`, pdf::STUse::chunk-133, p302-304:
  declarations must avoid reserved tokens and soft-device-like identifiers.

Expected mathematical values are sampleMean=2.5 and weightedSum=30.
This regression verifies saved source/declarations and native conversion;
it does not claim runtime execution of those expected values.
