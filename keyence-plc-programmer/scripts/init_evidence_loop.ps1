param(
  [Parameter(Mandatory=$true)]
  [string]$TaskId,

  [string]$Root = (Join-Path ([IO.Path]::GetTempPath()) 'keyence-plc-programmer\evidence'),

  [string]$ImplementationInbox = '',

  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function ConvertTo-Slug {
  param([string]$Value)
  $slug = ($Value.Trim() -replace '[^\p{L}\p{Nd}_.-]+', '_').Trim('_')
  if (-not $slug) { throw 'TaskId produced an empty slug.' }
  return $slug
}

function Write-TextFile {
  param([string]$Path, [string]$Content)
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [System.IO.File]::WriteAllText($Path, [string]$Content, $script:utf8NoBom)
}

$taskSlug = ConvertTo-Slug $TaskId
$evidenceRoot = Join-Path $Root $taskSlug
if ((Test-Path -LiteralPath $evidenceRoot) -and -not $Force) {
  throw "Evidence root already exists. Use -Force only when deliberately reusing it: $evidenceRoot"
}

New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
$dirs = @(
  'source_snapshot',
  'work',
  'validation',
  'review_inbox',
  'agent_outbox',
  '.evidence_review\triggers',
  '.evidence_review\diffs',
  '.evidence_review\reviews',
  '.evidence_review\html'
)
foreach ($dir in $dirs) {
  New-Item -ItemType Directory -Force -Path (Join-Path $evidenceRoot $dir) | Out-Null
  Write-TextFile -Path (Join-Path $evidenceRoot (Join-Path $dir '.keep')) -Content ''
}

if (-not $ImplementationInbox) {
  $ImplementationInbox = Join-Path $evidenceRoot 'agent_outbox'
}

$contract = [ordered]@{
  schema = 'kv-evidence-loop/v1'
  task_id = $TaskId
  task_slug = $taskSlug
  created_at = (Get-Date).ToString('s')
  evidence_root = $evidenceRoot
  implementation_inbox = $ImplementationInbox
  watched_subdirs = @('source_snapshot', 'work', 'validation')
  ignored_subdirs = @('.git', '.evidence_review', 'review_inbox', 'agent_outbox')
  trigger = [ordered]@{
    mode = 'filesystem_watcher_passive_forced'
    debounce_seconds = 2
    reviewer = 'codex exec read-only reviewer'
    diff_required = $true
  }
  required_outputs = [ordered]@{
    latest_review = (Join-Path $evidenceRoot 'review_inbox\latest_review.md')
    audit_html = (Join-Path $evidenceRoot 'audit.html')
    manifest = (Join-Path $evidenceRoot 'evidence_contract.json')
  }
}

Write-TextFile -Path (Join-Path $evidenceRoot 'evidence_contract.json') -Content ($contract | ConvertTo-Json -Depth 8)
Write-TextFile -Path (Join-Path $evidenceRoot '.gitignore') -Content @'
.evidence_review/runtime/
*.tmp
~$*
'@

Write-TextFile -Path (Join-Path $evidenceRoot 'README_EVIDENCE_LOOP.md') -Content @"
# Evidence Loop

Task: $TaskId

Active evidence root:

$evidenceRoot

Only these folders are implementation evidence inputs:

- source_snapshot
- work
- validation

Every file change under those folders must be reviewed by the passive watcher before success is claimed.
Reviewer output is written to:

- review_inbox\latest_review.md
- audit.html
"@

Push-Location $evidenceRoot
try {
  if (-not (Test-Path -LiteralPath '.git')) {
    git init | Out-Null
    git config user.name 'codex-evidence-loop' | Out-Null
    git config user.email 'codex-evidence-loop@local' | Out-Null
  }
  git add README_EVIDENCE_LOOP.md evidence_contract.json .gitignore source_snapshot\.keep work\.keep validation\.keep review_inbox\.keep agent_outbox\.keep | Out-Null
  $hasCommit = $true
  git rev-parse --verify --quiet HEAD *> $null 2>$null
  if ($LASTEXITCODE -ne 0) { $hasCommit = $false }
  $pending = git diff --cached --name-only
  if ($pending) {
    git commit -m 'Initialize evidence loop scaffold' | Out-Null
  } elseif (-not $hasCommit) {
    git commit --allow-empty -m 'Initialize evidence loop scaffold' | Out-Null
  }
} finally {
  Pop-Location
}

$html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>Evidence Loop - $TaskId</title>
  <style>
    body { font-family: Segoe UI, Microsoft YaHei, sans-serif; margin: 24px; line-height: 1.5; }
    code { background: #f4f4f4; padding: 2px 4px; border-radius: 3px; }
    .fail { color: #b00020; font-weight: 700; }
    .ok { color: #0a7a20; font-weight: 700; }
  </style>
</head>
<body>
  <h1>Evidence Loop</h1>
  <p><b>Task:</b> <code>$TaskId</code></p>
  <p><b>Evidence root:</b> <code>$evidenceRoot</code></p>
  <p><b>Trigger mode:</b> <span class="ok">filesystem watcher passive forced</span></p>
  <h2>Paths</h2>
  <ul>
    <li>Contract: <code>$(Join-Path $evidenceRoot 'evidence_contract.json')</code></li>
    <li>Latest review: <code>$(Join-Path $evidenceRoot 'review_inbox\latest_review.md')</code></li>
    <li>Reviewer internals: <code>$(Join-Path $evidenceRoot '.evidence_review')</code></li>
  </ul>
  <h2>Latest Review</h2>
  <p class="fail">No review has run yet.</p>
</body>
</html>
"@
Write-TextFile -Path (Join-Path $evidenceRoot 'audit.html') -Content $html

[pscustomobject]@{
  ok = $true
  task_id = $TaskId
  evidence_root = $evidenceRoot
  contract = (Join-Path $evidenceRoot 'evidence_contract.json')
  audit_html = (Join-Path $evidenceRoot 'audit.html')
} | ConvertTo-Json -Depth 4
