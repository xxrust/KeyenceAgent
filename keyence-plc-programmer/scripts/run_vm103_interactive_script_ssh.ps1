param(
  [Parameter(Mandatory=$true)]
  [string]$LocalScriptPath,

  [string]$VmScriptPath = '',
  [string[]]$ScriptArguments = @(),
  [string]$RemoteWorkRoot = $env:KEYENCE_REMOTE_WORK_ROOT,
  [string]$HostName = $env:VM103_SSH_HOST,
  [string]$UserName = 'agent',
  [string]$Password = $env:VM103_SSH_PASSWORD,
  [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $LocalScriptPath)) {
  throw "LocalScriptPath not found: $LocalScriptPath"
}
if (-not $HostName) {
  throw 'HostName was not supplied. Set VM103_SSH_HOST or pass -HostName.'
}
if (-not $Password) {
  throw 'Password was not supplied. Set VM103_SSH_PASSWORD or pass -Password.'
}
if (-not $RemoteWorkRoot) {
  $RemoteWorkRoot = '$env:TEMP\keyence-plc-programmer'
}
if (-not $VmScriptPath) {
  $VmScriptPath = (Join-Path $RemoteWorkRoot ('tools\kvstudio\' + [IO.Path]::GetFileName($LocalScriptPath)))
}

function Resolve-PythonExe {
  $pyenvPython = (& pyenv which python 2>$null)
  if ($LASTEXITCODE -eq 0 -and $pyenvPython -and (Test-Path -LiteralPath $pyenvPython)) {
    return $pyenvPython
  }
  $command = Get-Command python.exe -ErrorAction Stop
  return $command.Source
}

$payload = @{
  host = $HostName
  user = $UserName
  password = $Password
  local_script = (Resolve-Path -LiteralPath $LocalScriptPath).Path
  vm_script = $VmScriptPath
  script_arguments = $ScriptArguments
  timeout_seconds = $TimeoutSeconds
  remote_work_root = $RemoteWorkRoot
} | ConvertTo-Json -Depth 5 -Compress

$python = Resolve-PythonExe
$driver = Join-Path $env:TEMP ('run_vm103_interactive_ssh_' + [Guid]::NewGuid().ToString('N') + '.py')
@'
import base64
import json
import os
import posixpath
import sys
import time
import paramiko


def ps_single(value):
    return "'" + str(value).replace("'", "''") + "'"


def ps_arg(value):
    value = str(value)
    if not value:
        return '""'
    if any(ch.isspace() for ch in value) or '"' in value:
        return '"' + value.replace('"', '""') + '"'
    return value


cfg = json.loads(base64.b64decode(sys.argv[1]).decode("utf-8"))
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(
    cfg["host"],
    username=cfg["user"],
    password=cfg["password"],
    timeout=10,
    auth_timeout=10,
    banner_timeout=10,
    look_for_keys=False,
    allow_agent=False,
)

vm_script = cfg["vm_script"]
remote_dir = vm_script.rsplit("\\", 1)[0]
task_name = "CodexKV_" + os.urandom(6).hex()
run_root = cfg["remote_work_root"].rstrip("\\") + r"\vm-103\interactive_runs" + "\\" + task_name
timeout_seconds = int(cfg["timeout_seconds"])

mkdir_ps = (
    "$ErrorActionPreference='Stop'; New-Item -ItemType Directory -Force -Path "
    + ps_single(remote_dir)
    + " | Out-Null"
)
mkdir_cmd = (
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand "
    + base64.b64encode(mkdir_ps.encode("utf-16le")).decode("ascii")
)
stdin, stdout, stderr = client.exec_command(mkdir_cmd, timeout=30)
rc = stdout.channel.recv_exit_status()
if rc != 0:
    raise SystemExit(stderr.read().decode("utf-8", "replace"))

sftp = client.open_sftp()
remote_sftp_path = "/" + vm_script.replace("\\", "/")
remote_sftp_dir = posixpath.dirname(remote_sftp_path)
parts = remote_sftp_dir.strip("/").split("/")
cur = ""
for part in parts:
    cur += "/" + part
    try:
        sftp.mkdir(cur)
    except OSError:
        pass
sftp.put(cfg["local_script"], remote_sftp_path)
sftp.close()

script_arg_line = " ".join(
    ["-WindowStyle", "Hidden", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps_arg(vm_script)]
    + [ps_arg(v) for v in cfg.get("script_arguments", [])]
)

remote_ps = r"""
$ErrorActionPreference='Stop'
$taskName={task_name}
$runRoot={run_root}
$argLine={arg_line}
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
Set-Content -LiteralPath (Join-Path $runRoot 'task_argline.txt') -Value $argLine -Encoding UTF8
$interactiveUser=(Get-CimInstance Win32_ComputerSystem).UserName
if(-not $interactiveUser){{ throw 'No interactive Windows user is logged on.' }}
Set-Content -LiteralPath (Join-Path $runRoot 'interactive_user.txt') -Value $interactiveUser -Encoding UTF8
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argLine
$principal=New-ScheduledTaskPrincipal -UserId $interactiveUser -LogonType Interactive -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds {timeout_seconds})
try {{ Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }} catch {{}}
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
$deadline=(Get-Date).AddSeconds({timeout_seconds})
do {{
  Start-Sleep -Seconds 2
  $info=Get-ScheduledTaskInfo -TaskName $taskName
  $state=(Get-ScheduledTask -TaskName $taskName).State
}} while($state -eq 'Running' -and (Get-Date) -lt $deadline)
$info=Get-ScheduledTaskInfo -TaskName $taskName
$state=(Get-ScheduledTask -TaskName $taskName).State
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
Write-Output ('TASK_STATE=' + $state)
Write-Output ('TASK_RESULT=' + $info.LastTaskResult)
Write-Output ('RUN_ROOT=' + $runRoot)
exit ([int]$info.LastTaskResult)
""".format(
    task_name=ps_single(task_name),
    run_root=ps_single(run_root),
    arg_line=ps_single(script_arg_line),
    timeout_seconds=timeout_seconds,
)

encoded = base64.b64encode(remote_ps.encode("utf-16le")).decode("ascii")
stdin, stdout, stderr = client.exec_command(
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand " + encoded,
    timeout=timeout_seconds + 120,
)
out = stdout.read().decode("utf-8", "replace")
err = stderr.read().decode("utf-8", "replace")
rc = stdout.channel.recv_exit_status()
print(out, end="")
if err:
    print(err, end="", file=sys.stderr)
client.close()
sys.exit(rc)
'@ | Set-Content -LiteralPath $driver -Encoding UTF8

$payloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
& $python $driver $payloadB64
exit $LASTEXITCODE
