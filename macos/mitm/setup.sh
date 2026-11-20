#!/bin/bash
# macOS MITM setup:
#   - local CA and api.anthropic.com leaf certificate (openssl)
#   - CA trusted in the System keychain (security)
#   - hosts entry 127.0.0.1 api.anthropic.com
#   - pfctl redirect 443 -> 8443, with a boot LaunchDaemon
#
# Requires root. The gateway itself keeps running as the desktop user.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo env QCLAUDE_HOME=\"...\" $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd)"
QCLAUDE_HOME="${QCLAUDE_HOME:-}"
if [ -z "$QCLAUDE_HOME" ]; then
  TARGET_USER="${SUDO_USER:-$(stat -f%Su /dev/console)}"
  QCLAUDE_HOME="/Users/$TARGET_USER/Library/Application Support/QClaudeCode"
fi
TARGET_USER="${SUDO_USER:-$(stat -f%Su /dev/console)}"
TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || echo staff)"
MITM_DIR="$QCLAUDE_HOME/desktop/mitm"
PF_CONF="/etc/pf.conf"
PF_ANCHOR="/etc/pf.anchors/com.qclaude"
PF_DAEMON="/Library/LaunchDaemons/com.qclaude.pf.plist"
HOSTS="/etc/hosts"

if [ ! -d "$MITM_DIR" ]; then
  echo "MITM directory not found: $MITM_DIR" >&2
  exit 1
fi

TMP="$(mktemp /tmp/qclaude-mitm.XXXXXX)"
trap 'rm -f "$TMP" "$TMP.2"' EXIT

echo "1/5 certificates"
CA_KEY="$MITM_DIR/ca.key"
CA_CRT="$MITM_DIR/ca.crt"
LEAF_KEY="$MITM_DIR/leaf.key"
LEAF_CRT="$MITM_DIR/leaf.crt"
LEAF_CSR="$MITM_DIR/leaf.csr"

cat >"$MITM_DIR/ca.cnf" <<'EOF'
[req]
prompt = no
distinguished_name = dn
x509_extensions = v3_ca

[dn]
CN = QClaude Local CA

[v3_ca]
basicConstraints = critical,CA:TRUE,pathlen:1
keyUsage = critical,keyCertSign,cRLSign,digitalSignature
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

cat >"$MITM_DIR/leaf.cnf" <<'EOF'
[req]
prompt = no
distinguished_name = dn
req_extensions = v3_req

[dn]
CN = api.anthropic.com

[v3_req]
subjectAltName = @alt_names
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = api.anthropic.com
DNS.2 = *.anthropic.com
EOF

