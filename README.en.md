# QClaude Code

[Русский](README.ru.md) · [中文](README.zh-CN.md) · **English**

> **Educational, non-commercial project.** This repository was created solely
> for demonstration and learning purposes. It is not affiliated with or
> endorsed by Anthropic, DeepSeek, Tencent, Alibaba, or OpenRouter. It is not
> intended for commercial use, resale, bypassing paid access, or violating any
> provider's terms of service. Use it at your own risk; you are responsible for
> complying with all applicable terms and laws.

QClaude Code runs the real Claude Code and Claude Desktop against third-party
models through the official `ANTHROPIC_BASE_URL` mechanism. A small local
gateway sits between the client and the provider: it routes models, records
tokens and cost, retries failures, and removes blocks that a provider rejects.

The project started as a practical experiment: how far can you go with a
non-Anthropic backend without forking Claude Code or patching its binaries?

## What you get

- **The real Claude Code.** No client forks or patches. Only environment
  variables and a local HTTP gateway.
- **Four ready providers:** DeepSeek, Tencent Hunyuan, Alibaba Cloud Bailian
  (Qwen), OpenRouter. Add your own with one JSON file.
- **Model routing.** `opus` → heavy model, `haiku` and tool-less background
  calls → cheap model, everything else → main model.
- **Cost accounting.** Tokens, cache hits, request cost, web search, optional
  daily budget. For OpenRouter the exact `usage.cost` is used.
- **Protection from silent failures.** If a model cannot see images, the
  gateway does not send one silently; the route and reason are visible in the
  log and response headers.
- **Document handling.** For DeepSeek, PDFs are uploaded through the Files API
  and lifted out of `tool_result` to the top level of the message.
- **Context pruning.** Old tool results are elided so long sessions stop
  resending hundreds of thousands of tokens every turn.
- **Windows installer.** One command: Node.js, Claude Code, Claude Desktop,
  gateway, autostart, and a key smoke test.
- **Documentation in three languages** and settings examples for every
  provider.

## How it works

```text
Claude Code / Claude Desktop
        │  ANTHROPIC_BASE_URL=http://127.0.0.1:8788
        ▼
QClaude Gateway (Node.js, zero dependencies)
  ├─ selects the provider from gateway/config.json
  ├─ routes claude-opus / claude-sonnet / claude-haiku
  ├─ sanitizes the request: cache_control, document, attachments
  ├─ counts tokens, cache hits and cost
  └─ writes gateway/logs/requests.jsonl
        │
        ▼
DeepSeek / Tencent / Alibaba / OpenRouter
```

The provider receives a normal Anthropic Messages API request. Claude Code does
not know it is not talking to Anthropic: for the client it is just another
base URL.

## Providers

| Provider | Base URL | Key variable | Example models |
|---|---|---|---|
| DeepSeek | `https://api.deepseek.com/anthropic` | `DEEPSEEK_API_KEY` | `deepseek-flash[1m]`, `deepseek-v4-pro` |
| Tencent Hunyuan | `https://api.hunyuan.cloud.tencent.com/anthropic` | `TENCENT_API_KEY` | `hunyuan-2.0-instruct-20251111`, `hunyuan-2.0-thinking-20251109` |
| Alibaba Bailian | `https://dashscope.aliyuncs.com/apps/anthropic` | `DASHSCOPE_API_KEY` | `qwen3.7-plus`, `qwen3.7-max`, `qwen3.6-flash` |
| OpenRouter | `https://openrouter.ai/api` | `OPENROUTER_API_KEY` | `anthropic/claude-sonnet-4.5`, `anthropic/claude-opus-4.5`, `anthropic/claude-haiku-4.5` |

Exact model IDs change. Check the provider console, or the OpenRouter models
page. Alternative billing endpoints (Tencent TokenHub, Alibaba Coding Plan) and
full details are in [`docs/en/providers.md`](docs/en/providers.md).

> **Verification status.** The DeepSeek path was live-tested on 2026-11-19
> (request, streaming, tools, PDF, cost log). The Tencent, Alibaba and
> OpenRouter presets are based on the providers' official documentation and
> were not live-tested in this repository. Verify the model IDs and auth header
> for your account before relying on them.

## Quick start (Windows)

Requirements: Windows 10/11, PowerShell 5.1+, internet. The installer brings
Node.js 22+, Claude Code, Claude Desktop and `winget` dependencies if missing.

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

If execution policy blocks `irm | iex`:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex"
```

The installer:

1. checks Node.js 22+ and installs LTS if needed (winget or a portable ZIP in
   `%LOCALAPPDATA%\QClaudeCode\tools\node`);
2. installs `@anthropic-ai/claude-code` with npm;
3. installs Claude Desktop with `winget install Anthropic.Claude`;
4. copies the gateway to `%LOCALAPPDATA%\QClaudeCode`;
5. asks for a provider and API key (hidden input) and stores the key in a user
   environment variable;
6. adds the gateway to autostart at
   `HKCU\...\Run\QClaudeGateway`;
7. starts the gateway and sends one cheap request to verify the key.

Non-interactive install:

```powershell
$env:QCLAUDE_PROVIDER = 'alibaba'
$env:QCLAUDE_API_KEY  = 'sk-...'
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

