# Builds the release ZIP, the self-contained install.ps1 and SHA256SUMS.
#   .\scripts\build-release.ps1
#   .\scripts\build-release.ps1 -Version 1.0.1 -Repo owner/repo
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Repo = 'killedfriend/q-claude-bypass',
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $Version) { $Version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim() }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 1.2.3, got '$Version'" }
if ($Repo -notmatch '^[\w.-]+/[\w.-]+$') { throw "Repo must look like owner/name, got '$Repo'" }
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }

$stage = Join-Path $OutDir "stage\qclaude-code-$Version"
$zipVersioned = Join-Path $OutDir "qclaude-code-$Version.zip"
$zipLatest = Join-Path $OutDir 'qclaude-code.zip'

if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

function Copy-Filtered([string]$From, [string]$To) {
    $source = Resolve-Path $From
    Get-ChildItem $source -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($source.Path.Length + 1)
        if ($rel -match '(^|\\)logs(\\|$)') { return }
        if ($_.Extension -eq '.pfx' -or $_.Name -eq 'setup.log' -or $_.Name -eq 'install.json') { return }
        if ($_.Name -match '\.bak-') { return }
        $dst = Join-Path $To $rel
        New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
        Copy-Item $_.FullName $dst -Force
    }
}

Write-Host "staging $Version from $root" -ForegroundColor Cyan

$files = @(
    'README.md', 'README.ru.md', 'README.en.md', 'README.zh-CN.md',
    'LICENSE', 'CHANGELOG.md', 'SECURITY.md', 'CONTRIBUTING.md', 'VERSION',
    'install.ps1', 'install.cmd', 'uninstall.ps1', 'env.ps1', 'qclaude.ps1',
    'qclaude-gw.ps1', 'test-connection.ps1', 'package.json'
)
foreach ($f in $files) {
    $src = Join-Path $root $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $stage $f) -Force }
}

foreach ($dir in @('gateway', 'desktop', 'docs', 'examples')) {
    $src = Join-Path $root $dir
    if (Test-Path $src) {
        New-Item -ItemType Directory -Force (Join-Path $stage $dir) | Out-Null
        Copy-Filtered -From $src -To (Join-Path $stage $dir)
    }
}

# Point the release installer at this repository and this version.
$sourceLines = Get-Content (Join-Path $root 'install.ps1')
$installerLines = foreach ($line in $sourceLines) {
    if ($line.Contains('[string]$Repo = ')) {
        '    [string]$Repo = ''' + $Repo + ''','
    } elseif ($line.Contains('[string]$Version = ')) {
        '    [string]$Version = ''' + $Version + ''','
    } else {
        $line
    }
}
$installer = ($installerLines -join "`n") + "`n"
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $OutDir 'install.ps1'), $installer, $utf8)
[IO.File]::WriteAllText((Join-Path $stage 'install.ps1'), $installer, $utf8)

$uninstaller = Get-Content (Join-Path $root 'uninstall.ps1') -Raw
[IO.File]::WriteAllText((Join-Path $OutDir 'uninstall.ps1'), $uninstaller, $utf8)

# Replace the repository URL in staged text files (OpenRouter attribution etc.).
Get-ChildItem $stage -Recurse -File | Where-Object { $_.Extension -in @('.md', '.json', '.mjs', '.ps1', '.txt', '.yml', '.yaml') } | ForEach-Object {
    $text = Get-Content $_.FullName -Raw
    if ($text.Contains('https://github.com/killedfriend/q-claude-bypass')) {
        $text = $text.Replace('https://github.com/killedfriend/q-claude-bypass', "https://github.com/$Repo")
        [IO.File]::WriteAllText($_.FullName, $text, $utf8)
    }
}

if (Test-Path $zipVersioned) { Remove-Item $zipVersioned -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipVersioned -CompressionLevel Optimal
Copy-Item $zipVersioned $zipLatest -Force

$installCmd = Join-Path $OutDir 'install.cmd'
Copy-Item (Join-Path $root 'install.cmd') $installCmd -Force

$assets = @(
    $zipVersioned,
    $zipLatest,
    (Join-Path $OutDir 'install.ps1'),
    $installCmd,
    (Join-Path $OutDir 'uninstall.ps1')
)
$lines = foreach ($asset in $assets) {
    $hash = (Get-FileHash $asset -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $(Split-Path $asset -Leaf)"
}
[IO.File]::WriteAllText((Join-Path $OutDir 'SHA256SUMS.txt'), (($lines -join "`n") + "`n"), $utf8)

Write-Host ''
Write-Host "version : $Version" -ForegroundColor Green
Write-Host "repo    : $Repo"
Write-Host "zip     : $zipVersioned"
Write-Host "latest  : $zipLatest"
Write-Host "install : $(Join-Path $OutDir 'install.ps1')"
Write-Host "hashes  : $(Join-Path $OutDir 'SHA256SUMS.txt')"
