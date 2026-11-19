#Requires -RunAsAdministrator
# Removes the hosts entry, the CA, the leaf cert and the pfx.
$ErrorActionPreference = 'Continue'

Write-Host 'hosts' -ForegroundColor Cyan
$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
$lines = Get-Content $hosts | Where-Object { $_ -notmatch 'qclaude-mitm' -and $_ -notmatch '^\s*127\.0\.0\.1\s+api\.anthropic\.com\s*$' }
Set-Content -Path $hosts -Value $lines -Encoding ASCII

Write-Host 'certificates' -ForegroundColor Cyan
Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -eq 'CN=api.anthropic.com' } |
    ForEach-Object { Remove-Item -Path $_.PSPath -Force; Write-Host "  removed leaf $($_.Thumbprint)" }

Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object { $_.Subject -eq 'CN=QClaude Local CA' } |
    ForEach-Object { Remove-Item -Path $_.PSPath -Force; Write-Host "  removed CA $($_.Thumbprint)" }

$pfx = Join-Path $PSScriptRoot 'api.anthropic.com.pfx'
if (Test-Path $pfx) { Remove-Item $pfx -Force; Write-Host "  removed $pfx" }

Write-Host 'done' -ForegroundColor Green
