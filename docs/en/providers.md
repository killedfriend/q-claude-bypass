# Providers

> **Educational, non-commercial project.** Provider names and endpoints are
> used only to describe interoperability. This project is not affiliated with
> them. Check current documentation, pricing and terms before use.

All five presets use an Anthropic-compatible endpoint. The gateway normalizes
model names, authentication and unsupported blocks, so Claude Code always sees
`claude-*` public model names.

## Summary

| Provider | Preset | Base URL | Auth | Default main model |
|---|---|---|---|---|
| DeepSeek | `gateway/providers/deepseek.json` | `https://api.deepseek.com/anthropic` | `Authorization: Bearer` + `DEEPSEEK_API_KEY` | `deepseek-flash[1m]` |
| Tencent Hunyuan | `gateway/providers/tencent.json` | `https://api.hunyuan.cloud.tencent.com/anthropic` | `x-api-key` + `TENCENT_API_KEY` | `hunyuan-2.0-instruct-20251111` |
| Alibaba Bailian | `gateway/providers/alibaba.json` | `https://dashscope.aliyuncs.com/apps/anthropic` | `Authorization: Bearer` + `DASHSCOPE_API_KEY` | `qwen3.7-plus` |
| OpenRouter | `gateway/providers/openrouter.json` | `https://openrouter.ai/api` | `Authorization: Bearer` + `OPENROUTER_API_KEY` | `anthropic/claude-sonnet-4.5` |
| Homyak API (Russia only) | `gateway/providers/homyak.json` | `https://api.homyakstudio.ru` | `Authorization: Bearer` + `HOMYAK_API_KEY` | `homyak-flash` |

Model IDs are examples and change over time.

> **Verification status.** DeepSeek was live-tested on 2026-11-19. Tencent,
> Alibaba, OpenRouter and Homyak API presets are based on the providers'
> official documentation and were not live-tested in this repository. Check the model
> IDs, endpoint and auth header for your account.

## DeepSeek

Create a key at <https://platform.deepseek.com/api_keys>.

```powershell
[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY', 'sk-...', 'User')
```

Direct Claude Code settings (`~/.claude/settings.json`):

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "sk-...",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "claude-sonnet-4-5[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-5[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
    "CLAUDE_CODE_SUBAGENT_MODEL": "claude-sonnet-4-5"
  }
}
```

Why the names look like Claude models: Claude Code validates model names
client-side. DeepSeek maps `claude-opus*` to `deepseek-v4-pro` and other
`claude*` names to `deepseek-flash`; the `[1m]` suffix selects a 1M context.
The gateway applies the same mapping explicitly, so the public names stay
stable even if the upstream IDs change.

DeepSeek-specific behavior in the gateway:

- **Vision routing.** `deepseek-v4-pro` silently ignores images. Requests with
  images are rerouted to `deepseek-flash` when a vision route exists.
- **PDF.** Inline `document` blocks are uploaded through the Files API
  (`rich_layout_recognition`) and cached by SHA-256. Nested documents inside
  `tool_result` are lifted to the top level of the user message.
- **Web search.** `usage.server_tool_use` is billed per call and added to the
  request cost.
- **Peak pricing.** Weekdays 09:00–12:00 and 14:00–18:00 Beijing time. Chinese
  holidays are not modelled.

## Tencent Hunyuan

Create an API key in the Hunyuan console:
<https://console.cloud.tencent.com/hunyuan>.

The Anthropic-compatible endpoint is:

```text
https://api.hunyuan.cloud.tencent.com/anthropic
```

Supported models in the current documentation are
`hunyuan-2.0-thinking-20251109` and `hunyuan-2.0-instruct-20251111`.
The API key is sent as `x-api-key` in the gateway preset. Tencent's Claude Code
guide uses `ANTHROPIC_AUTH_TOKEN` for direct mode; both routes are documented
by the provider.

Direct settings example:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.hunyuan.cloud.tencent.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "your-tencent-api-key",
    "ANTHROPIC_MODEL": "hunyuan-2.0-instruct-20251111",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "hunyuan-2.0-thinking-20251109",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "hunyuan-2.0-instruct-20251111",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "hunyuan-2.0-instruct-20251111",
    "CLAUDE_CODE_SUBAGENT_MODEL": "hunyuan-2.0-instruct-20251111"
  }
}
```

