# Claude Code -> selected provider (direct Anthropic-compatible endpoint).
# Dot-source:  . .\env.ps1
# Or use a launcher:  .\qclaude.ps1  (direct)  /  .\qclaude-gw.ps1  (gateway)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

$config = Get-Content (Join-Path $here 'gateway\config.json') -Raw | ConvertFrom-Json
$providerId = $env:QCLAUDE_PROVIDER
if (-not $providerId) { $providerId = $config.provider }
if (-not $providerId) { throw 'provider is not set in gateway\config.json' }

$providerFile = Join-Path $here "gateway\providers\$providerId.json"
if (-not (Test-Path $providerFile)) { throw "unknown provider '$providerId': $providerFile not found" }
$provider = Get-Content $providerFile -Raw | ConvertFrom-Json

# --- API key -------------------------------------------------------------
$keyEnv = $provider.auth.env
$key = [Environment]::GetEnvironmentVariable($keyEnv, 'Process')
if (-not $key) { $key = [Environment]::GetEnvironmentVariable($keyEnv, 'User') }

if (-not $key) {
    Write-Host "$($provider.name) API key not found (variable $keyEnv)." -ForegroundColor Yellow
    Write-Host "Create a key: $($provider.docs)" -ForegroundColor Yellow
    $secure = Read-Host 'Paste API key (input is hidden)' -AsSecureString
    $plain = (New-Object System.Net.NetworkCredential('', $secure)).Password
    if ([string]::IsNullOrWhiteSpace($plain)) { throw 'No key provided.' }
    [Environment]::SetEnvironmentVariable($keyEnv, $plain, 'User')
    [Environment]::SetEnvironmentVariable($keyEnv, $plain, 'Process')
    $key = $plain
    Write-Host "Saved as user environment variable $keyEnv (not in this repo)." -ForegroundColor Green
}

# --- Route Claude Code to the provider ------------------------------------
$env:ANTHROPIC_BASE_URL   = $provider.upstream
$env:ANTHROPIC_AUTH_TOKEN = $key
$env:ANTHROPIC_API_KEY    = ''
$env:ANTHROPIC_MODEL      = $provider.client.direct.model
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $provider.client.direct.opus
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $provider.client.direct.sonnet
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $provider.client.direct.haiku
$env:CLAUDE_CODE_SUBAGENT_MODEL     = $provider.client.direct.subagent

# Agent sessions are long, but a huge context is resent on every turn.
# 200000 is the cost/quality sweet spot; raise it deliberately if needed.
$env:CLAUDE_CODE_EFFORT_LEVEL        = 'max'
$env:CLAUDE_CODE_AUTO_COMPACT_WINDOW = '200000'

Write-Host "Claude Code -> $($provider.name)  [$env:ANTHROPIC_MODEL]" -ForegroundColor Cyan
