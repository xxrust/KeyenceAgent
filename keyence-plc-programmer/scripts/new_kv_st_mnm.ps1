<#
.SYNOPSIS
Offline ST/MNM packaging, exact exported-body comparison, or empty-shell checks.
.DESCRIPTION
DeviceCode must come from target-project export evidence. Packaging does not
establish that KV STUDIO accepts ST MNM import. Compare checks one pure AREA_ST
body and rejects additional ladder code. CheckEmptyShell is a separate operation
and never reports that ST code was verified. SourcePath is UTF-8.
#>
[CmdletBinding(DefaultParameterSetName = 'Pack')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Pack')]
    [Parameter(Mandatory = $true, ParameterSetName = 'Compare')][string]$SourcePath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z_][A-Za-z0-9_]{0,47}$')][string]$ModuleName,
    [Parameter(Mandatory = $true)][ValidateSet('scan', 'function_block')][string]$Category,
    [Parameter(Mandatory = $true, ParameterSetName = 'Pack')][string]$OutPath,
    [Parameter(Mandatory = $true, ParameterSetName = 'Compare')]
    [Parameter(Mandatory = $true, ParameterSetName = 'EmptyShell')][string]$ExportPath,
    [Parameter(Mandatory = $true, ParameterSetName = 'EmptyShell')][switch]$CheckEmptyShell,
    [Parameter(Mandatory = $true)][ValidateSet(59, 60, 63)][int]$DeviceCode,
    [Parameter(ParameterSetName = 'Pack')][ValidateSet('WindowsAnsi', 'Utf16LE')][string]$OutputEncoding = 'Utf16LE'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-StrictAnsiEncoding {
    $codePage = [Microsoft.Win32.Registry]::GetValue(
        'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\CodePage', 'ACP', $null)
    if (-not $codePage) { throw 'KV_ST_ANSI_UNAVAILABLE: Windows ANSI code page could not be determined.' }
    return [Text.Encoding]::GetEncoding([int]$codePage,
        [Text.EncoderFallback]::ExceptionFallback, [Text.DecoderFallback]::ExceptionFallback)
}

function Get-LogicalLines([string]$Text) {
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    # A final newline terminates the last line; additional blank lines are content.
    if ($normalized.EndsWith("`n")) { $normalized = $normalized.Substring(0, $normalized.Length - 1) }
    return ,([string[]]($normalized -split "`n"))
}

function Get-CodeMask([string]$Text) {
    $buffer = $Text.ToCharArray()
    $quote = [char]0
    $blockDepth = 0
    $blockStyle = ''
    $lineComment = $false
    for ($index = 0; $index -lt $buffer.Length; $index++) {
        $current = $Text[$index]
        $next = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }
        if ($lineComment) {
            if ($current -eq "`r" -or $current -eq "`n") { $lineComment = $false }
            else { $buffer[$index] = ' ' }
        } elseif ($blockDepth -gt 0) {
            if (($blockStyle -eq 'iec' -and $current -eq '(' -and $next -eq '*') -or
                ($blockStyle -eq 'c' -and $current -eq '/' -and $next -eq '*')) {
                $blockDepth++; $buffer[$index] = ' '; $buffer[++$index] = ' '
            } elseif ($current -eq '*' -and (($blockStyle -eq 'iec' -and $next -eq ')') -or ($blockStyle -eq 'c' -and $next -eq '/'))) {
                $blockDepth--; $buffer[$index] = ' '; $buffer[++$index] = ' '
            } elseif ($current -ne "`r" -and $current -ne "`n") { $buffer[$index] = ' ' }
        } elseif ($quote -ne [char]0) {
            $buffer[$index] = ' '
            if (($current -eq '\' -or $current -eq '$') -and $next -eq $quote) {
                $buffer[++$index] = ' '
            } elseif ($current -eq $quote -and $next -eq $quote) {
                $buffer[++$index] = ' '
            } elseif ($current -eq $quote) { $quote = [char]0 }
        } elseif ($current -eq '/' -and $next -eq '/') {
            $lineComment = $true; $buffer[$index] = ' '; $buffer[++$index] = ' '
        } elseif ($current -eq '(' -and $next -eq '*') {
            $blockDepth = 1; $blockStyle = 'iec'; $buffer[$index] = ' '; $buffer[++$index] = ' '
        } elseif ($current -eq '/' -and $next -eq '*') {
            $blockDepth = 1; $blockStyle = 'c'; $buffer[$index] = ' '; $buffer[++$index] = ' '
        } elseif ($current -eq "'" -or $current -eq '"') {
            $quote = $current; $buffer[$index] = ' '
        }
    }
    if ($blockDepth -ne 0 -or $quote -ne [char]0) {
        throw 'KV_ST_SOURCE_UNTERMINATED: An ST comment or quoted value is not terminated.'
    }
    return (-join $buffer)
}

