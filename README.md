# Wired Server 2.5.3 — Universal Binary

A macOS application for running a [Wired 2.0](https://github.com/nark/WiredServer) file server and chat server.
This fork updates the original project for modern macOS (12 Monterey and later) with Apple Silicon support, a system service architecture, and a Universal Binary build.

## What's New in This Fork

- **Universal Binary** — runs natively on Apple Silicon (arm64) and Intel (x86_64)
- **LaunchDaemon** — runs as a true system service at boot, independent of any logged-in user
- **Dedicated service account** — the server process runs as a hidden system user (no interactive login)
- **System data directory** — server data stored in `/Library/Wired/data/` (no longer in `~/Library`)
- **Automatic migration** — existing installations are migrated on first Start
- **SHA-256 / SHA-512 support** — updated crypto for modern clients
- **OpenSSL 3.x compatibility** — updated for current OpenSSL API

## System Requirements

| | |
|---|---|
| **macOS** | 12 Monterey or later |
| **Architecture** | Universal (Apple Silicon + Intel) |
| **Privileges** | Administrator password required for Install / Start / Stop |

## Data Directory

| File | Path |
|---|---|
| Configuration | `/Library/Wired/data/etc/wired.conf` |
| Log | `/Library/Wired/data/wired.log` |
| Database | `/Library/Wired/data/database.sqlite3` |
| Server binary | `/Library/Wired/wired` |

## Building from Source

### Prerequisites

- Xcode 14 or later
- CocoaPods

### Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/joergmaertin/Wired-Server-2.5.3-Universal-Binary.git
   cd Wired-Server-2.5.3-Universal-Binary
   ```

2. Install CocoaPods dependencies:
   ```bash
   pod install
   ```

3. Open the workspace in Xcode:
   ```bash
   open WiredServer.xcworkspace
   ```

4. Select the **Wired Server** scheme and build.

## External Volume Access (TCC)

If your files directory is on an external volume, grant **Full Disk Access** to `/Library/Wired/wired` in:

```
System Settings → Privacy & Security → Full Disk Access
```

## License

Distributed under the BSD 2-Clause License.

- Copyright © 2003–2009 Axel Andersson
- Copyright © 2011–2026 Rafaël Warnault / Read-Write Software
- macOS compatibility and maintenance by Professor©

See `wired/LICENSE` for the full license text.

## Original Project

Based on [nark/WiredServer](https://github.com/nark/WiredServer) by Rafaël Warnault.
