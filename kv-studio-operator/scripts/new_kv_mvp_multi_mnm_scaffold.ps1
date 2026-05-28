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
New-Item -ItemType Directory -Force -Path $ScaffoldRoot | Out-Null

$modelPath = Join-Path $ScaffoldRoot 'scaffold.model.json'
$renderer = Join-Path (Split-Path -Parent $PSCommandPath) 'render_kv_mvp_scaffold_model.ps1'
if (-not (Test-Path -LiteralPath $renderer -PathType Leaf)) {
  throw "Scaffold model renderer not found: $renderer"
}

$model = [ordered]@{
  schema_version = 1
  scaffold_version = '3.0.0'
  template = 'MultiMnmBoolStructured'
  evidence = 'scaffold_model'
  project = [ordered]@{
    name = $ProjectName
    cpu_model = $CpuModel
    local_program = $MainModuleName
  }
  task = [ordered]@{
    summary = $TaskSummary
  }
  modules = @(
    [ordered]@{
      name = $MainModuleName
      module_type = 0
      mnm = [ordered]@{
        comment = 'Multi-MNM MVP main scan module.'
        instructions = @(
          'LD G_StartCommand'
          'AND G_ReadyPermissive'
          'OUT G_RunCommand'
          'END'
          'ENDH'
        )
      }
      variables = [ordered]@{
        global = @(
          [ordered]@{ name='G_StartCommand'; data_type='BOOL'; initial_value='FALSE'; comment='Start request consumed by the main module.' }
          [ordered]@{ name='G_ReadyPermissive'; data_type='BOOL'; initial_value='FALSE'; comment='Main-module permissive input.' }
          [ordered]@{ name='G_RunCommand'; data_type='BOOL'; initial_value='FALSE'; comment='Command bit produced by the main module and consumed by the auxiliary module.' }
        )
        local = @(
          [ordered]@{ name='MainWork'; data_type='BOOL'; initial_value='FALSE'; comment='Main module local work bit verified through local-variable audit.' }
          [ordered]@{ name='MainDiag'; data_type='BOOL'; initial_value='FALSE'; comment='Main module extra local diagnostic bit for local-variable table coverage.' }
        )
      }
    }
    [ordered]@{
      name = $AuxModuleName
      module_type = 0
      mnm = [ordered]@{
        comment = 'Multi-MNM MVP auxiliary scan module.'
        instructions = @(
          'LD G_RunCommand'
          'AND G_JamClear'
          'OUT G_ReadyIndicator'
          'END'
          'ENDH'
        )
      }
      variables = [ordered]@{
        global = @(
          [ordered]@{ name='G_RunCommand'; data_type='BOOL'; initial_value='FALSE'; comment='Command bit shared from the main module.' }
          [ordered]@{ name='G_JamClear'; data_type='BOOL'; initial_value='FALSE'; comment='Auxiliary-module permissive input.' }
          [ordered]@{ name='G_ReadyIndicator'; data_type='BOOL'; initial_value='FALSE'; comment='Auxiliary-module output indicator.' }
        )
        local = @(
          [ordered]@{ name='AuxWork'; data_type='BOOL'; initial_value='FALSE'; comment='Auxiliary module local work bit verified through local-variable audit.' }
          [ordered]@{ name='AuxDiag'; data_type='BOOL'; initial_value='FALSE'; comment='Auxiliary module extra local diagnostic bit for local-variable table coverage.' }
        )
      }
    }
  )
}

$model | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $modelPath -Encoding UTF8

& powershell -NoProfile -ExecutionPolicy Bypass -File $renderer -ModelPath $modelPath -ScaffoldRoot $ScaffoldRoot
exit $LASTEXITCODE
