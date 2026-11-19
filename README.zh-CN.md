# QClaude Code

[![Release](https://img.shields.io/github/v/release/killedfriend/q-claude-bypass?label=release)](https://github.com/killedfriend/q-claude-bypass/releases)
[![CI](https://github.com/killedfriend/q-claude-bypass/actions/workflows/ci.yml/badge.svg)](https://github.com/killedfriend/q-claude-bypass/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.en.md) · [Русский](README.ru.md) · **中文**

> **教学用非商业项目。** 本仓库仅用于演示和学习目的，与 Anthropic、DeepSeek、
> 腾讯、阿里巴巴或 OpenRouter 没有任何关联，也未获得其认可。本项目不得用于
> 商业用途、转售、绕过付费访问或违反任何服务商条款。使用风险自负；请自行遵守
> 适用的服务条款和法律法规。

QClaude Code 通过官方 `ANTHROPIC_BASE_URL` 机制，让真正的 Claude Code 和
Claude Desktop 使用第三方模型。客户端与模型服务之间有一个本地网关：它负责
模型路由、Token 与费用统计、失败重试，以及清理服务商不接受的请求块。

这个项目最初只是一个实践实验：不 fork Claude Code、不修改客户端二进制，
到底能把非 Anthropic 后端用到什么程度？

## 主要功能

- **真正的 Claude Code。** 不修改客户端，只使用环境变量和本地 HTTP 网关。
- **四个现成服务商：** DeepSeek、腾讯混元、阿里云百炼（Qwen）、OpenRouter。
  新增服务商只需要一个 JSON 文件。
- **模型路由。** `opus` → 重型模型，`haiku` 和无工具的后台调用 → 廉价模型，
  其余 → 主模型。
- **费用统计。** Token、缓存命中、单次请求费用、联网搜索、可选的每日预算。
  OpenRouter 会直接使用响应中的 `usage.cost`。
- **避免静默错误。** 模型不支持图片时，网关不会悄悄把图片发过去；路由和原因
  会写入日志并出现在响应头中。
- **文档处理。** 对 DeepSeek，PDF 通过 Files API 上传，并从 `tool_result`
  提升到消息顶层。
- **上下文裁剪。** 旧的工具结果会被替换为占位文本，避免长会话每轮重发几十万
  Token。
- **Windows 安装器。** 一条命令完成 Node.js、Claude Code、Claude Desktop、
  网关、开机自启和密钥检查。
- **三语文档**以及每个服务商的配置示例。

## 工作原理

```text
Claude Code / Claude Desktop
        │  ANTHROPIC_BASE_URL=http://127.0.0.1:8788
        ▼
QClaude Gateway（Node.js，零依赖）
  ├─ 从 gateway/config.json 选择服务商
  ├─ 路由 claude-opus / claude-sonnet / claude-haiku
  ├─ 清理请求：cache_control、document、附件
  ├─ 统计 Token、缓存命中和费用
  └─ 写入 gateway/logs/requests.jsonl
        │
        ▼
DeepSeek / 腾讯 / 阿里云 / OpenRouter
```

服务商收到的是标准 Anthropic Messages API 请求。Claude Code 并不知道自己
没有连接 Anthropic：对它来说，这只是另一个 Base URL。

## 服务商

| 服务商 | Base URL | 密钥变量 | 模型示例 |
|---|---|---|---|
| DeepSeek | `https://api.deepseek.com/anthropic` | `DEEPSEEK_API_KEY` | `deepseek-flash[1m]`、`deepseek-v4-pro` |
| 腾讯混元 | `https://api.hunyuan.cloud.tencent.com/anthropic` | `TENCENT_API_KEY` | `hunyuan-2.0-instruct-20251111`、`hunyuan-2.0-thinking-20251109` |
| 阿里云百炼 | `https://dashscope.aliyuncs.com/apps/anthropic` | `DASHSCOPE_API_KEY` | `qwen3.7-plus`、`qwen3.7-max`、`qwen3.6-flash` |
| OpenRouter | `https://openrouter.ai/api` | `OPENROUTER_API_KEY` | `anthropic/claude-sonnet-4.5`、`anthropic/claude-opus-4.5`、`anthropic/claude-haiku-4.5` |

模型 ID 会变化。请在服务商控制台或 OpenRouter 模型页面确认。腾讯 TokenHub、
阿里云 Coding Plan 等计费端点和完整说明见
[`docs/zh/providers.md`](docs/zh/providers.md)。

> **验证状态。** DeepSeek 路径已在 2026-11-19 用真实请求验证（普通请求、
> 流式、工具、PDF、费用记录）。腾讯、阿里云和 OpenRouter 预设基于服务商官方
> 文档编写，未在本仓库中做真实请求验证。使用前请核对账户支持的模型 ID 和
> 认证头。

## 快速开始（Windows）

要求：Windows 10/11、PowerShell 5.1+、可访问互联网。安装器会自动安装
Node.js 22+、Claude Code、Claude Desktop 和 `winget` 依赖。

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

如果执行策略阻止 `irm | iex`：

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex"
```

安装器会：

1. 检查 Node.js 22+，必要时安装 LTS（winget 或
   `%LOCALAPPDATA%\QClaudeCode\tools\node` 下的便携版）；
2. 通过 npm 安装 `@anthropic-ai/claude-code`；
3. 通过 `winget install Anthropic.Claude` 安装 Claude Desktop；
4. 把网关复制到 `%LOCALAPPDATA%\QClaudeCode`；
5. 询问服务商和 API 密钥（输入隐藏），并保存到用户环境变量；
6. 在 `HKCU\...\Run\QClaudeGateway` 注册开机自启；
7. 启动网关并发送一次低价请求验证密钥。

非交互安装：

```powershell
$env:QCLAUDE_PROVIDER = 'alibaba'
$env:QCLAUDE_API_KEY  = 'sk-...'
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

安装后请打开新的终端：

```powershell
qclaude-gw
```

`qclaude-gw` 是 `claude` 的包装器：必要时启动网关，并把所有参数原样传给
Claude Code。

检查与诊断：

```powershell
Invoke-RestMethod http://127.0.0.1:8788/health
node "$env:LOCALAPPDATA\QClaudeCode\gateway\report.mjs"
Get-Content "$env:LOCALAPPDATA\QClaudeCode\gateway\logs\requests.jsonl" -Tail 5
```

卸载：

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/uninstall.ps1 | iex
```

## 从仓库手动运行

```powershell
git clone https://github.com/killedfriend/q-claude-bypass.git
cd q-claude-bypass

.\test-connection.ps1      # 一次低价请求，检查密钥
.\qclaude.ps1              # 直连服务商
.\qclaude-gw.ps1           # 通过本地网关
.\gateway\start.ps1        # 前台启动网关
.\gateway\start.ps1 -Stop  # 停止后台网关
node gateway\report.mjs    # 按日期、模型和服务商统计费用
```

默认服务商是 DeepSeek。切换方式：

```powershell
# 编辑 gateway/config.json -> "provider": "alibaba"
# 或只对当前进程生效：
$env:GATEWAY_PROVIDER = 'alibaba'
.\gateway\start.ps1
```

密钥保存在用户环境变量中（`DEEPSEEK_API_KEY`、`TENCENT_API_KEY`、
`DASHSCOPE_API_KEY` 或 `OPENROUTER_API_KEY`）。仓库中不包含任何密钥。

## 文件说明

| 路径 | 用途 |
|---|---|
| `install.ps1` | Windows 一条命令安装器 |
| `install.cmd` | 双击运行安装器的包装脚本 |
| `uninstall.ps1` | 删除自启、网关和客户端设置 |
| `qclaude-gw.ps1` | 通过本地网关启动 Claude Code |
| `qclaude.ps1` | 直连服务商启动 Claude Code |
| `env.ps1` | 服务商选择、密钥、模型和公共环境变量 |
| `test-connection.ps1` | 单次请求检查密钥 |
| `gateway/server.mjs` | 网关，Node 22，零依赖 |
| `gateway/config.json` | 公共配置：端口、路由、限制、日志 |
| `gateway/providers/*.json` | 服务商预设 |
| `gateway/report.mjs` | 费用报告 |
| `gateway/lib/*.mjs` | 配置、计价、路由、上下文裁剪 |
| `desktop/` | 实验性的 Claude Desktop 绑定（策略、MITM） |
| `examples/claude-settings/` | 直连模式的 `~/.claude/settings.json` 示例 |
| `docs/zh`、`docs/en`、`docs/ru` | 完整文档 |
| `scripts/build-release.ps1` | 构建发布 ZIP 和产物 |

## 文档

- [安装](docs/zh/installation.md) — 安装器、手动安装、升级、卸载、自启。
- [服务商](docs/zh/providers.md) — 腾讯、阿里云、OpenRouter、DeepSeek：
  密钥、端点、模型、配置示例。
- [配置](docs/zh/configuration.md) — 网关、路由、计价、日志、预算、环境变量。
- [故障排查](docs/zh/troubleshooting.md) — 401/404/429、模型、Desktop、端口、
  Node.js、UAC。

English: [`docs/en`](docs/en) · Русский: [`docs/ru`](docs/ru).

## Claude Desktop

安装器会安装 Claude Desktop，但**不会**自动重定向它的流量：该应用并不总是
读取环境变量和 managed-settings。可选方案：

1. **CC Switch** — 第三方工具，可为 Desktop 提供本地路由。
2. **实验性策略** — `install.ps1 -ConfigureDesktop` 写入 managed-settings 和
   注册表策略；部分 Desktop 版本会忽略它们。
3. **MITM** — `desktop/mitm/setup-mitm.ps1` 创建本地 CA 和
   `api.anthropic.com` 证书，修改 `hosts`，并启用网关 TLS 监听。这是最可靠
   但侵入性最强的方法，需要管理员权限。

使用 MITM 前请阅读 [`docs/zh/troubleshooting.md`](docs/zh/troubleshooting.md)
和安全说明。回滚：`desktop/mitm/teardown-mitm.ps1`。

## 安全与限制

- 网关只监听 `127.0.0.1`，不适合暴露到网络。没有认证时不要把 `listen.host`
  改成 `0.0.0.0`。
- API 密钥保存在用户环境变量中，不写入仓库。
- `gateway/logs/requests.jsonl` 包含模型、Token、工具名和错误，不包含提示词
  正文。设置 `GATEWAY_DUMP=1` 会把完整请求写入 `logs/last-request.json`，
  不要在敏感数据上启用。
- 本项目是非官方项目。Claude Code 更新或服务商 API 变化都可能导致失效。
  回滚不需要成本：停止网关即可。
- DeepSeek 峰谷计价不考虑中国法定节假日。
- `count_tokens` 是估算值，上下文指示器不精确。
- 各服务商对图片和 PDF 的支持不同。请查看日志中的 `notes` 和响应头
  `x-gateway-route`。
- Claude Desktop 和 MITM 属于实验功能。不了解后果时不要在工作机器上使用。

## 许可证

MIT，见 [LICENSE](LICENSE)。

本项目按“原样”提供，不附带任何保证。作者不对费用、数据丢失或违反服务商
条款承担责任。
