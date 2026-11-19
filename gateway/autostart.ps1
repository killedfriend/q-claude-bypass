# Starts the gateway in the background with the right environment.
# Used by the logon task / Run key; safe to run by hand.

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'gw-env.ps1')

$cfg = Get-Content (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
$port = [int]$cfg.listen.port
$server = Join-Path $PSScriptRoot 'server.mjs'
$logs = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force $logs | Out-Null

try {
    $r = Invoke-WebRequest "http://127.0.0.1:$port/health" -TimeoutSec 1 -UseBasicParsing
    if ($r.StatusCode -eq 200) { return }
} catch { }

$node = (Get-Command node -ErrorAction Stop).Source
Start-Process -FilePath $node `
    -ArgumentList ('"' + $server + '"') `
    -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
