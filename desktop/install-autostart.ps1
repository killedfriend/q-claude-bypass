# Registers a logon task that starts the gateway (with TLS) before you open Claude.
#   .\desktop\install-autostart.ps1
#   .\desktop\install-autostart.ps1 -Remove
param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$taskName = 'QClaude Gateway'
$script = Join-Path (Split-Path $PSScriptRoot -Parent) 'gateway\autostart.ps1'

if ($Remove) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "removed task: $taskName"
    return
}

if (-not (Test-Path $script)) { throw "not found: $script" }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
    -Description 'Local Anthropic-compatible gateway for Claude Code / Claude Desktop' -Force | Out-Null

Write-Host "registered task: $taskName" -ForegroundColor Green
Write-Host "it runs at logon: $script"
