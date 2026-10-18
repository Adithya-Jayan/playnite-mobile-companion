# Playnite Mobile Companion & Delta Sync

[![Playnite](https://img.shields.io/badge/Playnite-Repository-orange.svg)](https://github.com/JosefNemec/Playnite)
[![Playnite Website](https://img.shields.io/badge/Website-playnite.link-blue.svg)](https://playnite.link/)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android-blue.svg)](https://flutter.dev/)
[![C# / .NET](https://img.shields.io/badge/.NET%20Framework-4.6.2-purple.svg)](https://dotnet.microsoft.com/)
[![Flutter](https://img.shields.io/badge/Flutter-3.22+-02569B.svg)](https://flutter.dev/)
[![Cloud Sync](https://img.shields.io/badge/Cloud%20Sync-Google%20Drive%20v3-green.svg)](https://developers.google.com/drive)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An offline-first mobile companion system for **[Playnite](https://github.com/JosefNemec/Playnite)** ([playnite.link](https://playnite.link/)). Browse and search your PC video game collection, rich metadata, achievements, play session timelines, and video micro-trailers on your Android device via personal Google Drive or local storage synchronization with incremental delta updates.

---

## About the Project

**Playnite Mobile Companion** connects your desktop Playnite library to your mobile device with an offline-first design:

- **Offline-First Browsing:** The companion app downloads your library into a local SQLite database (with FTS5 search) on your Android device. Once synced, you can browse, filter, and inspect your full collection completely offline.
- **Incremental Delta Synchronization:** After the initial export, modifying metadata or completing a play session updates only the changed game payloads and newly added media assets, rather than requiring full library re-exports.
- **Personal Storage Independence:** Uses your personal Google Drive (with least-privilege `drive.file` scope) or a local shared folder as the synchronization intermediary. No third-party accounts, subscription services, or proprietary relay servers are required.
- **Rich Addon Integration:** Aggregates metadata from popular Playnite extensions including SuccessStory, HowLongToBeat, GameActivity, and ExtraMetadataLoader.

---

## Parts of the Project

The project is split into two complementary components:

```
+-------------------------------------------------------------------------+
|                       Playnite Mobile Delta Sync                        |
+------------------------------------+------------------------------------+
|  1. Desktop Addon (Playnite)       |  2. Mobile Companion (Flutter)     |
|     `playnite-exporter-plugin`     |     `playnite-mobile-companion`    |
|                                    |                                    |
|  - C# / .NET Framework 4.6.2       |  - Flutter 3.x / Dart 3.x          |
|  - Hooks: OnGameStopped, Library   |  - Android (APK) & Cross-Platform  |
|  - Rich Addon Data Extraction      |  - Local SQLite (Drift / sqflite)  |
|  - Deterministic JSON & SHA-256    |  - Instant FTS5 Offline Search     |
|  - Google Drive REST API v3        |  - Video Micro-Trailer Player      |
|  - Native Progress Bar with ETA    |  - Global Statistics Dashboard     |
+------------------------------------+------------------------------------+
```

### 1. Playnite Desktop Exporter Addon (`playnite-exporter-plugin`)
- **SDK Lifecycle Hooks:** Automatically triggers single-game delta syncs the moment you exit a game (`OnGameStopped`), capturing playtime, new achievements, and session dates in real time.
- **Rich Addon Pipeline:** Extracts structured data from popular Playnite extensions:
  - **SuccessStory:** Unlocked and locked achievements, gamer scores, and icons.
  - **HowLongToBeat:** Main Story, Main + Extra, and Completionist target times.
  - **GameActivity:** Detailed play session history and timeline graphs.
  - **ExtraMetadataLoader:** High-resolution transparent game logos and looping video micro-trailers.
  - **CheckDlc:** DLC ownership and listings.
  - **SteamReviews & SystemChecker:** Hardware requirements and community review scores.
- **Content-Addressable Storage (CAS):** Deduplicates cover art and wallpapers by SHA-256 hash.
- **Two-Phase Atomic Commit:** Ensures the remote `sync_index.json` is committed last, preventing corrupt or partial states on network drops.

### 2. Flutter Mobile Companion (`playnite-mobile-companion`)
- **Strict Read-Only Design:** Clean viewer, tracker, and statistics dashboard without bloated game launchers or store API logins.
- **Smooth High-FPS Browsing:** Virtualized Grid, List, and Detail views with customizable card scaling.
- **Instant Search & Multi-Criteria Filtering:** Local SQLite/FTS5 filtering across platforms, genres, sources, completion statuses, tags, and review scores.
- **Game Detail View:** Hero header with transparent logos, auto-looping micro-trailers, achievement showcases, HLTB completion badges, and external links (Steam, IGDB, PCGamingWiki).
- **Global Statistics Dashboard:** Total games, cumulative playtime, completion rate donut charts, and platform breakdown graphs.
- **Built-in Demo Library:** Allows testing and exploring the app immediately without configuring cloud credentials.

---

## Architectural Flow

```mermaid
flowchart LR
    subgraph Desktop["Windows PC (Playnite)"]
        PlayniteCore["Playnite Database\n(Games & Metadata)"]
        Addons["Whitelisted Addons\n(SuccessStory, HLTB, Activity)"]
        Exporter["Mobile Delta Sync Plugin\n(playnite-exporter-plugin)"]
        PlayniteCore --> Exporter
        Addons --> Exporter
    end

    subgraph Storage["Cloud / Shared Storage (PlayniteSync)"]
        SyncIndex["sync_index.json\n(Authoritative Manifest)"]
        Games["games/{game_id}.json\n(Granular Payloads)"]
        Media["media/\n(Covers, Logos, Trailers)"]
    end

    subgraph Mobile["Android Companion Device"]
        MobileApp["Playnite Companion\n(playnite-mobile-companion)"]
        SQLite[("Local SQLite Database\n(Drift + FTS5 Search)")]
        UI["High-FPS Library, Stats,\nTrailers & Achievements"]
        MobileApp --> SQLite
        SQLite --> UI
    end

    Exporter -- "Delta Push (Incremental)" --> Storage
    Storage -- "Incremental Pull" --> MobileApp
```

---

## Documentation & Detailed Guides

The project documentation is organized into focused sub-pages:

* [**Google Cloud Platform & Storage Setup Guide**](docs/setup-and-auth.md)  
  Step-by-step instructions for creating a Google Cloud project, configuring the `drive.file` OAuth consent screen, generating Desktop Client IDs, and setting up Local Folder / Google Drive for Desktop sync.

* [**Building from Source Guide**](docs/building.md)  
  Prerequisites, toolchain setup, and exact commands to compile and package both the `.pext` Playnite desktop extension and the Android `.apk` mobile installer.

* [**Installation & Usage Guide**](docs/installation-and-usage.md)  
  How to install the extension in Playnite, configure settings, run your first full export, install the mobile APK on Android, and explore all companion features.

* [**Architecture & Protocol Specification**](docs/architecture-and-specs.md)  
  Deep dive into the delta-sync protocol, deterministic JSON serialization, content-addressable media storage, supported addon schemas, and SQLite database design.

---

## Quick Start Overview

### 1. Set Up Storage
1. Configure a Google Cloud OAuth Client ID with the `drive.file` scope (see [Setup & Auth Guide](docs/setup-and-auth.md)), **OR** use **Local Folder Staging** with Google Drive for Desktop.

### 2. Install the Desktop Addon
1. Download or build [`MobileDeltaSyncExporter.pext`](docs/building.md).
2. Double-click the `.pext` file to install it into Playnite.
3. Open **Settings > Add-ons > Extension Settings > Mobile Delta Sync**.
4. Enter your Client ID / Secret (or select Local Folder) and click **Connect**.
5. Trigger **Main Menu > @Mobile Delta Sync > Force Full Re-Export & Upload** to create the initial cloud snapshot.

### 3. Install the Mobile App
1. Download or build [`playnite-mobile-companion.apk`](docs/building.md).
2. Install the APK on your Android device (via `adb install` or file transfer).
3. Open the app, go to **Sync Settings**, connect to your Google Drive folder (or tap **Load Demo Library**), and tap **Run Delta Sync Now**.

---

## Project Structure

```text
Playnite_Addon/
|-- .gitignore                             # Git ignore rules (secrets, build outputs, caches)
|-- DEPLOYMENT_GUIDE.md                    # Comprehensive deployment and operations manual
|-- README.md                              # Main project documentation
|-- docs/                                  # Modular GitHub documentation
|   |-- setup-and-auth.md                  # Google Cloud OAuth & storage setup guide
|   |-- building.md                        # Prerequisites & compilation commands (.pext / .apk)
|   |-- installation-and-usage.md          # Installation, first export & usage walkthrough
|   +-- architecture-and-specs.md          # Delta-sync protocol, data schema & architecture
|-- dist/                                  # Packaged distribution artifacts (.pext & .apk)
|   |-- MobileDeltaSyncExporter.pext       # Ready-to-install Playnite extension
|   +-- playnite-mobile-companion.apk      # Ready-to-install Android companion app
|-- playnite-exporter-plugin/              # Playnite C# .NET Desktop Addon
|   |-- PlayniteExporterPlugin.csproj      # .NET Framework 4.6.2 project file
|   |-- extension.yaml                     # Playnite plugin manifest
|   |-- Addons/                            # Whitelisted addon extractors (SuccessStory, HLTB, etc.)
|   |-- Common/                            # Deterministic serializer, hasher, progress estimator
|   |-- Configuration/                     # Settings, DPAPI token storage & WPF ViewModels
|   |-- Models/                            # Unified JSON data models & manifest contracts
|   |-- Services/                          # Metadata aggregator & ExportCoordinator sync engine
|   |-- Storage/                           # Google Drive REST client & Local Folder provider
|   +-- Views/                             # WPF / XAML SettingsView interface
|-- playnite-exporter-plugin.Tests/        # Automated test suite (30 unit & integration tests)
|   |-- PlayniteExporterPlugin.Tests.csproj
|   +-- ...                                # Unit tests verifying delta diff, CAS, and hashing
+-- playnite-mobile-companion/             # Flutter Mobile Companion App
    |-- pubspec.yaml                       # Flutter dependencies (Drift, SQLite, video_player)
    |-- lib/
    |   |-- core/                          # App theme, database helpers, and network clients
    |   +-- features/
    |       |-- library/                   # Virtualized Grid/List views, search & filter drawer
    |       |-- game_detail/               # Game detail hero header, micro-trailer & addon cards
    |       |-- stats/                     # Global statistics dashboard & charts
    |       +-- sync/                      # DeltaPullManager, settings & OAuth browser flow
    +-- test/                              # Automated Flutter test suites
```

---

## Security, Privacy & Zero Secrets

- **Least-Privilege Cloud Scope:** The extension and mobile app request only `https://www.googleapis.com/auth/drive.file`. The app can **only** access the files and folders it creates (e.g., `PlayniteSync`). It cannot see, read, or modify any other files in your personal Google Drive.
- **Local Credential Encryption:** On Windows, OAuth refresh tokens are encrypted using the native **Windows Data Protection API (DPAPI)** tied to your Windows user account.
- **Zero Third-Party Servers:** Communication occurs exclusively between your personal computer, your mobile phone, and Google's official REST API endpoints (`https://www.googleapis.com/drive/v3/`). There are no telemetry servers, analytics trackers, or intermediary relays.
- **No Secrets in Git:** All client credentials and tokens are entered dynamically by the user and are strictly ignored via `.gitignore`.

---

## Contributing

Contributions, bug reports, and feature suggestions are welcome!
1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/amazing-feature`).
3. Ensure automated tests pass:
   - Desktop: `dotnet test playnite-exporter-plugin.Tests\PlayniteExporterPlugin.Tests.csproj`
   - Mobile: `flutter test` (in `playnite-mobile-companion`)
4. Commit your changes (`git commit -m 'Add amazing feature'`).
5. Push to the branch (`git push origin feature/amazing-feature`).
6. Open a Pull Request.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
