#!/usr/bin/env bash
# QClaude Code installer for macOS.
#
# Recommended:
#   unzip QClaudeCode-*.zip
#   ./QClaudeCode-*/install.command
#
# CLI:
#   bash macos/install.sh [--provider deepseek] [--no-mitm]
#
# Educational, non-commercial project. Use at your own risk.
set -euo pipefail

MOUNT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd -P "$MOUNT_DIR/.." && pwd)"
INSTALL_DIR="${QCLAUDE_INSTALL_DIR:-$HOME/Library/Application Support/QClaudeCode}"
PROVIDER="${QCLAUDE_PROVIDER:-}"
NO_MITM=0
SKIP_DESKTOP=0
SKIP_CLAUDE_CODE=0
NO_START=0
VERSION="$(cat "$SOURCE_DIR/VERSION" 2>/dev/null || echo dev)"
MITM_OK=0

usage() {
  cat <<'EOF'
Usage: install.sh [options]

  --provider <id>       deepseek | tencent | alibaba | openrouter
  --no-mitm             do not configure Claude Desktop MITM
  --skip-desktop        do not install/configure Claude Desktop (implies --no-mitm)
  --skip-claude-code    do not install Claude Code
  --no-start            install the LaunchAgent but do not start the gateway
  --install-dir <path>  default: ~/Library/Application Support/QClaudeCode
  --help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --provider) PROVIDER="${2:-}"; shift 2 ;;
    --no-mitm) NO_MITM=1; shift ;;
    --skip-desktop) SKIP_DESKTOP=1; NO_MITM=1; shift ;;
    --skip-claude-code) SKIP_CLAUDE_CODE=1; shift ;;
    --no-start) NO_START=1; shift ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer is for macOS." >&2
  exit 1
fi

if [ ! -f "$SOURCE_DIR/gateway/server.mjs" ]; then
  echo "Run install.sh from the extracted QClaude Code package." >&2
  echo "Expected: $SOURCE_DIR/gateway/server.mjs" >&2
  exit 1
fi

echo
echo "QClaude Code installer (macOS)"
echo "Educational, non-commercial project. Provided as-is, without warranty."
echo "version $VERSION"
echo

# ---------------------------------------------------------------- Node.js
echo "==> Node.js"
if ! command -v node >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "    installing Node.js with Homebrew..."
    brew install node@22 || brew install node
    export PATH="/opt/homebrew/opt/node@22/bin:/usr/local/opt/node@22/bin:$PATH"
  else
    echo "Node.js 22+ is required: https://nodejs.org/en/download" >&2
    echo "Or install Homebrew, then: brew install node@22" >&2
    exit 1
  fi
fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$NODE_MAJOR" -lt 22 ]; then
  echo "Node.js 22+ is required; found $(node --version)." >&2
  if command -v brew >/dev/null 2>&1; then
    brew install node@22
    export PATH="/opt/homebrew/opt/node@22/bin:/usr/local/opt/node@22/bin:$PATH"
  else
    exit 1
  fi
fi
echo "    found $(node --version)"

# ---------------------------------------------------------------- Claude Code
if [ "$SKIP_CLAUDE_CODE" -eq 0 ]; then
  echo "==> Claude Code"
  if command -v claude >/dev/null 2>&1; then
    echo "    found $(command -v claude)"
  elif command -v npm >/dev/null 2>&1; then
    npm install -g @anthropic-ai/claude-code@latest
  else
    echo "npm not found; install Node.js 22+ first." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------- Desktop
if [ "$SKIP_DESKTOP" -eq 0 ]; then
  echo "==> Claude Desktop"
  if [ -d "/Applications/Claude.app" ]; then
    echo "    found /Applications/Claude.app"
  elif command -v brew >/dev/null 2>&1; then
    echo "    installing Claude Desktop with Homebrew..."
    brew install --cask claude || echo "    install it manually: https://claude.ai/download" >&2
  else
    echo "    install it manually: https://claude.ai/download" >&2
  fi
fi

# ---------------------------------------------------------------- stop old
echo "==> Stopping old gateway"
launchctl bootout "gui/$(id -u)/com.qclaude.gateway" >/dev/null 2>&1 || true
OLD_PID=""
if [ -f "$INSTALL_DIR/gateway/logs/gateway.pid" ]; then
  OLD_PID="$(cat "$INSTALL_DIR/gateway/logs/gateway.pid" 2>/dev/null || true)"
fi
if [ -z "$OLD_PID" ] && command -v lsof >/dev/null 2>&1; then
  OLD_PID="$(lsof -tiTCP:8788 -sTCP:LISTEN 2>/dev/null || true)"
fi
if [ -n "$OLD_PID" ]; then kill $OLD_PID >/dev/null 2>&1 || true; fi

mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/gateway/logs" "$INSTALL_DIR/bin"

