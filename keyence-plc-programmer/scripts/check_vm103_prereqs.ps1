param(
  [string]$HolderId = 'codex-official-repro-103',
  [int]$Vmid = 103,
  [string]$PveSsh = 'root@127.0.0.1',
  [int]$PveSshPort = 10022,
  [string]$AccessApi = 'http://127.0.0.1:8765'
)

$ErrorActionPreference = 'Continue'

function Result([string]$Name, [bool]$Ok, [string]$Detail) {
  [pscustomobject]@{
    Check = $Name
    Ok = $Ok
    Detail = $Detail
  }
}

$results = @()

$apiOk = $false
try {
  $vm = Invoke-RestMethod -Uri "$AccessApi/v1/vms/$Vmid" -TimeoutSec 5
  $apiOk = $true
  $holderOk = ($vm.business_status -eq 'reserved' -and $vm.holder_id -eq $HolderId)
  $results += Result 'access-api' $true "VM $Vmid status=$($vm.runtime_status)/$($vm.business_status) holder=$($vm.holder_id)"
  $results += Result 'vm-reservation' $holderOk "expected holder=$HolderId actual=$($vm.holder_id)"
} catch {
  $results += Result 'access-api' $false $_.Exception.Message
}

$tunnel = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $PveSshPort -State Listen -ErrorAction SilentlyContinue
$results += Result 'pve-ssh-tunnel-listen' ([bool]$tunnel) "127.0.0.1:$PveSshPort"

$pveOk = $false
if ($tunnel) {
  $probe = & ssh -p $PveSshPort -o BatchMode=yes -o ConnectTimeout=5 $PveSsh "qm status $Vmid" 2>&1
  $pveOk = ($LASTEXITCODE -eq 0)
  $results += Result 'pve-qm-status' $pveOk ($probe -join "`n")
} else {
  $results += Result 'pve-qm-status' $false 'Skipped because local PVE SSH tunnel is not listening.'
}

$helper = Join-Path $env:USERPROFILE '.codex\skills\windows-vm-codex-operator\scripts\windows_vm_operator.py'
$results += Result 'windows-vm-operator-helper' (Test-Path -LiteralPath $helper) $helper

$results | Format-Table -AutoSize

if ($results | Where-Object { -not $_.Ok }) {
  exit 1
}
