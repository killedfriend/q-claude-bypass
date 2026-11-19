# 配置

> **教学用非商业项目。** 配置示例仅用于学习。服务商条款、费用和数据处理
> 由使用者自行负责。

## 文件

| 文件 | 作用 |
|---|---|
| `gateway/config.json` | 公共设置：端口、公共模型、路由、上下文、限制 |
| `gateway/providers/<id>.json` | 服务商：上游、认证、模型、价格、能力 |
| `%USERPROFILE%\.claude\settings.json` | Claude Code 环境 |
| `%USERPROFILE%\.claude.json` | Claude Code onboarding 状态 |
| `gateway/logs/requests.jsonl` | 每个请求一行 JSON |
| `gateway/logs/gateway.pid` | 运行中网关的 PID |
| `gateway/logs/last-request.json` | 完整请求，仅在 `GATEWAY_DUMP=1` 时生成 |

环境变量：

| 变量 | 作用 |
|---|---|
| `GATEWAY_PROVIDER` | 服务商 ID，覆盖 `config.json` |
| `GATEWAY_PORT` | 监听端口 |
| `GATEWAY_HOST` | 监听地址（保持 `127.0.0.1`） |
| `GATEWAY_UPSTREAM` | 覆盖服务商上游 |
| `GATEWAY_LOG` | 覆盖日志路径 |
| `GATEWAY_MAX_CHARS` | 上下文裁剪阈值 |
| `GATEWAY_DUMP` | `1` 时写入完整上游请求 |
| `GATEWAY_TLS_PFX`、`GATEWAY_TLS_PASSPHRASE` | Windows Desktop MITM 的 TLS 监听 |
| `GATEWAY_TLS_CERT`、`GATEWAY_TLS_KEY` | PEM TLS 监听 |

## 公共配置

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

| 键 | 含义 |
|---|---|
| `provider` | `gateway/providers/` 中的预设 ID |
| `listen.host` | 绑定地址。没有认证时保持 loopback |
| `listen.port` | 默认 8788 |
| `publicModels` | Claude Code 和 Desktop 看到的模型。保持 Claude 风格名称 |
| `routing.opusToHeavy` | 名称含 `opus` 的请求使用 `models.heavy` |
| `routing.haikuToCheap` | 名称含 `haiku` 的请求使用 `models.cheap` |
| `routing.cheapWithoutTools` | 无工具请求使用 `models.cheap` |
| `context.maxChars` | 裁剪前的请求体大小阈值 |
| `context.keepRecentToolResults` | 最近多少个工具结果不裁剪 |
| `context.elideAboveChars` | 只裁剪长于该值的工具结果 |
| `limits.dailyBudget` | 每日费用上限（服务商货币）；`0` 关闭 |
| `limits.maxRetries` | 408/429/5xx 重试次数 |
| `limits.timeoutMs` | 上游硬超时 |

## 服务商配置

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

| 键 | 含义 |
|---|---|
| `upstream` | 不含 `/v1/messages` 的基础 URL |
| `currency` | `CNY`、`USD`、`EUR`；用于日志和报告 |
| `auth.mode` | `gateway` 使用环境变量密钥；`passthrough` 转发客户端密钥 |
| `auth.header` | `authorization` 或 `x-api-key` |
| `auth.scheme` | `Bearer ` 或空字符串 |
| `auth.env` | 保存密钥的环境变量 |
| `headers` | 额外的上游静态请求头 |
| `models` | 实际上游模型 ID：`main`、`heavy`、`cheap` |
| `vision` | 确认支持图片的模型 |
| `documents` | `deepseek-files`、`native` 或 `none` |
| `cacheControl` | `strip`（默认）或 `keep`；仅在服务商支持时使用 |
| `cheapProfile` | 廉价调用的修改：`effort`、`thinking`、`maxTokens` |
| `pricing` | 每 1M Token；可含 `peak`/`offPeak` |
| `client.direct` | `qclaude.ps1` 直连模式使用的模型名 |
| `client.gateway` | `qclaude-gw.ps1` 使用的公共 Claude 名称 |

## 路由

顺序：

1. 模型名含 `opus` 且 `opusToHeavy` 开启 → `heavy`。
2. 否则含 `haiku` 且 `haikuToCheap` 开启 → `cheap`。
3. 否则没有工具且 `cheapWithoutTools` 开启 → `cheap`。
4. 否则 → `main`。

然后：

