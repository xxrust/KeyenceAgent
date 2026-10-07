param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$source=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/runner_children/create_project_local_guarded.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Create runner parse failed'}
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-BoundCreateControl'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$script:lookups=0
function Find-ChildByAutomationId { $script:lookups++; throw 'Lookup must not occur after foreground rejection' }
function Assert-KvUiForegroundHwnd { param($ExpectedHwnd,$Step); throw 'KV_TEST_WRONG_FOREGROUND' }
$rejected=$false
try { Get-BoundCreateControl ([IntPtr]1234) '1000' 'ControlType.Edit' } catch { $rejected=$_.Exception.Message -eq 'KV_TEST_WRONG_FOREGROUND' }
if(!$rejected -or $script:lookups -ne 0){throw 'Control lookup did not stop on HWND mismatch'}
$calls=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in @('Set-TextById','Select-ComboById','Click-ById')},$true))
foreach($call in $calls){
  if($call.Extent.Text -notmatch '\$(newProjectHwnd|adminHwnd)\b'){throw "Unbound field operation: $($call.Extent.Text)"}
}
$null=New-Item -ItemType Directory -Force -Path $OutDir
@{ok=$true;ui_started=$false;wrong_foreground_rejected_before_lookup=$true;bound_field_operations=$calls.Count}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed wrong-window rejection and $($calls.Count) explicit field bindings"
