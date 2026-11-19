# Shared environment for the gateway: active provider key + optional TLS cert.
# Dot-source from any launcher.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

$config = Get-Content (Join-Path $here 'config.json') -Raw | ConvertFrom-Json
$providerId = $env:GATEWAY_PROVIDER
if (-not $providerId) { $providerId = $config.provider }
if (-not $providerId) { throw 'provider is not set in gateway\config.json' }

$providerFile = Join-Path $here "providers\$providerId.json"
if (-not (Test-Path $providerFile)) { throw "unknown provider '$providerId': $providerFile not found" }
$provider = Get-Content $providerFile -Raw | ConvertFrom-Json

$keyEnv = $provider.auth.env
if (-not $keyEnv) { throw "provider '$providerId' has no auth.env" }

$key = [Environment]::GetEnvironmentVariable($keyEnv, 'Process')
if (-not $key) {
    $key = [Environment]::GetEnvironmentVariable($keyEnv, 'User')
    if ($key) { [Environment]::SetEnvironmentVariable($keyEnv, $key, 'Process') }
}

$env:GATEWAY_PROVIDER = $providerId

$pfx = Join-Path $here '..\desktop\mitm\api.anthropic.com.pfx'
if ((Test-Path $pfx) -and -not $env:GATEWAY_TLS_PFX) {
    $env:GATEWAY_TLS_PFX = (Resolve-Path $pfx).Path
    $env:GATEWAY_TLS_PASSPHRASE = 'qclaude'
}
