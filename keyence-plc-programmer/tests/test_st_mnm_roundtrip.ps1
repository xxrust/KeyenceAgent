param([string]$OutDir = (Join-Path $env:TEMP ('kv_st_mnm_' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scriptPath = Join-Path $PSScriptRoot '../scripts/new_kv_st_mnm.ps1'
[IO.Directory]::CreateDirectory($OutDir) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$ansi = [Text.Encoding]::Default
$source = Join-Path $OutDir 'source.st'
$mnm = Join-Path $OutDir 'module.mnm'
$export = Join-Path $OutDir 'export.mnm'
$results = [Collections.Generic.List[string]]::new()

function Assert-Rejected([string]$Name, [scriptblock]$Action, [string]$Code) {
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike "*$Code*") { throw "Unexpected failure in ${Name}: $($_.Exception.Message)" }
        $results.Add($Name); return
    }
    throw "Expected rejection: $Name"
}

$body = "// Preserve comments, indentation and empty lines.`n`nIF Enabled THEN`n    Result := 1.0; // keep this comment`nEND_IF;`n;`n`n"
[IO.File]::WriteAllText($source, $body, $utf8)
foreach ($category in @('scan', 'function_block')) {
    $pack = & $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category $category -OutPath $mnm | ConvertFrom-Json
    if (-not $pack.ok -or $pack.source_lines -ne 7) { throw 'Pack failed to preserve source lines.' }
    $compare = & $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category $category -ExportPath $mnm | ConvertFrom-Json
    if (-not $compare.ok) { throw 'Roundtrip failed.' }
    $results.Add("roundtrip_$category")
}
$clean = [IO.File]::ReadAllText($mnm, $ansi)
& $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category function_block -OutPath $export -OutputEncoding WindowsAnsi | Out-Null
& $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category function_block -ExportPath $export | Out-Null
$results.Add('explicit_ansi_roundtrip')
foreach ($legacy in @(@{category='scan';device=63}, @{category='function_block';device=59})) {
    & $scriptPath -DeviceCode $legacy.device -SourcePath $source -ModuleName TestST -Category $legacy.category -OutPath $export | Out-Null
    & $scriptPath -DeviceCode $legacy.device -SourcePath $source -ModuleName TestST -Category $legacy.category -ExportPath $export | Out-Null
    $results.Add("explicit_legacy_device_$($legacy.device)")
}
[IO.File]::WriteAllText($export, $clean.Replace("`r`n", "`n"), $utf8)
& $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category function_block -ExportPath $export | Out-Null
$results.Add('newline_only_normalization')
[IO.File]::WriteAllText($export, $clean, [Text.UnicodeEncoding]::new($false, $true))
& $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category function_block -ExportPath $export | Out-Null
$results.Add('utf16_export')

$mutations = @(
    @{ name='changed_code'; text=$clean.Replace('Result := 1.0;', 'Result := 2.0;'); code='KV_ST_MNM_BODY_MISMATCH' },
    @{ name='removed_comment'; text=$clean.Replace(' // keep this comment', ''); code='KV_ST_MNM_BODY_MISMATCH' },
    @{ name='removed_blank'; text=$clean.Replace("`r`n;`r`n", "`r`n"); code='KV_ST_MNM_BODY_MISMATCH' },
    @{ name='extra_st'; text=$clean.Replace("`r`nEND`r`n", "`r`n;Result := 3.0;`r`nEND`r`n"); code='KV_ST_MNM_BODY_MISMATCH' },
    @{ name='extra_ladder'; text=$clean.Replace("`r`nEND`r`n", "`r`nLD CR2002`r`nEND`r`n"); code='KV_ST_MNM_EXTRA_INSTRUCTION' },
    @{ name='second_area'; text=$clean.Replace("`r`nEND`r`n", "`r`nAREA_ST`r`nEND`r`n"); code='KV_ST_MNM_EXTRA_INSTRUCTION' },
    @{ name='trailing_module'; text=$clean + ';MODULE:Other'; code='KV_ST_MNM_EXTRA_INSTRUCTION' },
    @{ name='wrong_module'; text=$clean.Replace(';MODULE:TestST', ';MODULE:Other'); code='KV_ST_MNM_MODULE_MISMATCH' },
    @{ name='wrong_type'; text=$clean.Replace(';MODULE_TYPE:2', ';MODULE_TYPE:0'); code='KV_ST_MNM_TYPE_MISMATCH' },
    @{ name='wrong_device'; text=$clean.Replace('DEVICE:60', 'DEVICE:59'); code='KV_ST_MNM_DEVICE_INVALID' },
    @{ name='missing_endh'; text=$clean.Replace("ENDH`r`n", ''); code='KV_ST_MNM_INCOMPLETE' }
)
foreach ($mutation in $mutations) {
    [IO.File]::WriteAllText($export, $mutation.text, $ansi)
    Assert-Rejected $mutation.name { & $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category function_block -ExportPath $export } $mutation.code
}
foreach ($injection in @('DEVICE:60', ';MODULE:Other', ';;MODULE:Other', ';MODULE_TYPE:0', 'AREA_ST', 'ENDH')) {
    [IO.File]::WriteAllText($source, "Result := 1.0;`n$injection`n", $utf8)
    Assert-Rejected "inject_$injection" { & $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -OutPath $mnm } 'KV_ST_CONTAINER_INJECTION'
}
foreach ($wrapper in @('VAR', 'VAR_INPUT', 'END_VAR', 'PROGRAM Demo', 'FUNCTION_BLOCK Demo', 'FUNCTION Demo')) {
    [IO.File]::WriteAllText($source, "$wrapper`nResult := 1.0;`n", $utf8)
    Assert-Rejected "wrapper_$wrapper" { & $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -OutPath $mnm } 'KV_ST_DECLARATION_WRAPPER'
}
[IO.File]::WriteAllText($source, "// VAR belongs in a table.`n(* FUNCTION_BLOCK is only a comment. *)`nResult := 1.0;`n", $utf8)
& $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -OutPath $mnm | Out-Null
$results.Add('keywords_in_comments_preserved')
[IO.File]::WriteAllText($source, "/* VAR`nFUNCTION_BLOCK is only a comment. */`nResult := 1.0;`n", $utf8)
& $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -OutPath $mnm | Out-Null
$results.Add('c_style_comment_keywords_preserved')
[IO.File]::WriteAllText($source, 'Result := 1.0; VAR illegal: REAL; END_VAR;', $utf8)
Assert-Rejected 'inline_declaration_wrapper' { & $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -OutPath $mnm } 'KV_ST_DECLARATION_WRAPPER'
[IO.File]::WriteAllText($source, "Result := 1.0; // " + [char]0x4E2D + [char]0x6587, $utf8)
& $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -OutPath $mnm -OutputEncoding WindowsAnsi | Out-Null
& $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -ExportPath $mnm | Out-Null
$results.Add('ansi_non_ascii_comment')
[IO.File]::WriteAllBytes($source, [byte[]]@(0xC3, 0x28))
Assert-Rejected 'invalid_source_utf8' { & $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -OutPath $mnm } 'KV_ST_SOURCE_ENCODING_INVALID'
[IO.File]::WriteAllText($source, "Result := 1.0; // " + [char]::ConvertFromUtf32(0x1F642), $utf8)
if ($ansi.CodePage -ne 65001) {
    Assert-Rejected 'unrepresentable_ansi' { & $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -OutPath $mnm -OutputEncoding WindowsAnsi } 'KV_ST_ANSI_UNREPRESENTABLE'
}
& $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -OutPath $mnm -OutputEncoding Utf16LE | Out-Null
& $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -ExportPath $mnm | Out-Null
$results.Add('explicit_utf16_pack_unicode_roundtrip')
[IO.File]::WriteAllText($source, "// only a comment`n", $utf8)
Assert-Rejected 'empty_executable_body' { & $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -OutPath $mnm } 'KV_ST_SOURCE_EMPTY'
$shell = "DEVICE:60`r`n;MODULE:TestST`r`n;MODULE_TYPE:0`r`n"
foreach ($suffix in @('', "END`r`nENDH`r`n")) {
    [IO.File]::WriteAllText($export, $shell + $suffix, [Text.UnicodeEncoding]::new($false, $true))
    $emptyResult = & $scriptPath -DeviceCode 60 -ModuleName TestST -Category scan -ExportPath $export -CheckEmptyShell | ConvertFrom-Json
    if (-not $emptyResult.empty_shell_verified -or $emptyResult.st_body_verified) { throw 'Empty shell was confused with verified ST.' }
    $results.Add("empty_shell_suffix_length_$($suffix.Length)")
}
[IO.File]::WriteAllText($source, 'Result := 1.0;', $utf8)
Assert-Rejected 'shell_is_not_st_body' { & $scriptPath -DeviceCode 60 -SourcePath $source -ModuleName TestST -Category scan -ExportPath $export } 'KV_ST_MNM_CONTAINER_INVALID'
[IO.File]::WriteAllText($export, $clean, $ansi)
Assert-Rejected 'st_is_not_empty_shell' { & $scriptPath -DeviceCode 60 -ModuleName TestST -Category function_block -ExportPath $export -CheckEmptyShell } 'KV_ST_SHELL_NOT_EMPTY'
[IO.File]::WriteAllText($export, $shell + "LD CR2002`r`nEND`r`nENDH`r`n", $ansi)
Assert-Rejected 'ladder_is_not_empty_shell' { & $scriptPath -DeviceCode 60 -ModuleName TestST -Category scan -ExportPath $export -CheckEmptyShell } 'KV_ST_MNM_CONTAINER_INVALID'
[pscustomobject]@{ok=$true; count=$results.Count; cases=@($results); out_dir=$OutDir} | ConvertTo-Json -Depth 4
