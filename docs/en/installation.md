# Installation

> **Educational, non-commercial project.** This repository is a demonstration
> and learning project. It is not affiliated with Anthropic, DeepSeek, Tencent,
> Alibaba or OpenRouter. Do not use it commercially or in violation of provider
> terms. Use at your own risk.

## Requirements

- Windows 10 or 11 (x64).
- PowerShell 5.1 or newer.
- Internet access to GitHub, npm, nodejs.org and your provider.
- An API key from DeepSeek, Tencent Cloud, Alibaba Cloud Model Studio, or
  OpenRouter.
- Optional: `winget` (App Installer) for Claude Desktop. The installer falls
  back to a manual link if it is missing.
- Administrator rights and UAC approval for the default Claude Desktop MITM
  setup (hosts + Trusted Root). Use `-NoMitm` to skip it.

Node.js, Claude Code and Claude Desktop do not have to be installed beforehand.

## One-command install

Open a normal PowerShell window (administrator is not required for the core
install) and run:

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

If the execution policy blocks the command:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex"
```

The installer asks for:

1. the provider (DeepSeek, Tencent, Alibaba, OpenRouter);
2. the API key (hidden input).

The key is saved as a user environment variable and is never written to the
repository.

To pass installer switches (for example `-NoMitm`), download the script first:

```powershell
Invoke-WebRequest https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 -OutFile install.ps1
.\install.ps1 -NoMitm
```

### Non-interactive install

```powershell
$env:QCLAUDE_PROVIDER = 'alibaba'
$env:QCLAUDE_API_KEY  = 'sk-...'
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

Avoid putting a key directly on a command line: it can end up in the PowerShell
history or process list. Prefer the hidden prompt.

### Installer options

Run the script from a downloaded file to pass parameters:

```powershell
.\install.ps1 -Provider openrouter -InstallDir D:\Tools\QClaude
```

| Option | Meaning |
|---|---|
| `-Provider` | `deepseek`, `tencent`, `alibaba`, `openrouter` |
| `-ApiKey` | API key; if omitted, the installer prompts |
| `-InstallDir` | Install directory, default `%LOCALAPPDATA%\QClaudeCode` |
| `-ClaudeHome` | Claude settings directory, default `%USERPROFILE%\.claude` |
| `-SourceDir` | Install from a local checkout instead of a release ZIP |
| `-Repo` | GitHub repository used for the release download |
| `-Version` | Release version used for the download |
| `-SkipNode` | Do not check or install Node.js |
| `-SkipClaudeCode` | Do not install Claude Code |
| `-SkipClaudeDesktop` | Do not install Claude Desktop or configure its MITM |
| `-SkipAutostart` | Do not register the logon entry or start the gateway |
| `-SkipSmokeTest` | Do not send the verification request |
| `-NoPersistKey` | Keep the key only for this process (autostart will not see it) |
| `-NoStart` | Do not start the gateway after installation |
| `-NoMitm` | Skip the automatic Claude Desktop MITM (hosts, CA, port 443) |
| `-ConfigureDesktop` | Apply the experimental Desktop policy (requires UAC) |

## What the installer changes

| Location | Change |
|---|---|
| `%LOCALAPPDATA%\QClaudeCode` | Gateway, launchers, docs, examples |
| `%LOCALAPPDATA%\QClaudeCode\bin` | `qclaude` and `qclaude-gw` wrappers, added to user PATH |
| `%LOCALAPPDATA%\QClaudeCode\tools\node` | Portable Node.js, only if Node.js was missing and winget failed |
| `%USERPROFILE%\.claude\settings.json` | Adds gateway `ANTHROPIC_*` variables, keeps other settings |
| `%USERPROFILE%\.claude.json` | Sets `hasCompletedOnboarding: true` |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` | `QClaudeGateway` logon entry |
| User environment | Provider key variable, e.g. `DASHSCOPE_API_KEY` |
| Optional, with `-ConfigureDesktop` | `C:\Program Files\ClaudeCode\managed-settings.json` and `HKLM\SOFTWARE\Policies\ClaudeCode` |
| `%LOCALAPPDATA%\QClaudeCode\desktop\mitm` | Local CA certificate, `api.anthropic.com` PFX |
| Windows `hosts` | `127.0.0.1 api.anthropic.com` (marked `# qclaude-mitm`) |
| Windows Trusted Root | `CN=QClaude Local CA` |
| `%LOCALAPPDATA%\QClaudeCode\gateway\logs` | Runtime logs |

The installer does not modify Claude Code or Claude Desktop binaries.

