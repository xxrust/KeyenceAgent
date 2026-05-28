param(
  [Parameter(Mandatory=$true)]
  [string]$ScaffoldRoot,

  [string]$ProjectName = ('KvMultiMnmMvp_' + (Get-Date -Format 'yyyyMMdd_HHmmss')),
  [string]$CpuModel = 'KV-X310',
  [string]$MainModuleName = 'Main_MVP',
  [string]$AuxModuleName = 'Aux_MVP',
  [string]$TaskSummary = 'Two scan-executed MNM modules with merged globals, per-module locals, and compile verification.'
)

$ErrorActionPreference = 'Stop'

$ScaffoldRoot = [IO.Path]::GetFullPath($ScaffoldRoot)
$mnmDir = Join-Path $ScaffoldRoot 'mnm'
$varDir = Join-Path $ScaffoldRoot 'variables'
New-Item -ItemType Directory -Force -Path $ScaffoldRoot, $mnmDir, $varDir | Out-Null

function Write-Text([string]$Path, [string]$Text, [Text.Encoding]$Encoding) {
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($Path, $Text, $Encoding)
}

function New-VariableTsv([object[]]$Rows) {
  $lines = @('scope' + "`t" + 'owner_program' + "`t" + 'name' + "`t" + 'data_type' + "`t" + 'device' + "`t" + 'initial_value' + "`t" + 'comment' + "`t" + 'evidence' + "`t" + 'status')
  foreach ($row in $Rows) {
    $lines += @(
      [string]$row.scope
      [string]$row.owner_program
      [string]$row.name
      [string]$row.data_type
      [string]$row.device
      [string]$row.initial_value
      [string]$row.comment
      [string]$row.evidence
      [string]$row.status
    ) -join "`t"
  }
  return ($lines -join "`r`n") + "`r`n"
}

$mainMnmPath = Join-Path $mnmDir ($MainModuleName + '.mnm')
$auxMnmPath = Join-Path $mnmDir ($AuxModuleName + '.mnm')
$mainGlobalTsv = Join-Path (Join-Path $varDir $MainModuleName) 'global_variables.tsv'
$mainLocalTsv = Join-Path (Join-Path $varDir $MainModuleName) 'local_variables.tsv'
$auxGlobalTsv = Join-Path (Join-Path $varDir $AuxModuleName) 'global_variables.tsv'
$auxLocalTsv = Join-Path (Join-Path $varDir $AuxModuleName) 'local_variables.tsv'

$mainMnm = @"
DEVICE:63
;MODULE:$MainModuleName
;MODULE_TYPE:0
; Multi-MNM MVP main scan module.
LD G_StartCommand
AND G_ReadyPermissive
OUT G_RunCommand
END
ENDH
"@.TrimStart()

$auxMnm = @"
DEVICE:63
;MODULE:$AuxModuleName
;MODULE_TYPE:0
; Multi-MNM MVP auxiliary scan module.
LD G_RunCommand
AND G_JamClear
OUT G_ReadyIndicator
END
ENDH
"@.TrimStart()

Write-Text $mainMnmPath $mainMnm ([Text.Encoding]::Unicode)
Write-Text $auxMnmPath $auxMnm ([Text.Encoding]::Unicode)

