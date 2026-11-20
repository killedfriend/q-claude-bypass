# macOS

> **教学用非商业项目。** macOS 支持目前是 MVP。脚本会在 GitHub Actions 的
> `macos-latest` 上检查，但真实 Mac 上的 Claude Desktop GUI、证书信任和完整
> 流程尚未验证。使用风险自负。

## 支持内容

- Node.js 网关（本身已跨平台）。
- Claude Code 的 `qclaude`、`qclaude-gw` 启动器。
- 通过 LaunchAgent `com.qclaude.gateway` 开机自启。
- Claude Desktop MITM：OpenSSL 本地 CA、`security` 信任、`hosts`、
  `pfctl` 443 → 8443 重定向。
- 在 macOS GitHub Actions runner 上构建 `.zip` 和 `.pkg`。

## 要求

- macOS 12+（Apple Silicon 或 Intel）。
- Node.js 22+。
- Claude Code（`npm install -g @anthropic-ai/claude-code`）。
- Claude Desktop 可选；安装器会尝试 `brew install --cask claude`。
- MITM 需要管理员密码：`hosts`、System keychain、`pfctl`。
- 用户不需要 Xcode Command Line Tools；构建 `.pkg` 需要 `pkgbuild`。

## 从 ZIP 安装（推荐）

从 Releases 下载 `QClaudeCode-<version>-macos.zip` 并解压。

Finder：

1. 打开 `QClaudeCode-<version>` 文件夹。
2. 右键 `install.command` → **打开**。如果提示未知开发者，再次右键 → 打开。
3. 选择服务商并粘贴 API 密钥。
4. 确认 MITM 的管理员密码提示。

终端：

```bash
cd ~/Downloads/QClaudeCode-*
bash macos/install.sh
```

常用参数：

```bash
bash macos/install.sh --provider deepseek
bash macos/install.sh --provider homyak
bash macos/install.sh --provider openrouter --no-mitm
bash macos/install.sh --skip-desktop
bash macos/install.sh --install-dir "$HOME/QClaude"
```

可用预设与 Windows 相同：DeepSeek、腾讯、阿里云、OpenRouter 和 Homyak API。

## 从 PKG 安装

`.pkg` 未签名。它把运行时安装到 `/usr/local/share/qclaude`，并提供
`qclaude-setup` 命令。

1. 右键 `.pkg` → **打开**（Gatekeeper）。
2. 安装后在终端执行：

```bash
qclaude-setup
```

`qclaude-setup` 会运行同一个用户级安装器：复制到
`~/Library/Application Support/QClaudeCode`、保存密钥、安装 LaunchAgent，并在
未指定 `--no-mitm` 时配置 MITM。

该包未签名、未 notarized。正式分发需要 Apple Developer 账号、签名和
notarization。

## 安装器修改哪些文件

| 路径 | 用途 |
|---|---|
| `~/Library/Application Support/QClaudeCode` | 网关、启动器、文档、env |
| `~/Library/Application Support/QClaudeCode/env` | API 密钥，权限 `600` |
| `~/.zshrc` | 把 `.../QClaudeCode/bin` 加入 PATH |
| `~/Library/LaunchAgents/com.qclaude.gateway.plist` | 网关自启 |
| `~/.claude/settings.json` | Claude Code 的 `ANTHROPIC_*` |
| `~/.claude.json` | `hasCompletedOnboarding: true` |
| `/etc/hosts` | `127.0.0.1 api.anthropic.com`（仅 MITM） |
| System keychain | `QClaude Local CA`（仅 MITM） |
| `/etc/pf.conf`、`/etc/pf.anchors/com.qclaude` | 443 → 8443 重定向 |
| `/Library/LaunchDaemons/com.qclaude.pf.plist` | 开机恢复 pf |

## MITM 与 pfctl

macOS 不允许普通用户监听 443。因此：

```text
Claude Desktop → https://api.anthropic.com:443
      │ hosts → 127.0.0.1
      ▼
pfctl redirect 443 → 127.0.0.1:8443
      ▼
QClaude gateway TLS (用户, 8443) → DeepSeek / 腾讯 / 阿里云 / OpenRouter
```

`macos/mitm/setup.sh` 会：

1. 用 OpenSSL 创建 CA 和 `api.anthropic.com` 证书；
2. 通过 `security` 把 CA 加入 System keychain；
3. 把 `127.0.0.1 api.anthropic.com` 写入 `/etc/hosts`；
4. 创建 `/etc/pf.anchors/com.qclaude` 并在 `/etc/pf.conf` 中引用；
5. 安装 `com.qclaude.pf` LaunchDaemon，开机恢复 pf；
6. 启用并加载 pf。

检查：

```bash
curl -k https://api.anthropic.com/health
# 应返回网关健康 JSON
```

跳过 MITM：

```bash
bash macos/install.sh --no-mitm
```

之后移除：

```bash
sudo env QCLAUDE_HOME="$HOME/Library/Application Support/QClaudeCode" \
  "$HOME/Library/Application Support/QClaudeCode/macos/mitm/teardown.sh"
```

## 命令

```bash
qclaude-gw                 # 通过网关运行 Claude Code
qclaude-gw -p "..."        # headless
qclaude                    # 直连服务商

~/"Library/Application Support/QClaudeCode/gateway/start.sh" --background
~/"Library/Application Support/QClaudeCode/gateway/start.sh" --stop
curl http://127.0.0.1:8788/health
```

安装后打开新终端，或执行：

```bash
source ~/.zshrc
```

## 卸载

```bash
bash ~/"Library/Application Support/QClaudeCode/macos/uninstall.sh"
```

选项：

```bash
--keep-settings       保留 ~/.claude/settings.json
--no-mitm-cleanup     保留 hosts、CA 和 pf
--remove-key          删除密钥文件
```

如果取消 MITM teardown，安装目录会保留以便重试。

## 限制

- 真实 Mac 上的 Claude Desktop GUI 和系统证书信任尚未验证。
- `pfctl` 回环重定向在不同 macOS 版本上可能不同；请用
  `curl -k https://api.anthropic.com/health` 验证。
- `.pkg` 未签名；Gatekeeper 会警告。
- 企业 VPN、TLS 检查、受管 Mac 可能与 MITM 冲突。
- 模型、价格和服务商 API 会变化；请查看服务商文档。
- 与 Anthropic、DeepSeek、腾讯、阿里巴巴、OpenRouter 无关联。

## 故障排查

```bash
# 网关
curl -v http://127.0.0.1:8788/health
tail -n 50 ~/"Library/Application Support/QClaudeCode/gateway/logs/launchd.err.log"

# LaunchAgent
launchctl print "gui/$(id -u)/com.qclaude.gateway"

# hosts / 证书 / pf
grep qclaude-mitm /etc/hosts
security find-certificate -c "QClaude Local CA" /Library/Keychains/System.keychain
sudo pfctl -s nat | grep 8443
sudo pfctl -a com.qclaude -sr

# 网关 TLS
lsof -nP -iTCP:8443 -sTCP:LISTEN
```

如果重启后 MITM 失效，检查 LaunchDaemon：

```bash
sudo launchctl print system/com.qclaude.pf
sudo pfctl -E
sudo pfctl -f /etc/pf.conf
```
