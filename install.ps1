#Requires -Version 5.1
<#
.SYNOPSIS
  One-command Windows installer for QClaude Code.

.DESCRIPTION
  Installs Node.js if needed, Claude Code (npm), Claude Desktop (winget),
  the local gateway, a per-user logon autostart entry, and a local MITM
  certificate/hosts entry so Claude Desktop uses the gateway. Then runs a
  smoke test against the selected provider.

  MITM setup requires administrator rights and changes the machine-wide hosts
  file and Trusted Root store. Use -NoMitm to skip it, and uninstall.ps1 to
  revert it.

  Educational / non-commercial project. Use at your own risk.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -Provider alibaba

.EXAMPLE
  irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
#>
[CmdletBinding()]
param(
    # No ValidateSet here: Windows PowerShell rejects an unbound ValidateSet
    # parameter when the script is piped into Invoke-Expression (irm | iex).
    [string]$Provider,

    [string]$ApiKey,

    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'QClaudeCode'),

    [string]$ClaudeHome = (Join-Path $env:USERPROFILE '.claude'),

    [string]$SourceDir,

    [string]$Repo = 'killedfriend/q-claude-bypass',

    [string]$Version = '1.1.1',

    [switch]$SkipNode,
    [switch]$SkipClaudeCode,
    [switch]$SkipClaudeDesktop,
    [switch]$SkipAutostart,
    [switch]$SkipSmokeTest,
    [switch]$NoPersistKey,
    [switch]$NoStart,
    [switch]$NoMitm,
    [switch]$ConfigureDesktop
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:TempDir = $null
$script:Problems = @()
$script:MitmOk = $false

function Write-Step($text) {
    Write-Host ''
    Write-Host "==> $text" -ForegroundColor Cyan
}

function Write-Ok($text) { Write-Host "    $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "    $text" -ForegroundColor Yellow; $script:Problems += $text }

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

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($machine) { $parts += $machine }
    if ($user) { $parts += $user }
    if ($parts.Count -gt 0) { $env:Path = ($parts -join ';') }
}

function Add-UserPath([string]$dir) {
    if (-not $dir) { return }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($userPath) { $parts = @($userPath -split ';' | Where-Object { $_ }) }
    if ($parts -notcontains $dir) {
        $newPath = (($parts + $dir) -join ';')
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    }
    if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$env:Path;$dir" }
}

function Write-Utf8NoBom([string]$path, [string]$text) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($path, $text, $utf8)
}

function Get-NodeMajor {
    try {
        $v = (& node --version 2>$null)
        if ($v -match '^v(\d+)') { return [int]$Matches[1] }
    } catch { }
    return 0
}

