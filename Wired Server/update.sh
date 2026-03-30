#!/bin/sh
exec 2>&1
set -x

SOURCE="$1"
LIBRARY="$2"

DATA="/Library/Wired/data"

INSTALL_USER=$(echo "$LIBRARY" | sed -E 's,/Users/([^/]+)/.*,\1,')
[ -z "$INSTALL_USER" ] && INSTALL_USER="$USER"

# ── Update system binaries ────────────────────────────────────────────────────
install -m 755 -d "/Library/Wired" || exit 1
install -m 755 "$SOURCE/Wired/wired"            "/Library/Wired" || exit 1
install -m 755 "$SOURCE/Wired/wiredctl"         "/Library/Wired" || exit 1
install -m 755 "$SOURCE/Wired/rebuild-index.sh" "/Library/Wired" 2>/dev/null || true
install -m 644 "$SOURCE/Wired/wired.xml"        "$DATA"          || exit 1

# ── Read service user/group from wired.conf ───────────────────────────────────
CONF_USER=$(grep -m1 '^user = ' "$DATA/etc/wired.conf" 2>/dev/null | sed 's/^user = //')
CONF_GROUP=$(grep -m1 '^group = ' "$DATA/etc/wired.conf" 2>/dev/null | sed 's/^group = //')
[ -z "$CONF_USER"  ] && CONF_USER="wired"
[ -z "$CONF_GROUP" ] && CONF_GROUP="wired"

# ── Ensure macOS group still exists (re-create if deleted) ───────────────────
if ! dscl . -read "/Groups/${CONF_GROUP}" >/dev/null 2>&1; then
    CONF_GID=$(dscl . -list /Groups PrimaryGroupID | awk '{print $2}' | sort -n | \
        awk 'BEGIN{id=300} $1==id{id++} END{print id}')
    dscl . -create "/Groups/${CONF_GROUP}"
    dscl . -create "/Groups/${CONF_GROUP}" PrimaryGroupID "$CONF_GID"
    dscl . -create "/Groups/${CONF_GROUP}" Password "*"
    dscl . -create "/Groups/${CONF_GROUP}" RealName "Wired Server"
fi
CONF_GID=$(dscl . -read "/Groups/${CONF_GROUP}" PrimaryGroupID 2>/dev/null | awk '{print $2}')

# ── Ensure macOS user still exists (re-create if deleted) ────────────────────
if ! dscl . -read "/Users/${CONF_USER}" >/dev/null 2>&1; then
    CONF_UID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | \
        awk 'BEGIN{id=300} $1==id{id++} END{print id}')
    dscl . -create "/Users/${CONF_USER}"
    dscl . -create "/Users/${CONF_USER}" UniqueID "$CONF_UID"
    dscl . -create "/Users/${CONF_USER}" PrimaryGroupID "$CONF_GID"
    dscl . -create "/Users/${CONF_USER}" UserShell /usr/bin/false
    dscl . -create "/Users/${CONF_USER}" RealName "Wired Server"
    dscl . -create "/Users/${CONF_USER}" NFSHomeDirectory /Library/Wired
    dscl . -create "/Users/${CONF_USER}" Password "*"
    dscl . -create "/Users/${CONF_USER}" IsHidden 1
fi

# ── Re-apply ownership ────────────────────────────────────────────────────────
chown "${CONF_USER}:${CONF_GROUP}" "/Library/Wired" 2>/dev/null || true
chown -R "${CONF_USER}:${CONF_GROUP}" "$DATA" || exit 1
chmod -R 755 "$DATA" || exit 1
find "$DATA" -type f -exec chmod 644 {} \; 2>/dev/null || true
chmod 755 "/Library/Wired/wired" "/Library/Wired/wiredctl" 2>/dev/null || true
# Re-apply ACL so WiredServer.app (running as INSTALL_USER) can read data.
chmod -R +a "user:$INSTALL_USER allow read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,file_inherit,directory_inherit" "$DATA" 2>/dev/null || true

echo "WIREDSERVER_SCRIPT_OK"
exit 0
