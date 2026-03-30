#!/bin/sh

LIBRARY="$1"

LABEL="fr.read-write.WiredServer"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"

# ── Stop the LaunchDaemon ─────────────────────────────────────────────────────
# Disable first so KeepAlive does not cause launchd to restart the daemon.
/bin/launchctl disable "system/${LABEL}" 2>&1
/bin/launchctl bootout "system/${LABEL}" 2>&1 || \
    /bin/launchctl bootout system "${PLIST}" 2>&1 || true

# ── Also stop old LaunchAgent if still present (migration from gui domain) ────
INSTALL_USER=$(echo "$LIBRARY" | sed -E 's,/Users/([^/]+)/.*,\1,')
[ -z "$INSTALL_USER" ] && INSTALL_USER="$USER"
INSTALL_UID=$(id -u "$INSTALL_USER" 2>/dev/null)
if [ -n "$INSTALL_UID" ]; then
    /bin/launchctl bootout "gui/${INSTALL_UID}/${LABEL}" 2>/dev/null || true
fi
rm -f "/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null || true

echo "WIREDSERVER_SCRIPT_OK"
exit 0