function Resolve-Source {
    if ($SourceDir) {
        $candidate = (Resolve-Path $SourceDir).Path
        if (Test-Path (Join-Path $candidate 'gateway\server.mjs')) { return $candidate }
        throw "SourceDir does not contain gateway\server.mjs: $candidate"
    }

    $scriptRoot = $PSScriptRoot
    if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }
    if (Test-Path (Join-Path $scriptRoot 'gateway\server.mjs')) { return $scriptRoot }

    Write-Step 'Downloading release package'
    $script:TempDir = Join-Path ([IO.Path]::GetTempPath()) ("qclaude-install-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $script:TempDir | Out-Null

    $versioned = "https://github.com/$Repo/releases/download/v$Version/qclaude-code-$Version.zip"
    $latest = "https://github.com/$Repo/releases/latest/download/qclaude-code.zip"
    $zip = Join-Path $script:TempDir 'qclaude-code.zip'

    $urls = @($versioned, $latest)
    $downloaded = $false
    foreach ($url in $urls) {
        try {
            Write-Host "    $url"
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 120
            $downloaded = $true
            break
        } catch {
            Write-Host "    not available: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    }
    if (-not $downloaded) {
        throw "Could not download the release package. Check the repo name and network: https://github.com/$Repo/releases"
    }

    $expanded = Join-Path $script:TempDir 'expanded'
    Expand-Archive -Path $zip -DestinationPath $expanded -Force
    $server = Get-ChildItem $expanded -Recurse -Filter 'server.mjs' |
        Where-Object { $_.FullName -match '\\gateway\\server\.mjs$' } |
        Select-Object -First 1
    if (-not $server) { throw 'release package does not contain gateway\server.mjs' }
    return (Split-Path (Split-Path $server.FullName -Parent) -Parent)
}

function Ensure-Node {
    if ($SkipNode) { return }
    Write-Step 'Node.js'

    if ((Get-NodeMajor) -ge 22) {
        Write-Ok "found $(& node --version)"
        return
    }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host '    installing Node.js LTS with winget...'
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & winget install --id OpenJS.NodeJS.LTS -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Host
        $ErrorActionPreference = $previous
        Refresh-Path
        if ((Get-NodeMajor) -ge 22) {
            Write-Ok "installed $(& node --version)"
            return
        }
    }

    # No admin required: portable Node zip in the install directory.
    Write-Host '    falling back to a portable Node.js zip...'
    $index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -TimeoutSec 60
    $lts = $index | Where-Object { $_.lts -ne $false } | Select-Object -First 1
    if (-not $lts) { throw 'could not resolve the current Node.js LTS version' }

    $nodeRoot = Join-Path $InstallDir 'tools\node'
    New-Item -ItemType Directory -Force $nodeRoot | Out-Null
    $nodeZip = Join-Path $script:TempDir "node-$($lts.version)-win-x64.zip"
    if (-not $script:TempDir) {
        $script:TempDir = Join-Path ([IO.Path]::GetTempPath()) ("qclaude-install-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force $script:TempDir | Out-Null
        $nodeZip = Join-Path $script:TempDir 'node.zip'
    }
    $url = "https://nodejs.org/dist/$($lts.version)/node-$($lts.version)-win-x64.zip"
    Write-Host "    $url"
    Invoke-WebRequest -Uri $url -OutFile $nodeZip -UseBasicParsing -TimeoutSec 300
    $unpack = Join-Path $script:TempDir 'node-unpack'
    Expand-Archive -Path $nodeZip -DestinationPath $unpack -Force
    $inner = Get-ChildItem $unpack -Directory | Select-Object -First 1
    Copy-Item (Join-Path $inner.FullName '*') $nodeRoot -Recurse -Force

    Add-UserPath $nodeRoot
    Refresh-Path
    if ((Get-NodeMajor) -lt 22) { throw 'Node.js installation failed; install Node.js 22+ manually and rerun' }
    Write-Ok "installed portable $(& node --version) in $nodeRoot"
}

function Ensure-ClaudeCode {
    if ($SkipClaudeCode) { return }
    Write-Step 'Claude Code'

    $npmPath = $null
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($npm) { $npmPath = $npm.Source }
    if (-not $npmPath) {
        $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
        if ($nodeCmd) {
            $candidate = Join-Path (Split-Path $nodeCmd.Source -Parent) 'npm.cmd'
            if (Test-Path $candidate) { $npmPath = $candidate }
        }
    }
    if (-not $npmPath) { throw 'npm.cmd not found; install Node.js 22+ and rerun' }

    Write-Host '    npm install -g @anthropic-ai/claude-code@latest'
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $npmPath install -g '@anthropic-ai/claude-code@latest' 2>&1 | Out-Host
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous

    if ($code -ne 0) {
        Write-Warn 'global npm install failed, retrying into the user install directory'
        $prefix = Join-Path $InstallDir 'npm'
        New-Item -ItemType Directory -Force $prefix | Out-Null
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $npmPath install -g --prefix $prefix '@anthropic-ai/claude-code@latest' 2>&1 | Out-Host
        $fallbackCode = $LASTEXITCODE
        $ErrorActionPreference = $previous
        if ($fallbackCode -ne 0) { throw "Claude Code installation failed (npm exit code $fallbackCode)" }
        Add-UserPath $prefix
    }

    Refresh-Path
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) {
        $fallback = Join-Path (Join-Path $InstallDir 'npm') 'claude.cmd'
        if (Test-Path $fallback) {
            Add-UserPath (Split-Path $fallback -Parent)
            Write-Ok "installed to $fallback"
        } else {
            Write-Warn 'claude command not found on PATH yet; open a new terminal'
        }
    } else {
        Write-Ok "found $($claude.Source)"
    }
}

function Ensure-ClaudeDesktop {
    if ($SkipClaudeDesktop) { return }
    Write-Step 'Claude Desktop'

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Warn 'winget not found. Install Claude Desktop manually: https://claude.ai/download'
        return
    }

    $installed = $false
    try {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $list = (& winget list --id Anthropic.Claude -e --accept-source-agreements 2>$null | Out-String)
        $ErrorActionPreference = $previous
        if ($list -match 'Anthropic\.Claude') { $installed = $true }
    } catch { }

    if ($installed) {
        Write-Ok 'already installed'
        return
    }

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & winget install --id Anthropic.Claude -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Host
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) {
        Write-Warn 'winget could not install Claude Desktop. Use https://claude.ai/download'
    } else {
        Write-Ok 'installed'
    }
}

