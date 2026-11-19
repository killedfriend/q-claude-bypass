# 服务商

> **教学用非商业项目。** 文中服务商名称和端点仅用于说明兼容性。本项目与它们
> 无关联。使用前请确认最新文档、价格和条款。

四个预设都使用 Anthropic 兼容端点。网关会统一模型名、认证方式和不支持的
请求块，因此 Claude Code 始终看到 `claude-*` 公共模型名。

## 概览

| 服务商 | 预设 | Base URL | 认证 | 默认主模型 |
|---|---|---|---|---|
| DeepSeek | `gateway/providers/deepseek.json` | `https://api.deepseek.com/anthropic` | `Authorization: Bearer` + `DEEPSEEK_API_KEY` | `deepseek-flash[1m]` |
| 腾讯混元 | `gateway/providers/tencent.json` | `https://api.hunyuan.cloud.tencent.com/anthropic` | `x-api-key` + `TENCENT_API_KEY` | `hunyuan-2.0-instruct-20251111` |
| 阿里云百炼 | `gateway/providers/alibaba.json` | `https://dashscope.aliyuncs.com/apps/anthropic` | `Authorization: Bearer` + `DASHSCOPE_API_KEY` | `qwen3.7-plus` |
| OpenRouter | `gateway/providers/openrouter.json` | `https://openrouter.ai/api` | `Authorization: Bearer` + `OPENROUTER_API_KEY` | `anthropic/claude-sonnet-4.5` |

模型 ID 只是示例，会随时间变化。

> **验证状态。** DeepSeek 已在 2026-11-19 用真实请求验证。腾讯、阿里云和
> OpenRouter 预设基于官方文档编写，未在本仓库中做真实请求验证。请核对账户
> 支持的模型 ID、端点和认证头。

## DeepSeek

创建密钥：<https://platform.deepseek.com/api_keys>。

```powershell
[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY', 'sk-...', 'User')
```

Claude Code 直连设置（`~/.claude/settings.json`）：

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

为什么模型名看起来像 Claude：Claude Code 会在客户端校验模型名。DeepSeek 在
服务端把 `claude-opus*` 映射为 `deepseek-v4-pro`，其他 `claude*` 映射为
`deepseek-flash`；`[1m]` 后缀启用 1M 上下文。网关显式做同样的映射，因此公共
名称保持稳定。

DeepSeek 在网关中的特殊行为：

- **图像路由。** `deepseek-v4-pro` 会静默忽略图片。存在视觉路由时，含图片的
  请求会改走 `deepseek-flash`。
- **PDF。** 内联 `document` 通过 Files API（`rich_layout_recognition`）上传，
  并按 SHA-256 缓存。`tool_result` 内的文档会被提升到用户消息顶层。
- **联网搜索。** `usage.server_tool_use` 按次计费，并计入请求费用。
- **峰谷价格。** 北京时间工作日 09:00–12:00 和 14:00–18:00。中国法定节假日
  未建模。

## 腾讯混元

在混元控制台创建密钥：<https://console.cloud.tencent.com/hunyuan>。

Anthropic 兼容端点：

```text
https://api.hunyuan.cloud.tencent.com/anthropic
```

当前文档支持的模型：`hunyuan-2.0-thinking-20251109` 和
`hunyuan-2.0-instruct-20251111`。网关预设使用 `x-api-key` 发送密钥。腾讯的
Claude Code 指南在直连模式使用 `ANTHROPIC_AUTH_TOKEN`；两种方式都由服务商
文档覆盖。

直连设置：

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

### 腾讯 TokenHub / Coding Plan

腾讯正在把新模型接入迁移到 TokenHub。Coding Plan 端点：

```text
https://api.lkeap.cloud.tencent.com/coding/anthropic
```

使用 Coding Plan 密钥和套餐中的模型名（例如 `glm-5`）。复制
`gateway/providers/tencent.json` 为本地预设，修改 `upstream`、`models`、
`client` 和密钥变量，然后在 `gateway/config.json` 中设置 `provider`。

