#!/usr/bin/env bash
# Direct launcher: Claude Code with the selected provider.
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

if ! command -v claude >/dev/null 2>&1; then
  echo "claude not found on PATH. Install: npm install -g @anthropic-ai/claude-code" >&2
  exit 127
fi

exec claude "$@"

