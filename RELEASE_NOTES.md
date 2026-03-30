# Wired Server — Release Notes

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

- **External volumes (TCC)**: If your files directory is on an external volume, macOS may restrict the server's access due to Transparency, Consent & Control (TCC). If the server cannot list files on the volume, grant **Full Disk Access** to `/Library/Wired/wired` in **System Settings → Privacy & Security → Full Disk Access**.

---

*Copyright © 2003–2009 Axel Andersson. Copyright © 2011–2025 Rafaël Warnault. Distributed under the BSD license.*
