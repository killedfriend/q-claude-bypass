# macOS

> **Educational, non-commercial project.** macOS support is an MVP. The scripts
> are checked in GitHub Actions on `macos-latest`, but a live Claude Desktop,
> certificate trust and GUI flow have not been tested on a real Mac. Use at your
> own risk.

## What is supported

- Node.js gateway (already cross-platform).
- `qclaude` and `qclaude-gw` launchers for Claude Code.
- LaunchAgent autostart `com.qclaude.gateway`.
- Claude Desktop MITM: local CA via `openssl`, trust via `security`, `hosts`,
  and `pfctl` redirect `443 → 8443`.
- `.zip` and `.pkg` builds on a macOS GitHub Actions runner.

## Requirements

- macOS 12+ (Apple Silicon or Intel).
- Node.js 22+.
- Claude Code (`npm install -g @anthropic-ai/claude-code`).
- Claude Desktop optional; the installer tries `brew install --cask claude`.
- Administrator password for MITM: `hosts`, System keychain, `pfctl`.
- Xcode Command Line Tools are not required for users; the package builder needs
  `pkgbuild`.

## Install from ZIP (recommended)

Download `QClaudeCode-<version>-macos.zip` from Releases and unzip it.

In Finder:

1. Open the `QClaudeCode-<version>` folder.
2. Right-click `install.command` → **Open**. If macOS warns about an unknown
   developer, repeat right-click → Open.
3. Choose a provider and paste the API key.
4. Approve the administrator password prompt for MITM.

From Terminal:

```bash
cd ~/Downloads/QClaudeCode-*
bash macos/install.sh
```

Useful flags:

```bash
bash macos/install.sh --provider deepseek
bash macos/install.sh --provider homyak
bash macos/install.sh --provider openrouter --no-mitm
bash macos/install.sh --skip-desktop
bash macos/install.sh --install-dir "$HOME/QClaude"
```

The same provider presets as Windows are available: DeepSeek, Tencent, Alibaba,
OpenRouter and Homyak API.

## Install from PKG

The `.pkg` is unsigned. It installs the runtime into `/usr/local/share/qclaude`
and the `qclaude-setup` command.

1. Right-click the `.pkg` → **Open** (Gatekeeper).
2. After installation, open Terminal:

```bash
qclaude-setup
```

`qclaude-setup` runs the same per-user installer: copies files to
`~/Library/Application Support/QClaudeCode`, stores the key, installs the
LaunchAgent and configures MITM unless `--no-mitm` is passed.

The package is not signed or notarized. A proper distribution needs an Apple
Developer account, signing and notarization.

## What the installer changes

| Path | Purpose |
|---|---|
| `~/Library/Application Support/QClaudeCode` | Gateway, launchers, docs, env |
| `~/Library/Application Support/QClaudeCode/env` | API key, mode `600` |
| `~/.zshrc` | Adds `.../QClaudeCode/bin` to PATH |
| `~/Library/LaunchAgents/com.qclaude.gateway.plist` | Gateway autostart |
| `~/.claude/settings.json` | `ANTHROPIC_*` for Claude Code |
| `~/.claude.json` | `hasCompletedOnboarding: true` |
| `/etc/hosts` | `127.0.0.1 api.anthropic.com` (MITM only) |
| System keychain | `QClaude Local CA` (MITM only) |
| `/etc/pf.conf`, `/etc/pf.anchors/com.qclaude` | Redirect 443 → 8443 |
| `/Library/LaunchDaemons/com.qclaude.pf.plist` | Restores pf at boot |

## MITM and pfctl

macOS does not allow a normal user to listen on port 443. Therefore:

```text
Claude Desktop → https://api.anthropic.com:443
      │ hosts → 127.0.0.1
      ▼
pfctl redirect 443 → 127.0.0.1:8443
      ▼
QClaude gateway TLS (user, 8443) → DeepSeek / Tencent / Alibaba / OpenRouter
```

`macos/mitm/setup.sh`:

1. creates a CA and an `api.anthropic.com` certificate with OpenSSL;
2. trusts the CA in the System keychain via `security`;
3. adds `127.0.0.1 api.anthropic.com` to `/etc/hosts`;
4. creates `/etc/pf.anchors/com.qclaude` and references it from `/etc/pf.conf`;
5. installs the `com.qclaude.pf` LaunchDaemon to restore pf at boot;
6. enables and loads pf.

Check:

```bash
curl -k https://api.anthropic.com/health
# should return the gateway health JSON
```

Skip MITM:

```bash
bash macos/install.sh --no-mitm
```

Remove it later:

```bash
sudo env QCLAUDE_HOME="$HOME/Library/Application Support/QClaudeCode" \
  "$HOME/Library/Application Support/QClaudeCode/macos/mitm/teardown.sh"
```

## Commands

```bash
qclaude-gw                 # Claude Code through the gateway
qclaude-gw -p "..."        # headless
qclaude                    # direct to the provider

~/"Library/Application Support/QClaudeCode/gateway/start.sh" --background
~/"Library/Application Support/QClaudeCode/gateway/start.sh" --stop
curl http://127.0.0.1:8788/health
```

Open a new terminal after installation, or run:

```bash
source ~/.zshrc
```

## Uninstall

```bash
bash ~/"Library/Application Support/QClaudeCode/macos/uninstall.sh"
```

Options:

```bash
--keep-settings       leave ~/.claude/settings.json untouched
--no-mitm-cleanup     keep hosts, CA and pf rules
--remove-key          delete the key file
```

If MITM teardown is cancelled, the install directory is kept for a retry.

## Limitations

- Claude Desktop GUI and system certificate trust have not been tested on a real
  Mac.
- `pfctl` redirect on loopback may behave differently across macOS versions;
  verify with `curl -k https://api.anthropic.com/health`.
- The `.pkg` is unsigned; Gatekeeper will warn.
- Corporate VPN, TLS inspection and managed Macs may conflict with MITM.
- Models, prices and provider APIs change; check provider documentation.
- Not affiliated with Anthropic, DeepSeek, Tencent, Alibaba or OpenRouter.

## Troubleshooting

```bash
# gateway
curl -v http://127.0.0.1:8788/health
tail -n 50 ~/"Library/Application Support/QClaudeCode/gateway/logs/launchd.err.log"

# LaunchAgent
launchctl print "gui/$(id -u)/com.qclaude.gateway"

# hosts / cert / pf
grep qclaude-mitm /etc/hosts
security find-certificate -c "QClaude Local CA" /Library/Keychains/System.keychain
sudo pfctl -s nat | grep 8443
sudo pfctl -a com.qclaude -sr

# gateway TLS
lsof -nP -iTCP:8443 -sTCP:LISTEN
```

If MITM stops working after a reboot, check the LaunchDaemon:

```bash
sudo launchctl print system/com.qclaude.pf
sudo pfctl -E
sudo pfctl -f /etc/pf.conf
```
