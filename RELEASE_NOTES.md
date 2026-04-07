# Wired Server — Release Notes

## Version 2.5.6

### What's New

---

### LaunchAgent Mode (User Session)

A new **Launch mode** toggle in the Settings → General tab lets you choose how the Wired server runs:

- **System Daemon** (default) — runs as a macOS LaunchDaemon in the system domain under a dedicated service account (`wired`). Starts automatically at boot, even before any user logs in.
- **User Agent** — runs as a LaunchAgent in your user session. No dedicated service account is required, and the server inherits your full TCC (privacy) permissions — including access to external drives — without any additional configuration.

The toggle is disabled while the server is running. To switch modes: **Stop → select mode → Start**.

The chosen mode is saved as `launchmode = daemon|agent` in `wired.conf` and persists across launches.

---

### macOS 26 (Tahoe) Compatibility

Several reliability fixes for macOS 26 (Darwin 25), where launchd's FSEvents handler triggers automatic service restarts when a plist is written to `LaunchDaemons/` or `LaunchAgents/`:

- **Adaptive port-bindability probe**: After stopping the server, the scripts now wait until the TCP port is actually bindable (using a `socket.bind()` probe, up to 40 seconds) rather than a fixed-duration sleep. This adapts automatically to macOS 26's variable kernel socket-state hold time.
- **FSEvents race fix**: The plist is now written only after the previous service instance has been fully unregistered, preventing a race between launchd's auto-start trigger and the explicit `bootstrap` call.
- **Bootstrap "already loaded" tolerance**: If launchd auto-starts the service via FSEvents between the registration poll and the explicit `bootstrap` call, the script correctly recognises the service as running rather than exiting with an error.

---

### Known Limitation — Second Start Required After Stop with Active Clients

On macOS 26 (Tahoe), if the server is stopped while clients are actively connected, **clicking Start once may show a brief failure state**. Clicking Start a second time starts the server reliably.

**Root cause**: When active SSL connections are present at stop time, the server performs a graceful `SSL_shutdown` on each connection before exiting. This can take up to ~65 seconds. During that time the TCP port remains bound by the process, even after a forced kill. macOS 26's kernel holds the socket state for a variable period after process exit that is not visible to standard tools. The adaptive probe mitigates this but cannot guarantee the port is free within the poll window in all cases.

**Workaround**: Wait a few seconds after Stop, then click Start again. In normal daily operation — where the mode is set once and left unchanged — this situation only arises after an explicit Stop with active connected clients.

---

### System Requirements

| | |
|---|---|
| **macOS** | 10.13 High Sierra or later |
| **Architecture** | Universal (Apple Silicon + Intel) |
| **Privileges** | Administrator password required for Install / Start / Stop |

---

### Upgrading from 2.5.5

No migration required. Sparkle will offer the update automatically if **Check for Updates at Launch** is enabled, or click **Check for Updates…** in the Updates tab.

The default launch mode after upgrade is **System Daemon** — no change in behaviour from 2.5.5.

---

## Version 2.5.5

### What's New

---

### Port Check Fixed

The built-in internet port checker now uses **portchecker.co** as the primary service with hackertarget.com as a fallback. The previous single-service approach was frequently rate-limited and returned false negatives even when the port was reachable.

---

### Auto-Update Checks on Every Launch

Wired Server now checks for available updates immediately at every launch, rather than waiting for Sparkle's built-in 24-hour interval to expire. The check runs silently in the background a few seconds after startup so it does not delay the app's responsiveness.

---

### Updates Tab in Settings

A new **Updates** tab in the Settings window lets you enable or disable automatic update checks and automatic downloads independently.

---

### Window Position and Size Remembered

The Settings window now saves and restores its exact position and size across launches. The window opens exactly where you left it.

---

### Distribution

- **`WiredServer-2.5.5.zip`** — used by Sparkle for in-app auto-update. Both the ZIP and the app inside are notarized by Apple.
- **`WiredServer-2.5.5.dmg`** — for manual download and installation. Notarized and stapled (works offline without a Gatekeeper warning).

