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
# Sanitize: allow only alphanumeric, underscore, hyphen.
# Prevents XML plist injection and dscl/chown misuse if wired.conf is modified.
CONF_USER=$(echo "$CONF_USER"   | tr -cd 'a-zA-Z0-9_-')
CONF_GROUP=$(echo "$CONF_GROUP" | tr -cd 'a-zA-Z0-9_-')
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

# ── Disable BEFORE any file writes ───────────────────────────────────────────
# On macOS 26, launchd's FSEvents handler for /Library/LaunchDaemons/ fires the
# moment the plist is written.  If the service is still ENABLED at that point,
# launchd auto-restarts wired — racing with our kill/bootout sequence below.
# Disabling first suppresses that FSEvents-triggered restart.
/bin/launchctl disable "system/${LABEL}" 2>/dev/null || true

# ── Re-apply ownership on start ───────────────────────────────────────────────
if [ -f "$DATA/etc/wired.conf" ]; then
    chown "${CONF_USER}:${CONF_GROUP}" "/Library/Wired" 2>/dev/null || true
    chown -R "${CONF_USER}:${CONF_GROUP}" "$DATA" 2>/dev/null || true
    chmod -R 755 "$DATA" 2>/dev/null || true
    find "$DATA" -type f -exec chmod 644 {} \; 2>/dev/null || true
    chmod 755 "/Library/Wired/wired" "/Library/Wired/wiredctl" 2>/dev/null || true

    # ── Fix ownership of the files directory ──────────────────────────────────
    # "files =" can be a relative path (resolved from $DATA, the daemon's
    # WorkingDirectory) or an absolute path chosen by the user.
    CONF_FILES=$(grep -m1 '^files = ' "$DATA/etc/wired.conf" 2>/dev/null | sed 's/^files = //')
    if [ -n "$CONF_FILES" ]; then
        case "$CONF_FILES" in
            /*) FILES_PATH="$CONF_FILES" ;;
            *)  FILES_PATH="$DATA/$CONF_FILES" ;;
        esac
        # Guard: restrict chown -R to safe user-data directories.
        # Prevents accidental ownership changes on system paths if
        # files= is set to / or a sensitive location in wired.conf.
        case "$FILES_PATH" in
            /Users/*|/Volumes/*|/Library/Wired/*)
                mkdir -p "$FILES_PATH" 2>/dev/null || true
                chown -R "${CONF_USER}:${CONF_GROUP}" "$FILES_PATH" 2>/dev/null || true
                ;;
            *)
                echo "WARNING: files path '$FILES_PATH' outside allowed dirs; skipping chown" >&2
                ;;
        esac
    fi
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

# ── Stop old LaunchAgent if still running (switching from agent → daemon) ─────
if [ -n "$INSTALL_UID" ]; then
    /bin/launchctl disable "gui/${INSTALL_UID}/${LABEL}" 2>/dev/null || true
    /bin/launchctl bootout "gui/${INSTALL_UID}/${LABEL}" 2>/dev/null || true
fi
rm -f "/Users/${INSTALL_USER}/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null || true
# Send SIGTERM; wait up to 10 s for graceful exit (pgrep catches any
# KeepAlive-respawned instance too).  Fall back to SIGKILL so the port is
# guaranteed free even when SSL_shutdown is slow (observed: up to 65 s with
# connected clients).
killall wired 2>/dev/null || true
for _i in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x wired >/dev/null 2>&1 || break
    sleep 1
done
if pgrep -x wired >/dev/null 2>&1; then
    killall -KILL wired 2>/dev/null || true
fi

# 1. Bootout if still registered (belt+suspenders after disable+kill above).
if /bin/launchctl print "system/${LABEL}" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/${LABEL}" 2>&1 || true
fi

# 1b. Wait for wired to fully exit (SIGKILL if still alive after 10 s).
for _i in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x wired >/dev/null 2>&1 || break
    sleep 1
done
if pgrep -x wired >/dev/null 2>&1; then
    killall -KILL wired 2>/dev/null || true
fi
# ── Wait until the wired port is actually bindable ────────────────────────────
# macOS 26 holds kernel TCP socket state for a variable time (up to ~35 s)
# after process exit, invisible to lsof.  Probe with SO_REUSEADDR bind() so
# we wait exactly as long as needed and no longer.
_wport=$(grep -m1 '^port ' "${DATA}/etc/wired.conf" 2>/dev/null \
    | sed -E 's/^port[[:space:]]*=[[:space:]]*//' | tr -d '[:space:]')
[ -z "$_wport" ] && _wport=4871
for _pw in $(seq 1 40); do
    python3 -c "
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(('', int(sys.argv[1])))
    s.close()
    sys.exit(0)
except OSError:
    pass
s.close()
sys.exit(1)" "$_wport" 2>/dev/null && break
    sleep 1
done

# 2. Enable after bootout: service is now unregistered.  Must come before
#    bootstrap so launchd doesn't reject the bootstrap of a disabled service.
#    On macOS 26, enable can trigger launchd to auto-start wired asynchronously
#    (FSEvents on /Library/LaunchDaemons/).  We wait up to 2 s for that to
#    happen; if the service self-registers we skip the explicit bootstrap
#    entirely, avoiding an "already loaded" conflict.
# 3. Remove stale pid BEFORE enable so auto-started wired writes a fresh pid.
rm -f "${DATA}/wired.pid" 2>/dev/null || true

# 4. Enable after bootout (must come before bootstrap so launchd accepts it).
#    On macOS 26, enable can trigger launchd to auto-start wired asynchronously
#    via FSEvents on /Library/LaunchDaemons/.  Poll for up to 3 s so we catch
#    fast auto-starts early and only fall back to explicit bootstrap when launchd
#    definitely won't self-register — avoids the EADDRINUSE race between an
#    auto-start and an explicit bootstrap call.
/bin/launchctl enable "system/${LABEL}" 2>&1 || true

for _i in 1 2 3 4 5 6 7 8 9 10; do
    /bin/launchctl print "system/${LABEL}" >/dev/null 2>&1 && break
    sleep 1
done

# 5. Bootstrap only if launchd did not self-register within the poll window.
if ! /bin/launchctl print "system/${LABEL}" >/dev/null 2>&1; then
    # bootstrap may fail with "already loaded" if FSEvents auto-started wired
    # between our poll and this call; in that case the service IS registered,
    # so re-check before treating it as a real error.
    /bin/launchctl bootstrap system "${PLIST}" 2>&1 || \
        /bin/launchctl print "system/${LABEL}" >/dev/null 2>&1 || exit 1
fi

# 5. Wait until wired has written its pid file, which it does only AFTER
#    wd_server_listen() succeeds (i.e. after bind + listen).  This gives
#    the caller a reliable signal that the server is actually accepting
#    connections before we return WIREDSERVER_SCRIPT_OK.
for _i in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "${DATA}/wired.pid" ] && break
    sleep 1
done

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
