#!/usr/bin/env bash
# Remove QClaude Code from macOS: LaunchAgent, optional MITM, PATH block,
# Claude settings and the install directory.
set -euo pipefail

INSTALL_DIR="${QCLAUDE_INSTALL_DIR:-$HOME/Library/Application Support/QClaudeCode}"
KEEP_SETTINGS=0
NO_MITM_CLEANUP=0
REMOVE_KEY=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --keep-settings) KEEP_SETTINGS=1; shift ;;
    --no-mitm-cleanup) NO_MITM_CLEANUP=1; shift ;;
    --remove-key) REMOVE_KEY=1; shift ;;
    --help|-h)
      cat <<'EOF'
Usage: uninstall.sh [options]
  --install-dir <path>
  --keep-settings
  --no-mitm-cleanup
  --remove-key
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

echo "QClaude Code uninstaller (macOS)"

# 1. LaunchAgent and gateway
echo "==> LaunchAgent"
launchctl bootout "gui/$(id -u)/com.qclaude.gateway" >/dev/null 2>&1 || true
rm -f "$HOME/Library/LaunchAgents/com.qclaude.gateway.plist"
pkill -f "$INSTALL_DIR/gateway/server.mjs" >/dev/null 2>&1 || true
echo "    removed"

# 2. MITM
MITM_OK=1
if [ "$NO_MITM_CLEANUP" -eq 0 ] && [ -f "$INSTALL_DIR/desktop/mitm/setup.sh" ]; then
  if grep -q 'qclaude-mitm' /etc/hosts 2>/dev/null || [ -f "$INSTALL_DIR/desktop/mitm/leaf.crt" ]; then
    echo "==> MITM teardown"
    if sudo env QCLAUDE_HOME="$INSTALL_DIR" "$INSTALL_DIR/macos/mitm/teardown.sh"; then
      echo "    removed"
    else
      MITM_OK=0
      echo "    teardown failed or was cancelled" >&2
    fi
  fi
fi

# 3. Claude settings
if [ "$KEEP_SETTINGS" -eq 0 ]; then
  echo "==> Claude settings"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    if (!fs.existsSync(path)) process.exit(0);
    let o;
    try { o = JSON.parse(fs.readFileSync(path, "utf8")); } catch { process.exit(0); }
    if (!o.env) process.exit(0);
    const ours = [
      "ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY",
      "ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL",
      "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL",
      "CLAUDE_CODE_SUBAGENT_MODEL", "CLAUDE_CODE_EFFORT_LEVEL",
      "CLAUDE_CODE_AUTO_COMPACT_WINDOW", "CLAUDE_GATEWAY_ALLOW_LOOPBACK"
    ];
    for (const k of ours) delete o.env[k];
    fs.writeFileSync(path, JSON.stringify(o, null, 2) + "\n");
  ' "$HOME/.claude/settings.json"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    if (!fs.existsSync(path)) process.exit(0);
    let o;
    try { o = JSON.parse(fs.readFileSync(path, "utf8")); } catch { process.exit(0); }
    delete o.hasCompletedOnboarding;
    fs.writeFileSync(path, JSON.stringify(o, null, 2) + "\n");
  ' "$HOME/.claude.json"
  echo "    cleaned"
fi

# 4. PATH block
echo "==> PATH block"
RC="$HOME/.zshrc"
if [ -f "$RC" ] && grep -Fq '# >>> qclaude >>>' "$RC"; then
  cp "$RC" "$RC.qclaude.bak"
  awk '
    /^# >>> qclaude >>>$/ { skip=1; next }
    /^# <<< qclaude <<<$/ { skip=0; next }
    !skip { print }
  ' "$RC.qclaude.bak" >"$RC"
  echo "    removed from ~/.zshrc"
fi

# 5. key / directory
if [ "$REMOVE_KEY" -eq 1 ]; then
  rm -f "$INSTALL_DIR/env"
  echo "==> Removed API key file"
fi

if [ "$MITM_OK" -eq 1 ]; then
  if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "==> Removed $INSTALL_DIR"
  fi
else
  echo "Install directory kept so MITM can be reverted:" >&2
  echo "  sudo env QCLAUDE_HOME=\"$INSTALL_DIR\" \"$INSTALL_DIR/macos/mitm/teardown.sh\"" >&2
fi

echo "done"