$mainGlobalRows = @(
  [pscustomobject]@{ scope='global'; owner_program=''; name='G_StartCommand'; data_type='BOOL'; device=''; initial_value='FALSE'; comment='Start request consumed by the main module.'; evidence='multi_mnm_scaffold'; status='defined' },
  [pscustomobject]@{ scope='global'; owner_program=''; name='G_ReadyPermissive'; data_type='BOOL'; device=''; initial_value='FALSE'; comment='Main-module permissive input.'; evidence='multi_mnm_scaffold'; status='defined' },
  [pscustomobject]@{ scope='global'; owner_program=''; name='G_RunCommand'; data_type='BOOL'; device=''; initial_value='FALSE'; comment='Command bit produced by the main module and consumed by the auxiliary module.'; evidence='multi_mnm_scaffold'; status='defined' }
)
$mainLocalRows = @(
  [pscustomobject]@{ scope='local'; owner_program=$MainModuleName; name='MainWork'; data_type='BOOL'; device=''; initial_value='FALSE'; comment='Main module local work bit verified through local-variable audit.'; evidence='multi_mnm_scaffold'; status='defined' },
  [pscustomobject]@{ scope='local'; owner_program=$MainModuleName; name='MainDiag'; data_type='BOOL'; device=''; initial_value='FALSE'; comment='Main module extra local diagnostic bit for local-variable table coverage.'; evidence='multi_mnm_scaffold'; status='defined' }
)
$auxGlobalRows = @(
  [pscustomobject]@{ scope='global'; owner_program=''; name='G_RunCommand'; data_type='BOOL'; device=''; initial_value='FALSE'; comment='Command bit shared from the main module.'; evidence='multi_mnm_scaffold'; status='defined' },
  [pscustomobject]@{ scope='global'; owner_program=''; name='G_JamClear'; data_type='BOOL'; device=''; initial_value='FALSE'; comment='Auxiliary-module permissive input.'; evidence='multi_mnm_scaffold'; status='defined' },
  [pscustomobject]@{ scope='global'; owner_program=''; name='G_ReadyIndicator'; data_type='BOOL'; device=''; initial_value='FALSE'; comment='Auxiliary-module output indicator.'; evidence='multi_mnm_scaffold'; status='defined' }
)
$auxLocalRows = @(
  [pscustomobject]@{ scope='local'; owner_program=$AuxModuleName; name='AuxWork'; data_type='BOOL'; device=''; initial_value='FALSE'; comment='Auxiliary module local work bit verified through local-variable audit.'; evidence='multi_mnm_scaffold'; status='defined' },
  [pscustomobject]@{ scope='local'; owner_program=$AuxModuleName; name='AuxDiag'; data_type='BOOL'; device=''; initial_value='FALSE'; comment='Auxiliary module extra local diagnostic bit for local-variable table coverage.'; evidence='multi_mnm_scaffold'; status='defined' }
)

Write-Text $mainGlobalTsv (New-VariableTsv $mainGlobalRows) ([Text.Encoding]::Default)
Write-Text $mainLocalTsv (New-VariableTsv $mainLocalRows) ([Text.Encoding]::Default)
Write-Text $auxGlobalTsv (New-VariableTsv $auxGlobalRows) ([Text.Encoding]::Default)
Write-Text $auxLocalTsv (New-VariableTsv $auxLocalRows) ([Text.Encoding]::Default)

$manifest = [ordered]@{
  schema_version = 2
  project = [ordered]@{
    name = $ProjectName
    cpu_model = $CpuModel
    local_program = $MainModuleName
  }
  version = [ordered]@{
    scaffold_version = '2.1.0'
    created_at = (Get-Date).ToString('s')
    template = 'MultiMnmBool'
  }
  task = [ordered]@{
    summary = $TaskSummary
    agent_fill_rule = 'For every mnm_files[] entry, edit that MNM file and its paired variables.global_tsv / variables.local_tsv before running KV STUDIO.'
  }
  checklist = 'CHECKLIST.md'
  mnm_files = @(
    [ordered]@{
      path = ('mnm/' + [IO.Path]::GetFileName($mainMnmPath))
      module_name = $MainModuleName
      module_type = 0
      encoding = 'UTF-16LE'
      variables = [ordered]@{
        global_tsv = ('variables/' + $MainModuleName + '/global_variables.tsv')
        local_tsv = ('variables/' + $MainModuleName + '/local_variables.tsv')
      }
    },
    [ordered]@{
      path = ('mnm/' + [IO.Path]::GetFileName($auxMnmPath))
      module_name = $AuxModuleName
      module_type = 0
      encoding = 'UTF-16LE'
      variables = [ordered]@{
        global_tsv = ('variables/' + $AuxModuleName + '/global_variables.tsv')
        local_tsv = ('variables/' + $AuxModuleName + '/local_variables.tsv')
      }
    }
  )
  variables = [ordered]@{
    schema = 'per_mnm'
    sets = @(
      [ordered]@{
        module_name = $MainModuleName
        global_tsv = ('variables/' + $MainModuleName + '/global_variables.tsv')
        local_tsv = ('variables/' + $MainModuleName + '/local_variables.tsv')
      },
      [ordered]@{
        module_name = $AuxModuleName
        global_tsv = ('variables/' + $AuxModuleName + '/global_variables.tsv')
        local_tsv = ('variables/' + $AuxModuleName + '/local_variables.tsv')
      }
    )
    encoding = 'system-default ANSI'
  }
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ScaffoldRoot 'scaffold.json') -Encoding UTF8

