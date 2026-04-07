#!/bin/sh
exec 2>&1
set -x

LIBRARY="$1"

LABEL="fr.read-write.WiredServer"
DATA="/Library/Wired/data"
OLD_DATA="$LIBRARY/Wired"

INSTALL_USER=$(echo "$LIBRARY" | sed -E 's,/Users/([^/]+)/.*,\1,')
[ -z "$INSTALL_USER" ] && INSTALL_USER="$USER"
INSTALL_UID=$(id -u "$INSTALL_USER" 2>/dev/null)

if [ -z "$INSTALL_UID" ]; then
    echo "ERROR: could not determine install user UID"
    exit 1
fi

AGENT_PLIST_DIR="/Users/${INSTALL_USER}/Library/LaunchAgents"
PLIST="${AGENT_PLIST_DIR}/${LABEL}.plist"

# ── Migrate from old location if needed ───────────────────────────────────────
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

# ── Disable BOTH service variants BEFORE killing wired ───────────────────────
# With KeepAlive=true, launchd restarts wired the instant killall kills it.
# Disabling first suppresses that restart so the port is truly free before we
# call bootstrap.
/bin/launchctl disable "gui/${INSTALL_UID}/${LABEL}" 2>/dev/null || true

# ── Also stop any running LaunchDaemon (switching from daemon → agent) ────────
/bin/launchctl disable "system/${LABEL}" 2>/dev/null || true
/bin/launchctl bootout "system/${LABEL}" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/${LABEL}.plist" 2>/dev/null || true
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

# ── Take ownership of data dir (was owned by "wired" service user in daemon mode)
if [ -f "$DATA/etc/wired.conf" ]; then
    chown -R "$INSTALL_USER" "$DATA" 2>/dev/null || true
    chmod -R 755 "$DATA" 2>/dev/null || true
    find "$DATA" -type f -exec chmod 644 {} \; 2>/dev/null || true
    chmod 755 "/Library/Wired/wired" "/Library/Wired/wiredctl" 2>/dev/null || true
fi

# ── Ensure LaunchAgents directory exists ──────────────────────────────────────
mkdir -p "$AGENT_PLIST_DIR"
chown "$INSTALL_USER" "$AGENT_PLIST_DIR" 2>/dev/null || true

# ── Remove any old agent registration and stale pid BEFORE writing new plist ──
# On macOS 26 writing the plist triggers an FSEvents auto-start immediately.
# Bootout here ensures no launchd-managed wired is killed after that start.
/bin/launchctl bootout "gui/${INSTALL_UID}/${LABEL}" 2>/dev/null || true
rm -f "${DATA}/wired.pid" 2>/dev/null || true

# ── Generate LaunchAgent plist (no UserName key → runs as the gui session owner)
cat <<EOF >"$PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Disabled</key>
	<false/>
	<key>Label</key>
	<string>${LABEL}</string>
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
chown "$INSTALL_USER" "$PLIST"
chmod 644 "$PLIST"

# ── Enable + start via launchd ────────────────────────────────────────────────
# On macOS 26 the plist write above already triggers an FSEvents auto-start;
# enable here makes that start durable (KeepAlive/RunAtLoad persist across
# reboots).  The poll below detects the auto-start and skips bootstrap.
/bin/launchctl enable "gui/${INSTALL_UID}/${LABEL}" 2>&1 || true

for _i in 1 2 3 4 5 6 7 8 9 10; do
    /bin/launchctl print "gui/${INSTALL_UID}/${LABEL}" >/dev/null 2>&1 && break
    sleep 1
done

if ! /bin/launchctl print "gui/${INSTALL_UID}/${LABEL}" >/dev/null 2>&1; then
    # bootstrap may fail with "already loaded" if FSEvents auto-started wired
    # between our poll and this call; in that case the service IS registered,
    # so re-check before treating it as a real error.
    /bin/launchctl bootstrap "gui/${INSTALL_UID}" "${PLIST}" 2>&1 || \
        /bin/launchctl print "gui/${INSTALL_UID}/${LABEL}" >/dev/null 2>&1 || exit 1
fi

# Wait until wired has written its pid file (done only after bind+listen).
for _i in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "${DATA}/wired.pid" ] && break
    sleep 1
done

# ── Pre-build the file index in the logged-in user's TCC session ──────────────
if [ -n "$INSTALL_UID" ]; then
    REBUILD="/Library/Wired/rebuild-index.sh"
    [ -f "$REBUILD" ] && \
        /bin/launchctl asuser "$INSTALL_UID" /bin/sh "$REBUILD" 2>/dev/null || true
fi

echo "WIREDSERVER_SCRIPT_OK"
exit 0
