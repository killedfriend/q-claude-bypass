# Configuration

> **Educational, non-commercial project.** Configuration examples are provided
> for learning. You are responsible for provider terms, costs and data handling.

## Files

| File | Scope |
|---|---|
| `gateway/config.json` | Shared gateway settings: port, public models, routing, context, limits |
| `gateway/providers/<id>.json` | Provider: upstream, auth, models, pricing, capabilities |
| `%USERPROFILE%\.claude\settings.json` | Claude Code environment |
| `%USERPROFILE%\.claude.json` | Claude Code onboarding state |
| `gateway/logs/requests.jsonl` | One JSON object per request |
| `gateway/logs/gateway.pid` | Running gateway PID |
| `gateway/logs/last-request.json` | Full payload, only with `GATEWAY_DUMP=1` |

Environment overrides:

| Variable | Effect |
|---|---|
| `GATEWAY_PROVIDER` | Provider ID, overrides `config.json` |
| `GATEWAY_PORT` | Listen port |
| `GATEWAY_HOST` | Listen host (keep `127.0.0.1`) |
| `GATEWAY_UPSTREAM` | Override the provider upstream |
| `GATEWAY_LOG` | Override the log path |
| `GATEWAY_MAX_CHARS` | Context size threshold for pruning |
| `GATEWAY_DUMP` | `1` writes the full upstream request |
| `GATEWAY_TLS_PFX`, `GATEWAY_TLS_PASSPHRASE` | Windows TLS listener for Desktop MITM |
| `GATEWAY_TLS_CERT`, `GATEWAY_TLS_KEY` | PEM TLS listener |

## Shared config

```json
{
  "version": 2,
  "provider": "deepseek",
  "listen": { "host": "127.0.0.1", "port": 8788 },
  "logFile": "logs/requests.jsonl",
  "publicModels": [
    "claude-sonnet-4-5[1m]",
    "claude-opus-4-5",
    "claude-haiku-4-5"
  ],
  "routing": {
    "opusToHeavy": true,
    "haikuToCheap": true,
    "cheapWithoutTools": true
  },
  "context": {
    "enabled": true,
    "maxChars": 500000,
    "keepRecentToolResults": 8,
    "elideAboveChars": 4000
  },
  "limits": {
    "dailyBudget": 0,
    "maxRetries": 2,
    "timeoutMs": 600000
  }
}
```

| Key | Meaning |
|---|---|
| `provider` | Provider preset ID. Must have a matching file in `gateway/providers/` |
| `listen.host` | Bind address. Keep loopback unless you add authentication |
| `listen.port` | Default 8788 |
| `publicModels` | Model IDs Claude Code and Desktop see. Keep Claude-like names |
| `routing.opusToHeavy` | Requests with `opus` in the name use `models.heavy` |
| `routing.haikuToCheap` | Requests with `haiku` use `models.cheap` |
| `routing.cheapWithoutTools` | Requests without tools use `models.cheap` |
| `context.maxChars` | Body size threshold before pruning |
| `context.keepRecentToolResults` | Number of newest tool results never elided |
| `context.elideAboveChars` | Only elide tool results longer than this |
| `limits.dailyBudget` | Maximum spend per day in provider currency; `0` disables |
| `limits.maxRetries` | Retries on 408/429/5xx |
| `limits.timeoutMs` | Hard upstream timeout |

## Provider config

```json
{
  "name": "OpenRouter",
  "docs": "https://openrouter.ai/",
  "upstream": "https://openrouter.ai/api",
  "currency": "USD",
  "auth": {
    "mode": "gateway",
    "header": "authorization",
    "scheme": "Bearer ",
    "env": "OPENROUTER_API_KEY"
  },
  "headers": { "X-Title": "QClaude Code" },
  "models": {
    "main": "anthropic/claude-sonnet-4.5",
    "heavy": "anthropic/claude-opus-4.5",
    "cheap": "anthropic/claude-haiku-4.5"
  },
  "vision": ["anthropic/claude-sonnet-4.5"],
  "documents": "native",
  "cheapProfile": { "maxTokens": 4096 },
  "pricing": {
    "anthropic/claude-sonnet-4.5": { "input": 3, "cacheRead": 0.3, "output": 15 }
  },
  "client": {
    "direct":  { "model": "...", "opus": "...", "sonnet": "...", "haiku": "...", "subagent": "..." },
    "gateway": { "model": "claude-sonnet-4-5[1m]", "opus": "claude-opus-4-5", "sonnet": "claude-sonnet-4-5[1m]", "haiku": "claude-haiku-4-5", "subagent": "claude-sonnet-4-5" }
  }
}
```

| Key | Meaning |
|---|---|
| `upstream` | Base URL without `/v1/messages` |
| `currency` | `CNY`, `USD`, `EUR`; used in logs and reports |
| `auth.mode` | `gateway` uses the environment key; `passthrough` forwards the client key |
| `auth.header` | `authorization` or `x-api-key` |
| `auth.scheme` | `Bearer ` or empty string |
| `auth.env` | Environment variable that holds the key |
| `headers` | Extra static upstream headers |
| `models` | Actual upstream model IDs for `main`, `heavy`, `cheap` |
| `vision` | Models known to accept images |
| `documents` | `deepseek-files`, `native`, or `none` |
| `cacheControl` | `strip` (default) or `keep`; keep only if the provider supports it |
| `cheapProfile` | Mutations for cheap calls: `effort`, `thinking`, `maxTokens` |
| `pricing` | Per 1M tokens; optional `peak`/`offPeak` |
| `client.direct` | Model names for `qclaude.ps1` (direct mode) |
| `client.gateway` | Model names for `qclaude-gw.ps1` (public Claude names) |

## Routing

Request order:

