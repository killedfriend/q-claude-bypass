param([switch]$Stop, [switch]$Background)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

$cfg = Get-Content (Join-Path $here 'config.json') -Raw | ConvertFrom-Json
$port = [int]$cfg.listen.port
$pidFile = Join-Path $here 'logs\gateway.pid'

function Get-GatewayPid {
    if (Test-Path $pidFile) {
        $saved = Get-Content $pidFile -Raw -ErrorAction SilentlyContinue
        if ($saved -and $saved.Trim() -match '^\d+$') {
            $candidate = [int]$saved.Trim()
            if (Get-Process -Id $candidate -ErrorAction SilentlyContinue) { return $candidate }
        }
    }
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($conn) { return ($conn | Select-Object -First 1 -ExpandProperty OwningProcess) }
    return $null
}

if ($Stop) {
    $gatewayPid = Get-GatewayPid
    if (-not $gatewayPid) { Write-Host 'gateway is not running'; return }
    $proc = Get-Process -Id $gatewayPid -ErrorAction SilentlyContinue
    if ($proc) {
        Stop-Process -Id $gatewayPid -Force
        Write-Host "stopped pid $gatewayPid"
    } else {
        Write-Host "pid $gatewayPid is gone"
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    return
}

$running = $null
try { $running = Invoke-WebRequest "http://127.0.0.1:$port/health" -TimeoutSec 1 -UseBasicParsing } catch { }
if ($running) {
    Write-Host "gateway is already running on port $port. Stop it first: .\gateway\start.ps1 -Stop"
    return
}

. (Join-Path $here 'gw-env.ps1')

if ($Background) {
    $node = (Get-Command node -ErrorAction Stop).Source
    New-Item -ItemType Directory -Force (Join-Path $here 'logs') | Out-Null
    Start-Process -FilePath $node `
        -ArgumentList ('"' + (Join-Path $here 'server.mjs') + '"') `
        -WorkingDirectory $here -WindowStyle Hidden
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        try {
            $r = Invoke-WebRequest "http://127.0.0.1:$port/health" -TimeoutSec 1 -UseBasicParsing
            if ($r.StatusCode -eq 200) { Write-Host "gateway started on http://127.0.0.1:$port"; return }
        } catch { }
    }
    throw 'gateway did not start; see gateway\logs\err.log'
}

Write-Host "gateway on http://127.0.0.1:$port  (Ctrl+C to stop)" -ForegroundColor Cyan
node (Join-Path $here 'server.mjs')