$versionText = @"
# Project Version

Project: $ProjectName
CPU: $CpuModel
Modules: $MainModuleName, $AuxModuleName
Scaffold version: 2.1.0
Template: MultiMnmBool

## Change Notes

- Initial multi-MNM scaffold generated by new_kv_mvp_multi_mnm_scaffold.ps1.
- Both MNM files are scan-executed modules with per-module local variables and merged globals.
"@
Set-Content -LiteralPath (Join-Path $ScaffoldRoot 'VERSION.md') -Value $versionText -Encoding UTF8

$taskText = @"
# Task

$TaskSummary

## Implemented Behavior

- $MainModuleName sets G_RunCommand when G_StartCommand and G_ReadyPermissive are true.
- $AuxModuleName sets G_ReadyIndicator when G_RunCommand and G_JamClear are true.
- Globals are defined in per-module TSV files and merged once by the runner.
- Locals are defined per module and each module owns its own local TSV; use runner AuditVariablePersistence for hard close/reopen/copy evidence.

## Acceptance

- Import both MNM files as scan-executed modules.
- Define merged global variables once.
- Define local variables for $MainModuleName and $AuxModuleName with audit evidence when AuditVariablePersistence is used.
- Compile/convert through KV STUDIO with copied result text showing OK.
"@
Set-Content -LiteralPath (Join-Path $ScaffoldRoot 'TASK.md') -Value $taskText -Encoding UTF8

$checklistText = @"
# KV STUDIO Operation Checklist

Project: $ProjectName
CPU: $CpuModel
Modules: $MainModuleName, $AuxModuleName
Template: MultiMnmBool

## Steps

- [ ] Confirm this scaffold is disposable or explicitly approved for KV STUDIO operation.
- [ ] Confirm scaffold.json contains both MNM entries and each entry has module_type 0.
- [ ] Confirm every MNM file is UTF-16LE and contains ;MODULE_TYPE:0.
- [ ] Confirm $MainModuleName has paired global and local TSV files.
- [ ] Confirm $AuxModuleName has paired global and local TSV files.
- [ ] Confirm executable global variables are referenced by their paired MNM file.
- [ ] Confirm local variable rows use owner_program equal to the target module name.
- [ ] Confirm no operation will type program text directly into the ladder/program editor.

## Required Evidence

- Same-run project creation result.
- Same-run import_mnm_1 and import_mnm_2 results.
- Same-run module placement checks for both modules.
- Same-run variable definition checks for both modules.
- Same-run conversion result copied from KV STUDIO.
"@
Set-Content -LiteralPath (Join-Path $ScaffoldRoot 'CHECKLIST.md') -Value $checklistText -Encoding UTF8

[pscustomobject]@{
  ok = $true
  scaffold_root = $ScaffoldRoot
  manifest = (Join-Path $ScaffoldRoot 'scaffold.json')
  checklist = (Join-Path $ScaffoldRoot 'CHECKLIST.md')
  mnm_files = @($mainMnmPath, $auxMnmPath)
  variable_sets = @(
    [pscustomobject]@{ module_name = $MainModuleName; global_tsv = $mainGlobalTsv; local_tsv = $mainLocalTsv },
    [pscustomobject]@{ module_name = $AuxModuleName; global_tsv = $auxGlobalTsv; local_tsv = $auxLocalTsv }
  )
} | ConvertTo-Json -Depth 5
