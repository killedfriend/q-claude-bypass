#Requires -Version 5.1
<#
.SYNOPSIS
  Removes QClaude Code: gateway autostart, install directory and Claude settings.

.DESCRIPTION
  Claude Code and Claude Desktop are left installed unless you pass the
  corresponding switch. API keys are left in user environment unless -RemoveApiKey.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'QClaudeCode'),
    [string]$ClaudeHome = (Join-Path $env:USERPROFILE '.claude'),
    [switch]$RemoveApiKey,
    [switch]$RemoveClaudeCode,
    [switch]$RemoveClaudeDesktop,
    [switch]$KeepSettings
)

$ErrorActionPreference = 'Continue'

function Remove-EnvKeys([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    try {
        $obj = Get-Content $Path -Raw | ConvertFrom-Json
        if (-not $obj.PSObject.Properties['env']) { return }
        $ours = @(
            'ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY',
            'ANTHROPIC_MODEL', 'ANTHROPIC_DEFAULT_OPUS_MODEL',
            'ANTHROPIC_DEFAULT_SONNET_MODEL', 'ANTHROPIC_DEFAULT_HAIKU_MODEL',
            'CLAUDE_CODE_SUBAGENT_MODEL', 'CLAUDE_GATEWAY_ALLOW_LOOPBACK'
        )
        foreach ($k in $ours) {
            if ($obj.env.PSObject.Properties[$k]) {
                $obj.env.PSObject.Properties.Remove($k)
            }
        }
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($Path, (($obj | ConvertTo-Json -Depth 100) + "`n"), $utf8)
        Write-Host "cleaned $Path"
    } catch {
        Write-Host "could not clean $Path : $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host 'QClaude Code uninstaller' -ForegroundColor White

# 1. Autostart
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (Test-Path $runKey) {
    Remove-ItemProperty -Path $runKey -Name 'QClaudeGateway' -ErrorAction SilentlyContinue
    Write-Host 'removed logon entry QClaudeGateway'
}

# 2. Stop gateway
$pidFile = Join-Path $InstallDir 'gateway\logs\gateway.pid'
if (Test-Path $pidFile) {
    $saved = Get-Content $pidFile -Raw -ErrorAction SilentlyContinue
    if ($saved -and $saved.Trim() -match '^\d+$') {
        Stop-Process -Id ([int]$saved.Trim()) -Force -ErrorAction SilentlyContinue
        Write-Host 'stopped gateway'
    }
}

# 3. Claude settings
if (-not $KeepSettings) {
    Remove-EnvKeys (Join-Path $ClaudeHome 'settings.json')
    $claudeJson = Join-Path (Split-Path $ClaudeHome -Parent) '.claude.json'
    if (Test-Path $claudeJson) {
        try {
            $cj = Get-Content $claudeJson -Raw | ConvertFrom-Json
            $cj.PSObject.Properties.Remove('hasCompletedOnboarding')
            $utf8 = New-Object System.Text.UTF8Encoding($false)
            [IO.File]::WriteAllText($claudeJson, (($cj | ConvertTo-Json -Depth 100) + "`n"), $utf8)
            Write-Host "cleaned $claudeJson"
        } catch { }
    }
}

# 4. API keys
if ($RemoveApiKey) {
    foreach ($name in @('DEEPSEEK_API_KEY', 'TENCENT_API_KEY', 'DASHSCOPE_API_KEY', 'OPENROUTER_API_KEY')) {
        [Environment]::SetEnvironmentVariable($name, $null, 'User')
        Write-Host "removed user variable $name"
    }
}

# 5. Optional apps
if ($RemoveClaudeCode) {
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($npm) {
        & $npm.Source uninstall -g '@anthropic-ai/claude-code' 2>&1 | Out-Host
    }
}
if ($RemoveClaudeDesktop) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & winget uninstall --id Anthropic.Claude -e --silent 2>&1 | Out-Host
    }
}

# 6. Install directory
if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "removed $InstallDir"
}

Write-Host 'done' -ForegroundColor Green
