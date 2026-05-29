param(
  [Parameter(Mandatory=$true)]
  [string]$ScaffoldRoot,

  [string]$ProjectName = ('KvMvp_' + (Get-Date -Format 'yyyyMMdd_HHmmss')),
  [string]$CpuModel = 'KV-X310',
  [string]$ModuleName = 'Main_MVP',
  [ValidateSet('Minimal','TrafficLight')]
  [string]$Template = 'Minimal',
  [string]$TaskSummary = 'Describe the PLC task here.'
)

$ErrorActionPreference = 'Stop'

$ScaffoldRoot = [IO.Path]::GetFullPath($ScaffoldRoot)
$moduleDir = Join-Path (Join-Path $ScaffoldRoot 'modules') $ModuleName
New-Item -ItemType Directory -Force -Path $ScaffoldRoot, $moduleDir | Out-Null

function Write-Text([string]$Path, [string]$Text, [Text.Encoding]$Encoding) {
  [IO.File]::WriteAllText($Path, $Text, $Encoding)
}

function New-Cn([int[]]$CodePoints) {
  -join ($CodePoints | ForEach-Object { [char]$_ })
}

$mnmPath = Join-Path $moduleDir ($ModuleName + '.mnm')
$globalTsv = Join-Path $moduleDir 'global_variables.tsv'
$localTsv = Join-Path $moduleDir 'local_variables.tsv'

if ($Template -eq 'TrafficLight') {
  $cnStart = New-Cn @(0x542F,0x52A8)
  $cnRedLed = (New-Cn @(0x7EA2)) + 'LED' + (New-Cn @(0x706F))
  $cnYellowLed = (New-Cn @(0x9EC4)) + 'LED' + (New-Cn @(0x706F))
  $cnGreenLed = (New-Cn @(0x7EFF)) + 'LED' + (New-Cn @(0x706F))
  $cnState = New-Cn @(0x72B6,0x6001)
  $cnCount = New-Cn @(0x8BA1,0x6570)

  $mnmText = @"
DEVICE:63
;MODULE:$ModuleName
;MODULE_TYPE:0
AREA_ST
;// MVP traffic light program.
;// Input display name: $cnStart
;// Output display names: $cnRedLed, $cnYellowLed, $cnGreenLed
;// Local display names: $cnState, $cnCount
;// Executable identifiers stay ASCII for KV STUDIO parser compatibility.
;IF StartIn = 0 THEN
;    RedLed := 1;
;    YellowLed := 0;
;    GreenLed := 0;
;    State := 0;
;    Count := 0;
;ELSE
;    Count := Count + 1;
;    CASE State OF
;        0:
;            RedLed := 1;
;            YellowLed := 0;
;            GreenLed := 0;
;            IF Count >= 100 THEN
;                Count := 0;
;                State := 1;
;            END_IF;
;        1:
;            RedLed := 0;
;            YellowLed := 0;
;            GreenLed := 1;
;            IF Count >= 100 THEN
;                Count := 0;
;                State := 2;
;            END_IF;
;        2:
;            RedLed := 0;
;            YellowLed := 1;
;            GreenLed := 0;
;            IF Count >= 30 THEN
;                Count := 0;
;                State := 0;
;            END_IF;
;        ELSE
;            State := 0;
;            Count := 0;
;    END_CASE;
;END_IF;
END
ENDH
"@.TrimStart()

  $globalText = @"
scope	owner_program	name	data_type	device	initial_value	comment	evidence	status
global		$cnStart	BOOL		FALSE	Input display name requested by task; executable sample uses direct device R000.	scaffold	display_name
global		$cnRedLed	BOOL		FALSE	Output display name requested by task; executable sample uses direct device R500.	scaffold	display_name
global		$cnYellowLed	BOOL		FALSE	Output display name requested by task; executable sample reserves R501 in task notes.	scaffold	display_name
global		$cnGreenLed	BOOL		FALSE	Output display name requested by task; executable sample reserves R502 in task notes.	scaffold	display_name
global		G_StartIn	INT		0	Generic executable input placeholder for the start signal.	scaffold	defined
global		G_RedLed	INT		0	Generic executable output placeholder for the red lamp.	scaffold	defined
global		G_YellowLed	INT		0	Generic executable output placeholder for the yellow lamp.	scaffold	defined
global		G_GreenLed	INT		0	Generic executable output placeholder for the green lamp.	scaffold	defined
"@

  $localText = @"
scope	owner_program	name	data_type	device	initial_value	comment	evidence	status
local	$ModuleName	State	INT		0	ASCII execution local state: 0=red, 1=green, 2=yellow.	scaffold	defined
local	$ModuleName	Count	INT		0	ASCII execution scan counter.	scaffold	defined
local	$ModuleName	StartIn	UINT		0	ASCII execution alias for start input.	scaffold	defined
local	$ModuleName	RedLed	UINT		0	ASCII execution alias for red output.	scaffold	defined
local	$ModuleName	YellowLed	UINT		0	ASCII execution alias for yellow output.	scaffold	defined
local	$ModuleName	GreenLed	UINT		0	ASCII execution alias for green output.	scaffold	defined
local	$ModuleName	$cnState	INT		0	Local display name requested by task.	scaffold	display_name
local	$ModuleName	$cnCount	INT		0	Local display name requested by task.	scaffold	display_name
"@
} else {
  $mnmText = @"
DEVICE:63
;MODULE:$ModuleName
;MODULE_TYPE:0
; Minimal BOOL scaffold program. Replace these mnemonics for the task.
LD G_Input
OUT G_Output
END
ENDH
"@.TrimStart()

  $globalText = @"
scope	owner_program	name	data_type	device	initial_value	comment	evidence	status
global		G_Input	BOOL		FALSE	Generic global input placeholder.	scaffold	defined
global		G_Output	BOOL		FALSE	Generic global output placeholder.	scaffold	defined
"@

  $localText = @"
scope	owner_program	name	data_type	device	initial_value	comment	evidence	status
local	$ModuleName	Work	BOOL		FALSE	Generic local working bit.	scaffold	defined
local	$ModuleName	Result	BOOL		FALSE	Generic local result bit.	scaffold	defined
"@
}

