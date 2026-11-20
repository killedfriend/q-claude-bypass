#!/usr/bin/env bash
# Foreground gateway process used by the LaunchAgent.
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -h "$SELF" ]; do
  DIR="$(cd -P "$(dirname "$SELF")" && pwd)"
  SELF="$(readlink "$SELF")"
  if [[ "$SELF" != /* ]]; then SELF="$DIR/$SELF"; fi
done
GATEWAY_DIR="$(cd -P "$(dirname "$SELF")" && pwd)"
QCLAUDE_HOME="$(cd -P "$GATEWAY_DIR/.." && pwd)"
export QCLAUDE_HOME

ENV_FILE="$QCLAUDE_HOME/env.sh"
if [ ! -f "$ENV_FILE" ]; then
  ENV_FILE="$(cd -P "$GATEWAY_DIR/.." && pwd)/macos/env.sh"
fi
# shellcheck disable=SC1091
. "$ENV_FILE"

mkdir -p "$GATEWAY_DIR/logs"
cd "$GATEWAY_DIR"
exec node server.mjs