if [ ! -f "$CA_CRT" ] || [ ! -f "$CA_KEY" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$CA_KEY" -out "$CA_CRT" -days 1825 -config "$MITM_DIR/ca.cnf" >/dev/null 2>&1
  echo "  created CA"
else
  echo "  reusing CA"
fi

rm -f "$LEAF_KEY" "$LEAF_CRT" "$LEAF_CSR"
openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$LEAF_KEY" -out "$LEAF_CSR" -config "$MITM_DIR/leaf.cnf" >/dev/null 2>&1
openssl x509 -req -in "$LEAF_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
  -out "$LEAF_CRT" -days 825 -extensions v3_req -extfile "$MITM_DIR/leaf.cnf" >/dev/null 2>&1
rm -f "$LEAF_CSR" "$MITM_DIR/ca.srl"

if ! openssl x509 -in "$LEAF_CRT" -noout -text | grep -q 'DNS:api.anthropic.com'; then
  echo "leaf certificate is missing the api.anthropic.com SAN" >&2
  exit 1
fi
chmod 600 "$CA_KEY" "$LEAF_KEY"
chown "$TARGET_USER:$TARGET_GROUP" "$CA_KEY" "$CA_CRT" "$LEAF_KEY" "$LEAF_CRT" "$MITM_DIR/ca.cnf" "$MITM_DIR/leaf.cnf"
echo "  leaf: $LEAF_CRT"

echo "2/5 Trusted Root"
if ! security find-certificate -c "QClaude Local CA" /Library/Keychains/System.keychain >/dev/null 2>&1; then
  security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CA_CRT" >/dev/null
  echo "  CA added to System keychain"
else
  echo "  CA already trusted"
fi

echo "3/5 hosts"
cp -p "$HOSTS" "$MITM_DIR/hosts.backup" 2>/dev/null || true
awk '!/# qclaude-mitm/ && !/^[[:space:]]*127\.0\.0\.1[[:space:]]+api\.anthropic\.com[[:space:]]*$/' "$HOSTS" >"$TMP"
printf '\n# qclaude-mitm\n127.0.0.1 api.anthropic.com\n' >>"$TMP"
cat "$TMP" >"$HOSTS"
echo "  hosts -> 127.0.0.1"

echo "4/5 pf redirect 443 -> 8443"
mkdir -p /etc/pf.anchors
cp "$SCRIPT_DIR/pf-anchor.conf" "$PF_ANCHOR"
chmod 644 "$PF_ANCHOR"
[ -f "$PF_CONF.qclaude.bak" ] || cp -p "$PF_CONF" "$PF_CONF.qclaude.bak"

RDR_START="# >>> qclaude-mitm rdr >>>"
RDR_END="# <<< qclaude-mitm rdr <<<"
FILTER_START="# >>> qclaude-mitm filter >>>"
FILTER_END="# <<< qclaude-mitm filter <<<"
RDR_BLOCK="$RDR_START
rdr-anchor \"com.qclaude\"
$RDR_END"
FILTER_BLOCK="$FILTER_START
anchor \"com.qclaude\"
load anchor \"com.qclaude\" from \"/etc/pf.anchors/com.qclaude\"
$FILTER_END"

awk -v s="$RDR_START" -v e="$RDR_END" -v s2="$FILTER_START" -v e2="$FILTER_END" '
  $0 == s { skip=1; next }
  $0 == e { skip=0; next }
  $0 == s2 { skip=1; next }
  $0 == e2 { skip=0; next }
  !skip { print }
' "$PF_CONF" >"$TMP"

if grep -q '^[[:space:]]*rdr-anchor[[:space:]]' "$TMP"; then
  awk -v block="$RDR_BLOCK" '
    { lines[NR]=$0; if ($0 ~ /^[[:space:]]*rdr-anchor[[:space:]]/) last=NR }
    END { for (i=1; i<=NR; i++) { print lines[i]; if (i==last) print block } }
  ' "$TMP" >"$TMP.2"
else
  { printf '%s\n' "$RDR_BLOCK"; cat "$TMP"; } >"$TMP.2"
fi
mv "$TMP.2" "$TMP"
printf '\n%s\n' "$FILTER_BLOCK" >>"$TMP"

if ! /sbin/pfctl -n -f "$TMP" >/dev/null 2>&1; then
  echo "pf.conf validation failed; restoring the original" >&2
  cp -p "$PF_CONF.qclaude.bak" "$PF_CONF" 2>/dev/null || true
  exit 1
fi
cat "$TMP" >"$PF_CONF"

chmod 755 "$SCRIPT_DIR/pf-load.sh"
sed "s|__QCLAUDE_HOME__|$QCLAUDE_HOME|g" "$SCRIPT_DIR/launchdaemon.plist.in" >"$PF_DAEMON"
chmod 644 "$PF_DAEMON"
launchctl bootout system/com.qclaude.pf >/dev/null 2>&1 || true
launchctl bootstrap system "$PF_DAEMON" >/dev/null 2>&1 || true

/sbin/pfctl -E >/dev/null 2>&1 || true
if ! /sbin/pfctl -f "$PF_CONF"; then
  echo "pfctl could not load the rules; restoring the previous pf.conf" >&2
  cp -p "$PF_CONF.qclaude.bak" "$PF_CONF" 2>/dev/null || true
  /sbin/pfctl -f "$PF_CONF" >/dev/null 2>&1 || true
  exit 1
fi
echo "  pf anchor loaded"

echo "5/5 done"
echo "The gateway must run as the desktop user and listen on 127.0.0.1:8443."
echo "Restart Claude Desktop completely after setup."