function Read-ExportMnm([string]$Path, [Text.Encoding]$AnsiEncoding) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 4 -and (($bytes[0] -eq 255 -and $bytes[1] -eq 254 -and $bytes[2] -eq 0 -and $bytes[3] -eq 0) -or
        ($bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 254 -and $bytes[3] -eq 255))) {
        throw 'KV_ST_MNM_ENCODING_UNSUPPORTED: UTF-32 is not a supported MNM encoding.'
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        return [Text.UTF8Encoding]::new($false, $true).GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
        return [Text.UnicodeEncoding]::new($false, $false, $true).GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) {
        return [Text.UnicodeEncoding]::new($true, $false, $true).GetString($bytes, 2, $bytes.Length - 2)
    }
    return $AnsiEncoding.GetString($bytes)
}

$sourceFile = $null
$sourceLines = [string[]]@()
$isEmptyShell = $PSCmdlet.ParameterSetName -eq 'EmptyShell'
if (-not $isEmptyShell) {
$sourceFile = (Resolve-Path -LiteralPath $SourcePath).Path
$sourceBytes = [IO.File]::ReadAllBytes($sourceFile)
try { $source = [Text.UTF8Encoding]::new($false, $true).GetString($sourceBytes) }
catch { throw "KV_ST_SOURCE_ENCODING_INVALID: SourcePath must contain valid UTF-8. $($_.Exception.Message)" }
if ($source.Length -gt 0 -and $source[0] -eq [char]0xFEFF) { $source = $source.Substring(1) }
if ($source -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') {
    throw 'KV_ST_SOURCE_CONTROL_CHARACTER: Unsupported source control character.'
}
$codeMask = Get-CodeMask $source
if ([string]::IsNullOrWhiteSpace($codeMask)) { throw 'KV_ST_SOURCE_EMPTY: Executable ST statements are required.' }
if ($codeMask -match '(?i)\b(VAR(?:_[A-Z_]+)?|END_VAR|PROGRAM|END_PROGRAM|FUNCTION_BLOCK|END_FUNCTION_BLOCK|FUNCTION|END_FUNCTION)\b') {
    throw 'KV_ST_DECLARATION_WRAPPER: Register declarations in KV STUDIO variable tables; provide executable ST only.'
}
if ($source -match '(?im)^\s*;*\s*(?:DEVICE\s*:|MODULE(?:_TYPE)?\s*:|AREA_ST\s*$|ENDH\s*$|END\s*$)') {
    throw 'KV_ST_CONTAINER_INJECTION: Source contains an MNM container/header line.'
}
$sourceLines = Get-LogicalLines $source
}
$ansi = Get-StrictAnsiEncoding
$moduleType = if ($Category -eq 'function_block') { 2 } else { 0 }
if ($Category -eq 'function_block' -and $DeviceCode -eq 63) {
    throw 'KV_ST_DEVICE_CATEGORY_INVALID: DEVICE:63 is not accepted for a function block.'
}

if ($PSCmdlet.ParameterSetName -eq 'Pack') {
    $targetFile = [IO.Path]::GetFullPath($OutPath)
    if ($targetFile -ieq $sourceFile) { throw 'KV_ST_OUTPUT_IS_SOURCE: SourcePath and OutPath must differ.' }
    $container = @("DEVICE:$deviceCode", ";MODULE:$ModuleName", ";MODULE_TYPE:$moduleType", 'AREA_ST')
    # Prefix every source line, including comments, blank lines and ST semicolons.
    $container += @($sourceLines | ForEach-Object { ';' + $_ })
    $container += @('END', 'ENDH')
    $containerText = ($container -join "`r`n") + "`r`n"
    if ($OutputEncoding -eq 'WindowsAnsi') {
        try { $payload = $ansi.GetBytes($containerText) }
        catch { throw "KV_ST_ANSI_UNREPRESENTABLE: Source cannot be represented in Windows ANSI code page $($ansi.CodePage). $($_.Exception.Message)" }
    } else {
        $unicode = [Text.UnicodeEncoding]::new($false, $true, $true)
        $payload = [byte[]]($unicode.GetPreamble() + $unicode.GetBytes($containerText))
    }
    $parent = [IO.Path]::GetDirectoryName($targetFile)
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    [IO.File]::WriteAllBytes($targetFile, $payload)
    [pscustomobject]@{
        ok = $true; operation = 'pack_st_mnm'; module_name = $ModuleName; category = $Category
        source_path = $sourceFile; output_path = $targetFile; ansi_code_page = $ansi.CodePage
        source_lines = $sourceLines.Count; source_sha256 = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
        output_sha256 = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash
        device_code = $DeviceCode; output_encoding = $OutputEncoding; offline_only = $true; ui_import_verified = $false
    } | ConvertTo-Json -Depth 4
    return
}

