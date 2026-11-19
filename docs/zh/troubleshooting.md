# 故障排查

> **教学用非商业项目。** 诊断可能暴露提示词、文件内容和 API 元数据。分享
> 日志前请先检查并脱敏。使用风险自负。

## 先做五项检查

```powershell
# 1. 网关是否在运行？
Invoke-RestMethod http://127.0.0.1:8788/health

# 2. 当前服务商和路由？
(Invoke-RestMethod http://127.0.0.1:8788/health) | Format-List

# 3. 最后一个请求是什么？
Get-Content gateway\logs\requests.jsonl -Tail 1

# 4. 最后一个请求的状态和错误？
(Get-Content gateway\logs\requests.jsonl -Tail 1 | ConvertFrom-Json) | Select-Object status, err

# 5. 密钥能否直接使用？
.\test-connection.ps1
```

如果 `/health` 失败，网关没有运行：

```powershell
.\gateway\start.ps1 -Background
```

或前台运行以查看错误：

```powershell
.\gateway\start.ps1
```

## 401 / 403 / invalid API key

症状：`authentication_error`、`invalid_api_key`、`AccessDenied`、HTTP 401
或 403。

原因与处理：

1. **进程环境里没有密钥。** 安装后打开新终端，或显式设置：
   ```powershell
   $env:DASHSCOPE_API_KEY = 'sk-...'
   ```
2. **密钥类型不匹配。** 阿里云按量付费、Coding Plan、Token Plan 的密钥不能
   混用。核对密钥类型与 base URL。
3. **认证头错误。** DeepSeek 和阿里云使用 `Authorization: Bearer`；腾讯预设
   使用 `x-api-key`。检查 `auth.header` 和 `auth.scheme`。
4. **密钥被禁用或余额不足。** 查看服务商控制台。
5. **密钥含空格或引号。** 用隐藏输入重新输入，不要把引号粘进变量。

不经过 Claude Code 测试：

```powershell
.\test-connection.ps1
```

## `claude-code:unrecognized_model`

部分 Claude Code 版本会在客户端校验模型名。公开名称必须像 Claude 模型。

- 使用网关：它提供 `claude-sonnet-4-5[1m]`、`claude-opus-4-5`、
  `claude-haiku-4-5`，再映射到上游。
- 直连模式使用预设中的 `client.direct` 名称。DeepSeek 的名称看起来像
  Claude，因为 DeepSeek 在服务端做了映射。
- 腾讯/阿里云/OpenRouter 直连时，如果客户端拒绝原生名称，请改用网关
  （`qclaude-gw.ps1`）。

## `API Error: Invalid URL`

`ANTHROPIC_BASE_URL` 必须带协议：

```text
https://api.deepseek.com/anthropic
```

而不是 `api.deepseek.com/anthropic`。所有服务商都一样。

## 404 / no route

- `POST /v1/messages` 是最终路径。网关会自动在 `upstream` 后追加
  `/v1/messages`，不要把该路径写进 `upstream`。
- OpenRouter Base URL 是 `https://openrouter.ai/api`，不是
  `https://openrouter.ai/api/v1`。
- 阿里云 Base URL 以 `/apps/anthropic` 结尾，不要再加 `/v1`。
- 查看 `/health` 中的 `upstream`。

## 429 / rate limit

- 服务商限流。等待后重试。
- 网关已按 `limits.maxRetries` 对 429 做退避重试。
- 减少后台调用：调整 `CLAUDE_CODE_EFFORT_LEVEL`、上下文、并行子代理数量。
- 网关每日预算也会返回 429：
  ```json
  { "limits": { "dailyBudget": 0 } }
  ```

## 5xx / timeout

- 网关会重试 408/429/500/502/503/504。
- `limits.timeoutMs` 默认 10 分钟。极长回合可能超时；请谨慎增大。
- 查看服务商状态和日志中的 `err`。
- 上游过载时切换服务商或模型。

## 流式输出中断、工具不执行

- 部分服务商不支持全部 Anthropic SSE 事件。查看兼容性表。
- 只有服务商接受 Anthropic `document` 块时才使用 `documents: native`，否则
  用 `none`（附件替换为占位文本）。
- 工具调用需要模型支持 `tool_use`，这取决于服务商。
- 先用简单请求测试：
  ```powershell
  claude -p "Reply with exactly OK" --output-format text
  ```

## 图片

- DeepSeek `deepseek-v4-pro` 会静默忽略图片。网关会尽量把图片请求改到
  `deepseek-flash`；查看 `applied` 中的 `images: heavy->main`。
- 没有视觉模型时，日志会写
  `images: no vision-capable model configured`。请求仍会发出，模型可能幻觉。
- 腾讯/阿里云请确认所选模型支持图片。
- 用带已知数字的截图验证。

## PDF 与文档

- DeepSeek 只通过 Files API 接收 PDF。内联 base64 `document` 由网关上传。
- `tool_result` 内的文档会为 DeepSeek 提升到顶层；否则模型回答
  `NO-DOCUMENT`。
- 上传文件按 SHA-256 缓存在 `gateway/logs/files.json`。
- `documents: "none"` 时附件被替换为占位文本，模型读不到 PDF。
- `documents: "native"` 时原样传递（OpenRouter 支持 PDF）。
- Files API 解析按量计费，请查看控制台。

## Claude Desktop

