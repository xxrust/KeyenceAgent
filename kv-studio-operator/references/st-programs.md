# ST Programs and Numeric FBs

Use this route for executable ST with numeric variables, arrays and FB instances.
The BOOL-only `create_kv_complete_module` contract is not a product-language limit.
`create_kv_st_module`, `import_kv_module` and `export_kv_project_mnm` are published
for the verified scope below. Capability status in the manifest is authoritative.

## Product Format

KV STUDIO does not require choosing a separate ST module language when creating
a program. KVSUSE.pdf pp432-434 (`pdf::KVSUSE::chunk-129`) and STUse.pdf pp20-22
describe domain ST: unconditional scan execution without a ladder condition.
`AREA_ST` in MNM is this ST container, not a translation of the algorithm into
ladder instructions. Executable ST source is kept in a separate `.st` file;
MNM exports represent it with one leading semicolon per source line. Preserve the
complete source, including lines beginning with comments. Do not invent a
native-ST creation dialog based on another PLC vendor's conventions.

Use programmer's `scripts/new_kv_st_mnm.ps1` to compare exported source or prepare
offline serialization. Export capability alone does not prove re-import works.
MNM reading restrictions differ between KVS11 and current X-series manuals;
resolve the target version and require actual import evidence. KV-X520 domain ST
was actually imported using `DEVICE:60` and UTF-16LE BOM. The same task with
Windows ANSI encoding did not create a module; do not reuse the BOOL fixture's
DEVICE:63/59 or ANSI encoding for this ST route. Use the pack helper with
`-DeviceCode 60 -OutputEncoding Utf16LE`. `;MODULE_TYPE:0` is a normal program and
`2` a user FB. The header is not itself a declaration of the module category.

## Preparation and Preflight

Prepare every module's source, declaration TSV and KB evidence before UI work.
The existing variable schema supports REAL/LREAL and one-dimensional
`ARRAY[lower..upper] OF` scalar types. Use descriptive names: `FitB` is valid,
bare `B` is reserved, and `C0` resembles a device. The common declaration
validator rejects the documented keyword list and device-like names. Its list
does not claim to contain every instruction or function name; check names that
coincide with instructions/functions in Wiki. Evidence: STUse.pdf pp302-304,
`pdf::STUse::chunk-133`.

Declarations are editor objects, not IEC `VAR...END_VAR` blocks in the ST body.
FB arrays use the documented direction and shape, usually IN-OUT for caller
storage. A call requires a declared instance with data type equal to the FB
name. Pass that actual existing type in `AllowedCustomDataTypes`; the whitelist
does not create or prove the FB exists.

Run `set_kv_variables -PlanOnly` for declaration validation and
`import_kv_module -PlanOnly` for the module envelope, create-only target and
exact parent. These are input/plan gates. The target compiler proves actual
ST syntax and type acceptance; host numerical tests prove a separate layer.

## Compose Existing Interfaces

For a complete new module, use `create_kv_st_module`. It composes the steps below
in one flat plan. This is the contract
shape; omit `arguments_path` for scan programs and use the real existing parent:

```json
{
  "schema_version": 1,
  "module_name": "FB_YourAlgorithm",
  "category": "function_block",
  "parent_path": ["功能块"],
  "source_path": "FB_YourAlgorithm.st",
  "body_path": "FB_YourAlgorithm.mnm",
  "locals_path": "locals.tsv",
  "arguments_path": "arguments.tsv",
  "evidence_paths": ["evidence/wiki.json"]
}
```

