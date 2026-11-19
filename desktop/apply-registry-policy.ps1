#Requires -RunAsAdministrator
# Claude Code reads managed settings from HKLM\SOFTWARE\Policies\ClaudeCode.
# The value name is "Settings" and it holds the whole settings JSON.
$ErrorActionPreference = 'Stop'

$key = 'HKLM:\SOFTWARE\Policies\ClaudeCode'
New-Item -Path $key -Force | Out-Null

$settings = @'
{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:8788","ANTHROPIC_AUTH_TOKEN":"local-gateway","ANTHROPIC_API_KEY":"","ANTHROPIC_MODEL":"claude-sonnet-4-5[1m]","ANTHROPIC_DEFAULT_OPUS_MODEL":"claude-opus-4-5","ANTHROPIC_DEFAULT_SONNET_MODEL":"claude-sonnet-4-5[1m]","ANTHROPIC_DEFAULT_HAIKU_MODEL":"claude-haiku-4-5","CLAUDE_GATEWAY_ALLOW_LOOPBACK":"true"}}
'@

Remove-ItemProperty -Path $key -Name 'env' -ErrorAction SilentlyContinue
New-ItemProperty -Path $key -Name 'Settings' -Value $settings -PropertyType String -Force | Out-Null

Write-Host "written: $key -> Settings" -ForegroundColor Green
Get-ItemProperty $key | Format-List
