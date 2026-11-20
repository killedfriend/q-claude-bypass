#!/usr/bin/env bash
# Start/stop the gateway on macOS.
#   gateway/start.sh              # foreground
#   gateway/start.sh --background # via LaunchAgent (or nohup fallback)
#   gateway/start.sh --stop
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

CONFIG="$QCLAUDE_HOME/gateway/config.json"
PORT="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).listen.port))' "$CONFIG")"
HEALTH="http://127.0.0.1:$PORT/health"
LABEL="com.qclaude.gateway"
UID_NUM="$(id -u)"

stop_gateway() {
  local pids
  pids="$(pgrep -f "$QCLAUDE_HOME/gateway/server.mjs" || true)"
  if [ -n "$pids" ]; then
    # SIGTERM lets the gateway close the pid file cleanly.
    kill $pids 2>/dev/null || true
    for _ in $(seq 1 20); do
      sleep 0.25
      pgrep -f "$QCLAUDE_HOME/gateway/server.mjs" >/dev/null 2>&1 || break
    done
    pids="$(pgrep -f "$QCLAUDE_HOME/gateway/server.mjs" || true)"
    if [ -n "$pids" ]; then kill -9 $pids 2>/dev/null || true; fi
    echo "stopped gateway"
  else
    echo "gateway is not running"
  fi
}

case "${1:-}" in
  --stop)
    stop_gateway
    ;;
  --background)
    mkdir -p "$GATEWAY_DIR/logs"
    if launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
      launchctl kickstart -k "gui/$UID_NUM/$LABEL"
    else
      nohup "$GATEWAY_DIR/run.sh" >>"$GATEWAY_DIR/logs/out.log" 2>>"$GATEWAY_DIR/logs/err.log" &
    fi
    for _ in $(seq 1 60); do
      sleep 0.25
      if curl -fsS "$HEALTH" >/dev/null 2>&1; then
        echo "gateway started on http://127.0.0.1:$PORT"
        exit 0
      fi
    done
    echo "gateway did not start; see $GATEWAY_DIR/logs" >&2
    exit 1
    ;;
  *)
    exec "$GATEWAY_DIR/run.sh"
    ;;
esac

