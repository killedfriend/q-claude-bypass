# Local pre-flight: JSON, PowerShell syntax, Node tests, docs and secret scan.
[CmdletBinding()]
param([switch]$SkipTests)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$problems = @()

Write-Host 'JSON' -ForegroundColor Cyan
Get-ChildItem $root -Recurse -Filter *.json | Where-Object {
    $_.FullName -notmatch '\\node_modules\\|\\dist\\|\\gateway\\logs\\'
} | ForEach-Object {
    try { Get-Content $_.FullName -Raw | ConvertFrom-Json | Out-Null }
    catch { $problems += "JSON: $($_.FullName): $($_.Exception.Message)" }
}

Write-Host 'PowerShell syntax' -ForegroundColor Cyan
Get-ChildItem $root -Recurse -Filter *.ps1 | ForEach-Object {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        $problems += "PS1: $($_.FullName): $($errors[0].Message)"
    }
}

Write-Host 'JavaScript syntax' -ForegroundColor Cyan
Get-ChildItem (Join-Path $root 'gateway') -Recurse -Filter *.mjs | ForEach-Object {
    & node --check $_.FullName 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $problems += "JS: $($_.FullName)" }
}

Write-Host 'Documentation' -ForegroundColor Cyan
foreach ($path in @(
    'README.ru.md', 'README.en.md', 'README.zh-CN.md',
    'docs/ru/installation.md', 'docs/ru/providers.md', 'docs/ru/configuration.md', 'docs/ru/troubleshooting.md',
    'docs/en/installation.md', 'docs/en/providers.md', 'docs/en/configuration.md', 'docs/en/troubleshooting.md',
    'docs/zh/installation.md', 'docs/zh/providers.md', 'docs/zh/configuration.md', 'docs/zh/troubleshooting.md'
)) {
    if (-not (Test-Path (Join-Path $root $path))) { $problems += "missing doc: $path" }
}

Write-Host 'Secrets' -ForegroundColor Cyan
$patterns = @(
    'sk-[A-Za-z0-9]{20,}',
    'sk-or-v1-[A-Za-z0-9]{20,}',
    'ghp_[A-Za-z0-9]{30,}',
    'BEGIN (RSA |EC )?PRIVATE KEY'
)
Get-ChildItem $root -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\node_modules\\|\\dist\\|\\gateway\\logs\\|\\tests\\parity\\(hook-input|hook-fired|note)'
} | ForEach-Object {
    $text = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $text) { return }
    foreach ($p in $patterns) {
        if ($text -match $p) { $problems += "possible secret in $($_.FullName) ($p)" }
    }
}

if (-not $SkipTests) {
    Write-Host 'Node tests' -ForegroundColor Cyan
    # Use npm.cmd: Windows PowerShell 5.1 mangles arguments through npm.ps1.
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
    if (-not $npm) {
        $problems += 'npm not found'
    } else {
        & $npm.Source test 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { $problems += 'npm test failed' }
    }
}

Write-Host ''
if ($problems.Count -gt 0) {
    Write-Host "FAILED: $($problems.Count) problem(s)" -ForegroundColor Red
    $problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'OK: repository checks passed' -ForegroundColor Green
