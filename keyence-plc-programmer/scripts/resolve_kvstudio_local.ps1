param(
  [string]$ShortcutPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\KEYENCE KV STUDIO Ver.12G\KV STUDIO Ver.12G.lnk',
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-KvStudioLocal {
  param([string]$ShortcutPath)

  $candidates = New-Object System.Collections.Generic.List[string]
  if ($ShortcutPath -and (Test-Path -LiteralPath $ShortcutPath)) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    if ($shortcut.TargetPath) {
      $launcher = $shortcut.TargetPath
      $candidates.Add($launcher)
      $root = Split-Path -Parent $launcher
      $candidates.Add((Join-Path $root 'KVS12\KVS\Kvs.exe'))
      $candidates.Add((Join-Path $root 'KVS11\KVS\Kvs.exe'))
    }
  }

  $candidates.Add('D:\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe')
  $candidates.Add('D:\KEYENCE\KVS12G\KVS11\KVS\Kvs.exe')
  $candidates.Add('C:\Program Files (x86)\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe')
  $candidates.Add('C:\Program Files (x86)\KEYENCE\KVS12\KVS\Kvs.exe')

  $kvs = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) -and ((Split-Path -Leaf $_) -ieq 'Kvs.exe') } | Select-Object -First 1
  if (-not $kvs) {
    throw ('KV STUDIO Kvs.exe not found. Checked: ' + (($candidates | Select-Object -Unique) -join '; '))
  }

  $launcher = ''
  if ($ShortcutPath -and (Test-Path -LiteralPath $ShortcutPath)) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $launcher = $shortcut.TargetPath
  }

  [pscustomobject]@{
    ShortcutPath = $ShortcutPath
    LauncherPath = $launcher
    KvsExe = (Resolve-Path -LiteralPath $kvs).Path
    WorkingDirectory = (Split-Path -Parent $kvs)
  }
}

$result = Resolve-KvStudioLocal -ShortcutPath $ShortcutPath
if ($OutDir) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'kvstudio_local.json') -Encoding UTF8
}
$result | ConvertTo-Json -Depth 4