---

### System Requirements

| | |
|---|---|
| **macOS** | 10.13 High Sierra or later |
| **Architecture** | Universal (Apple Silicon + Intel) |
| **Privileges** | Administrator password required for Install / Start / Stop |

---

### Upgrading from 2.5.4

No migration required. Sparkle will offer the update automatically if **Check for Updates at Launch** is enabled, or click **Check for Updates…** in the Updates tab.

---

## Version 2.5.4

### What's New

---

### Automatic Updates via Sparkle

Wired Server now checks for updates automatically at launch and notifies you when a new version is available. Updates can be installed directly from within the app — no manual download required.

- Update checks use a signed `appcast.xml` feed hosted on GitHub
- All releases are signed with a DSA key, verified by Sparkle before installing
- Automatic background checks can be configured in the app preferences

---

### Distributed as Notarized DMG

Starting with this release, Wired Server is distributed as a **signed and notarized DMG** image. The app is:

- Code-signed with a **Developer ID Application** certificate
- Notarized by Apple — Gatekeeper will not block the app on any supported macOS version
- Stapled — the notarization ticket is embedded in the DMG, so it works offline

---

### Rebuild Index Reliability

The **Rebuild Index** function now runs with the correct user session context, ensuring that file system access (TCC permissions) is honoured correctly on macOS 13 and later. The index rebuild is launched via `launchctl asuser` so it inherits the installing user's Full Disk Access grants rather than running in the restricted system context.

---

### Script Hardening

Install, Update, Start, and Stop scripts have received several reliability and security improvements:

- `CONF_USER` and `CONF_GROUP` values read from `wired.conf` are now sanitised before being passed to `dscl` and `chown`, preventing injection of unexpected arguments
- The recursive `chown` on the files directory is skipped if the path resolves outside `/Library/Wired/data/` (e.g. an external volume), avoiding unintended permission changes
- The Update button correctly detects whether a newer binary is available and performs a clean stop → update → restart cycle

---

### System Requirements

| | |
|---|---|
| **macOS** | 12 Monterey or later |
| **Architecture** | Universal (Apple Silicon + Intel) |
| **Privileges** | Administrator password required for Install / Start / Stop |

---

### Upgrading from 2.5.3

No migration is required. Open the app and click **Start** — the service will continue running with your existing configuration.

---

## Version 2.5.3

### What's New

---

### System Service Architecture

Wired Server now runs as a **macOS LaunchDaemon** — a true system service — instead of a per-user LaunchAgent. This means:

- The server starts automatically at **system boot**, even before any user logs in
- The server keeps running regardless of which user is logged in or whether anyone is logged in at all
- The server is more reliable and resilient on macOS 12 (Monterey) and later

---

### Dedicated Service Account

On first install or start, Wired Server automatically creates a hidden macOS system account that runs the server process. This account is:

- **Invisible** — it does not appear in the login window or System Settings → Users & Groups
- **Restricted** — it cannot log in interactively
- **Configurable** — the account name is taken from the `user =` and `group =` settings in `wired.conf` (default: `wired`)

If you change `user =` or `group =` in `wired.conf` and click **Start**, the new account is created automatically.

---

### New Data Directory

Server data has moved from `~/Library/Wired/` to a system-wide location:

| File | Path |
|---|---|
| Configuration | `/Library/Wired/data/etc/wired.conf` |
| Log | `/Library/Wired/data/wired.log` |
| Database | `/Library/Wired/data/database.sqlite3` |
| PID / Status | `/Library/Wired/data/wired.pid`, `/Library/Wired/data/wired.status` |
| Server binary | `/Library/Wired/wired` |

**Existing installations are migrated automatically** the first time you click Start after updating.

---

### Files Directory Permissions

The files directory configured in `wired.conf` (setting `files =`) now automatically receives the correct ownership and permissions every time the server starts:

- **Default** (`files = files`): resolves to `/Library/Wired/data/files`
- **Custom absolute path** (e.g. `files = /Volumes/MyDrive/WiredFiles`): the directory on your external drive or custom location is used directly