## 阿里云百炼（Qwen）

创建密钥：<https://bailian.console.aliyun.com/>。

当前 Anthropic 兼容端点：

| 套餐 | Base URL |
|---|---|
| 按量付费 | `https://dashscope.aliyuncs.com/apps/anthropic` |
| Coding Plan | `https://coding.dashscope.aliyuncs.com/apps/anthropic` |
| Token Plan | `https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic` |

旧端点 `https://dashscope.aliyuncs.com/api/v2/apps/claude-code-proxy` 已弃用，
仅支持已下架模型。

直连设置：

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

密钥类型必须与端点匹配。按量付费的 `sk-` 密钥不能用于 Coding Plan 或
Token Plan 端点。

网关预设：`qwen3.7-plus`（main）、`qwen3.7-max`（heavy）、
`qwen3.6-flash`（cheap）。

## OpenRouter

创建密钥：<https://openrouter.ai/keys>。

OpenRouter 提供 Anthropic Messages 端点：

```text
https://openrouter.ai/api/v1/messages
```

Claude Code 会在 `ANTHROPIC_BASE_URL` 后追加 `/v1/messages`，因此 Base URL
应为 `https://openrouter.ai/api`（不是 `.../api/v1`）。

直连设置：

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

网关预设还会发送 `HTTP-Referer` 和 `X-Title`，OpenRouter 用它们做归属标识。
如果发布自己的分支，请替换 `gateway/providers/openrouter.json` 中的仓库 URL。

OpenRouter 在响应中返回 `usage.cost`。网关保存精确值，而不是按价格表估算；
价格表只作为后备。

## 切换服务商

编辑 `gateway/config.json`：

```json
{ "provider": "alibaba" }
```

或只对当前进程生效：

```powershell
$env:GATEWAY_PROVIDER = 'openrouter'
.\gateway\start.ps1
```

修改后重启网关。运行中的请求不会重新加载配置。

安装器会把服务商写入 `gateway/config.json`，并把密钥保存到对应的用户变量。

## 添加自定义服务商

1. 复制 `gateway/providers/openrouter.json` 为
   `gateway/providers/my-provider.json`。
2. 填写 `name`、`docs`、`upstream`、`currency`、`auth`、`models`、`vision`、
   `documents`、`pricing` 和 `client`。
3. 在 `gateway/config.json` 中设置 `"provider": "my-provider"`。
4. 把密钥放入 `auth.env` 指定的变量。
5. 重启网关并检查 `GET /health`。

服务商 ID 必须匹配 `[a-z0-9][a-z0-9_-]*`。预设从
`gateway/providers/` 加载。

最小示例：

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

## 示例

所有服务商的直连设置模板：

- `examples/claude-settings/deepseek.settings.json`
- `examples/claude-settings/tencent.settings.json`
- `examples/claude-settings/alibaba.settings.json`
- `examples/claude-settings/openrouter.settings.json`

这些是模板：替换 `<YOUR_..._KEY>`，把 `env` 块合并到现有的
`~/.claude/settings.json`。不要覆盖其他设置。

## 兼容性

| 功能 | DeepSeek | 腾讯 | 阿里云 | OpenRouter |
|---|---|---|---|---|
| 流式输出 | 是 | 是 | 是 | 是 |
| 工具调用 | 是 | 是 | 是 | 是 |
| 图片 | 仅 flash；网关会改路由 | 取决于模型 | 取决于模型 | 取决于模型 |
| PDF | Files API | 不支持 | 不支持 | 原生支持 |
| 服务端联网搜索 | 计费并记录 | 取决于模型 | 取决于模型 | 取决于模型 |
| 响应中的精确费用 | 否 | 否 | 否 | 是（`usage.cost`） |

服务商能力会变化。请求失败时查看
`gateway/logs/requests.jsonl`、`notes` 字段和 `x-gateway-route`。
