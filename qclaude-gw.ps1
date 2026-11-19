# Claude Code through the local gateway (logs, routing, retries).
# Direct mode stays available: .\qclaude.ps1
#
# No param() block: keep every argument in $args verbatim (see qclaude.ps1).

. (Join-Path $PSScriptRoot 'env.ps1')

$config = Get-Content (Join-Path $PSScriptRoot 'gateway\config.json') -Raw | ConvertFrom-Json
$providerId = $env:QCLAUDE_PROVIDER
if (-not $providerId) { $providerId = $config.provider }
$provider = Get-Content (Join-Path $PSScriptRoot "gateway\providers\$providerId.json") -Raw | ConvertFrom-Json

$base = "http://127.0.0.1:$($config.listen.port)"
$env:ANTHROPIC_BASE_URL   = $base
$env:ANTHROPIC_AUTH_TOKEN = 'local-gateway'
$env:ANTHROPIC_API_KEY    = ''
$env:ANTHROPIC_MODEL      = $provider.client.gateway.model
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $provider.client.gateway.opus
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $provider.client.gateway.sonnet
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $provider.client.gateway.haiku
$env:CLAUDE_CODE_SUBAGENT_MODEL     = $provider.client.gateway.subagent
$env:GATEWAY_PROVIDER = $providerId

function Test-Gateway {
    try {
        $r = Invoke-WebRequest "$base/health" -TimeoutSec 1 -UseBasicParsing
        return $r.StatusCode -eq 200
    } catch { return $false }
}

if (-not (Test-Gateway)) {
    Write-Host 'starting gateway...' -ForegroundColor DarkGray
    & (Join-Path $PSScriptRoot 'gateway\autostart.ps1')

    $up = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        if (Test-Gateway) { $up = $true; break }
    }
    if (-not $up) { throw 'gateway did not start; run: node gateway\server.mjs' }
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw 'claude not found on PATH. Install: npm install -g @anthropic-ai/claude-code'
}

# Continue, not Stop: claude writes warnings to stderr, and PowerShell 5.1
# turns that into a terminating NativeCommandError. Exit code still propagates.
$ErrorActionPreference = 'Continue'
& claude @args
if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
