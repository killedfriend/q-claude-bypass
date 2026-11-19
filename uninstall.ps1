#Requires -Version 5.1
<#
.SYNOPSIS
  Removes QClaude Code: gateway autostart, install directory and Claude settings.

.DESCRIPTION
  Claude Code and Claude Desktop are left installed unless you pass the
  corresponding switch. API keys are left in user environment unless
  -RemoveApiKey. The Claude Desktop MITM (hosts entry, local CA, certificate)
  is removed automatically; use -NoMitmCleanup to keep it.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'QClaudeCode'),
    [string]$ClaudeHome = (Join-Path $env:USERPROFILE '.claude'),
    [switch]$RemoveApiKey,
    [switch]$RemoveClaudeCode,
    [switch]$RemoveClaudeDesktop,
    [switch]$KeepSettings,
    [switch]$NoMitmCleanup
)

$ErrorActionPreference = 'Continue'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedScript([string]$ScriptPath) {
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList $argLine
    return $p.ExitCode
}

function Remove-UserPath([string]$dir) {
    if (-not $dir) { return }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { return }
    $parts = @($userPath -split ';' | Where-Object { $_ -and $_ -ne $dir })
    $newPath = ($parts -join ';')
    if ($newPath -ne $userPath) {
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host "removed from user PATH: $dir"
    }
}

function Remove-EnvKeys([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    try {
        $obj = Get-Content $Path -Raw | ConvertFrom-Json
        if (-not $obj.PSObject.Properties['env']) { return }
        $ours = @(
            'ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY',
            'ANTHROPIC_MODEL', 'ANTHROPIC_DEFAULT_OPUS_MODEL',
            'ANTHROPIC_DEFAULT_SONNET_MODEL', 'ANTHROPIC_DEFAULT_HAIKU_MODEL',
            'CLAUDE_CODE_SUBAGENT_MODEL', 'CLAUDE_CODE_EFFORT_LEVEL',
            'CLAUDE_CODE_AUTO_COMPACT_WINDOW', 'CLAUDE_GATEWAY_ALLOW_LOOPBACK'
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
$candidates = @()
$pidFile = Join-Path $InstallDir 'gateway\logs\gateway.pid'
if (Test-Path $pidFile) {
    $saved = Get-Content $pidFile -Raw -ErrorAction SilentlyContinue
    if ($saved -and $saved.Trim() -match '^\d+$') { $candidates += [int]$saved.Trim() }
}
$conn = Get-NetTCPConnection -LocalPort 8788 -State Listen -ErrorAction SilentlyContinue
if ($conn) { $candidates += ($conn | Select-Object -ExpandProperty OwningProcess -Unique) }
foreach ($gatewayPid in ($candidates | Select-Object -Unique)) {
    if (Get-Process -Id $gatewayPid -ErrorAction SilentlyContinue) {
        Stop-Process -Id $gatewayPid -Force -ErrorAction SilentlyContinue
        Write-Host "stopped gateway pid $gatewayPid"
    }
}

# 3. MITM (hosts entry, local CA, certificate, PFX)
$mitmCleanupOk = $true
if (-not $NoMitmCleanup) {
    $mitmPfx = Join-Path $InstallDir 'desktop\mitm\api.anthropic.com.pfx'
    $hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hasHostsEntry = $false
    try { $hasHostsEntry = [bool](Select-String -Path $hosts -Pattern 'qclaude-mitm' -Quiet) } catch { }
    $hasMitm = $hasHostsEntry -or (Test-Path $mitmPfx)

    if ($hasMitm) {
        $helper = Join-Path $InstallDir 'desktop\mitm\teardown-mitm.ps1'
        if (-not (Test-Path $helper)) {
            Write-Host "MITM cleanup helper not found: $helper" -ForegroundColor Red
            Write-Host 'hosts still points api.anthropic.com to 127.0.0.1; fix it manually.' -ForegroundColor Red
            $mitmCleanupOk = $false
        } else {
            try {
                if (Test-Admin) {
                    & $helper
                    $code = $LASTEXITCODE
                } else {
                    Write-Host 'administrator rights are required to remove the MITM certificate; accepting UAC...'
                    $code = Invoke-ElevatedScript $helper
                }
                if ($code -ne 0) {
                    Write-Host "MITM cleanup returned exit code $code" -ForegroundColor Red
                    $mitmCleanupOk = $false
                } else {
                    Write-Host 'MITM certificate, hosts entry and PFX removed'
                }
            } catch {
                Write-Host "MITM cleanup was not completed: $($_.Exception.Message)" -ForegroundColor Red
                $mitmCleanupOk = $false
            }
        }
    }
} else {
    Write-Host 'MITM cleanup skipped (-NoMitmCleanup)'
}

# 4. Claude settings
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

# 5. API keys
if ($RemoveApiKey) {
    foreach ($name in @('DEEPSEEK_API_KEY', 'TENCENT_API_KEY', 'DASHSCOPE_API_KEY', 'OPENROUTER_API_KEY')) {
        [Environment]::SetEnvironmentVariable($name, $null, 'User')
        Write-Host "removed user variable $name"
    }
}

# 6. Optional apps
if ($RemoveClaudeCode) {
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($npm) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $npm.Source uninstall -g '@anthropic-ai/claude-code' 2>&1 | Out-Host
        $ErrorActionPreference = $previous
    }
}
if ($RemoveClaudeDesktop) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & winget uninstall --id Anthropic.Claude -e --silent 2>&1 | Out-Host
        $ErrorActionPreference = $previous
    }
}

# 7. Install directory and PATH entries
Remove-UserPath (Join-Path $InstallDir 'bin')
Remove-UserPath (Join-Path $InstallDir 'npm')
Remove-UserPath (Join-Path $InstallDir 'tools\node')
if (Test-Path $InstallDir) {
    if ($mitmCleanupOk) {
        Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "removed $InstallDir"
    } else {
        Write-Host "kept $InstallDir so MITM can be reverted" -ForegroundColor Yellow
        Write-Host "run: powershell -ExecutionPolicy Bypass -File `"$InstallDir\desktop\mitm\teardown-mitm.ps1`"" -ForegroundColor Yellow
    }
}

Write-Host 'done' -ForegroundColor Green