### Tencent TokenHub / Coding Plan

Tencent is migrating new model access to TokenHub. The Coding Plan endpoint is:

```text
https://api.lkeap.cloud.tencent.com/coding/anthropic
```

Use a Coding Plan key and the model name from the plan (for example `glm-5`).
To use it, copy `gateway/providers/tencent.json` to a local preset, change
`upstream`, `models`, `client`, and the key variable, then set `provider` in
`gateway/config.json`.

## Alibaba Cloud Bailian (Qwen)

Create an API key in the Model Studio console:
<https://bailian.console.aliyun.com/>.

Current Anthropic-compatible endpoints:

| Plan | Base URL |
|---|---|
| Pay-as-you-go | `https://dashscope.aliyuncs.com/apps/anthropic` |
| Coding Plan | `https://coding.dashscope.aliyuncs.com/apps/anthropic` |
| Token Plan | `https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic` |

The old endpoint `https://dashscope.aliyuncs.com/api/v2/apps/claude-code-proxy`
is deprecated and only serves retired models.

Direct settings example:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://dashscope.aliyuncs.com/apps/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "sk-...",
    "ANTHROPIC_MODEL": "qwen3.7-plus",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "qwen3.7-max",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "qwen3.7-plus",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "qwen3.6-flash",
    "CLAUDE_CODE_SUBAGENT_MODEL": "qwen3.7-plus"
  }
}
```

The API key type must match the endpoint. A pay-as-you-go `sk-` key will not
work with the Coding Plan or Token Plan endpoint.

Gateway preset defaults: `qwen3.7-plus` (main), `qwen3.7-max` (heavy),
`qwen3.6-flash` (cheap).

## OpenRouter

Create a key at <https://openrouter.ai/keys>.

OpenRouter exposes an Anthropic Messages endpoint at:

```text
https://openrouter.ai/api/v1/messages
```

Claude Code appends `/v1/messages` to `ANTHROPIC_BASE_URL`, so the base URL is
`https://openrouter.ai/api` (not `.../api/v1`).

Direct settings example:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://openrouter.ai/api",
    "ANTHROPIC_AUTH_TOKEN": "sk-or-v1-...",
    "ANTHROPIC_MODEL": "anthropic/claude-sonnet-4.5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "anthropic/claude-opus-4.5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "anthropic/claude-sonnet-4.5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "anthropic/claude-haiku-4.5",
    "CLAUDE_CODE_SUBAGENT_MODEL": "anthropic/claude-sonnet-4.5"
  }
}
```

The gateway preset also sends `HTTP-Referer` and `X-Title` headers, which
OpenRouter uses for attribution. Replace the example repository URL in
`gateway/providers/openrouter.json` if you publish your own fork.

OpenRouter returns `usage.cost` in the response. The gateway stores that exact
value instead of estimating from the price table; the table is only a fallback.

## Homyak API (Russia only)

A Russian service with an Anthropic-compatible endpoint to DeepSeek. It is
intended for users in Russia: the balance and billing are in RUB, and it
accepts local payment methods, so no foreign card is needed.

- Sign up, top up and create a key:
  <https://homyakstudio.ru/?utm_source=github>.
- Payment: Russian bank card, SBP, MirPay and SberPay; top-up from 500 ₽,
  invoices for companies from 1 000 ₽.
- Anthropic base URL: `https://api.homyakstudio.ru` (Claude Code appends
  `/v1/messages`).
- The `sk-hmk-…` key is sent as `Authorization: Bearer`.

There is one model, `homyak-flash` (DeepSeek V4.1 Flash): 1M context, 384K
output, images, tools. Prices in RUB per 1M tokens:

