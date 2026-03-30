#!/bin/sh
exec 2>&1
set -x

SOURCE="$1"
LIBRARY="$2"
MIGRATE="$3"

# Derive the logged-in username from the LIBRARY path (/Users/<user>/Library).
# $USER is "root" when running via AuthorizationExecuteWithPrivileges.
INSTALL_USER=$(echo "$LIBRARY" | sed -E 's,/Users/([^/]+)/.*,\1,')
[ -z "$INSTALL_USER" ] && INSTALL_USER="$USER"

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA="/Library/Wired/data"
OLD_DATA="$LIBRARY/Wired"

LABEL="fr.read-write.WiredServer"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"

# ── System binaries ───────────────────────────────────────────────────────────
install -m 755 -d "/Library/Wired" || exit 1
install -m 755 "$SOURCE/Wired/wired"            "/Library/Wired" || exit 1
install -m 755 "$SOURCE/Wired/wiredctl"         "/Library/Wired" || exit 1
install -m 755 "$SOURCE/Wired/rebuild-index.sh" "/Library/Wired" 2>/dev/null || true

# ── Data directory ─────────────────────────────────────────────────────────────
install -m 775 -d "$DATA"       || exit 1
install -m 755 -d "$DATA/etc"   || exit 1

# ── Migrate from old location (~/Library/Wired → /Library/Wired/data) ─────────
if [ -d "$OLD_DATA" ] && [ ! -f "$DATA/etc/wired.conf" ]; then
    [ -f "$OLD_DATA/etc/wired.conf" ] && \
        cp "$OLD_DATA/etc/wired.conf" "$DATA/etc/wired.conf"
    for db in database.sqlite3 database.sqlite3-wal database.sqlite3-shm database.sqlite3.bak; do
        [ -f "$OLD_DATA/$db" ] && cp "$OLD_DATA/$db" "$DATA/$db"
    done
    [ -f "$OLD_DATA/banner.png" ] && cp "$OLD_DATA/banner.png" "$DATA/banner.png"
fi

# ── Install default files if not already present ──────────────────────────────
if [ ! -f "$DATA/banner.png" ]; then
    install -m 644 "$SOURCE/Wired/banner.png" "$DATA" || exit 1
fi

# Copy wired.conf from bundle only on first install (preserve on update).
if [ ! -f "$DATA/etc/wired.conf" ]; then
    install -m 644 "$SOURCE/Wired/etc/wired.conf" "$DATA/etc" || exit 1
fi

install -m 644 "$SOURCE/Wired/etc/wired.conf" "$DATA/etc/wired.conf.dist" || exit 1
install -m 644 "$SOURCE/Wired/wired.xml"       "$DATA"                     || exit 1
cp -r "$SOURCE/Wired/files" "$DATA/files" || exit 1

echo "-L $DATA/wired.log -i 1000" > "$DATA/etc/wired.flags"
touch "$DATA/wired.log"

# ── Patch wired.conf paths ─────────────────────────────────────────────────────
sed -E -i '' "s,^#?banner = .+\$,banner = $DATA/banner.png," "$DATA/etc/wired.conf" || exit 1
sed -E -i '' 's,^#?port = 2000$,port = 4871,' "$DATA/etc/wired.conf" || exit 1
# Set files to the installing user's Public folder only on first install
# (i.e. only when the placeholder value "files" is still present).
sed -E -i '' "s,^#?files = files\$,files = /Users/$INSTALL_USER/Public," "$DATA/etc/wired.conf" || exit 1
# Correct any residual banner path pointing to the old ~/Library/Wired location.
sed -E -i '' "s,^banner = $OLD_DATA/,banner = $DATA/," "$DATA/etc/wired.conf" 2>/dev/null || true

# ── Read service user/group from wired.conf ───────────────────────────────────
# wired.conf is the source of truth.  The matching macOS account is created
# below so launchd can switch to it via UserName in the LaunchDaemon plist.
CONF_USER=$(grep -m1 '^user = ' "$DATA/etc/wired.conf" 2>/dev/null | sed 's/^user = //')
CONF_GROUP=$(grep -m1 '^group = ' "$DATA/etc/wired.conf" 2>/dev/null | sed 's/^group = //')
[ -z "$CONF_USER"  ] && CONF_USER="wired"
[ -z "$CONF_GROUP" ] && CONF_GROUP="wired"

