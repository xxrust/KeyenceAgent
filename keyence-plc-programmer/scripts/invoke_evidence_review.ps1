param(
  [Parameter(Mandatory=$true)]
  [string]$EvidenceRoot,

  [string]$Reason = 'manual',

  [string]$CodexExe = 'codex',

  [string]$ReviewerModel = '',

  [switch]$NoAgent
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$env:LANG = 'C.UTF-8'
$env:LC_ALL = 'C.UTF-8'

function Write-TextFile {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [AllowNull()]
    [object]$Content
  )
  $parent = Split-Path -Parent $Path
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $text = if ($null -eq $Content) { '' } else { [string]$Content }
  [System.IO.File]::WriteAllText($Path, $text, $script:utf8NoBom)
}

function HtmlEscape {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return '' }
  return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Invoke-CaptureText {
  param(
    [Parameter(Mandatory=$true)]
    [scriptblock]$Command
  )
  $output = & $Command 2>&1
  if ($null -eq $output) {
    return ''
  }
  return (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
}

if (-not (Test-Path -LiteralPath $EvidenceRoot)) {
  throw "EvidenceRoot not found: $EvidenceRoot"
}

$EvidenceRoot = (Resolve-Path -LiteralPath $EvidenceRoot).Path
$contractPath = Join-Path $EvidenceRoot 'evidence_contract.json'
if (-not (Test-Path -LiteralPath $contractPath)) {
  throw "Missing evidence_contract.json: $contractPath"
}

$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$reviewRoot = Join-Path $EvidenceRoot '.evidence_review'
$diffRoot = Join-Path $reviewRoot 'diffs'
$reviewDir = Join-Path $reviewRoot 'reviews'
$runtimeRoot = Join-Path $reviewRoot 'runtime'
$reviewInbox = Join-Path $EvidenceRoot 'review_inbox'
$implementationInbox = [string]$contract.implementation_inbox

New-Item -ItemType Directory -Force -Path @(
  $diffRoot,
  $reviewDir,
  $runtimeRoot,
  $reviewInbox,
  $implementationInbox
) | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$statusPath = Join-Path $diffRoot "status_$stamp.txt"
$nameStatusPath = Join-Path $diffRoot "name_status_$stamp.txt"
$statPath = Join-Path $diffRoot "diff_stat_$stamp.txt"
$diffPath = Join-Path $diffRoot "diff_$stamp.patch"
$untrackedPath = Join-Path $diffRoot "untracked_$stamp.txt"
$reviewPath = Join-Path $reviewDir "review_$stamp.md"
$eventPath = Join-Path $reviewRoot 'latest_event.json'
$latestReview = Join-Path $reviewInbox 'latest_review.md'
$implementationLatestReview = Join-Path $implementationInbox 'latest_review.md'
$auditHtmlPath = Join-Path $EvidenceRoot 'audit.html'

Push-Location $EvidenceRoot
try {
  if (-not (Test-Path -LiteralPath '.git')) {
    git init | Out-Null
    git config user.name 'codex-evidence-loop' | Out-Null
    git config user.email 'codex-evidence-loop@local' | Out-Null
    git commit --allow-empty -m 'Initialize evidence loop repository' | Out-Null
  }

  git add -N source_snapshot work validation 2>$null
  Write-TextFile -Path $statusPath -Content (Invoke-CaptureText { git -c core.quotepath=false status --short source_snapshot work validation })
  Write-TextFile -Path $nameStatusPath -Content (Invoke-CaptureText { git -c core.quotepath=false diff --name-status -- source_snapshot work validation })
  Write-TextFile -Path $statPath -Content (Invoke-CaptureText { git -c core.quotepath=false diff --stat -- source_snapshot work validation })
  Write-TextFile -Path $diffPath -Content (Invoke-CaptureText { git -c core.quotepath=false diff --no-ext-diff --find-renames -- source_snapshot work validation })
  Write-TextFile -Path $untrackedPath -Content (Invoke-CaptureText { git -c core.quotepath=false ls-files --others --exclude-standard -- source_snapshot work validation })
} finally {
  Pop-Location
}

$statusText = if (Test-Path -LiteralPath $statusPath) { Get-Content -LiteralPath $statusPath -Raw } else { '' }
$nameStatusText = if (Test-Path -LiteralPath $nameStatusPath) { Get-Content -LiteralPath $nameStatusPath -Raw } else { '' }
$statText = if (Test-Path -LiteralPath $statPath) { Get-Content -LiteralPath $statPath -Raw } else { '' }
$diffText = if (Test-Path -LiteralPath $diffPath) { Get-Content -LiteralPath $diffPath -Raw } else { '' }
$untrackedText = if (Test-Path -LiteralPath $untrackedPath) { Get-Content -LiteralPath $untrackedPath -Raw } else { '' }
$hasChanges = (
  ($statusText.Trim().Length -gt 0) -or
  ($diffText.Trim().Length -gt 0) -or
  ($untrackedText.Trim().Length -gt 0)
)

$promptPath = Join-Path $runtimeRoot "review_prompt_$stamp.md"
$prompt = @"
You are an independent reviewer agent triggered forcibly by a filesystem watcher.
You are not the implementation agent.

Rules:
- Read only. Do not modify files.
- Base the review on the git diff artifacts and the current EvidenceRoot only.
- Do not use old logs, quarantined folders, or artifacts outside this EvidenceRoot as success evidence.
- During the current review, audit.html, review_inbox/latest_review.md, and agent_outbox/latest_review.md may still point to the previous review; the implementation script updates them after you exit. Do not fail the current diff because those delivery files are stale during your own execution.
- Return Markdown with these sections:
  1. Verdict: PASS / WARN / FAIL
  2. Changed Files
  3. Diff Findings
  4. Evidence Integrity
  5. Required Actions For Implementation Agent
  6. Paths Reviewed

EvidenceRoot:
$EvidenceRoot

Trigger reason:
$Reason

Required files:
- status: $statusPath
- name-status: $nameStatusPath
- diff-stat: $statPath
- diff: $diffPath
- untracked: $untrackedPath
- contract: $contractPath

Verdict rules:
- Missing diff artifacts: FAIL.
- Old logs or old directories used as input/success evidence: FAIL.
- Validation artifacts that cannot support the claimed pass: FAIL.
- Key implementation changes without reviewable evidence: WARN or FAIL.
"@
Write-TextFile -Path $promptPath -Content $prompt

if (-not $hasChanges) {
  $review = @"
# Evidence Review $stamp

## Verdict: PASS

No watched evidence changes were detected.

## Changed Files

None.

## Diff Findings

No diff under source_snapshot, work, or validation.

## Evidence Integrity

Evidence root: $EvidenceRoot

## Required Actions For Implementation Agent

No action required.

## Paths Reviewed

- $statusPath
- $nameStatusPath
- $statPath
- $diffPath
- $untrackedPath
"@
  Write-TextFile -Path $reviewPath -Content $review
} elseif ($NoAgent) {
  $review = @"
# Evidence Review $stamp

## Verdict: WARN

Agent review was disabled with `-NoAgent`; deterministic diff capture completed.

## Changed Files

---- text ----
$statusText
----

## Diff Findings

Name status:

---- text ----
$nameStatusText
----

Diff stat:

---- text ----
$statText
----

Full diff file: $diffPath

## Evidence Integrity

This is smoke-mode review. It verifies the forced trigger and diff capture path, but it cannot approve PLC benchmark success.

## Required Actions For Implementation Agent

Run the same evidence review without `-NoAgent` before claiming implementation success.

## Paths Reviewed

- $statusPath
- $nameStatusPath
- $statPath
- $diffPath
- $untrackedPath
"@
  Write-TextFile -Path $reviewPath -Content $review
} else {
  $codexArgs = @('exec', '--skip-git-repo-check', '--sandbox', 'read-only', '-C', $EvidenceRoot, '-o', $reviewPath)
  if ($ReviewerModel) {
    $codexArgs += @('-m', $ReviewerModel)
  }
  $codexArgs += @('-')

  Get-Content -LiteralPath $promptPath -Raw | & $CodexExe @codexArgs
  if ($LASTEXITCODE -ne 0) {
    $fallback = @"
# Evidence Review $stamp

## Verdict: FAIL

Reviewer agent command failed with exit code $LASTEXITCODE.

## Changed Files

---- text ----
$statusText
----

## Diff Findings

Diff was captured before the agent failure: $diffPath

## Evidence Integrity

The passive trigger worked, but independent agent review did not complete.

## Required Actions For Implementation Agent

Fix reviewer invocation before claiming any PLC/KV result.

## Paths Reviewed

- $promptPath
- $statusPath
- $diffPath
"@
    Write-TextFile -Path $reviewPath -Content $fallback
  }
}

if (-not (Test-Path -LiteralPath $reviewPath)) {
  throw "Review output was not created: $reviewPath"
}

Copy-Item -LiteralPath $reviewPath -Destination $latestReview -Force
Copy-Item -LiteralPath $reviewPath -Destination $implementationLatestReview -Force

$reviewText = Get-Content -LiteralPath $reviewPath -Raw
$eventRecord = [ordered]@{
  schema = 'kv-evidence-review-event/v1'
  triggered_at = (Get-Date).ToString('s')
  reason = $Reason
  evidence_root = $EvidenceRoot
  has_changes = $hasChanges
  status = $statusPath
  name_status = $nameStatusPath
  diff_stat = $statPath
  diff = $diffPath
  untracked = $untrackedPath
  review = $reviewPath
  latest_review = $latestReview
  implementation_latest_review = $implementationLatestReview
  audit_html = $auditHtmlPath
}
Write-TextFile -Path $eventPath -Content ($eventRecord | ConvertTo-Json -Depth 6)

$html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>Evidence Audit - $(HtmlEscape $contract.task_id)</title>
  <style>
    body { font-family: Segoe UI, Microsoft YaHei, sans-serif; margin: 24px; line-height: 1.5; }
    code, pre { background: #f4f4f4; padding: 2px 4px; border-radius: 3px; }
    pre { padding: 12px; overflow: auto; white-space: pre-wrap; }
    .box { border: 1px solid #ddd; padding: 12px; margin: 12px 0; border-radius: 6px; }
  </style>
</head>
<body>
  <h1>Evidence Audit</h1>
  <div class="box">
    <p><b>Task:</b> <code>$(HtmlEscape $contract.task_id)</code></p>
    <p><b>Evidence root:</b> <code>$(HtmlEscape $EvidenceRoot)</code></p>
    <p><b>Triggered at:</b> <code>$(HtmlEscape $eventRecord.triggered_at)</code></p>
    <p><b>Trigger reason:</b> <code>$(HtmlEscape $Reason)</code></p>
  </div>
  <h2>Execution And Review Paths</h2>
  <ul>
    <li>Status: <code>$(HtmlEscape $statusPath)</code></li>
    <li>Name status: <code>$(HtmlEscape $nameStatusPath)</code></li>
    <li>Diff stat: <code>$(HtmlEscape $statPath)</code></li>
    <li>Diff: <code>$(HtmlEscape $diffPath)</code></li>
    <li>Untracked: <code>$(HtmlEscape $untrackedPath)</code></li>
    <li>Review: <code>$(HtmlEscape $reviewPath)</code></li>
    <li>Implementation inbox: <code>$(HtmlEscape $implementationLatestReview)</code></li>
  </ul>
  <h2>Current Status</h2>
  <pre>$(HtmlEscape $statusText)</pre>
  <h2>Latest Review</h2>
  <pre>$(HtmlEscape $reviewText)</pre>
</body>
</html>
"@
Write-TextFile -Path $auditHtmlPath -Content $html

[pscustomobject]@{
  ok = $true
  evidence_root = $EvidenceRoot
  has_changes = $hasChanges
  review = $reviewPath
  latest_review = $latestReview
  implementation_latest_review = $implementationLatestReview
  audit_html = $auditHtmlPath
  diff = $diffPath
} | ConvertTo-Json -Depth 5