The MITM step is a machine-wide change. While the gateway is stopped,
`api.anthropic.com` is unreachable on this machine because `hosts` points it to
`127.0.0.1`. Uninstall reverts the hosts entry, certificates and PFX. Use
`-NoMitm` if that trade-off is not acceptable.

## Verify

Open a new terminal so PATH and the user environment are visible.

```powershell
qclaude-gw
```

In another terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:8788/health
```

Expected fields include `"ok": true`, the selected `provider`, `routes`, and
`keyConfigured: true`.

Check TLS interception (MITM default):

```powershell
Invoke-WebRequest https://api.anthropic.com/health -UseBasicParsing
```

It should return the gateway health JSON through the trusted local certificate.
If it fails, check that the gateway is running, port 443 is free, and the PFX
exists in `%LOCALAPPDATA%\QClaudeCode\desktop\mitm`.

Run a cheap request:

```powershell
$body = @{
  model = 'claude-haiku-4-5'
  max_tokens = 32
  messages = @(@{ role = 'user'; content = 'Reply with exactly: OK' })
} | ConvertTo-Json -Depth 5

Invoke-RestMethod http://127.0.0.1:8788/v1/messages -Method Post `
  -Headers @{ 'x-api-key' = 'local-gateway'; 'anthropic-version' = '2023-06-01' } `
  -ContentType 'application/json' -Body $body
```

Show spend:

```powershell
node "$env:LOCALAPPDATA\QClaudeCode\gateway\report.mjs"
```

## Manual installation

Use this when you want to inspect or modify the source first.

```powershell
git clone https://github.com/killedfriend/q-claude-bypass.git
cd q-claude-bypass

# 1. Node.js 22+
node --version

# 2. Claude Code
npm install -g @anthropic-ai/claude-code

# 3. Provider key (example: DeepSeek)
[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY', 'sk-...', 'User')

# 4. Select the provider
#    edit gateway/config.json -> "provider": "deepseek"
#    or use the environment for the current process:
$env:GATEWAY_PROVIDER = 'deepseek'

# 5. Check the key
.\test-connection.ps1

# 6. Run
.\qclaude-gw.ps1
```

To make the gateway start at logon manually:

```powershell
$install = (Resolve-Path .).Path
$cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$install\gateway\autostart.ps1`""
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
  -Name 'QClaudeGateway' -Value $cmd -PropertyType String -Force
```

There is also a Scheduled Task helper:

```powershell
.\desktop\install-autostart.ps1          # requires administrator
.\desktop\install-autostart.ps1 -Remove
```

## Upgrade

Run the installer again. It stops the old gateway, replaces the runtime files,
keeps `gateway/logs`, and rewrites `gateway/config.json` with the selected
provider. If you edited routes or limits, back up the file first.

```powershell
copy "$env:LOCALAPPDATA\QClaudeCode\gateway\config.json" "$env:LOCALAPPDATA\QClaudeCode\gateway\config.backup.json"
```

Provider presets are replaced by the new release. Keep custom presets in a
separate `.local.json` file and point `provider` at it.

## Uninstall

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/uninstall.ps1 | iex
```

The uninstaller removes:

- the `QClaudeGateway` logon entry;
- the running gateway process;
- the `ANTHROPIC_*` variables added to `~/.claude/settings.json`;
- the install directory.

It keeps Claude Code, Claude Desktop and API keys by default. Add switches:

```powershell
.\uninstall.ps1 -RemoveApiKey -RemoveClaudeCode -RemoveClaudeDesktop
```

`-KeepSettings` leaves Claude settings untouched.

MITM cleanup runs automatically. If UAC is cancelled, the install directory is
kept so you can retry:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\QClaudeCode\desktop\mitm\teardown-mitm.ps1"
```

`-NoMitmCleanup` skips this step and leaves the hosts/certificate changes in
place.

## Claude Desktop

The installer configures Desktop through a local MITM by default:

- local CA `CN=QClaude Local CA` in Trusted Root;
- certificate `CN=api.anthropic.com` (SAN `api.anthropic.com`,
  `*.anthropic.com`);
- hosts entry `127.0.0.1 api.anthropic.com`;
- PFX used by the gateway TLS listener on `127.0.0.1:443`.

`-NoMitm` skips it. The experimental managed-settings policy is still available
with `-ConfigureDesktop`, and CC Switch is a third-party alternative. See
[troubleshooting](troubleshooting.md#claude-desktop).

## Next

- [Providers](providers.md)
- [Configuration](configuration.md)
- [Troubleshooting](troubleshooting.md)
- [Support the author](support.md)
