# MNM Smoke Programming Reference

Use this only for minimal KEYENCE KV STUDIO smoke programs when a fast independent VM test is needed.
It is not a substitute for Wiki V2 evidence or KV STUDIO conversion on real projects.

## Validated Minimal Shape

The following MNM shape was imported/exported and converted successfully in KV STUDIO as a smoke project:

```text
DEVICE:60
;MODULE:CodexMnmType2Smoke
;MODULE_TYPE:2
LD R000
OUT R500
END
ENDH
```

Observed behavior:

- `DEVICE:60` was present in the exported MNM.
- `;MODULE_TYPE:2` was accepted for the module used in the smoke path.
- `LD R000` plus `OUT R500` produced two counted instructions.
- `END` and `ENDH` terminated the program body.
- The acceptance evidence for the original smoke project was KV STUDIO conversion success, not text generation alone.

## Fast Local Generator

Use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill>\scripts\new_mnm_smoke.ps1 `
  -ModuleName CodexMnmSmoke `
  -InputDevice R000 `
  -OutputDevice R500 `
  -OutPath C:\Users\Public\KVSkillPractice\smoke\CodexMnmSmoke.mnm
```

The generator only creates the MNM text. Import and conversion still require KV STUDIO tooling.
