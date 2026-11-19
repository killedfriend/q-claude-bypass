#Requires -RunAsAdministrator
# Pins Claude Desktop (and Claude Code) to the local gateway.
# Reversible: run revert-managed-settings.ps1 as administrator.
$ErrorActionPreference = 'Stop'

$dir = 'C:\Program Files\ClaudeCode'
$file = Join-Path $dir 'managed-settings.json'

New-Item -ItemType Directory -Force $dir | Out-Null

$json = @'
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8788",
    "ANTHROPIC_AUTH_TOKEN": "local-gateway",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "claude-sonnet-4-5[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-5[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
    "CLAUDE_GATEWAY_ALLOW_LOOPBACK": "true"
  }
}
'@

[IO.File]::WriteAllText($file, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "written: $file" -ForegroundColor Green
Write-Host 'Restart Claude Desktop and Claude Code sessions to pick this up.'