1. If the requested model contains `opus` and `opusToHeavy` is on → `heavy`.
2. Else if it contains `haiku` and `haikuToCheap` is on → `cheap`.
3. Else if there are no tools and `cheapWithoutTools` is on → `cheap`.
4. Else → `main`.

Then:

- If the request contains an image and the selected model is not in `vision`,
  the gateway tries `main`. If `main` is not vision-capable either, the request
  proceeds and the log records `images: no vision-capable model configured`.
  The response header `x-gateway-route` shows the selected route;
  `x-gateway-model` shows the actual upstream model.

Cheap calls additionally apply `cheapProfile`:

```json
{ "effort": "low", "thinking": "disabled", "maxTokens": 4096 }
```

Only add `effort`/`thinking` if the provider accepts those fields.

## Context pruning

Long agent sessions resend the whole transcript every turn. When
`JSON.stringify(body).length` exceeds `context.maxChars`, the gateway replaces
the text of the oldest `tool_result` blocks with:

```text
[tool output elided by gateway: 12345 chars]
```

It never removes messages or `tool_use`/`tool_result` pairs. The transformation
is deterministic, so the provider prefix cache can still hit.

Disable with:

```json
{ "context": { "enabled": false } }
```

Or tune per run:

```powershell
$env:GATEWAY_MAX_CHARS = '300000'
```

Pruning saves money but can remove information the model still needs. Increase
`keepRecentToolResults` if the model starts asking for already-read files.

## Pricing and cost

`pricing` is per 1 million tokens in the provider currency:

```json
{
  "model-id": { "input": 3, "cacheRead": 0.3, "output": 15 }
}
```

DeepSeek supports time-based rates:

```json
{
  "deepseek-flash": {
    "peak":    { "cacheRead": 0.04, "input": 2, "output": 8 },
    "offPeak": { "cacheRead": 0.02, "input": 1, "output": 4 }
  }
}
```

Cost calculation:

```text
(input_tokens * input + cache_read_tokens * cacheRead + output_tokens * output) / 1e6
```

If the provider returns `usage.cost` (OpenRouter does), that value wins.
Server-side web search is added per call using `webPricing` (DeepSeek only).
Missing pricing produces `cost: null`, not zero; the report prints `-`.

The daily budget is checked before a request:

```json
{ "limits": { "dailyBudget": 5 } }
```

`5` means 5 units of `currency` per local day. Logs from other currencies are
not counted toward the budget.

## Logs

Each line in `requests.jsonl` is a JSON object:

```json
{
  "ts": "2026-11-19T12:00:00.000Z",
  "day": "2026-11-19",
  "provider": "openrouter",
  "currency": "USD",
  "route": "main",
  "reqModel": "claude-sonnet-4-5[1m]",
  "upModel": "anthropic/claude-sonnet-4.5",
  "status": 200,
  "ms": 1234,
  "stream": true,
  "in": 1234,
  "cacheRead": 1000,
  "out": 56,
  "thinking": 0,
  "cost": 0.0042,
  "upCost": 0.0042,
  "tools": ["Read", "Bash"],
  "toolTypes": ["custom"],
  "applied": [],
  "notes": [],
  "err": null
}
```

Prompt and completion text are not stored. Tool names and error snippets are.
`GATEWAY_DUMP=1` writes the full request to `logs/last-request.json`, including
prompts and file data; treat that file as sensitive.

Report:

```powershell
node gateway\report.mjs        # last 14 days
node gateway\report.mjs 30     # last 30 days
```

## Client settings

`qclaude-gw.ps1` sets the client environment per process:

```text
ANTHROPIC_BASE_URL=http://127.0.0.1:8788
ANTHROPIC_AUTH_TOKEN=local-gateway
ANTHROPIC_API_KEY=
```

`ANTHROPIC_API_KEY` must be empty, otherwise Claude Code may prefer it over
`ANTHROPIC_AUTH_TOKEN`.

The installed `~/.claude/settings.json` uses the same values, so running plain
`claude` in a new terminal also goes through the gateway. Remove those keys or
use `uninstall.ps1` to revert.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` or `/health` | Health, provider, routes, spend, key presence |
| `GET` | `/v1/models` | Claude-like model list for Desktop sign-in |
| `POST` | `/v1/messages` | Anthropic Messages proxy |
| `POST` | `/v1/messages/count_tokens` | Local token estimate |

`/health` example:

```json
{
  "ok": true,
  "provider": "deepseek",
  "upstream": "https://api.deepseek.com/anthropic",
  "requests": 12,
  "errors": 0,
  "currency": "CNY",
  "spentToday": 0.0312,
  "keyConfigured": true,
  "routes": { "main": "deepseek-flash[1m]", "heavy": "deepseek-v4-pro", "cheap": "deepseek-flash" }
}
```

## Autostart

The installer writes a per-user Run entry:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run\QClaudeGateway
```

It runs `gateway\autostart.ps1`, which checks `/health` and starts Node hidden
if the gateway is not running. Request records go to
`gateway\logs\requests.jsonl`; run `gateway\start.ps1` in a terminal to see
startup errors. There is no admin requirement and no Windows service.

To disable:

```powershell
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name QClaudeGateway
```

The alternative Scheduled Task helper is in `desktop\install-autostart.ps1`.

## Security

- Keep `listen.host` on `127.0.0.1`.
- The gateway ignores client credentials when `auth.mode` is `gateway`; any
  local process can use it. That is acceptable for a single-user desktop but
  not for a shared machine.
- Keys live in user environment variables. Do not commit `.env` or provider
  files containing keys.
- Logs contain metadata. Dumps contain content.
- MITM installs a local CA and changes `hosts`; understand the risks and use
  `teardown-mitm.ps1` to revert.
