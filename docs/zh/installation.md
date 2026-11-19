# 安装

> **教学用非商业项目。** 本仓库仅用于演示和学习，与 Anthropic、DeepSeek、
> 腾讯、阿里巴巴或 OpenRouter 无关联。不得用于商业用途或违反服务商条款。
> 使用风险自负。

## 要求

- Windows 10 或 11（x64）。
- PowerShell 5.1 或更高版本。
- 可访问 GitHub、npm、nodejs.org 和所选用服务商。
- DeepSeek、腾讯云、阿里云百炼或 OpenRouter 的 API 密钥。
- 建议安装 `winget`（应用安装程序）。如果没有，安装器会给出 Claude Desktop
  的手动下载链接。
- 默认 Claude Desktop MITM 需要管理员权限和 UAC 确认（hosts + 受信任根证书）。
  可用 `-NoMitm` 跳过。

无需提前安装 Node.js、Claude Code 或 Claude Desktop。

## 一条命令安装

打开普通 PowerShell（核心安装不需要管理员权限）：

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

如果执行策略阻止该命令：

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex"
```

安装器会询问：

1. 服务商（DeepSeek、腾讯、阿里云、OpenRouter）；
2. API 密钥（隐藏输入）。

密钥会保存为用户环境变量，不会写入仓库。

如需传递参数（例如 `-NoMitm`），请先下载脚本：

```powershell
Invoke-WebRequest https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 -OutFile install.ps1
.\install.ps1 -NoMitm
```

### 非交互安装

```powershell
$env:QCLAUDE_PROVIDER = 'alibaba'
$env:QCLAUDE_API_KEY  = 'sk-...'
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

不要把密钥直接写在命令行中：它可能留在 PowerShell 历史或进程列表里。优先
使用隐藏输入。

### 安装器参数

下载 `install.ps1` 后以文件方式运行，可传入参数：

```powershell
.\install.ps1 -Provider openrouter -InstallDir D:\Tools\QClaude
```

| 参数 | 含义 |
|---|---|
| `-Provider` | `deepseek`、`tencent`、`alibaba`、`openrouter` |
| `-ApiKey` | API 密钥；省略则交互输入 |
| `-InstallDir` | 安装目录，默认 `%LOCALAPPDATA%\QClaudeCode` |
| `-ClaudeHome` | Claude 设置目录，默认 `%USERPROFILE%\.claude` |
| `-SourceDir` | 从本地仓库安装，而不是下载发布 ZIP |
| `-Repo` | 用于下载发布的 GitHub 仓库 |
| `-Version` | 下载的发布版本 |
| `-SkipNode` | 不检查或安装 Node.js |
| `-SkipClaudeCode` | 不安装 Claude Code |
| `-SkipClaudeDesktop` | 不安装 Claude Desktop，也不配置其 MITM |
| `-SkipAutostart` | 不注册自启，也不启动网关 |
| `-SkipSmokeTest` | 不发送验证请求 |
| `-NoPersistKey` | 密钥只保留在当前进程（自启将看不到） |
| `-NoStart` | 安装后不启动网关 |
| `-NoMitm` | 跳过自动 Claude Desktop MITM（hosts、CA、443 端口） |
| `-ConfigureDesktop` | 应用实验性 Desktop 策略（需要 UAC） |

## 安装器会修改什么

| 位置 | 修改 |
|---|---|
| `%LOCALAPPDATA%\QClaudeCode` | 网关、启动器、文档、示例 |
| `%LOCALAPPDATA%\QClaudeCode\bin` | `qclaude`、`qclaude-gw` 包装脚本，已加入用户 PATH |
| `%LOCALAPPDATA%\QClaudeCode\tools\node` | 便携版 Node.js，仅在系统没有 Node.js 且 winget 失败时 |
| `%USERPROFILE%\.claude\settings.json` | 添加网关的 `ANTHROPIC_*` 变量，保留其他设置 |
| `%USERPROFILE%\.claude.json` | 设置 `hasCompletedOnboarding: true` |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` | 注册 `QClaudeGateway` 自启项 |
| 用户环境变量 | 密钥变量，例如 `DASHSCOPE_API_KEY` |
| 可选，`-ConfigureDesktop` | `C:\Program Files\ClaudeCode\managed-settings.json` 和 `HKLM\SOFTWARE\Policies\ClaudeCode` |
| `%LOCALAPPDATA%\QClaudeCode\desktop\mitm` | 本地 CA 和 `api.anthropic.com` PFX |
| Windows `hosts` | `127.0.0.1 api.anthropic.com`（标记 `# qclaude-mitm`） |
| Windows 受信任根 | `CN=QClaude Local CA` |
| `%LOCALAPPDATA%\QClaudeCode\gateway\logs` | 运行日志 |

