#!/usr/bin/env bash
# Claude Code through the local gateway.
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -h "$SELF" ]; do
  DIR="$(cd -P "$(dirname "$SELF")" && pwd)"
  SELF="$(readlink "$SELF")"
  if [[ "$SELF" != /* ]]; then SELF="$DIR/$SELF"; fi
done
QCLAUDE_HOME="$(cd -P "$(dirname "$SELF")/.." && pwd)"
export QCLAUDE_HOME

ENV_FILE="$QCLAUDE_HOME/env.sh"
if [ ! -f "$ENV_FILE" ]; then
  ENV_FILE="$(cd -P "$(dirname "$SELF")" && pwd)/env.sh"
fi
# shellcheck disable=SC1091
. "$ENV_FILE"

CONFIG="$QCLAUDE_HOME/gateway/config.json"
PROVIDER_FILE="$QCLAUDE_HOME/gateway/providers/$QCLAUDE_PROVIDER.json"

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

PORT="$(json_field "$CONFIG" listen.port)"
BASE="http://127.0.0.1:$PORT"
export ANTHROPIC_BASE_URL="$BASE"
export ANTHROPIC_AUTH_TOKEN="local-gateway"
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL="$(json_field "$PROVIDER_FILE" client.gateway.model)"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$(json_field "$PROVIDER_FILE" client.gateway.opus)"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$(json_field "$PROVIDER_FILE" client.gateway.sonnet)"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$(json_field "$PROVIDER_FILE" client.gateway.haiku)"
export CLAUDE_CODE_SUBAGENT_MODEL="$(json_field "$PROVIDER_FILE" client.gateway.subagent)"

if ! curl -fsS "$BASE/health" >/dev/null 2>&1; then
  echo "starting gateway..." >&2
  "$QCLAUDE_HOME/gateway/start.sh" --background || true
  for _ in $(seq 1 60); do
    sleep 0.25
    if curl -fsS "$BASE/health" >/dev/null 2>&1; then break; fi
  done
fi

if ! curl -fsS "$BASE/health" >/dev/null 2>&1; then
  echo "gateway did not start; run: $QCLAUDE_HOME/gateway/start.sh" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "claude not found on PATH. Install: npm install -g @anthropic-ai/claude-code" >&2
  exit 127
fi

exec claude "$@"

