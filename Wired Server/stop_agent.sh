#!/bin/sh
exec 2>&1
set -x

LIBRARY="$1"

LABEL="fr.read-write.WiredServer"

INSTALL_USER=$(echo "$LIBRARY" | sed -E 's,/Users/([^/]+)/.*,\1,')
[ -z "$INSTALL_USER" ] && INSTALL_USER="$USER"
INSTALL_UID=$(id -u "$INSTALL_USER" 2>/dev/null)

PLIST="/Users/${INSTALL_USER}/Library/LaunchAgents/${LABEL}.plist"

# ── Stop the LaunchAgent ───────────────────────────────────────────────────────
if [ -n "$INSTALL_UID" ]; then
    /bin/launchctl disable "gui/${INSTALL_UID}/${LABEL}" 2>/dev/null || true
    /bin/launchctl bootout "gui/${INSTALL_UID}/${LABEL}" 2>/dev/null || true
fi
rm -f "$PLIST" 2>/dev/null || true

# ── Wait for wired to fully exit ──────────────────────────────────────────────
# bootout sends SIGTERM but returns immediately; wired may take many seconds to
# exit when it has active SSL connections.  Wait here (SIGKILL fallback) so the
# port is guaranteed free before we return SCRIPT_OK — mode-switching requires
# the port to be free before the next start script runs.
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
_wport=$(grep -m1 '^port ' /Library/Wired/data/etc/wired.conf 2>/dev/null \
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

echo "WIREDSERVER_SCRIPT_OK"
exit 0
