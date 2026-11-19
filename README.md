# QClaude Code

[![Release](https://img.shields.io/github/v/release/killedfriend/q-claude-bypass?label=release)](https://github.com/killedfriend/q-claude-bypass/releases)
[![CI](https://github.com/killedfriend/q-claude-bypass/actions/workflows/ci.yml/badge.svg)](https://github.com/killedfriend/q-claude-bypass/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Русский** · [English](README.en.md) · [中文](README.zh-CN.md)

> **Educational, non-commercial project.** Created for demonstration and
> learning only. Not affiliated with Anthropic, DeepSeek, Tencent, Alibaba or
> OpenRouter. Not intended for commercial use, resale, or violating provider
> terms. Use at your own risk.

> **Учебный некоммерческий проект.** Создан только для демонстрации и
> обучения. Не связан с Anthropic, DeepSeek, Tencent, Alibaba и OpenRouter.
> Не предназначен для коммерческого использования или нарушения условий
> провайдеров. Используйте на свой риск.

> **教学用非商业项目。** 仅用于演示和学习，与 Anthropic、DeepSeek、腾讯、
> 阿里巴巴、OpenRouter 无关联。不得用于商业用途、转售或违反服务商条款。
> 使用风险自负。

A local Anthropic-compatible gateway that lets the real Claude Code and Claude
Desktop run on DeepSeek, Tencent Hunyuan, Alibaba Qwen, or OpenRouter — with
model routing, token/cost accounting, retries, and context pruning.

```text
Claude Code -> http://127.0.0.1:8788 -> provider
```

## Start here

- [Русская документация](README.ru.md)
- [English documentation](README.en.md)
- [中文文档](README.zh-CN.md)

## One-command Windows install

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

The installer sets up Node.js 22+, Claude Code, Claude Desktop, the gateway,
logon autostart, and verifies the selected provider key.

## Providers

| Provider | Base URL | Key variable |
|---|---|---|
| DeepSeek | `https://api.deepseek.com/anthropic` | `DEEPSEEK_API_KEY` |
| Tencent Hunyuan | `https://api.hunyuan.cloud.tencent.com/anthropic` | `TENCENT_API_KEY` |
| Alibaba Bailian | `https://dashscope.aliyuncs.com/apps/anthropic` | `DASHSCOPE_API_KEY` |
| OpenRouter | `https://openrouter.ai/api` | `OPENROUTER_API_KEY` |

## Documentation

| | Русский | English | 中文 |
|---|---|---|---|
| Install | [installation](docs/ru/installation.md) | [installation](docs/en/installation.md) | [安装](docs/zh/installation.md) |
| Providers | [providers](docs/ru/providers.md) | [providers](docs/en/providers.md) | [服务商](docs/zh/providers.md) |
| Gateway config | [configuration](docs/ru/configuration.md) | [configuration](docs/en/configuration.md) | [配置](docs/zh/configuration.md) |
| Troubleshooting | [troubleshooting](docs/ru/troubleshooting.md) | [troubleshooting](docs/en/troubleshooting.md) | [故障排查](docs/zh/troubleshooting.md) |

## License

MIT. Provided “as is”, without warranty. See [LICENSE](LICENSE).