Paths resolve relative to the contract. Optional `globals_path` supplies new
global declarations; optional `allowed_custom_data_types` is an array of existing
FB names for caller instances. The gate verifies the saved CPU is KV-X520,
parent uniqueness, absent module, source/MNM identity, UTF-16LE/DEVICE60,
declaration ownership and types, unsupported property rejection, and evidence
fingerprints. Use `status=declared` and name/type TSV schemas from
`variable-editor.md`; include no nonempty initial values, device, retain or
comment properties. FB directions are IN/OUT/IN-OUT. At least one local is
required; do not invent unused state just to pass a gate.

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File <workflow> -ProjectPath <project.kpr> -ContractPath <contract.json> -OutDir <unique-plan-dir> -CreatedProjectResultPath <create_project_result.json> -PlanOnly
```

For execution, use a new output directory and omit PlanOnly. Omit the creation
result parameter for an existing project opened with its exact path. The result
is `workflow_result.json`; final semantic evidence is
`artifacts/verify/st_module_result.json`. The shared plan gate requires declaration
persistence, FB argument readback after locals, conversion, export and exact
source comparison; removing one of these cannot turn an incomplete task into a
successful plan. PlanOnly remains a preparation result.

Standalone `set_kv_variables`, `import_kv_module` and `export_kv_project_mnm`
PlanOnly routes write `execution_plan.json` and `plan_preflight_result.json`;
they do not all emit a planned `workflow_result.json`. The complete ST route
also emits that planned result. Do not infer planning failure solely from the
absence of a file that the selected interface does not promise.

Prepare independent modules and their non-UI checks together; execute desktop
work serially in dependency order. An FB must exist before planning the caller
that declares its instance. For existing single-table or single-body edits, use
the corresponding narrow interface instead of this create-only contract.

Discover each named capability before use. For a new project, retain
`create_kv_project`'s `artifacts/create/create_project_result.json`. A freshly
created Kvs process has no project path on its command line; subsequent import
and direct export accept `CreatedProjectResultPath` to bind the saved path,
PID, process start time and executable identity. Do not restart the application
just to add a command-line project path.

1. Create the target CPU project, or inspect the existing target and declarations.
2. Import each new program/FB through `import_kv_module`, with `ModuleName`,
   `Category=scan|function_block`, exact `ParentPath` where relevant, and its MNM.
   This is create-only; do not delete an existing module to simulate an update.
3. For FBs, set arguments; for every module, set locals. Register globals and
   caller instances before compiling their references. `set_kv_variables`
   performs save/close/reopen persistence checks. Use Append for new globals;
   Replace explicitly overwrites rows from the start and may confirm an overwrite
   dialog. It is not a request to delete every unrelated trailing row.
4. Create the caller ST module with an instance call. For a test driver whose
   behavior requires ordering, create and verify its scan order explicitly.
5. Compile with `compile_kv_project`, read the copied current-run diagnostics,
   and correct the actual sources/declarations before compiling again.
6. Export the current project through `export_kv_project_mnm` without restarting
   or making a Save As copy. Verify each exported ST body against its source,
   plus exact variable name/type and FB name/direction/type after editor reopen.

Conversion can mark the project dirty again after declaration persistence.
The export runner saves the bound project when needed and verifies its exact
title has no unsaved marker before and after export. Complete ST acceptance
requires `project_saved=true` and the clean `final_title` from that same export;
MNM export alone is not proof the project was saved.

Do not use the BOOL verifier that discards semicolon-leading MNM lines for ST:
that would discard the executable program. Retain the source and readback as
reviewable artifacts. A successful import is not evidence of a complete FB;
arguments, locals, caller instance, saved placement and compilation all matter.

After a diagnosed failure, repair the specific cause and validate its correction
before continuing. A completed public variable workflow owns editor cleanup;
an acknowledged error dialog alone does not establish the same final state.
Do not append ad hoc keystrokes between successful workflows.

## Evidence Boundaries

Actual desktop acceptance on KV-X520 / local KVS12:

- Final frozen regression 17: `H:/kvOp/st_quadratic_benchmark_20260920/integration/final_regression/17_st_numeric_scan_20260920_200457_763_35c7ae71`.
- Final frozen regression 18: `H:/kvOp/st_quadratic_benchmark_20260920/integration/final_regression/18_st_numeric_fb_20260920_200718_715_0c34120d`.
- Final save-closure regression 18: `H:/kvOp/st_quadratic_benchmark_20260920/integration/save_closure_regression/18_st_numeric_fb_20260920_202850_537_0cc04dd7`.
- Independent prepared inputs, blank creation, scan, FB, caller, and save-closure follow-up: `H:/kvOp/st_cold_forward_20260920/validation/live-report.md`. The initial pass needed one supervisor-discovered final-save repair; it is not described as an intervention-free completion.
- Complete quadratic project, then Gaussian ST FB and actual caller: `H:/kvOp/st_quadratic_benchmark_20260920/COMPLETION.md`.
- Separate direct scan/FB import and direct export: that benchmark's
  `integration/quadratic_import_live`, `gaussian_fb_import_live`, and `final_export_live`.

These are audit links, not inputs to copy into a new task. Final regression
14/15 also passed after shared import/variable changes. The final complete
workflow verifies declaration result project/module/source identity and rejects
code changes between steps. Read the final `workflow_result.json` for compilation
acceptance; the intermediate module verifier does not claim compiler acceptance.
Optional globals must be new names: preflight does not snapshot all existing
global names, so an existing-name collision may only be rejected during execution.

Report elapsed time, live attempts and operator/framework interventions separately
from algorithm revisions. Independent numerical counterexamples can require
algorithm changes even with a good skill. Never count Python or another host
model as PLC/simulator execution. Do not claim physical I/O, online download or
scan-time performance from saved source and a successful offline compile.