function Stop-Gateway {
    $pidFile = Join-Path $InstallDir 'gateway\logs\gateway.pid'
    $candidates = @()

    if (Test-Path $pidFile) {
        $saved = Get-Content $pidFile -Raw -ErrorAction SilentlyContinue
        if ($saved -and $saved.Trim() -match '^\d+$') { $candidates += [int]$saved.Trim() }
    }

    $conn = Get-NetTCPConnection -LocalPort 8788 -State Listen -ErrorAction SilentlyContinue
    if ($conn) { $candidates += ($conn | Select-Object -ExpandProperty OwningProcess -Unique) }

    foreach ($gatewayPid in ($candidates | Select-Object -Unique)) {
        $proc = Get-Process -Id $gatewayPid -ErrorAction SilentlyContinue
        if (-not $proc) { continue }
        $isGateway = $true
        try {
            $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$gatewayPid" -ErrorAction Stop
            $isGateway = [bool]($cim.CommandLine -match 'server\.mjs')
        } catch { }
        if ($isGateway) {
            Stop-Process -Id $gatewayPid -Force -ErrorAction SilentlyContinue
            Write-Host "    stopped old gateway (pid $gatewayPid)"
        }
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

function Copy-Runtime {
    param([string]$From, [string]$To)
    Write-Step "Installing gateway files to $To"
    New-Item -ItemType Directory -Force $To | Out-Null

    $files = @(
        'env.ps1', 'qclaude.ps1', 'qclaude-gw.ps1', 'test-connection.ps1',
        'README.md', 'README.ru.md', 'README.en.md', 'README.zh-CN.md',
        'LICENSE', 'CHANGELOG.md', 'VERSION'
    )
    foreach ($f in $files) {
        $src = Join-Path $From $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $To $f) -Force }
    }

    foreach ($dir in @('gateway', 'desktop', 'docs', 'examples')) {
        $srcDir = Join-Path $From $dir
        if (-not (Test-Path $srcDir)) { continue }
        Get-ChildItem $srcDir -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($srcDir.Length + 1)
            if ($rel -match '(^|\\)logs(\\|$)') { return }
            if ($_.Extension -eq '.pfx' -or $_.Name -eq 'setup.log') { return }
            $dst = Join-Path (Join-Path $To $dir) $rel
            New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
            Copy-Item $_.FullName $dst -Force
        }
    }

    # User-facing commands on PATH, so `qclaude-gw` works in a new terminal.
    $bin = Join-Path $To 'bin'
    New-Item -ItemType Directory -Force $bin | Out-Null
    $gwCmd = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$To\qclaude-gw.ps1`" %*`r`n"
    $directCmd = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$To\qclaude.ps1`" %*`r`n"
    Write-Utf8NoBom (Join-Path $bin 'qclaude-gw.cmd') $gwCmd
    Write-Utf8NoBom (Join-Path $bin 'qclaude.cmd') $directCmd
    Add-UserPath $bin
    Write-Ok 'files copied; qclaude-gw added to PATH'
}