# ---------------------------------------------------------------- copy
echo "==> Installing files to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/docs" "$INSTALL_DIR/examples"
if [ "$SOURCE_DIR" != "$INSTALL_DIR" ]; then
  rsync -a --exclude logs "$SOURCE_DIR/gateway/" "$INSTALL_DIR/gateway/"
  rsync -a "$SOURCE_DIR/desktop/" "$INSTALL_DIR/desktop/"
  rsync -a "$SOURCE_DIR/macos/" "$INSTALL_DIR/macos/"
  rsync -a "$SOURCE_DIR/docs/" "$INSTALL_DIR/docs/"
  rsync -a "$SOURCE_DIR/examples/" "$INSTALL_DIR/examples/"
  for f in README.md README.ru.md README.en.md README.zh-CN.md LICENSE CHANGELOG.md VERSION; do
    if [ -f "$SOURCE_DIR/$f" ]; then cp "$SOURCE_DIR/$f" "$INSTALL_DIR/$f"; fi
  done
else
  echo "    source and destination are the same; keeping existing files"
fi

cp "$INSTALL_DIR/macos/env.sh" "$INSTALL_DIR/env.sh"
chmod +x "$INSTALL_DIR/macos/install.sh" "$INSTALL_DIR/macos/uninstall.sh" \
  "$INSTALL_DIR/macos/qclaude.sh" "$INSTALL_DIR/macos/qclaude-gw.sh" \
  "$INSTALL_DIR/macos/gateway/run.sh" "$INSTALL_DIR/macos/gateway/start.sh" \
  "$INSTALL_DIR/macos/mitm/setup.sh" "$INSTALL_DIR/macos/mitm/teardown.sh" \
  "$INSTALL_DIR/macos/mitm/pf-load.sh"
cp "$INSTALL_DIR/macos/qclaude.sh" "$INSTALL_DIR/bin/qclaude"
cp "$INSTALL_DIR/macos/qclaude-gw.sh" "$INSTALL_DIR/bin/qclaude-gw"
chmod +x "$INSTALL_DIR/bin/qclaude" "$INSTALL_DIR/bin/qclaude-gw"

# ---------------------------------------------------------------- provider
if [ -z "$PROVIDER" ]; then
  echo "==> Provider"
  echo "  1. DeepSeek"
  echo "  2. Tencent Hunyuan"
  echo "  3. Alibaba Cloud Bailian (Qwen)"
  echo "  4. OpenRouter"
  echo "  5. Homyak API (homyakstudio.ru, RUB)"
  read -r -p "  Choose provider [1]: " CHOICE
  case "${CHOICE:-1}" in
    2) PROVIDER=tencent ;;
    3) PROVIDER=alibaba ;;
    4) PROVIDER=openrouter ;;
    5) PROVIDER=homyak ;;
    *) PROVIDER=deepseek ;;
  esac
fi
case "$PROVIDER" in
  deepseek|tencent|alibaba|openrouter|homyak) ;;
  *) echo "Unknown provider: $PROVIDER" >&2; exit 2 ;;
esac
PROVIDER_FILE="$INSTALL_DIR/gateway/providers/$PROVIDER.json"
if [ ! -f "$PROVIDER_FILE" ]; then
  echo "Provider preset not found: $PROVIDER_FILE" >&2
  exit 1
fi

node -e '
  const fs = require("fs");
  const p = process.argv[1];
  const o = JSON.parse(fs.readFileSync(p, "utf8"));
  o.provider = process.argv[2];
  fs.writeFileSync(p, JSON.stringify(o, null, 2) + "\n");
' "$INSTALL_DIR/gateway/config.json" "$PROVIDER"

# ---------------------------------------------------------------- key
KEY_ENV="$(node -e '
  const fs = require("fs");
  process.stdout.write(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).auth.env);
' "$PROVIDER_FILE")"

KEY=""
if [ -f "$INSTALL_DIR/env" ]; then
  # shellcheck disable=SC1091
  set -a
  . "$INSTALL_DIR/env"
  set +a
  eval "KEY=\${$KEY_ENV:-}"
fi
if [ -z "$KEY" ]; then
  eval "KEY=\${$KEY_ENV:-}"
fi
if [ -z "$KEY" ]; then
  echo "==> API key"
  echo "    create one: $(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).docs)' "$PROVIDER_FILE")"
  read -r -s -p "    Paste API key (hidden): " KEY
  echo
fi
if [ -z "$KEY" ]; then
  echo "No API key provided." >&2
  exit 1
fi
umask 077
printf '%s=%q\n' "$KEY_ENV" "$KEY" >"$INSTALL_DIR/env"
chmod 600 "$INSTALL_DIR/env"

# ---------------------------------------------------------------- Claude settings
echo "==> Claude Code settings"
SETTINGS="$HOME/.claude/settings.json"
CLAUDE_JSON="$HOME/.claude.json"
mkdir -p "$HOME/.claude"
if [ -f "$SETTINGS" ]; then cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d%H%M%S)"; fi
if [ -f "$CLAUDE_JSON" ]; then cp "$CLAUDE_JSON" "$CLAUDE_JSON.bak-$(date +%Y%m%d%H%M%S)"; fi