# ── Create macOS group if not already present ─────────────────────────────────
if ! dscl . -read "/Groups/${CONF_GROUP}" >/dev/null 2>&1; then
    CONF_GID=$(dscl . -list /Groups PrimaryGroupID | awk '{print $2}' | sort -n | \
        awk 'BEGIN{id=300} $1==id{id++} END{print id}')
    dscl . -create "/Groups/${CONF_GROUP}"
    dscl . -create "/Groups/${CONF_GROUP}" PrimaryGroupID "$CONF_GID"
    dscl . -create "/Groups/${CONF_GROUP}" Password "*"
    dscl . -create "/Groups/${CONF_GROUP}" RealName "Wired Server"
fi
CONF_GID=$(dscl . -read "/Groups/${CONF_GROUP}" PrimaryGroupID 2>/dev/null | awk '{print $2}')

# ── Create macOS user if not already present ──────────────────────────────────
# Home directory is /Library/Wired — the same parent that holds the binary and
# the data directory.  UserShell=/usr/bin/false and IsHidden=1 prevent login.
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
CONF_UID=$(dscl . -read "/Users/${CONF_USER}" UniqueID 2>/dev/null | awk '{print $2}')

# ── Set ownership ─────────────────────────────────────────────────────────────
# /Library/Wired is the service user's home; it owns everything beneath it so
# wired can write WAL/SHM, PID, and log files without any privilege dance.
chown "${CONF_USER}:${CONF_GROUP}" "/Library/Wired" 2>/dev/null || true
chown -R "${CONF_USER}:${CONF_GROUP}" "$DATA" || exit 1
chmod -R 755 "$DATA" || exit 1
find "$DATA" -type f -exec chmod 644 {} \; 2>/dev/null || true
chmod 755 "/Library/Wired/wired" "/Library/Wired/wiredctl" 2>/dev/null || true

# Grant the installing user ACL access so WiredServer.app (running as
# INSTALL_USER) can read logs, status files, and the config without root.
chmod -R +a "user:$INSTALL_USER allow read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,file_inherit,directory_inherit" "$DATA" 2>/dev/null || true

# ── Best-effort Full Disk Access grant (system TCC.db) ────────────────────────
# On macOS 15 with SIP enabled this is often rejected for unsigned binaries.
# The user can grant Full Disk Access permanently via:
#   System Settings → Privacy & Security → Full Disk Access → add /Library/Wired/wired
TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
if [ -f "$TCC_DB" ]; then
    sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access VALUES('kTCCServiceSystemPolicyAllFiles','/Library/Wired/wired',1,2,4,1,NULL,NULL,0,'UNUSED',NULL,0,$(date +%s));" 2>/dev/null || true
fi

# ── Stop and remove old LaunchAgent if present (migration from gui domain) ────
INSTALL_UID=$(id -u "$INSTALL_USER" 2>/dev/null || echo "")
if [ -n "$INSTALL_UID" ]; then
    /bin/launchctl bootout "gui/${INSTALL_UID}/${LABEL}" 2>/dev/null || true
fi
rm -f "/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null || true

# ── Stop old LaunchDaemon if registered (so the new plist takes effect) ────────
/bin/launchctl bootout "system/${LABEL}" 2>/dev/null || true

# ── LaunchDaemon plist ────────────────────────────────────────────────────────
# launchd switches to the service user (UserName) before exec.
# wired.conf user/group match the running UID/GID → wi_switch_user() is a no-op.
# WorkingDirectory = /Library/Wired/data (not TCC-protected → no EX_CONFIG 78).
install -m 755 -d "/Library/LaunchDaemons" || exit 1

# Preserve the Disabled state from a previous installation if present.
if [ "$(defaults read "$PLIST" Disabled 2>/dev/null || echo 1)" = "1" ]; then
    DISABLED="true"
else
    DISABLED="false"
fi

cat <<EOF >"$PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Disabled</key>
	<${DISABLED}/>
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

echo "WIREDSERVER_SCRIPT_OK"
exit 0
