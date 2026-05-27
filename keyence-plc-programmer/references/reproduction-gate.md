# Official Reference Reproduction Gate

Use this checklist before claiming that a KEYENCE official reference program has been reproduced.

## Prompt-To-Artifact Checklist

Map each requested requirement to evidence:

- Requested CPU/model -> project setting or screenshot/log evidence.
- Requested units -> unit configuration evidence.
- Official reference behavior -> inspected reference programs, variables, and device maps.
- Official FB allowance -> list of directly imported FBs and their source package.
- Recreated user logic -> MNM files authored or edited by the agent.
- Variables -> global/local variable manifest and KV STUDIO variable editor reconstruction.
- Compile -> Ctrl+F2 pass evidence.

## Valid Reproduction Evidence

The result must show:

1. The target project is not the official reference folder copied or renamed.
2. Official FBs may be imported from `All.pregx` or an official package.
3. Program logic other than official FBs entered the project via MNM import or deliberate UI authoring.
4. Variables are recreated in KV STUDIO, including local variables and FB instances.
5. Ctrl+F2 compile/convert passes.
6. The program inventory matches the reference intent: modules, scan/task placement, major state transitions, and device interactions.

## Invalid Shortcuts

Reject the result if:

- The complete official project was copied.
- The complete official program package was imported and only renamed.
- Compile errors remain.
- Missing variables are ignored.
- Program logic is substantially absent but compile passes because reference behavior was removed.

## Iteration Loop

1. Compile with Ctrl+F2.
2. Copy all error messages from the conversion/error window.
3. Categorize errors as missing variable, missing FB type, device/map issue, syntax issue, or scope/type mismatch.
4. Fix variables before changing logic when the error is name/scope/type related.
5. Re-import MNM only after updating the manifest.
6. Repeat until compile passes.