$exportFile = (Resolve-Path -LiteralPath $ExportPath).Path
$exportLines = Get-LogicalLines (Read-ExportMnm $exportFile $ansi)
$actualBody = [Collections.Generic.List[string]]::new()
$seenDevice = $false; $seenModule = $false; $seenType = $false
$phase = 'header'
foreach ($line in $exportLines) {
    if ($phase -eq 'header') {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^DEVICE:(\d+)\s*$') {
            if ($seenDevice -or [int]$Matches[1] -ne $DeviceCode) { throw 'KV_ST_MNM_DEVICE_INVALID: Unexpected or repeated DEVICE header; match the target CPU export evidence.' }
            $seenDevice = $true; continue
        }
        if ($line -match '^;MODULE:(.*)$') {
            if ($seenModule -or $Matches[1] -cne $ModuleName) { throw 'KV_ST_MNM_MODULE_MISMATCH: Unexpected or repeated MODULE header.' }
            $seenModule = $true; continue
        }
        if ($line -match '^;MODULE_TYPE:(\d+)\s*$') {
            if ($seenType -or [int]$Matches[1] -ne $moduleType) { throw 'KV_ST_MNM_TYPE_MISMATCH: Unexpected or repeated MODULE_TYPE header.' }
            $seenType = $true; continue
        }
        if ($line -eq 'AREA_ST' -and $seenDevice -and $seenModule -and $seenType) {
            if ($isEmptyShell) { throw 'KV_ST_SHELL_NOT_EMPTY: An ST area exists in the purported empty shell.' }
            $phase = 'body'; continue
        }
        if ($line -eq 'END' -and $isEmptyShell -and $seenDevice -and $seenModule -and $seenType) { $phase = 'endh'; continue }
        if ($line.StartsWith(';') -and $line -notmatch '^;\s*(?:MODULE|DEVICE|AREA_ST)') { continue }
        throw "KV_ST_MNM_CONTAINER_INVALID: Unexpected header or instruction '$line'."
    } elseif ($phase -eq 'body') {
        if ($line -eq 'END') { $phase = 'endh'; continue }
        if (-not $line.StartsWith(';')) { throw "KV_ST_MNM_EXTRA_INSTRUCTION: Unexpected instruction in ST area '$line'." }
        $actualBody.Add($line.Substring(1))
    } elseif ($phase -eq 'endh') {
        if ($line -ne 'ENDH') { throw "KV_ST_MNM_EXTRA_INSTRUCTION: Expected ENDH, got '$line'." }
        $phase = 'complete'
    } elseif (-not [string]::IsNullOrWhiteSpace($line)) {
        throw "KV_ST_MNM_EXTRA_INSTRUCTION: Content follows ENDH: '$line'."
    }
}
if ($isEmptyShell -and $phase -eq 'header' -and $seenDevice -and $seenModule -and $seenType) { $phase = 'complete' }
if ($phase -ne 'complete') { throw "KV_ST_MNM_INCOMPLETE: Container stopped in phase '$phase'." }
if ($actualBody.Count -ne $sourceLines.Count) {
    throw "KV_ST_MNM_BODY_MISMATCH: Expected $($sourceLines.Count) ST lines, found $($actualBody.Count)."
}
for ($index = 0; $index -lt $sourceLines.Count; $index++) {
    if ($sourceLines[$index] -cne $actualBody[$index]) {
        throw "KV_ST_MNM_BODY_MISMATCH: ST source line $($index + 1) differs."
    }
}
[pscustomobject]@{
    ok = $true; operation = $(if ($isEmptyShell) { 'check_empty_mnm_shell' } else { 'compare_st_mnm' })
    module_name = $ModuleName; category = $Category; device_code = $DeviceCode
    source_path = $sourceFile; export_path = $exportFile; source_lines = $sourceLines.Count
    source_sha256 = $(if ($sourceFile) { (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash } else { $null })
    export_sha256 = (Get-FileHash -LiteralPath $exportFile -Algorithm SHA256).Hash
    comparison = $(if ($isEmptyShell) { 'empty shell only; ST content is not verified' } else { 'exact ST lines after container-prefix and newline normalization' })
    st_body_verified = -not $isEmptyShell; empty_shell_verified = $isEmptyShell; ui_import_verified = $false
} | ConvertTo-Json -Depth 4
