# Legacy name kept for compatibility.
# The current release builder is scripts\build-release.ps1.
#   .\pack-share.ps1                 -> dist\qclaude-code.zip (+ versioned)
#   .\pack-share.ps1 -Out C:\share   -> custom output directory
param([string]$Out)

$ErrorActionPreference = 'Stop'
$params = @{}
$version = (Get-Content (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
$params['Version'] = $version
if ($Out) { $params['OutDir'] = $Out }
& (Join-Path $PSScriptRoot 'scripts\build-release.ps1') @params