function Select-Provider {
    if ($Provider) { return $Provider }

    Write-Step 'Provider'
    Write-Host '  1. DeepSeek'
    Write-Host '  2. Tencent Hunyuan'
    Write-Host '  3. Alibaba Cloud Bailian (Qwen)'
    Write-Host '  4. OpenRouter'
    Write-Host '  5. Homyak API (homyakstudio.ru, RUB)'
    $choice = Read-Host '  Choose provider [1]'
    switch ($choice) {
        '2' { return 'tencent' }
        '3' { return 'alibaba' }
        '4' { return 'openrouter' }
        '5' { return 'homyak' }
        default { return 'deepseek' }
    }
}

function Set-ApiKey {
    param([string]$ProviderId, [string]$ProviderFile)

    $provider = Get-Content $ProviderFile -Raw | ConvertFrom-Json
    $keyEnv = $provider.auth.env
    $key = $ApiKey
    if (-not $key) { $key = [Environment]::GetEnvironmentVariable($keyEnv, 'Process') }
    if (-not $key) { $key = [Environment]::GetEnvironmentVariable($keyEnv, 'User') }
    if (-not $key -and $env:QCLAUDE_API_KEY) { $key = $env:QCLAUDE_API_KEY }

    if (-not $key) {
        Write-Step "$($provider.name) API key"
        Write-Host "    create one: $($provider.docs)"
        Write-Host "    it will be stored as user variable $keyEnv"
        $secure = Read-Host '    Paste API key (input is hidden)' -AsSecureString
        $key = (New-Object System.Net.NetworkCredential('', $secure)).Password
    }
    if ([string]::IsNullOrWhiteSpace($key)) { throw 'No API key provided.' }

    if (-not $NoPersistKey) {
        [Environment]::SetEnvironmentVariable($keyEnv, $key, 'User')
        Write-Ok "saved $keyEnv as a user environment variable"
    } else {
        Write-Warn "NoPersistKey is set: autostart will not see $keyEnv"
    }
    [Environment]::SetEnvironmentVariable($keyEnv, $key, 'Process')
}

function Set-ProviderConfig {
    param([string]$ProviderId, [string]$GatewayDir)
    $path = Join-Path $GatewayDir 'config.json'
    $cfg = Get-Content $path -Raw | ConvertFrom-Json
    $cfg.provider = $ProviderId
    Write-Utf8NoBom $path (($cfg | ConvertTo-Json -Depth 100) + "`n")
    Write-Ok "provider = $ProviderId"
}

function Merge-ClaudeSettings {
    param([string]$Path, [hashtable]$EnvValues)

    $obj = $null
    if (Test-Path $Path) {
        try { $obj = Get-Content $Path -Raw | ConvertFrom-Json }
        catch {
            $backup = "$Path.bak-" + (Get-Date -Format 'yyyyMMddHHmmss')
            Copy-Item $Path $backup -Force
            Write-Warn "invalid JSON in $Path, backed up to $backup"
        }
    }
    if (-not $obj) { $obj = New-Object psobject }

    if (-not $obj.PSObject.Properties['env']) {
        $obj | Add-Member -NotePropertyName 'env' -NotePropertyValue (New-Object psobject) -Force
    }
    foreach ($k in $EnvValues.Keys) {
        $obj.env | Add-Member -NotePropertyName $k -NotePropertyValue ([string]$EnvValues[$k]) -Force
    }

    New-Item -ItemType Directory -Force (Split-Path $Path -Parent) | Out-Null
    if (Test-Path $Path) {
        $backup = "$Path.bak-" + (Get-Date -Format 'yyyyMMddHHmmss')
        Copy-Item $Path $backup -Force
    }
    Write-Utf8NoBom $Path (($obj | ConvertTo-Json -Depth 100) + "`n")
    Write-Ok "updated $Path"
}