安装器现在**默认**通过本地 MITM 配置 Claude Desktop：在受信任根中加入 CA、为
`api.anthropic.com` 签发证书、把 `127.0.0.1 api.anthropic.com` 写入 `hosts`，
并生成网关 443 端口 TLS 监听使用的 PFX。需要 UAC 确认。

如果 Desktop 仍无法连接，按顺序检查：

```powershell
# 1. hosts 记录
Select-String "$env:SystemRoot\System32\drivers\etc\hosts" -Pattern 'qclaude-mitm'

# 2. CA 已受信任
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -eq 'CN=QClaude Local CA'

# 3. PFX 存在
Test-Path "$env:LOCALAPPDATA\QClaudeCode\desktop\mitm\api.anthropic.com.pfx"

# 4. 网关运行且 TLS 响应
Invoke-RestMethod http://127.0.0.1:8788/health
Invoke-WebRequest https://api.anthropic.com/health -UseBasicParsing

# 5. 443 端口由网关占用，而不是其他服务
Get-NetTCPConnection -LocalPort 443 -State Listen
```

常见原因：

- 安装时取消了 UAC：重新运行 `install.ps1` 并确认，或以管理员运行
  `desktop\mitm\setup-mitm.ps1`。
- 安装 MITM 前网关已在运行：重启网关
  （`gateway\start.ps1 -Stop`，再 `gateway\start.ps1`）。
- 其他进程占用 443：停止它，或使用 `-NoMitm` 和别的 Desktop 方案。
- 企业 VPN/代理检查 TLS：不要在不理解证书链的情况下混用。
- 使用了 `-NoMitm`：Desktop 未被拦截。手动安装：
  ```powershell
  .\desktop\mitm\setup-mitm.ps1        # 管理员
  ```

如果无法接受 MITM，可选：

1. **CC Switch** — 第三方本地路由器，带 Desktop 面板，使用
   `127.0.0.1:15721`。
2. **实验性策略** — 安装器加 `-ConfigureDesktop`，或：
   ```powershell
   .\desktop\apply-desktop-policy.ps1   # 管理员
   ```
   重启 Desktop 并检查是否生效。

回滚：

```powershell
.\desktop\mitm\teardown-mitm.ps1      # 管理员
.\desktop\revert-all.ps1              # 策略和 managed settings
```

`uninstall.ps1` 会自动运行 MITM teardown 并请求 UAC。如果取消 UAC，会保留
安装目录以便重试。

## 端口 8788 被占用

```powershell
Get-NetTCPConnection -LocalPort 8788 -State Listen
.\gateway\start.ps1 -Stop
```

或修改 `gateway/config.json` 和 `~/.claude/settings.json` 中的端口
（`ANTHROPIC_BASE_URL`）。

网关写入 `gateway/logs/gateway.pid`。`start.ps1 -Stop` 优先用它，再按端口
查找。

## Node.js 与 npm

- Claude Code 需要 Node.js 22+（`node --version`）。
- `npm install -g` 报 `EACCES`/`EPERM` 时，安装器会重试到
  `%LOCALAPPDATA%\QClaudeCode\npm` 并加入 PATH。
- 仍找不到 `claude` 时，打开新终端或：
  ```powershell
  $env:Path += ";$env:LOCALAPPDATA\QClaudeCode\npm"
  ```
- `npm.ps1` 可能被执行策略阻止；使用 `npm.cmd`。
- 便携版 Node 位于 `%LOCALAPPDATA%\QClaudeCode\tools\node`。

## winget / 安装 Claude Desktop

- `winget` 来自应用安装程序，可在 Microsoft Store 更新。
- 包 ID：`Anthropic.Claude`。
- winget 失败时，从 <https://claude.ai/download> 手动安装，然后用
  `-SkipClaudeDesktop` 重跑安装器。
- 核心网关不需要管理员；部分 winget/MSI 路径可能弹 UAC。

## UAC 与 `-ConfigureDesktop`

`-ConfigureDesktop` 写入 `C:\Program Files` 和 `HKLM`，需要管理员权限。
安装器会启动提权 PowerShell 并等待。取消 UAC 时其余安装仍会完成，只跳过
Desktop 策略。

## 执行策略

如果 `.\install.ps1` 被阻止：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

不要因为这个项目修改整台机器的执行策略。

## 日志与转储

```powershell
Get-Content gateway\logs\requests.jsonl -Tail 20
```

查看启动错误和未处理异常时，请在前台启动网关：

```powershell
.\gateway\start.ps1 -Stop
.\gateway\start.ps1
```

临时开启完整转储：

```powershell
$env:GATEWAY_DUMP = '1'
.\gateway\start.ps1
```

转储包含提示词、工具输出，可能还有文件数据。用完后删除
`logs\last-request.json` 并取消 `GATEWAY_DUMP`。

## 重置

软重置（保留应用和密钥）：

```powershell
.\gateway\start.ps1 -Stop
Remove-Item "$env:LOCALAPPDATA\QClaudeCode\gateway\logs" -Recurse -Force
```

完全重置：

```powershell
.\uninstall.ps1
```

用原服务商或新服务商重装：

```powershell
.\install.ps1 -Provider openrouter
```

## 仍未解决

收集：

- `GET /health` 输出；
- `requests.jsonl` 最后 5 行；
- Claude Code 的完整错误文本；
- 服务商、模型 ID 和端点（不要提供密钥）；
- Node.js、Claude Code 和 Windows 版本。

在仓库中开 issue。请隐去密钥、Token、提示词和个人路径。
