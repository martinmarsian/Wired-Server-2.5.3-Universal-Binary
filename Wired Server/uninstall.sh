#!/bin/sh

LIBRARY="$1"

LABEL="fr.read-write.WiredServer"

INSTALL_USER=$(echo "$LIBRARY" | sed -E 's,/Users/([^/]+)/.*,\1,')
[ -z "$INSTALL_USER" ] && INSTALL_USER="$USER"
INSTALL_UID=$(id -u "$INSTALL_USER" 2>/dev/null)

# ── Read service user/group from wired.conf before we delete everything ───────
CONF_USER=$(grep -m1 '^user = ' "/Library/Wired/data/etc/wired.conf" 2>/dev/null | sed 's/^user = //')
CONF_GROUP=$(grep -m1 '^group = ' "/Library/Wired/data/etc/wired.conf" 2>/dev/null | sed 's/^group = //')
[ -z "$CONF_USER"  ] && CONF_USER="wired"
[ -z "$CONF_GROUP" ] && CONF_GROUP="wired"

# ── Stop and remove the LaunchDaemon ──────────────────────────────────────────
/bin/launchctl disable "system/${LABEL}" 2>/dev/null || true
/bin/launchctl bootout "system/${LABEL}" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/${LABEL}.plist" 2>/dev/null || true

# ── Also remove old LaunchAgent if still present (migration) ──────────────────
if [ -n "$INSTALL_UID" ]; then
    /bin/launchctl bootout "gui/${INSTALL_UID}/${LABEL}" 2>/dev/null || true
fi
rm -f "/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null || true

# ── Remove the macOS service user and group ───────────────────────────────────
if dscl . -read "/Users/${CONF_USER}" >/dev/null 2>&1; then
    dscl . -delete "/Users/${CONF_USER}" 2>/dev/null || true
fi
if dscl . -read "/Groups/${CONF_GROUP}" >/dev/null 2>&1; then
    dscl . -delete "/Groups/${CONF_GROUP}" 2>/dev/null || true
fi

rm -rf "$LIBRARY/Wired" 2>/dev/null || true
rm -rf "/Library/Wired" || exit 1

echo "WIREDSERVER_SCRIPT_OK"
exit 0
