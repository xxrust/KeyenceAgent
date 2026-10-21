param(
    [Parameter(Mandatory=$true)][string]$OutDir,
    [string]$Name = '',
    [switch]$Continuous,
    [int]$IntervalMs = 300,
    [int]$MaxSeconds = 1800
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$null = New-Item -ItemType Directory -Force -Path $OutDir
$index = Join-Path $OutDir 'index.txt'
function Grab([string]$path) {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $g.Dispose(); $bmp.Dispose() }
}
if ($Continuous) {
    $deadline = (Get-Date).AddSeconds($MaxSeconds)
    $i = 0
    while ((Get-Date) -lt $deadline) {
        if (Test-Path (Join-Path $OutDir 'STOP')) { break }
        $i++
        $p = Join-Path $OutDir ('f{0:d4}.png' -f $i)
        try {
            Grab $p
            $p | Out-Null
            try { $t = (Get-Process -Name 'Kvs' -ErrorAction SilentlyContinue | Select-Object -First 1).MainWindowTitle } catch { $t = '' }
            Add-Content -LiteralPath $index -Value ((Get-Date).ToString('HH:mm:ss.fff') + "`t" + ('f{0:d4}.png' -f $i) + "`t" + $t) -Encoding UTF8
        } catch { }
        Start-Sleep -Milliseconds $IntervalMs
    }
    Write-Host ('frames=' + $i)
} else {
    if (-not $Name) { $Name = 'shot.png' }
    $p = Join-Path $OutDir $Name
    Grab $p
    Write-Host $p
}