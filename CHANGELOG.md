# Changelog

All notable changes are documented here. The project is educational and
non-commercial; compatibility is best-effort.

## 1.0.3 — 2026-11-19

- Claude Desktop MITM is now installed automatically by default:
  local CA, Trusted Root, `api.anthropic.com` certificate, hosts entry, and
  gateway TLS listener on port 443.
- UAC elevation is handled by the installer; `-NoMitm` opts out and
  `-SkipClaudeDesktop` skips both Desktop and MITM.
- `setup-mitm.ps1` is idempotent and returns proper exit codes.
- `uninstall.ps1` tears MITM down automatically; if UAC is cancelled, it keeps
  the install directory so cleanup can be retried.
- Added an HTTPS interception check to the installer.
- Updated all three language docs and the security notes.

## 1.0.2 — 2026-11-19

- The installer now creates `qclaude.cmd` and `qclaude-gw.cmd` in
  `%LOCALAPPDATA%\QClaudeCode\bin` and adds that directory to the user PATH.
  `qclaude-gw` works in a new terminal.
- The uninstaller removes those PATH entries.
- Installer native calls (npm, winget) no longer abort on harmless stderr
  output under PowerShell 5.1 `$ErrorActionPreference = 'Stop'`.
- The parity harness no longer deletes its own README.

## 1.0.1 — 2026-11-19

- `install.cmd` can now bootstrap the latest installer when it is downloaded
  alone, not only when it sits next to `install.ps1`.
- The installer writes `CLAUDE_CODE_EFFORT_LEVEL` and
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW` into Claude settings; the uninstaller
  removes them.
- Documented which provider presets were live-tested and which are based on
  official provider documentation.

## 1.0.0 — 2026-11-19

First public release.

- Generalized the DeepSeek-only gateway into provider presets:
  DeepSeek, Tencent Hunyuan, Alibaba Cloud Bailian (Qwen), OpenRouter.
- Added configurable auth (`Authorization: Bearer` or `x-api-key`), static
  upstream headers, model maps, currencies and pricing tables.
- Added `haikuToCheap` routing and per-provider `cheapProfile`.
- Added document modes: `deepseek-files`, `native`, `none`.
- OpenRouter exact `usage.cost` is stored when present.
- Added `GET /health` with provider, upstream, routes and key state.
- Added process PID file and reliable `gateway/start.ps1 -Stop`.
- Added a one-command Windows installer: Node.js, Claude Code, Claude Desktop,
  gateway, logon autostart, smoke test.
- Added an uninstaller.
- Added trilingual documentation (Russian, English, Simplified Chinese).
- Added direct-mode settings examples for all providers.
- Added Node test suite (config, routing, pricing, context, HTTP integration).
- Added CI and release workflows.
