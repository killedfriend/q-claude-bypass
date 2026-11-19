#Requires -RunAsAdministrator
# Removes the hosts entry, the CA, the leaf cert, the PFX and the setup log.
# Idempotent: safe to run when nothing is installed.
$ErrorActionPreference = 'Continue'

Write-Host 'hosts' -ForegroundColor Cyan
$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
try {
    $lines = Get-Content $hosts | Where-Object { $_ -notmatch 'qclaude-mitm' -and $_ -notmatch '^\s*127\.0\.0\.1\s+api\.anthropic\.com\s*$' }
    Set-Content -Path $hosts -Value $lines -Encoding ASCII
    Write-Host '  qclaude-mitm entry removed'
} catch {
    Write-Host "  could not update hosts: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host 'certificates' -ForegroundColor Cyan
Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -eq 'CN=api.anthropic.com' } |
    ForEach-Object { Remove-Item -Path $_.PSPath -Force; Write-Host "  removed leaf $($_.Thumbprint)" }

Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object { $_.Subject -eq 'CN=QClaude Local CA' } |
    ForEach-Object { Remove-Item -Path $_.PSPath -Force; Write-Host "  removed CA $($_.Thumbprint)" }

$pfx = Join-Path $PSScriptRoot 'api.anthropic.com.pfx'
if (Test-Path $pfx) { Remove-Item $pfx -Force; Write-Host "  removed $pfx" }
$log = Join-Path $PSScriptRoot 'setup.log'
if (Test-Path $log) { Remove-Item $log -Force; Write-Host "  removed $log" }

Write-Host 'done' -ForegroundColor Green
exit 0
