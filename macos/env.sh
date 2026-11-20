#!/usr/bin/env bash
# Shared macOS environment for QClaude Code.
# Source this file from the launchers:  . "$QCLAUDE_HOME/env.sh"
set -euo pipefail

QCLAUDE_HOME="${QCLAUDE_HOME:-$HOME/Library/Application Support/QClaudeCode}"
export QCLAUDE_HOME

CONFIG="$QCLAUDE_HOME/gateway/config.json"
if [ ! -f "$CONFIG" ]; then
  echo "QClaude config not found: $CONFIG" >&2
  return 1 2>/dev/null || exit 1
fi

json_field() {
  node -e '
    const fs = require("fs");
    const value = process.argv[2]
      .split(".")
      .reduce((o, k) => (o == null ? undefined : o[k]), JSON.parse(fs.readFileSync(process.argv[1], "utf8")));
    if (value === undefined || value === null) process.exit(2);
    process.stdout.write(String(value));
  ' "$1" "$2"
}

PROVIDER="${QCLAUDE_PROVIDER:-$(json_field "$CONFIG" provider)}"
if [ -z "$PROVIDER" ]; then
  echo "Provider is not configured in $CONFIG" >&2
  return 1 2>/dev/null || exit 1
fi
PROVIDER_FILE="$QCLAUDE_HOME/gateway/providers/$PROVIDER.json"
if [ ! -f "$PROVIDER_FILE" ]; then
  echo "Unknown provider '$PROVIDER': $PROVIDER_FILE not found" >&2
  return 1 2>/dev/null || exit 1
fi

KEY_ENV="$(json_field "$PROVIDER_FILE" auth.env)"
if [ -z "$KEY_ENV" ]; then
  echo "Provider '$PROVIDER' has no auth.env" >&2
  return 1 2>/dev/null || exit 1
fi
if [ -f "$QCLAUDE_HOME/env" ]; then
  # shellcheck disable=SC1091
  set -a
  . "$QCLAUDE_HOME/env"
  set +a
fi

KEY_VALUE="${!KEY_ENV:-}"
if [ -z "$KEY_VALUE" ]; then
  echo "API key $KEY_ENV is not set. Run: qclaude" >&2
  echo "or add $KEY_ENV=... to $QCLAUDE_HOME/env" >&2
  return 1 2>/dev/null || exit 1
fi

# Direct mode defaults. qclaude-gw overrides these for the local gateway.
export ANTHROPIC_BASE_URL="$(json_field "$PROVIDER_FILE" upstream)"
export ANTHROPIC_AUTH_TOKEN="$KEY_VALUE"
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL="$(json_field "$PROVIDER_FILE" client.direct.model)"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$(json_field "$PROVIDER_FILE" client.direct.opus)"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$(json_field "$PROVIDER_FILE" client.direct.sonnet)"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$(json_field "$PROVIDER_FILE" client.direct.haiku)"
export CLAUDE_CODE_SUBAGENT_MODEL="$(json_field "$PROVIDER_FILE" client.direct.subagent)"
export CLAUDE_CODE_EFFORT_LEVEL="${CLAUDE_CODE_EFFORT_LEVEL:-max}"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-200000}"
export GATEWAY_PROVIDER="$PROVIDER"
export QCLAUDE_PROVIDER="$PROVIDER"

# If the local MITM certificate exists, the gateway also listens with TLS on
# 8443. pfctl redirects 443 -> 8443 (macOS cannot bind 443 as a normal user).
if [ -f "$QCLAUDE_HOME/desktop/mitm/leaf.crt" ] && [ -f "$QCLAUDE_HOME/desktop/mitm/leaf.key" ]; then
  export GATEWAY_TLS_CERT="$QCLAUDE_HOME/desktop/mitm/leaf.crt"
  export GATEWAY_TLS_KEY="$QCLAUDE_HOME/desktop/mitm/leaf.key"
  export GATEWAY_TLS_PORT="${GATEWAY_TLS_PORT:-8443}"
fi
