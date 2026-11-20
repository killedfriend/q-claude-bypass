#!/bin/bash
# Remove the macOS MITM: pf redirect, hosts entry, trusted CA and certificates.
# Requires root. Idempotent.
set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo env QCLAUDE_HOME=\"...\" $0" >&2
  exit 1
fi

QCLAUDE_HOME="${QCLAUDE_HOME:-}"
if [ -z "$QCLAUDE_HOME" ]; then
  TARGET_USER="${SUDO_USER:-$(stat -f%Su /dev/console)}"
  QCLAUDE_HOME="/Users/$TARGET_USER/Library/Application Support/QClaudeCode"
fi
MITM_DIR="$QCLAUDE_HOME/desktop/mitm"
PF_CONF="/etc/pf.conf"
PF_ANCHOR="/etc/pf.anchors/com.qclaude"
PF_DAEMON="/Library/LaunchDaemons/com.qclaude.pf.plist"
HOSTS="/etc/hosts"
TMP="$(mktemp /tmp/qclaude-mitm-down.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

echo "pf"
launchctl bootout system/com.qclaude.pf >/dev/null 2>&1 || true
rm -f "$PF_DAEMON" "$PF_ANCHOR"

RDR_START="# >>> qclaude-mitm rdr >>>"
RDR_END="# <<< qclaude-mitm rdr <<<"
FILTER_START="# >>> qclaude-mitm filter >>>"
FILTER_END="# <<< qclaude-mitm filter <<<"
if [ -f "$PF_CONF" ]; then
  awk -v s="$RDR_START" -v e="$RDR_END" -v s2="$FILTER_START" -v e2="$FILTER_END" '
    $0 == s { skip=1; next }
    $0 == e { skip=0; next }
    $0 == s2 { skip=1; next }
    $0 == e2 { skip=0; next }
    !skip { print }
  ' "$PF_CONF" >"$TMP"
  cat "$TMP" >"$PF_CONF"
  /sbin/pfctl -f "$PF_CONF" >/dev/null 2>&1 || true
  /sbin/pfctl -X >/dev/null 2>&1 || true
  echo "  pf rules removed"
fi

echo "hosts"
cp -p "$HOSTS" "$MITM_DIR/hosts.backup" 2>/dev/null || true
awk '!/# qclaude-mitm/ && !/^[[:space:]]*127\.0\.0\.1[[:space:]]+api\.anthropic\.com[[:space:]]*$/' "$HOSTS" >"$TMP"
cat "$TMP" >"$HOSTS"
echo "  hosts entry removed"

echo "certificates"
security delete-certificate -c "QClaude Local CA" /Library/Keychains/System.keychain >/dev/null 2>&1 || true
rm -f "$MITM_DIR/ca.key" "$MITM_DIR/ca.crt" "$MITM_DIR/ca.cnf" \
      "$MITM_DIR/leaf.key" "$MITM_DIR/leaf.crt" "$MITM_DIR/leaf.cnf" \
      "$MITM_DIR/leaf.csr" "$MITM_DIR/ca.srl"
echo "  local CA and leaf removed"

echo "done"