The directory is created automatically if it does not exist yet (useful on first start). If you change `user =`, `group =`, or `files =` in `wired.conf`, the permissions are updated on the next Start — no manual `chown` required.

---

### Simplified Authorization

Administrative operations (Install, Start, Stop, Reindex) now require only **one password prompt per session**. Authorization is cached for five minutes — clicking Stop and then Start immediately afterwards does not ask for your password again.

---

### Status Bar Helper

The **Wired Server Helper** menu bar item now correctly reads the server status from the system data directory and displays live statistics (uptime, connected users, traffic) when the server is running.

---

### App Window Behavior

The Wired Server window now reliably comes to the foreground when the app is launched or reopened (e.g. via the Helper's "Open Wired Server…" menu item or by clicking the app icon in the Dock).

---

### System Requirements

| | |
|---|---|
| **macOS** | 12 Monterey or later |
| **Architecture** | Universal (Apple Silicon + Intel) |
| **Privileges** | Administrator password required for Install / Start / Stop |

---

### Upgrade from Earlier Versions

1. Open **Wired Server.app**
2. Click **Update** (downloads and installs the current server binary)
3. Click **Start**

The app will automatically migrate data from the old location, create the system service account, set correct permissions, and start the server. No manual steps are required.

---

### Known Limitations

#### External Drives Not Supported as Files Directory (macOS 15 and later)

Due to macOS TCC (Transparency, Consent & Control) restrictions, the files directory **cannot be located on an external drive** on macOS 15 (Sequoia) and later, including macOS 26 (Tahoe).

The Wired server runs as a LaunchDaemon under a dedicated system service account. This account operates outside any user session and therefore has no user-level TCC grants. **Granting Full Disk Access to `/Library/Wired/wired` in System Settings does not resolve this on macOS 15 and later** — macOS no longer applies user-granted TCC permissions to binaries running in the system domain.

On macOS 12 (Monterey), 13 (Ventura), and 14 (Sonoma), granting Full Disk Access to `/Library/Wired/wired` in System Settings may still allow access to external drives.

**Recommendation:** Keep the files directory on the system volume, e.g. `/Library/Wired/data/files` (the default).

#### Using the Configuration Profile on macOS 12–14 (Optional)

For users on macOS 12 (Monterey), 13 (Ventura), or 14 (Sonoma) who need to serve files from an external drive, a configuration profile (`WiredServerTCC.mobileconfig`) is included inside the app bundle. It grants Full Disk Access to the Wired Server daemon automatically, without navigating System Settings manually.

**Where to find it:**

1. In Finder, locate **Wired Server.app** (e.g. in `/Applications`)
2. Right-click → **Show Package Contents**
3. Navigate to **`Contents/Resources/`**
4. The file is named **`WiredServerTCC.mobileconfig`**

**How to install it:**

1. Double-click `WiredServerTCC.mobileconfig` — macOS will open System Settings automatically
2. Go to **System Settings → Privacy & Security → Profiles**
3. The profile **"Wired Server – Privacy Policy"** appears under *Downloaded Profiles* — click **Install…**
4. Enter your administrator password to confirm
5. Click **Stop**, then **Start** in Wired Server to apply the new permissions

The profile can be removed at any time via **System Settings → Privacy & Security → Profiles**.

---

#### Configuration Profiles (mobileconfig) No Longer Work (macOS 15 and later)

Installing a `.mobileconfig` profile to grant TCC permissions to the Wired server binary **no longer works on macOS 15 (Sequoia) and later**, including macOS 26 (Tahoe). Apple now requires supervised MDM enrollment (Apple Business Manager / Apple School Manager) for TCC configuration profiles to take effect. Manually installed profiles are silently ignored for TCC purposes.

On macOS 12–14, manually installed `.mobileconfig` profiles may still work for granting TCC permissions (see above).

---

*Copyright © 2003–2009 Axel Andersson. Copyright © 2011–2025 Rafaël Warnault. Distributed under the BSD license.*
