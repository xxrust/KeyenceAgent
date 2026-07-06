param(
  [string]$RequireWindowNamePattern = '',
  [bool]$ForbidLadderEditInsertBar = $true,
  [bool]$ForbidKvStudioMessageDialog = $true,
  [string]$OutJson = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Get-UiaTextSnapshot {
  $lastError = $null
  for ($attempt = 1; $attempt -le 4; $attempt++) {
    try {
      $root = [System.Windows.Automation.AutomationElement]::RootElement
      $all = $root.FindAll(
        [System.Windows.Automation.TreeScope]::Subtree,
        [System.Windows.Automation.Condition]::TrueCondition
      )
      $rows = @()
      for ($i = 0; $i -lt $all.Count; $i++) {
        try {
          $e = $all.Item($i)
          $name = [string]$e.Current.Name
          $class = [string]$e.Current.ClassName
          $automationId = [string]$e.Current.AutomationId
          if ($name -or $class -or $automationId) {
            $rows += [pscustomobject]@{
              Index = $i
              Name = $name
              Class = $class
              Type = $e.Current.ControlType.ProgrammaticName
              AutomationId = $automationId
            }
          }
        } catch [System.Windows.Automation.ElementNotAvailableException] {
          continue
        }
      }
      return $rows
    } catch {
      $lastError = $_.Exception.Message
      Start-Sleep -Milliseconds (200 * $attempt)
    }
  }
  throw "UIA snapshot failed after retries: $lastError"
}

$snapshot = @(Get-UiaTextSnapshot)
$issues = @()
$hazards = @()

$labelOverwrite = -join ([char[]](0x8986,0x76D6,0x0028,0x004F,0x0029))
$labelInsert = -join ([char[]](0x63D2,0x5165,0x0028,0x0049,0x0029))
$labelCancel = -join ([char[]](0x53D6,0x6D88,0x0028,0x0043,0x0029))
$labelComment = -join ([char[]](0x6CE8,0x91CA))
$emptyInputNeedle = -join ([char[]](0x8F93,0x5165,0x4EFB,0x4F55,0x5185,0x5BB9))
$convertResultTitle = -join ([char[]](0x8F6C,0x6362,0x7ED3,0x679C))

if ($RequireWindowNamePattern) {
  $matched = @($snapshot | Where-Object {
    $_.Type -eq 'ControlType.Window' -and $_.Name -match $RequireWindowNamePattern
  })
  if ($matched.Count -eq 0) {
    $issues += "Required target window not found: $RequireWindowNamePattern"
  }
}

if ($ForbidLadderEditInsertBar) {
  $insertBarControls = @($snapshot | Where-Object {
    $name = [string]$_.Name
    $isInsertBarName =
      $name -eq $labelOverwrite -or
      $name -eq $labelInsert -or
      $name -eq $labelCancel -or
      $name -eq $labelComment
    $isKvControl = ([string]$_.Type) -like 'ControlType.*'
    $isInsertBarName -and $isKvControl
  })
  if ($insertBarControls.Count -ge 3) {
    $issues += 'KV STUDIO ladder edit insert/overwrite bar is visible; global input would enter the ladder editor.'
    $hazards += $insertBarControls
  }
}

if ($ForbidKvStudioMessageDialog) {
  $messageDialog = @($snapshot | Where-Object {
    $isEmptyInputMessage = ([string]$_.Name).Contains($emptyInputNeedle)
    $isKvStudioDialog = ($_.Type -eq "ControlType.Window" -and $_.Name -eq "KV STUDIO" -and $_.Class -eq "#32770")
    $isConvertResultDialog = ($_.Type -eq "ControlType.Window" -and $_.Name -eq $convertResultTitle -and $_.Class -eq "#32770")
    $isEmptyInputMessage -or $isKvStudioDialog -or $isConvertResultDialog
  })
  if ($messageDialog.Count -gt 0) {
    $issues += 'KV STUDIO modal message dialog is visible; resolve it manually or with a dialog-specific UIA script before continuing.'
    $hazards += $messageDialog
  }
}

$report = [pscustomobject]@{
  ok = ($issues.Count -eq 0)
  issues = $issues
  hazards = @($hazards | Select-Object Index,Name,Class,Type,AutomationId)
  checked_at = (Get-Date).ToString('s')
}

if ($OutJson) {
  $parent = Split-Path -Parent $OutJson
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutJson -Encoding UTF8
}

if ($issues.Count -gt 0) {
  $issues | ForEach-Object { Write-Error $_ }
  exit 2
}

$report | ConvertTo-Json -Depth 5
