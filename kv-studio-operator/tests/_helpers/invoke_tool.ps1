function Invoke-TestTool {
  param(
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [string[]]$Arguments = @()
  )
  # Start a fresh Windows PowerShell per tool so its exit code is observable;
  # in-process "& $script" leaves $LASTEXITCODE empty for many scripts.
  if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) { throw "test tool missing: $ScriptPath" }
  $quoted = @($Arguments | ForEach-Object {
    $value = [string]$_
    if ($value -match '\s') { '"' + ($value -replace '"', '\"') + '"' } else { $value }
  })
  $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $ScriptPath + '"')) + $quoted
  $process = Start-Process -FilePath 'powershell' -ArgumentList $argumentList -Wait -PassThru -WindowStyle Hidden
  return [int]$process.ExitCode
}
