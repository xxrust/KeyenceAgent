# Read-only identity binding for a project created in an already-running Kvs.
function Get-KvCreatedProjectProcess([string]$ProjectPath,[string]$CreatedProjectResultPath) {
  $project=[IO.Path]::GetFullPath($ProjectPath)
  $receipt=Get-Content -LiteralPath $CreatedProjectResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($receipt.ok -isnot [bool] -or -not $receipt.ok -or -not $receipt.project_path -or [IO.Path]::GetFullPath([string]$receipt.project_path) -ine $project -or -not $receipt.requested_project_path -or [IO.Path]::GetFullPath([string]$receipt.requested_project_path) -ine $project -or -not $receipt.process_id -or -not $receipt.process_start_utc -or -not $receipt.kvs_exe) { throw 'KV_PROJECT_CREATION_EVIDENCE_INVALID' }
  $process=Get-Process -Id ([int]$receipt.process_id) -ErrorAction Stop
  $started=[DateTime]::Parse([string]$receipt.process_start_utc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
  $title='^KV STUDIO.* - \['+[regex]::Escape([IO.Path]::GetFileNameWithoutExtension($project))+'(?: \*)?\]$'
  if ($process.ProcessName -ine 'Kvs' -or $process.StartTime.ToUniversalTime() -ne $started -or $process.MainWindowHandle -eq 0 -or $process.MainWindowTitle -notmatch $title -or [IO.Path]::GetFullPath($process.Path) -ine [IO.Path]::GetFullPath([string]$receipt.kvs_exe)) { throw 'KV_PROJECT_CREATED_PROCESS_IDENTITY_MISMATCH' }
  $pathPattern='(?:^|\s)(?:"'+[regex]::Escape($project)+'"|'+[regex]::Escape($project)+')(?=\s|$)'
  $other=@(Get-CimInstance Win32_Process -Filter "Name='Kvs.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine -match $pathPattern -and [int]$_.ProcessId -ne $process.Id })
  if ($other.Count) { throw 'KV_PROJECT_PROCESS_AMBIGUOUS' }
  return $process
}
