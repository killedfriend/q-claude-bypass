#!/bin/bash
# Runs as root from /Library/LaunchDaemons/com.qclaude.pf.plist at boot.
# Enables pf and reloads the system ruleset, which references the QClaude anchor.
set -u
/sbin/pfctl -E >/dev/null 2>&1 || true
/sbin/pfctl -f /etc/pf.conf
