# Wiki V2 Evidence

Source database: H:/llm-wiki-v2-keyence/wiki.v2.cleaned.db.
Queried through the installed kv-studio-kb-programming public query entrypoint, with an explicit task-local JSON config selecting wiki_root. No legacy database or historical run was used.

Queries: ANB plus the user's original category phrase; OUT; ENDH. Current independent query output is retained in H:/kvOp/_validation/compose_round1_scan/validation/wiki_anb.json, wiki_out.json and wiki_endh.json.

## LD And ANB

- Source: LD_LDB_AND_ANB_OR_ORB.htm#操作说明.
- Chunk: chm::InstructionRef--KVSREF-FC24CM_021J-LD_LDB_AND_ANB_OR_ORB.htm::chunk-001.
- LD connects a normally open contact to the bus and passes its ON/OFF state to following instructions.
- ANB connects a normally closed contact in series.
- Example source: LD_LDB_AND_ANB_OR_ORB.htm#示例程序, chunk-003; mnemonic example: LD R000 OR DM0 ANB R001 OUT R500. R001 must be OFF for the output to be ON.

## OUT

- Source: 020401_OUT.html#OUT,-OUB-第-1-部分.
- Chunk: chm::KV7REF--24-020401_OUT.html::chunk-001.
- OUT transfers the preceding instruction ON/OFF result to the destination.
- Current instruction reference also returns htmlhelp source 02_01_Instruction_ContactInOut.html, source_anchor TOC_OUT, chunk-005.

## Application

END/ENDH query evidence: `020701_END.html#END,-ENDH-第-1-部分`, chunk `chm::KVPREF--27-020701_END.html::chunk-001`, says the program must contain END and ENDH, and ENDH immediately follows END when no subprogram or interrupt program is present. The current instruction reference also returns `02_05_Instruction_ConnectTerminate.html`, anchor `TOC_END`, chunk `02_05_Instruction_ConnectTerminate::chunk-002`.

LD Enable; ANB Reset; OUT Permit implements Enable AND NOT Reset. LD Permit; OUT Ready transfers Permit to Ready. Both are assigned every scan; no retained latch is requested. Truth table Enable/Reset -> Permit/Ready: 00 -> 00, 01 -> 00, 10 -> 11, 11 -> 00.

The installed programmer new_mnm_smoke.ps1 and operator renderer supply the MNM wrapper and END/ENDH termination. The operator public contract supplies module_type 2, category function_block and declaration layout. Exact project placement, persistence and conversion remain live acceptance requirements.