function Configure-ClaudeClient {
    param([string]$GatewayDir, [string]$ClaudeHomeDir)

    Write-Step 'Claude Code settings'
    $base = 'http://127.0.0.1:8788'
    $settingsPath = Join-Path $ClaudeHomeDir 'settings.json'
    Merge-ClaudeSettings -Path $settingsPath -EnvValues @{
        'ANTHROPIC_BASE_URL'                = $base
        'ANTHROPIC_AUTH_TOKEN'              = 'local-gateway'
        'ANTHROPIC_API_KEY'                 = ''
        'ANTHROPIC_MODEL'                   = 'claude-sonnet-4-5[1m]'
        'ANTHROPIC_DEFAULT_OPUS_MODEL'      = 'claude-opus-4-5'
        'ANTHROPIC_DEFAULT_SONNET_MODEL'    = 'claude-sonnet-4-5[1m]'
        'ANTHROPIC_DEFAULT_HAIKU_MODEL'     = 'claude-haiku-4-5'
        'CLAUDE_CODE_SUBAGENT_MODEL'        = 'claude-sonnet-4-5'
        'CLAUDE_CODE_EFFORT_LEVEL'          = 'max'
        'CLAUDE_CODE_AUTO_COMPACT_WINDOW'   = '200000'
        'CLAUDE_GATEWAY_ALLOW_LOOPBACK'     = 'true'
    }

    # Skip the Anthropic onboarding screen for a third-party endpoint.
    $profileDir = Split-Path $ClaudeHomeDir -Parent
    $claudeJson = Join-Path $profileDir '.claude.json'
    if (Test-Path $claudeJson) {
        try {
            $cj = Get-Content $claudeJson -Raw | ConvertFrom-Json
            $cj | Add-Member -NotePropertyName 'hasCompletedOnboarding' -NotePropertyValue $true -Force
            Copy-Item $claudeJson "$claudeJson.bak-" -Force -ErrorAction SilentlyContinue
            Write-Utf8NoBom $claudeJson (($cj | ConvertTo-Json -Depth 100) + "`n")
        } catch { Write-Warn "could not update $claudeJson" }
    } else {
        Write-Utf8NoBom $claudeJson "{`n  `"hasCompletedOnboarding`": true`n}`n"
        Write-Ok "created $claudeJson"
    }
}

function Install-Autostart {
    param([string]$GatewayDir)

    Write-Step 'Gateway autostart'
    $autostart = Join-Path $GatewayDir 'autostart.ps1'
    if (-not (Test-Path $autostart)) { throw "autostart script not found: $autostart" }

    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$autostart`""
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $runKey -Force | Out-Null
    New-ItemProperty -Path $runKey -Name 'QClaudeGateway' -Value $cmd -PropertyType String -Force | Out-Null
    Write-Ok 'logon entry HKCU\...\Run\QClaudeGateway'

    if ($NoStart) { return }
    Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$autostart`"" -WindowStyle Hidden
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 250
        try {
            $r = Invoke-WebRequest 'http://127.0.0.1:8788/health' -TimeoutSec 1 -UseBasicParsing
            if ($r.StatusCode -eq 200) { Write-Ok 'gateway is running'; return }
        } catch { }
    }
    Write-Warn 'gateway did not answer /health yet; run gateway\start.ps1 in a terminal to see the startup error'
}

function Invoke-SmokeTest {
    if ($SkipSmokeTest -or $NoStart) { return }
    Write-Step 'Smoke test'
    $body = @{
        model      = 'claude-haiku-4-5'
        max_tokens = 32
        messages   = @(@{ role = 'user'; content = 'Reply with exactly: OK' })
    } | ConvertTo-Json -Depth 6

    try {
        $r = Invoke-RestMethod -Uri 'http://127.0.0.1:8788/v1/messages' -Method Post `
            -Headers @{ 'x-api-key' = 'local-gateway'; 'anthropic-version' = '2023-06-01' } `
            -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 180
        $text = ($r.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ' '
        Write-Ok "reply: $text"
        Write-Host "    tokens in=$($r.usage.input_tokens) out=$($r.usage.output_tokens)"
    } catch {
        Write-Warn "smoke test failed: $($_.Exception.Message)"
        if ($_.ErrorDetails.Message) { Write-Host "    $($_.ErrorDetails.Message)" -ForegroundColor DarkYellow }
        Write-Host '    check the key, provider status and gateway\logs\requests.jsonl' -ForegroundColor DarkYellow
    }
}

function Install-Mitm {
    if ($NoMitm -or $SkipClaudeDesktop) {
        Write-Step 'Claude Desktop MITM'
        Write-Ok 'skipped'
        return
    }

    Write-Step 'Claude Desktop MITM'
    $helper = Join-Path $InstallDir 'desktop\mitm\setup-mitm.ps1'
    $pfx = Join-Path $InstallDir 'desktop\mitm\api.anthropic.com.pfx'
    if (-not (Test-Path $helper)) { Write-Warn 'MITM helper not found'; return }

    try {
        if (Test-Admin) {
            & $helper
            $code = $LASTEXITCODE
        } else {
            Write-Host '    administrator rights are required; accepting the UAC prompt...'
            $code = Invoke-ElevatedScript $helper
        }
    } catch {
        Write-Warn 'MITM was not installed (UAC cancelled or helper failed)'
        return
    }

    if ($code -ne 0) {
        Write-Warn "MITM helper returned exit code $code"
        return
    }
    if (-not (Test-Path $pfx)) {
        Write-Warn 'MITM finished without a PFX; Claude Desktop traffic is not intercepted'
        return
    }

    Write-Ok 'local CA trusted, hosts points api.anthropic.com to 127.0.0.1'
    Write-Ok "PFX ready: $pfx"
    $script:MitmOk = $true
}

function Test-Mitm {
    if (-not $script:MitmOk -or $NoMitm -or $SkipClaudeDesktop -or $NoStart) { return }
    Write-Step 'MITM check'
    try {
        $r = Invoke-WebRequest 'https://api.anthropic.com/health' -UseBasicParsing -TimeoutSec 8
        if ($r.StatusCode -eq 200) {
            Write-Ok 'TLS interception is served by the gateway'
        } else {
            Write-Warn "TLS interception returned HTTP $($r.StatusCode)"
        }
    } catch {
        Write-Warn "could not verify TLS interception: $($_.Exception.Message)"
        Write-Host '    check host port 443, the PFX and the local CA trust' -ForegroundColor DarkYellow
    }
}

function Configure-DesktopPolicy {
    if (-not $ConfigureDesktop) { return }
    Write-Step 'Claude Desktop policy (optional)'
    $helper = Join-Path $InstallDir 'desktop\apply-desktop-policy.ps1'
    if (-not (Test-Path $helper)) { Write-Warn 'desktop helper not found'; return }

    if (Test-Admin) {
        & $helper
    } else {
        Write-Host '    administrator rights are required; accepting the UAC prompt...'
        try {
            $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$helper`""
            if ($p.ExitCode -ne 0) { Write-Warn 'desktop policy helper returned an error' }
        } catch {
            Write-Warn 'desktop policy was not applied (UAC cancelled)'
        }
    }
}

