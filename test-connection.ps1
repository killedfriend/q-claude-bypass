# Smoke test: does the selected provider key work against its Anthropic endpoint?
# Runs one tiny request. Costs a few tokens. Does not touch Claude Code.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'env.ps1')

$config = Get-Content (Join-Path $here 'gateway\config.json') -Raw | ConvertFrom-Json
$providerId = $env:QCLAUDE_PROVIDER
if (-not $providerId) { $providerId = $config.provider }
$provider = Get-Content (Join-Path $here "gateway\providers\$providerId.json") -Raw | ConvertFrom-Json

$body = @{
    model      = $provider.client.direct.haiku
    max_tokens = 32
    messages   = @(@{ role = 'user'; content = 'Reply with exactly: OK' })
} | ConvertTo-Json -Depth 5

$headers = @{
    'anthropic-version' = '2023-06-01'
}
if ($provider.auth.header -eq 'x-api-key') {
    $headers['x-api-key'] = $env:ANTHROPIC_AUTH_TOKEN
} else {
    $headers['Authorization'] = "Bearer $($env:ANTHROPIC_AUTH_TOKEN)"
}

try {
    $r = Invoke-RestMethod -Uri "$($provider.upstream)/v1/messages" `
        -Method Post `
        -Headers $headers `
        -ContentType 'application/json; charset=utf-8' `
        -Body $body
    $text = ($r.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ' '
    Write-Host "API OK [$($provider.name)]. model=$($r.model) reply='$text'" -ForegroundColor Green
    Write-Host "tokens: in=$($r.usage.input_tokens) out=$($r.usage.output_tokens)"
}
catch {
    Write-Host "API FAILED [$($provider.name)]: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message }
    exit 1
}