Open a new terminal after installation:

```powershell
qclaude-gw
```

`qclaude-gw` is a wrapper around `claude`: it starts the gateway if necessary
and passes every argument to Claude Code unchanged.

Checks and diagnostics:

```powershell
Invoke-RestMethod http://127.0.0.1:8788/health
node "$env:LOCALAPPDATA\QClaudeCode\gateway\report.mjs"
Get-Content "$env:LOCALAPPDATA\QClaudeCode\gateway\logs\requests.jsonl" -Tail 5
```

Uninstall:

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/uninstall.ps1 | iex
```

## Manual use from the repository

```powershell
git clone https://github.com/killedfriend/q-claude-bypass.git
cd q-claude-bypass

.\test-connection.ps1      # one cheap request, verifies the key
.\qclaude.ps1              # direct to the provider
.\qclaude-gw.ps1           # through the local gateway
.\gateway\start.ps1        # gateway in the foreground
.\gateway\start.ps1 -Stop  # stop the background gateway
node gateway\report.mjs    # spend by day, model and provider
```

The default provider is DeepSeek. To switch:

```powershell
# edit gateway/config.json -> "provider": "alibaba"
# or set it for the current process only:
$env:GATEWAY_PROVIDER = 'alibaba'
.\gateway\start.ps1
```

The key lives in a user environment variable (`DEEPSEEK_API_KEY`,
`TENCENT_API_KEY`, `DASHSCOPE_API_KEY`, or `OPENROUTER_API_KEY`). No keys are
stored in the repository.

## Files

| Path | Purpose |
|---|---|
| `install.ps1` | One-command Windows installer |
| `install.cmd` | Double-click wrapper for the installer |
| `uninstall.ps1` | Removes autostart, gateway and client settings |
| `qclaude-gw.ps1` | Claude Code through the local gateway |
| `qclaude.ps1` | Claude Code directly to the provider |
| `env.ps1` | Provider selection, key, models, shared environment |
| `test-connection.ps1` | One-request key check |
| `gateway/server.mjs` | Gateway, Node 22, zero dependencies |
| `gateway/config.json` | Shared settings: port, routing, limits, logs |
| `gateway/providers/*.json` | Provider presets |
| `gateway/report.mjs` | Spend report |
| `gateway/lib/*.mjs` | Config, pricing, routing, context pruning |
| `desktop/` | Experimental Claude Desktop pinning (policy, MITM) |
| `examples/claude-settings/` | Direct-mode `~/.claude/settings.json` examples |
| `docs/en`, `docs/ru`, `docs/zh` | Full documentation |
| `scripts/build-release.ps1` | Builds the release ZIP and assets |

## Documentation

- [Installation](docs/en/installation.md) — installer, manual setup, upgrade,
  uninstall, autostart.
- [Providers](docs/en/providers.md) — Tencent, Alibaba, OpenRouter, DeepSeek:
  keys, endpoints, models, settings examples.
- [Configuration](docs/en/configuration.md) — gateway, routing, pricing, logs,
  budgets, environment variables.
- [Troubleshooting](docs/en/troubleshooting.md) — 401/404/429, models, Desktop,
  port, Node.js, UAC.

Русский: [`docs/ru`](docs/ru) · 中文: [`docs/zh`](docs/zh).

## Claude Desktop

The installer installs Claude Desktop but does **not** redirect its traffic
automatically: the app does not always read environment variables and
managed-settings. Options:

1. **CC Switch** — a third-party utility with local routing for Desktop.
2. **Experimental policy** — `install.ps1 -ConfigureDesktop` writes
   managed-settings and the registry policy; some Desktop builds ignore them.
3. **MITM** — `desktop/mitm/setup-mitm.ps1` creates a local CA and a certificate
   for `api.anthropic.com`, edits `hosts`, and enables the gateway TLS listener.
   This is the most reliable but also the most invasive method; administrator
   rights are required.

Read [`docs/en/troubleshooting.md`](docs/en/troubleshooting.md) and the security
section before using MITM. Rollback:
`desktop/mitm/teardown-mitm.ps1`.

## Security and limitations

- The gateway binds to `127.0.0.1` only and is not designed for network
  exposure. Do not set `listen.host` to `0.0.0.0` without authentication.
- API keys are stored in user environment variables, not in the repository.
- `gateway/logs/requests.jsonl` contains models, tokens, tool names and errors,
  but not prompt text. `GATEWAY_DUMP=1` writes the full request to
  `logs/last-request.json` — do not enable it on sensitive data.
- The project is unofficial. A Claude Code update or a provider API change can
  break it. Rollback is free: stop the gateway.
- Chinese public holidays are not modelled in DeepSeek peak pricing.
- `count_tokens` is an estimate; the context meter is approximate.
- Images and PDFs are supported differently by each provider. Check `notes` in
  the log and `x-gateway-route` in the response.
- Claude Desktop and MITM are experimental. Do not use them on a work machine
  without understanding the consequences.

## License

MIT. See [LICENSE](LICENSE).

Provided “as is”, without warranty. The authors are not responsible for costs,
data loss, or violations of provider terms.
