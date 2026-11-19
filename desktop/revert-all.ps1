#Requires -RunAsAdministrator
# Removes everything the desktop experiment added: registry policy + managed-settings file.
$ErrorActionPreference = 'Continue'

$key = 'HKLM:\SOFTWARE\Policies\ClaudeCode'
if (Test-Path $key) {
    Remove-Item $key -Recurse -Force
    Write-Host "removed registry: $key" -ForegroundColor Yellow
}

$file = 'C:\Program Files\ClaudeCode\managed-settings.json'
if (Test-Path $file) {
    Remove-Item $file -Force
    Write-Host "removed: $file" -ForegroundColor Yellow
}

$dir = 'C:\Program Files\ClaudeCode'
if ((Test-Path $dir) -and -not (Get-ChildItem $dir -Force)) {
    Remove-Item $dir -Force
    Write-Host "removed empty folder: $dir"
}

Write-Host 'done'