# ---------------------------------------------------------------------------
try {
    Write-Host ''
    Write-Host 'QClaude Code installer' -ForegroundColor White
    Write-Host 'Educational, non-commercial project. Provided as-is, without warranty.' -ForegroundColor DarkGray
    Write-Host "version $Version"

    if (-not $Provider -and $env:QCLAUDE_PROVIDER) { $Provider = $env:QCLAUDE_PROVIDER }
    if (-not $ApiKey -and $env:QCLAUDE_API_KEY) { $ApiKey = $env:QCLAUDE_API_KEY }

    $source = Resolve-Source
    Write-Ok "source: $source"

    Ensure-Node
    Ensure-ClaudeCode
    Ensure-ClaudeDesktop

    $providerId = Select-Provider
    if (-not $providerId) { $providerId = 'deepseek' }
    if ($providerId -notin @('deepseek', 'tencent', 'alibaba', 'openrouter', 'homyak')) {
        throw "unknown provider: $providerId"
    }
    $providerFile = Join-Path $source "gateway\providers\$providerId.json"
    if (-not (Test-Path $providerFile)) { throw "provider preset not found: $providerFile" }

    Stop-Gateway
    Copy-Runtime -From $source -To $InstallDir

    Set-ProviderConfig -ProviderId $providerId -GatewayDir (Join-Path $InstallDir 'gateway')
    Set-ApiKey -ProviderId $providerId -ProviderFile (Join-Path $InstallDir "gateway\providers\$providerId.json")
    Configure-ClaudeClient -GatewayDir (Join-Path $InstallDir 'gateway') -ClaudeHomeDir $ClaudeHome
    Configure-DesktopPolicy
    Install-Mitm

    if (-not $SkipAutostart) {
        Install-Autostart -GatewayDir (Join-Path $InstallDir 'gateway')
    } elseif (-not $NoMitm -and -not $SkipClaudeDesktop) {
        Write-Warn 'MITM is installed but autostart was skipped; Claude Desktop will not connect until the gateway is running'
    }
    Test-Mitm
    Invoke-SmokeTest

    $installMeta = [ordered]@{
        version     = $Version
        provider    = $providerId
        installDir  = $InstallDir
        installedAt = (Get-Date).ToUniversalTime().ToString('o')
        repo        = $Repo
        mitm        = [bool]$script:MitmOk
        mitmRequested = (-not $NoMitm -and -not $SkipClaudeDesktop)
    }
    Write-Utf8NoBom (Join-Path $InstallDir 'install.json') ($installMeta | ConvertTo-Json)

    Write-Step 'Done'
    Write-Host "    gateway : http://127.0.0.1:8788"
    if ($NoMitm) {
        Write-Host '    desktop : not intercepted (-NoMitm)'
    } elseif ($SkipClaudeDesktop) {
        Write-Host '    desktop : not installed (-SkipClaudeDesktop)'
    } elseif ($script:MitmOk) {
        Write-Host '    desktop : MITM on https://api.anthropic.com'
    } else {
        Write-Host '    desktop : MITM was requested but is not active; see warnings' -ForegroundColor Yellow
    }
    Write-Host "    logs    : $InstallDir\gateway\logs"
    Write-Host "    launch  : qclaude-gw"
    Write-Host "    report  : node `"$InstallDir\gateway\report.mjs`""
    Write-Host ''
    Write-Host '    Open a new terminal so PATH and environment variables are picked up.' -ForegroundColor Yellow
    Write-Host '    Educational / non-commercial project. Do not use it to break provider terms.' -ForegroundColor DarkGray

    if ($script:Problems.Count -gt 0) {
        Write-Host ''
        Write-Host 'Warnings:' -ForegroundColor Yellow
        $script:Problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
}
catch {
    Write-Host ''
    Write-Host "INSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}
finally {
    if ($script:TempDir -and (Test-Path $script:TempDir)) {
        Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