ENV_JSON="$(node -e '
  const fs = require("fs");
  const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const c = p.client.gateway;
  process.stdout.write(JSON.stringify({
    ANTHROPIC_BASE_URL: "http://127.0.0.1:8788",
    ANTHROPIC_AUTH_TOKEN: "local-gateway",
    ANTHROPIC_API_KEY: "",
    ANTHROPIC_MODEL: c.model,
    ANTHROPIC_DEFAULT_OPUS_MODEL: c.opus,
    ANTHROPIC_DEFAULT_SONNET_MODEL: c.sonnet,
    ANTHROPIC_DEFAULT_HAIKU_MODEL: c.haiku,
    CLAUDE_CODE_SUBAGENT_MODEL: c.subagent,
    CLAUDE_CODE_EFFORT_LEVEL: "max",
    CLAUDE_CODE_AUTO_COMPACT_WINDOW: "200000",
    CLAUDE_GATEWAY_ALLOW_LOOPBACK: "true"
  }));
' "$PROVIDER_FILE")"

node -e '
  const fs = require("fs");
  const path = process.argv[1];
  const additions = JSON.parse(process.argv[2]);
  let o = {};
  try { o = JSON.parse(fs.readFileSync(path, "utf8")); } catch {}
  o.env = Object.assign({}, o.env || {}, additions);
  fs.writeFileSync(path, JSON.stringify(o, null, 2) + "\n");
' "$SETTINGS" "$ENV_JSON"

node -e '
  const fs = require("fs");
  const path = process.argv[1];
  let o = {};
  try { o = JSON.parse(fs.readFileSync(path, "utf8")); } catch {}
  o.hasCompletedOnboarding = true;
  fs.writeFileSync(path, JSON.stringify(o, null, 2) + "\n");
' "$CLAUDE_JSON"

# ---------------------------------------------------------------- MITM
if [ "$NO_MITM" -eq 0 ]; then
  echo "==> Claude Desktop MITM"
  echo "    administrator rights are required for hosts, System keychain and pf."
  if sudo env QCLAUDE_HOME="$INSTALL_DIR" "$INSTALL_DIR/macos/mitm/setup.sh"; then
    MITM_OK=1
  else
    echo "    MITM was not configured; Claude Desktop will use the official endpoint." >&2
  fi
else
  echo "==> Claude Desktop MITM skipped"
fi

# ---------------------------------------------------------------- LaunchAgent
echo "==> Gateway LaunchAgent"
LA="$HOME/Library/LaunchAgents/com.qclaude.gateway.plist"
mkdir -p "$HOME/Library/LaunchAgents"
sed "s|__QCLAUDE_HOME__|$INSTALL_DIR|g" "$INSTALL_DIR/macos/launchagent.plist.in" >"$LA"
chmod 644 "$LA"
plutil -lint "$LA" >/dev/null
launchctl bootout "gui/$(id -u)/com.qclaude.gateway" >/dev/null 2>&1 || true
if ! launchctl bootstrap "gui/$(id -u)" "$LA" >/dev/null 2>&1; then
  launchctl load -w "$LA" >/dev/null 2>&1 || true
fi
launchctl enable "gui/$(id -u)/com.qclaude.gateway" >/dev/null 2>&1 || true
echo "    $LA"

# ---------------------------------------------------------------- PATH
MARK="# >>> qclaude >>>"
if ! grep -Fq "$MARK" "$HOME/.zshrc" 2>/dev/null; then
  {
    printf '\n%s\n' "$MARK"
    printf 'export PATH="%s/bin:$PATH"\n' "$INSTALL_DIR"
    printf '%s\n' "# <<< qclaude <<<"
  } >>"$HOME/.zshrc"
  echo "    added $INSTALL_DIR/bin to ~/.zshrc"
fi

# ---------------------------------------------------------------- start
if [ "$NO_START" -eq 0 ]; then
  echo "==> Gateway start"
  launchctl kickstart -k "gui/$(id -u)/com.qclaude.gateway" >/dev/null 2>&1 || true
  for _ in $(seq 1 60); do
    sleep 0.25
    if curl -fsS http://127.0.0.1:8788/health >/dev/null 2>&1; then break; fi
  done
  if curl -fsS http://127.0.0.1:8788/health >/dev/null 2>&1; then
    echo "    gateway is running"
  else
    echo "    gateway did not answer /health yet; see $INSTALL_DIR/gateway/logs" >&2
  fi
fi

cat >"$INSTALL_DIR/install.json" <<EOF
{
  "version": "$VERSION",
  "provider": "$PROVIDER",
  "installDir": "$INSTALL_DIR",
  "mitm": $([ "$MITM_OK" -eq 1 ] && echo true || echo false),
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo
echo "Done."
echo "  gateway : http://127.0.0.1:8788"
echo "  desktop : $([ "$MITM_OK" -eq 1 ] && echo 'MITM on https://api.anthropic.com' || echo 'not intercepted')"
echo "  launch  : qclaude-gw"
echo "  logs    : $INSTALL_DIR/gateway/logs"
echo
echo "Open a new terminal (or run: source ~/.zshrc) so PATH is updated."
echo "Educational / non-commercial project. Respect provider terms and local law."
