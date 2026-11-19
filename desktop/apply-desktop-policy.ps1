#Requires -RunAsAdministrator
# Applies both pieces of Claude Desktop policy used by this project:
#   - C:\Program Files\ClaudeCode\managed-settings.json
#   - HKLM\SOFTWARE\Policies\ClaudeCode -> Settings
# Experimental: recent Claude Desktop builds may ignore these on Windows.
# Reversible with revert-all.ps1.
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'apply-managed-settings.ps1')
& (Join-Path $PSScriptRoot 'apply-registry-policy.ps1')

Write-Host 'desktop policy applied (experimental)' -ForegroundColor Green