Write-Text $mnmPath $mnmText ([Text.Encoding]::Unicode)
Write-Text $globalTsv $globalText ([Text.Encoding]::Default)
Write-Text $localTsv $localText ([Text.Encoding]::Default)

$manifest = [ordered]@{
  schema_version = 2
  project = [ordered]@{
    name = $ProjectName
    cpu_model = $CpuModel
    local_program = $ModuleName
  }
  version = [ordered]@{
    scaffold_version = '2.0.0'
    created_at = (Get-Date).ToString('s')
    template = $Template
  }
  task = [ordered]@{
    summary = $TaskSummary
    agent_fill_rule = 'For every mnm_files[] entry, edit that module folder MNM file and its paired variables.global_tsv / variables.local_tsv before running KV STUDIO.'
  }
  checklist = 'CHECKLIST.md'
  mnm_files = @(
    [ordered]@{
      path = ('modules/' + $ModuleName + '/' + [IO.Path]::GetFileName($mnmPath))
      module_name = $ModuleName
      module_type = 0
      category = 'scan'
      device = 63
      encoding = 'UTF-16LE'
      variables = [ordered]@{
        global_tsv = ('modules/' + $ModuleName + '/global_variables.tsv')
        local_tsv = ('modules/' + $ModuleName + '/local_variables.tsv')
      }
    }
  )
  variables = [ordered]@{
    schema = 'per_mnm'
    sets = @(
      [ordered]@{
        module_name = $ModuleName
        category = 'scan'
        global_tsv = ('modules/' + $ModuleName + '/global_variables.tsv')
        local_tsv = ('modules/' + $ModuleName + '/local_variables.tsv')
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
Primary module: $ModuleName
Scaffold version: 2.0.0
Template: $Template

## Change Notes

- Initial scaffold generated by new_kv_mvp_scaffold.ps1.
- Agent updates this file when task logic, variables, IO mapping, or acceptance criteria change.
"@
Set-Content -LiteralPath (Join-Path $ScaffoldRoot 'VERSION.md') -Value $versionText -Encoding UTF8

$taskText = @"
# Task

$TaskSummary

## Agent Workflow

1. Read scaffold.json.
2. Edit modules/<module>/*.mnm for program logic.
3. Edit each module's paired modules/<module>/global_variables.tsv and modules/<module>/local_variables.tsv.
4. Update TASK.md and VERSION.md with the implemented behavior and version note.
5. Run run_kv_mvp_scaffold.ps1 against this scaffold.
"@
Set-Content -LiteralPath (Join-Path $ScaffoldRoot 'TASK.md') -Value $taskText -Encoding UTF8

$checklistText = @"
# KV STUDIO Operation Checklist

Project: $ProjectName
CPU: $CpuModel
Primary module: $ModuleName
Template: $Template

## Steps

- [ ] Confirm this scaffold is disposable or explicitly approved for KV STUDIO operation.
- [ ] Confirm scaffold.json project name, CPU model, module name, and MNM file list.
- [ ] Confirm every modules/<module>/*.mnm file has the intended ;MODULE_TYPE and program body.
- [ ] Confirm every mnm_files[] entry has a paired variables.global_tsv and variables.local_tsv.
- [ ] Confirm each module's global TSV contains the global variables required by that MNM module, or only the TSV header when that module has no global variables.
- [ ] Confirm each module's local TSV contains executable local variables for that module/program.
- [ ] Confirm local variables are intended for the module/program that KV STUDIO will show in the local-variable selector.
- [ ] Confirm the acceptance gate includes module placement, variable definition verification, and copied conversion result text.
- [ ] Confirm no operation will type program text directly into the ladder/program editor.

## Required Evidence

- Same-run project creation result.
- Same-run MNM import result.
- Same-run module placement check.
- Same-run variable definition check.
- Same-run conversion result copied from KV STUDIO.
"@
Set-Content -LiteralPath (Join-Path $ScaffoldRoot 'CHECKLIST.md') -Value $checklistText -Encoding UTF8

[pscustomobject]@{
  ok = $true
  scaffold_root = $ScaffoldRoot
  manifest = (Join-Path $ScaffoldRoot 'scaffold.json')
  checklist = (Join-Path $ScaffoldRoot 'CHECKLIST.md')
  mnm_files = @($mnmPath)
  variable_sets = @(
    [pscustomobject]@{
      module_name = $ModuleName
      global_tsv = $globalTsv
      local_tsv = $localTsv
    }
  )
} | ConvertTo-Json -Depth 4