| Tariff | Input | Cache | Output |
|---|---|---|---|
| Peak (weekdays 09:00–12:00 and 14:00–18:00 Beijing) | 39.00 ₽ | 0.78 ₽ | 156.00 ₽ |
| Off-peak | 19.50 ₽ | 0.39 ₽ | 78.00 ₽ |

Direct settings:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.homyakstudio.ru",
    "ANTHROPIC_AUTH_TOKEN": "sk-hmk-...",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "homyak-flash",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "homyak-flash",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "homyak-flash",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "homyak-flash",
    "CLAUDE_CODE_SUBAGENT_MODEL": "homyak-flash"
  }
}
```

In the gateway preset all three roles (`main`, `heavy`, `cheap`) point at
`homyak-flash`, and `currency` is `RUB`: `report.mjs` and the daily budget
count in rubles at peak/off-peak rates. PDFs are not supported; the gateway
strips `document` blocks and records the reason in `notes`.

## Switching providers

Edit `gateway/config.json`:

```json
{ "provider": "alibaba" }
```

Or set it for one process:

```powershell
$env:GATEWAY_PROVIDER = 'openrouter'
.\gateway\start.ps1
```

Restart the gateway after editing the config. Running requests are not
reloaded.

The installer writes the provider into `gateway/config.json` and stores the key
in the matching user variable.

## Adding a custom provider

1. Copy `gateway/providers/openrouter.json` to
   `gateway/providers/my-provider.json`.
2. Set `name`, `docs`, `upstream`, `currency`, `auth`, `models`, `vision`,
   `documents`, `pricing` and `client`.
3. Set `"provider": "my-provider"` in `gateway/config.json`.
4. Put the key in the variable named by `auth.env`.
5. Restart the gateway and check `GET /health`.

Provider ID must match `[a-z0-9][a-z0-9_-]*`. Provider files are loaded from
`gateway/providers/`.

Minimal example:

```json
{
  "name": "My Provider",
  "upstream": "https://api.example.com/anthropic",
  "currency": "USD",
  "auth": {
    "mode": "gateway",
    "header": "authorization",
    "scheme": "Bearer ",
    "env": "MY_PROVIDER_API_KEY"
  },
  "models": {
    "main": "model-main",
    "heavy": "model-heavy",
    "cheap": "model-cheap"
  },
  "vision": ["model-main"],
  "documents": "native",
  "cheapProfile": { "maxTokens": 4096 },
  "pricing": {},
  "client": {
    "direct": { "model": "model-main", "opus": "model-heavy", "sonnet": "model-main", "haiku": "model-cheap", "subagent": "model-main" },
    "gateway": { "model": "claude-sonnet-4-5[1m]", "opus": "claude-opus-4-5", "sonnet": "claude-sonnet-4-5[1m]", "haiku": "claude-haiku-4-5", "subagent": "claude-sonnet-4-5" }
  }
}
```

## Examples

Direct-mode settings for all providers:

- `examples/claude-settings/deepseek.settings.json`
- `examples/claude-settings/tencent.settings.json`
- `examples/claude-settings/alibaba.settings.json`
- `examples/claude-settings/openrouter.settings.json`
- `examples/claude-settings/homyak.settings.json`

These are templates: replace `<YOUR_..._KEY>` and merge the `env` block into
your existing `~/.claude/settings.json`. Do not overwrite unrelated settings.

## Compatibility notes

| Feature | DeepSeek | Tencent | Alibaba | OpenRouter | Homyak API |
|---|---|---|---|---|---|
| Streaming | yes | yes | yes | yes | yes |
| Tools | yes | yes | yes | yes | yes |
| Images | flash only; gateway reroutes | provider-dependent | provider-dependent | model-dependent | yes |
| PDF | Files API | omitted | omitted | native | omitted |
| Server-side web search | billed and logged | provider-dependent | provider-dependent | provider-dependent | no |
| Exact cost from response | no | no | no | yes (`usage.cost`) | no |

Provider features change. If a request fails, inspect
`gateway/logs/requests.jsonl`, the `notes` field, and `x-gateway-route`.