安装器不会修改 Claude Code 或 Claude Desktop 的二进制文件。

MITM 是机器级修改。网关停止时，本机无法访问 `api.anthropic.com`，因为
`hosts` 指向 `127.0.0.1`。卸载会恢复 hosts、证书和 PFX。如果无法接受这种
取舍，请使用 `-NoMitm`。

## 验证

打开新的终端，让 PATH 和用户环境变量生效：

```powershell
qclaude-gw
```

在另一个终端中：

```powershell
Invoke-RestMethod http://127.0.0.1:8788/health
```

应看到 `"ok": true`、所选 `provider`、`routes` 和 `keyConfigured: true`。

检查 TLS 拦截（默认 MITM）：

```powershell
Invoke-WebRequest https://api.anthropic.com/health -UseBasicParsing
```

应通过受信任的本地证书返回网关健康 JSON。若失败，请检查网关是否运行、443
端口是否空闲、PFX 是否位于 `%LOCALAPPDATA%\QClaudeCode\desktop\mitm`。

发送一次低价请求：

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

查看费用：

```powershell
node "$env:LOCALAPPDATA\QClaudeCode\gateway\report.mjs"
```

## 手动安装

如果想先阅读或修改源码：

```powershell
git clone https://github.com/killedfriend/q-claude-bypass.git
cd q-claude-bypass

# 1. Node.js 22+
node --version

# 2. Claude Code
npm install -g @anthropic-ai/claude-code

# 3. 服务商密钥（示例：DeepSeek）
[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY', 'sk-...', 'User')

# 4. 选择服务商
#    编辑 gateway/config.json -> "provider": "deepseek"
#    或仅对当前进程设置：
$env:GATEWAY_PROVIDER = 'deepseek'

# 5. 检查密钥
.\test-connection.ps1

# 6. 启动
.\qclaude-gw.ps1
```

手动配置自启：

```powershell
$install = (Resolve-Path .).Path
$cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$install\gateway\autostart.ps1`""
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
  -Name 'QClaudeGateway' -Value $cmd -PropertyType String -Force
```

也可以使用计划任务脚本：

```powershell
.\desktop\install-autostart.ps1          # 需要管理员
.\desktop\install-autostart.ps1 -Remove
```

## 升级

再次运行安装器。它会停止旧网关、替换运行时文件、保留 `gateway/logs`，并用
所选服务商重写 `gateway/config.json`。如果修改过路由或限制，请先备份：

```powershell
copy "$env:LOCALAPPDATA\QClaudeCode\gateway\config.json" "$env:LOCALAPPDATA\QClaudeCode\gateway\config.backup.json"
```

服务商预设会被新版本替换。自定义预设请放在单独的 `.local.json` 文件中，并让
`provider` 指向它。

## 卸载

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/uninstall.ps1 | iex
```

卸载器会删除：

- `QClaudeGateway` 自启项；
- 正在运行的网关进程；
- `~/.claude/settings.json` 中添加的 `ANTHROPIC_*` 变量；
- 安装目录。

默认保留 Claude Code、Claude Desktop 和 API 密钥。可附加：

```powershell
.\uninstall.ps1 -RemoveApiKey -RemoveClaudeCode -RemoveClaudeDesktop
```

`-KeepSettings` 保留 Claude 设置。

MITM 清理会自动执行。如果取消 UAC，安装目录会保留，便于重试：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\QClaudeCode\desktop\mitm\teardown-mitm.ps1"
```

`-NoMitmCleanup` 跳过清理，保留 hosts/证书修改。

## Claude Desktop

安装器默认通过本地 MITM 配置 Desktop：

- 受信任根中的 CA `CN=QClaude Local CA`；
- 证书 `CN=api.anthropic.com`（SAN `api.anthropic.com`、`*.anthropic.com`）；
- hosts 记录 `127.0.0.1 api.anthropic.com`；
- 网关 `127.0.0.1:443` TLS 监听使用的 PFX。

`-NoMitm` 可跳过。实验性 managed-settings 策略仍可通过 `-ConfigureDesktop`
启用，CC Switch 是第三方替代方案。参见
[故障排查](troubleshooting.md#claude-desktop)。

## 下一步

- [服务商](providers.md)
- [配置](configuration.md)
- [故障排查](troubleshooting.md)
- [支持作者](support.md)
