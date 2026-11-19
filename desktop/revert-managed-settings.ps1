#Requires -RunAsAdministrator
# Removes the managed settings that point Claude Desktop at the local gateway.
$ErrorActionPreference = 'Stop'

$dir = 'C:\Program Files\ClaudeCode'
$file = Join-Path $dir 'managed-settings.json'

if (Test-Path $file) {
    Remove-Item $file -Force
    Write-Host "removed: $file" -ForegroundColor Yellow
} else {
    Write-Host "nothing to remove: $file does not exist"
}

# Drop the folder too, but only if it is empty.
if ((Test-Path $dir) -and -not (Get-ChildItem $dir -Force)) {
    Remove-Item $dir -Force
    Write-Host "removed empty folder: $dir"
}
