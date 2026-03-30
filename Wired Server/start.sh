#!/bin/sh
exec 2>&1
set -x

LIBRARY="$1"

LABEL="fr.read-write.WiredServer"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
DATA="/Library/Wired/data"
OLD_DATA="$LIBRARY/Wired"

INSTALL_USER=$(echo "$LIBRARY" | sed -E 's,/Users/([^/]+)/.*,\1,')
[ -z "$INSTALL_USER" ] && INSTALL_USER="$USER"
INSTALL_UID=$(id -u "$INSTALL_USER" 2>/dev/null)

# ── Migrate from old location if needed ───────────────────────────────────────
# Handles the upgrade case where Start is clicked without first clicking
# Install/Update after the data-directory move was introduced.
if [ ! -f "$DATA/etc/wired.conf" ] && [ -f "$OLD_DATA/etc/wired.conf" ]; then
    install -m 775 -d "$DATA"       2>/dev/null
    install -m 755 -d "$DATA/etc"   2>/dev/null
    cp "$OLD_DATA/etc/wired.conf" "$DATA/etc/wired.conf"
    for db in database.sqlite3 database.sqlite3-wal database.sqlite3-shm database.sqlite3.bak; do
        [ -f "$OLD_DATA/$db" ] && cp "$OLD_DATA/$db" "$DATA/$db"
    done
    [ -f "$OLD_DATA/banner.png" ] && cp "$OLD_DATA/banner.png" "$DATA/banner.png"
    touch "$DATA/wired.log"
    sed -E -i '' "s,^banner = $OLD_DATA/,banner = $DATA/," "$DATA/etc/wired.conf" 2>/dev/null || true
fi

# ── Read service user/group from wired.conf ───────────────────────────────────
CONF_USER=$(grep -m1 '^user = ' "$DATA/etc/wired.conf" 2>/dev/null | sed 's/^user = //')
CONF_GROUP=$(grep -m1 '^group = ' "$DATA/etc/wired.conf" 2>/dev/null | sed 's/^group = //')
[ -z "$CONF_USER"  ] && CONF_USER="wired"
[ -z "$CONF_GROUP" ] && CONF_GROUP="wired"

# ── Ensure macOS group exists ─────────────────────────────────────────────────
if ! dscl . -read "/Groups/${CONF_GROUP}" >/dev/null 2>&1; then
    CONF_GID=$(dscl . -list /Groups PrimaryGroupID | awk '{print $2}' | sort -n | \
        awk 'BEGIN{id=300} $1==id{id++} END{print id}')
    dscl . -create "/Groups/${CONF_GROUP}"
    dscl . -create "/Groups/${CONF_GROUP}" PrimaryGroupID "$CONF_GID"
    dscl . -create "/Groups/${CONF_GROUP}" Password "*"
    dscl . -create "/Groups/${CONF_GROUP}" RealName "Wired Server"
fi
CONF_GID=$(dscl . -read "/Groups/${CONF_GROUP}" PrimaryGroupID 2>/dev/null | awk '{print $2}')

# ── Ensure macOS user exists ──────────────────────────────────────────────────
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

# ── Re-apply ownership on start ───────────────────────────────────────────────
if [ -f "$DATA/etc/wired.conf" ]; then
    chown "${CONF_USER}:${CONF_GROUP}" "/Library/Wired" 2>/dev/null || true
    chown -R "${CONF_USER}:${CONF_GROUP}" "$DATA" 2>/dev/null || true
    chmod -R 755 "$DATA" 2>/dev/null || true
    find "$DATA" -type f -exec chmod 644 {} \; 2>/dev/null || true
    chmod 755 "/Library/Wired/wired" "/Library/Wired/wiredctl" 2>/dev/null || true
    # Re-apply ACL so WiredServer.app (running as INSTALL_USER) can read data.
    chmod -R +a "user:$INSTALL_USER allow read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,file_inherit,directory_inherit" "$DATA" 2>/dev/null || true

    # ── Regenerate plist so it stays in sync with the current config ──────────
    cat <<EOF >"$PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Disabled</key>
	<false/>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>UserName</key>
	<string>${CONF_USER}</string>
	<key>KeepAlive</key>
	<true/>
	<key>OnDemand</key>
	<false/>
	<key>ProgramArguments</key>
	<array>
		<string>/Library/Wired/wired</string>
		<string>-x</string>
		<string>-d</string>
		<string>${DATA}</string>
		<string>-l</string>
		<string>-L</string>
		<string>${DATA}/wired.log</string>
		<string>-i</string>
		<string>1000</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>WorkingDirectory</key>
	<string>${DATA}</string>
</dict>
</plist>
EOF
    chmod 644 "$PLIST"
fi

# ── Stop old LaunchAgent if still running (migration from gui domain) ─────────
if [ -n "$INSTALL_UID" ]; then
    /bin/launchctl bootout "gui/${INSTALL_UID}/${LABEL}" 2>/dev/null || true
fi
rm -f "/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null || true

# 1. Enable the daemon so Disabled=false takes effect.
/bin/launchctl enable "system/${LABEL}" 2>&1

# 2. Bootout if currently registered so the updated plist takes effect.
if /bin/launchctl print "system/${LABEL}" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/${LABEL}" 2>&1 || true
fi

# 3. Bootstrap the daemon into the system domain.
/bin/launchctl bootstrap system "${PLIST}" 2>&1 || exit 1

# 4. Kickstart; -k kills any existing instance first.
/bin/launchctl kickstart -k "system/${LABEL}" 2>&1 || exit 1

# ── Pre-build the file index in the logged-in user's TCC session ─────────────
# The LaunchDaemon runs in the system context where TCC may deny opendir() on
# external volumes.  Running rebuild-index.sh via "launchctl asuser <uid>"
# puts it in the logged-in user's GUI session where removable-volume TCC
# grants are honoured.  The daemon finds the pre-built index on startup and
# skips its own (TCC-blocked) enumeration.
if [ -n "$INSTALL_UID" ]; then
    REBUILD="/Library/Wired/rebuild-index.sh"
    [ -f "$REBUILD" ] && \
        /bin/launchctl asuser "$INSTALL_UID" /bin/sh "$REBUILD" 2>/dev/null || true
fi

echo "WIREDSERVER_SCRIPT_OK"
exit 0
