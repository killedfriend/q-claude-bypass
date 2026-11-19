#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$key = 'HKLM:\SOFTWARE\Policies\ClaudeCode'
if (Test-Path $key) {
    Remove-Item $key -Recurse -Force
    Write-Host "removed: $key" -ForegroundColor Yellow
} else {
    Write-Host "nothing to remove: $key"
}