- 如果请求含图片且所选模型不在 `vision` 中，网关尝试 `main`。如果 `main`
  也不支持视觉，请求继续，并在日志中记录
  `images: no vision-capable model configured`。
- 响应头 `x-gateway-route` 显示路由，`x-gateway-model` 显示实际上游模型。

廉价调用还会应用 `cheapProfile`：

```json
{ "effort": "low", "thinking": "disabled", "maxTokens": 4096 }
```

只有服务商接受这些字段时才添加 `effort`/`thinking`。

## 上下文裁剪

长会话每轮都会重发完整记录。当 `JSON.stringify(body).length` 超过
`context.maxChars` 时，网关把最旧的 `tool_result` 文本替换为：

```text
[tool output elided by gateway: 12345 chars]
```

不会删除消息或 `tool_use`/`tool_result` 配对。转换是确定性的，因此服务商的
前缀缓存仍可命中。

关闭：

```json
{ "context": { "enabled": false } }
```

单次运行调整：

```powershell
$env:GATEWAY_MAX_CHARS = '300000'
```

裁剪能省钱，但可能删掉模型仍需要的信息。如果模型开始重复读取已读文件，请
增大 `keepRecentToolResults`。

## 价格与费用

`pricing` 按每 100 万 Token、服务商货币计算：

```json
{
  "model-id": { "input": 3, "cacheRead": 0.3, "output": 15 }
}
```

DeepSeek 支持峰谷价：

```json
{
  "deepseek-flash": {
    "peak":    { "cacheRead": 0.04, "input": 2, "output": 8 },
    "offPeak": { "cacheRead": 0.02, "input": 1, "output": 4 }
  }
}
```

计算：

```text
(input_tokens * input + cache_read_tokens * cacheRead + output_tokens * output) / 1e6
```

如果服务商返回 `usage.cost`（OpenRouter），使用该精确值。服务端联网搜索按
`webPricing` 每次调用计入（仅 DeepSeek）。没有价格时 `cost: null`，不是 0；
报告中显示 `-`。

每日预算在请求前检查：

```json
{ "limits": { "dailyBudget": 5 } }
```

`5` 表示当地每天 5 个 `currency` 单位。其他货币的日志不计入预算。

## 日志

`requests.jsonl` 每行：

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

不保存提示词和回复正文。会保存工具名和错误片段。`GATEWAY_DUMP=1` 会把完整
请求写入 `logs/last-request.json`，包含提示词和文件数据；请把它视为敏感文件。

报告：

```powershell
node gateway\report.mjs        # 最近 14 天
node gateway\report.mjs 30     # 最近 30 天
```

## 客户端设置

`qclaude-gw.ps1` 为当前进程设置：

```text
ANTHROPIC_BASE_URL=http://127.0.0.1:8788
ANTHROPIC_AUTH_TOKEN=local-gateway
ANTHROPIC_API_KEY=
```

`ANTHROPIC_API_KEY` 必须为空，否则 Claude Code 可能优先使用它。

安装后的 `~/.claude/settings.json` 使用相同值，因此新终端里直接运行 `claude`
也会走网关。可用 `uninstall.ps1` 删除这些键。

## 端点

| 方法 | 路径 | 用途 |
|---|---|---|
| `GET` | `/` 或 `/health` | 健康、服务商、路由、费用、密钥状态 |
| `GET` | `/v1/models` | Desktop 登录用的 Claude 风格模型列表 |
| `POST` | `/v1/messages` | Anthropic Messages 代理 |
| `POST` | `/v1/messages/count_tokens` | 本地 Token 估算 |

`/health` 示例：

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

## 自启

安装器写入用户级 Run 项：

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run\QClaudeGateway
```

它运行 `gateway\autostart.ps1`，检查 `/health`，必要时隐藏启动 Node。请求记录
在 `gateway\logs\requests.jsonl`；启动错误请在终端运行 `gateway\start.ps1`
查看。不需要管理员权限，也不是 Windows 服务。

禁用：

```powershell
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name QClaudeGateway
```

计划任务方案见 `desktop\install-autostart.ps1`。

## 安全

- 保持 `listen.host` 为 `127.0.0.1`。
- `auth.mode: gateway` 时网关忽略客户端密钥；本机任何进程都能使用。单人桌面
  可以接受，共用电脑不行。
- 密钥保存在用户环境变量。不要提交 `.env` 或含密钥的服务商文件。
- 日志含元数据，转储含内容。
- MITM 会安装本地 CA 并修改 `hosts`；请理解风险，并用
  `teardown-mitm.ps1` 回滚。
