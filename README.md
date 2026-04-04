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

## Known Limitations on macOS 15 (Sequoia) and Later

### External Drives Not Supported as Files Directory

Due to macOS TCC (Transparency, Consent & Control) restrictions, the files directory **cannot be located on an external drive** on macOS 15 (Sequoia) and later.

The Wired server runs as a LaunchDaemon under a dedicated system service account. This account operates outside any user session and therefore has no user-level TCC grants. Even granting **Full Disk Access** to `/Library/Wired/wired` in System Settings does not resolve this on macOS 15+ — macOS no longer applies user-granted TCC permissions to binaries running in the system domain.

**Recommendation:** Keep the files directory on the system volume (default: `/Library/Wired/data/files` or a subdirectory of it).

On macOS 12 (Monterey), 13 (Ventura), and 14 (Sonoma), granting Full Disk Access to `/Library/Wired/wired` in System Settings may still allow access to external drives, but this has not been verified on all configurations.

---

### Configuration Profiles (mobileconfig) No Longer Work

On macOS 15 (Sequoia) and later, installing a `.mobileconfig` profile to grant TCC permissions to the Wired server binary no longer works. Apple now requires **supervised MDM enrollment** (e.g. Apple Business Manager or Apple School Manager) for TCC configuration profiles to take effect. Manually installed profiles are silently ignored for TCC purposes.

This means there is currently **no supported way** to grant the Wired server daemon access to external volumes on macOS 15 and later without a supervised MDM setup.

On macOS 12–14, manually installed `.mobileconfig` profiles may still work for granting TCC permissions, but this depends on the specific macOS version and SIP configuration.

---

## Building from Source

### Prerequisites

- Xcode 14 or later
- CocoaPods

### Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/martinmarsian/wired-server-universal-binary.git
   cd wired-server-universal-binary
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

## License

Distributed under the BSD 2-Clause License.

- Copyright © 2003–2009 Axel Andersson
- Copyright © 2011–2026 Rafaël Warnault / Read-Write Software
- macOS compatibility and maintenance by Professor©

See `wired/LICENSE` for the full license text.

## Original Project

Based on [nark/WiredServer](https://github.com/nark/WiredServer) by Rafaël Warnault.
