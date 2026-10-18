# Playnite Mobile Delta Sync — End-to-End Deployment & Operations Guide

> **System Architecture:** High-Performance Distributed Game Library Companion  
> **Desktop Component:** C# .NET Generic Plugin (`playnite-exporter-plugin`)  
> **Mobile Component:** Flutter 3.38+ / Dart 3.10+ Native Companion (`playnite-mobile-companion`)  
> **Storage Layer:** Google Drive REST API v3 (Strict `drive.file` Scope) & Local File System Staging  
> **Document Version:** 1.0.0 — Production Release Candidate  

---

## Table of Contents
1. [Architectural Overview & Data Flow](#1-architectural-overview--data-flow)
2. [Playnite Desktop Extension Setup](#2-playnite-desktop-extension-setup)
   - [2.1 Building from Source](#21-building-from-source)
   - [2.2 Packaging as `.pext` via Playnite Toolbox](#22-packaging-as-pext-via-playnite-toolbox)
   - [2.3 Manual Drop-In Deployment](#23-manual-drop-in-deployment)
3. [Google Cloud Platform OAuth 2.0 Configuration](#3-google-cloud-platform-oauth-20-configuration)
   - [3.1 GCP Project & Drive API Activation](#31-gcp-project--drive-api-activation)
   - [3.2 OAuth Consent Screen Setup (`drive.file` Scope)](#32-oauth-consent-screen-setup-drivefile-scope)
   - [3.3 Desktop Client ID Credentials](#33-desktop-client-id-credentials)
   - [3.4 Mobile Client ID Credentials](#34-mobile-client-id-credentials)
4. [Desktop Plugin Configuration](#4-desktop-plugin-configuration)
   - [4.1 Storage Provider Selection (Google Drive vs Local Staging)](#41-storage-provider-selection-google-drive-vs-local-staging)
   - [4.2 Authentication Flow](#42-authentication-flow)
   - [4.3 Auto-Sync Triggers & Media Rules](#43-auto-sync-triggers--media-rules)
   - [4.4 First Full Library Export](#44-first-full-library-export)
5. [Flutter Mobile Companion Deployment](#5-flutter-mobile-companion-deployment)
   - [5.1 Environment Prerequisites](#51-environment-prerequisites)
   - [5.2 Building Release APK & App Bundle](#52-building-release-apk--app-bundle)
   - [5.3 Sideloading via ADB or Direct Transfer](#53-sideloading-via-adb-or-direct-transfer)
   - [5.4 Mobile Client Configuration](#54-mobile-client-configuration)
6. [End-to-End Verification Procedure](#6-end-to-end-verification-procedure)
   - [Step 1: Baseline Full Export Verification](#step-1-baseline-full-export-verification)
   - [Step 2: Mobile Ingestion & SQLite Normalization](#step-2-mobile-ingestion--sqlite-normalization)
   - [Step 3: Fast-Path Game Exit Verification](#step-3-fast-path-game-exit-verification)
   - [Step 4: Mobile Delta Pull Efficiency](#step-4-mobile-delta-pull-efficiency)
   - [Step 5: Orphan Pruning on Game Deletion](#step-5-orphan-pruning-on-game-deletion)
7. [Troubleshooting & Diagnostics](#7-troubleshooting--diagnostics)
   - [Google OAuth 403 / "Access Blocked: Test Users" Error](#google-oauth-403--access-blocked-test-users-error)
   - [Playnite Plugin Fails to Load / SDK Assembly Mismatch](#playnite-plugin-fails-to-load--sdk-assembly-mismatch)
   - [CAS Media Hash Invalidation & Network Jitter](#cas-media-hash-invalidation--network-jitter)
   - [Android Background Battery Optimization (Doze Mode)](#android-background-battery-optimization-doze-mode)
   - [Corrupt SQLite Cache Recovery](#corrupt-sqlite-cache-recovery)

---

## 1. Architectural Overview & Data Flow

```
+-----------------------------------------------------------------------------------------+
|                                    PLAYNITE DESKTOP                                     |
|                                                                                         |
|  +--------------------+    +----------------------+    +-----------------------------+  |
|  | Game Database &    | -> | Metadata Aggregator  | -> | Deterministic Serialization |  |
|  | Whitelisted Addons |    | & Media Processor    |    | (Lexicographical Key Sort)  |  |
|  +--------------------+    +----------------------+    +-----------------------------+  |
|                                                                        |                |
|                                              +-------------------------+                |
|                                              v                                          |
|                                  +-----------------------+                              |
|                                  |   Delta Hash Engine   |                              |
|                                  |   (SHA-256 Checksums) |                              |
|                                  +-----------------------+                              |
|                                              |                                          |
|                                              v                                          |
|                                  +-----------------------+                              |
|                                  |  Two-Phase Commit     |                              |
|                                  |  (Index written last) |                              |
|                                  +-----------------------+                              |
+----------------------------------------------|------------------------------------------+
                                               |
                          Sync Target: Google Drive or Local Folder
                                               |
                                               v
+-----------------------------------------------------------------------------------------+
|                                 REMOTE / SHARED STORAGE                                 |
|                                                                                         |
|   root/                                                                                 |
|     |-- manifest.json          (Global library metrics, taxonomy lookup)                |
|     |-- sync_index.json        (Authoritative index: relative paths, sha256, file IDs)  |
|     |-- games/                                                                          |
|     |     |-- {game_id}.json   (Unified game payload: core data + normalized addons)    |
|     +-- media/                                                                          |
|           |-- covers/          (Content-Addressable Storage: {sha256}.webp)             |
|           |-- backgrounds/                                                              |
|           +-- microtrailers/                                                            |
+-----------------------------------------------------------------------------------------+
                                               |
                                        Incremental Pull
                                               |
                                               v
+-----------------------------------------------------------------------------------------+
|                                FLUTTER MOBILE COMPANION                                 |
|                                                                                         |
|  +---------------------+   +----------------------+   +------------------------------+  |
|  | Delta Pull Manager  |-> | Atomic SQLite Txn    |-> | Indexed Queries & FTS5       |  |
|  | (O(Delta) Network)  |   | (Rollback on error)  |   | (Instant Offline Search)     |  |
|  +---------------------+   +----------------------+   +------------------------------+  |
|             |                                                        |                  |
|             v                                                        v                  |
|  +---------------------+                              +------------------------------+  |
|  | Viewport Media Pull |                              | Dynamic Addon Registry       |  |
|  | (On-demand caching) |                              | (Graceful Fallback Sections) |  |
|  +---------------------+                              +------------------------------+  |
+-----------------------------------------------------------------------------------------+
```

---

## 2. Playnite Desktop Extension Setup

The desktop component is built as a Generic Plugin conforming to Playnite 9/10 SDK specifications.

### 2.1 Building from Source
Ensure [.NET Framework 4.6.2 Developer Pack](https://dotnet.microsoft.com/en-us/download/dotnet-framework/net462) or newer and the [.NET 8+ SDK](https://dotnet.microsoft.com/download) are installed on your Windows machine.

```powershell
# Navigate to the plugin directory
cd C:\Users\adith\Documents\Code\Playnite_Addon\playnite-exporter-plugin

# Build Release binary configuration
dotnet build PlayniteExporterPlugin.csproj -c Release
```

The compiled output will be generated at:
`C:\Users\adith\Documents\Code\Playnite_Addon\playnite-exporter-plugin\bin\Release\net462\`

### 2.2 Packaging as `.pext` via Playnite Toolbox
Playnite provides the official `Playnite.Toolbox.exe` utility inside its installation directory (typically `%LocalAppData%\Playnite\` or `C:\Program Files\Playnite\`).

```powershell
# Define paths
$ToolboxPath = "$env:LocalAppData\Playnite\Playnite.Toolbox.exe"
$SourceDir = "C:\Users\adith\Documents\Code\Playnite_Addon\playnite-exporter-plugin\bin\Release\net462"
$OutputDir = "C:\Users\adith\Documents\Code\Playnite_Addon\dist"

# Create distribution directory
New-Item -ItemType Directory -Force -Path $OutputDir

# Pack the .pext package
& $ToolboxPath pack "$SourceDir" "$OutputDir\MobileDeltaSyncExporter.pext"
```

Once generated, double-clicking `MobileDeltaSyncExporter.pext` will prompt Playnite to install the extension automatically.

### 2.3 Manual Drop-In Deployment
For active development or headless installations without using the packaging toolbox:

1. Close Playnite if running.
2. Open PowerShell and create the target extension directory:
   ```powershell
   $ExtensionDir = "$env:AppData\Playnite\Extensions\MobileDeltaSyncExporter_d3b07384-d113-4c90-951b-10f88a91a92a"
   New-Item -ItemType Directory -Force -Path $ExtensionDir
   ```
3. Copy all files from the Release output into this folder:
   ```powershell
   Copy-Item -Path "C:\Users\adith\Documents\Code\Playnite_Addon\playnite-exporter-plugin\bin\Release\net462\*" -Destination $ExtensionDir -Recurse -Force
   ```
4. Verify the folder structure contains:
   ```text
   %AppData%\Playnite\Extensions\MobileDeltaSyncExporter_d3b07384-d113-4c90-951b-10f88a91a92a\
   |-- extension.yaml
   |-- icon.png
   |-- PlayniteExporterPlugin.dll
   |-- PlayniteExporterPlugin.pdb
   |-- Google.Apis.dll
   |-- Google.Apis.Auth.dll
   |-- Google.Apis.Core.dll
   |-- Google.Apis.Drive.v3.dll
   |-- Newtonsoft.Json.dll
   |-- Polly.dll
   |-- System.CodeDom.dll
   +-- System.ValueTuple.dll
   ```
5. Restart Playnite. Open **Main Menu -> Add-ons -> Installed -> Generic** and verify **Mobile Delta Sync Exporter** is listed and active.

---

## 3. Google Cloud Platform OAuth 2.0 Configuration

To synchronize securely with Google Drive, you must create a dedicated project in the Google Cloud Console. This ensures you maintain 100% data ownership and privacy.

> [!IMPORTANT]
> The extension requests **only** the `drive.file` scope (`https://www.googleapis.com/auth/drive.file`). This scope restricts access **strictly to files and folders created by this application**. The plugin and mobile companion have zero access to your personal files, photos, or documents on Google Drive.

### 3.1 GCP Project & Drive API Activation
1. Navigate to the [Google Cloud Console](https://console.cloud.google.com/).
2. Click the project dropdown in the top bar and select **New Project**.
3. Name the project `Playnite-Delta-Sync` and click **Create**.
4. In the search bar, enter **Google Drive API**, click the result, and click **Enable**.

### 3.2 OAuth Consent Screen Setup (`drive.file` Scope)
1. In the left navigation, select **APIs & Services** -> **OAuth consent screen**.
2. Select **External** user type and click **Create**.
3. Fill in the App Information:
   - **App name:** `Playnite Mobile Sync`
   - **User support email:** Select your personal Gmail address.
   - **Developer contact information:** Enter your personal Gmail address.
   - Click **Save and Continue**.
4. On the **Scopes** screen:
   - Click **Add or Remove Scopes**.
   - In the filter box, enter `drive.file`.
   - Check `.../auth/drive.file` (View and manage Google Drive files and folders that you have opened or created with this app).
   - Click **Update**, then click **Save and Continue**.
5. On the **Test Users** screen:
   - Click **Add Users**.
   - Add your own Google account email address (and any family accounts who will sync).
   - Click **Save and Continue**.
6. Review the summary and return to the dashboard. The application status will show as **In Testing**.

### 3.3 Desktop Client ID Credentials
1. In the left navigation, select **APIs & Services** -> **Credentials**.
2. Click **+ Create Credentials** -> **OAuth client ID**.
3. In the **Application type** dropdown, select **Desktop app**.
4. Enter name: `Playnite Desktop Exporter`.
5. Click **Create**.
6. A dialog appears showing your **Client ID** and **Client Secret**.
7. Keep this window open or click **Download JSON**.

### 3.4 Mobile Client ID Credentials
For Android/iOS token acquisition or direct REST integration:
1. Under **Credentials**, click **+ Create Credentials** -> **OAuth client ID**.
2. Select **Android** (or **Web Application** if using standard Web OAuth redirection).
3. Set Name: `Playnite Mobile Companion`.
4. Package name: `com.playnite.mobile_companion`.
5. Enter your debug/release SHA-1 signing certificate fingerprint.
   *(You can obtain this by running `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`)*.
6. Click **Create**.

---

## 4. Desktop Plugin Configuration

### 4.1 Storage Provider Selection (Google Drive vs Local Staging)
Open Playnite, then navigate to:
**Main Menu -> Settings -> Plugins -> Generic Plugins -> Mobile Delta Sync Exporter**

You are presented with two storage provider modes:

| Provider Mode | Primary Use Case | Configuration Required |
|---|---|---|
| **Google Drive** | Primary remote synchronization across mobile cellular/Wi-Fi | Client ID, Client Secret, Google Auth Token |
| **Local Folder** | Offline testing, local network testing, or third-party sync (Syncthing/SMB) | Local folder path (e.g. `C:\Users\<user>\PlayniteSync`) |

### 4.2 Authentication Flow (Google Drive Mode)
1. Select **Google Drive** as the Storage Type.
2. Enter the **Google Client ID** and **Google Client Secret** generated in [Section 3.3](#33-desktop-client-id-credentials).
3. Specify the remote folder name (default: `PlayniteSync`).
4. Click **Authenticate with Google Drive**.
5. Your default web browser will open to a Google authentication prompt.
   - If prompted with "Google haven't verified this app", click **Advanced** -> **Go to Playnite Mobile Sync (unsafe)**.
   - Check the permission box allowing access to files created by the application.
   - Click **Continue**.
6. The browser will redirect to `http://localhost:59821/authorize/` displaying **"Authentication successful! You can now close this tab."**
7. Back in Playnite, the status will show **Connected**. The refresh token is securely encrypted using Windows DPAPI (`DataProtectionScope.CurrentUser`) and stored in `%AppData%\Playnite\ExtensionsData\MobileDeltaSyncExporter_d3b07384-d113-4c90-951b-10f88a91a92a\tokens.dat`.

### 4.3 Auto-Sync Triggers & Media Rules
Under Plugin Settings:

- [x] **Auto-sync on library updated:**  
  Triggers a full incremental library diff when Playnite finishes updating games from Steam, Epic, GOG, or manual edits.
- [x] **Auto-sync on game exit:**  
  Triggers an instant fast-path delta update when a game session concludes. Only the target game's playtime, sessions, and `sync_index.json` are written to storage.
- [x] **Enable orphan pruning:**  
  When a game is removed or uninstalled from Playnite, deletes its remote JSON from storage and cleans the root index.
- **Media Settings:**
  - [x] Synchronize Cover Art (CAS WebP format)
  - [x] Synchronize Background Artwork
  - [x] Synchronize Logos
  - [x] Synchronize Microtrailers (Video trailers <10MB)
  - [ ] Synchronize Full Video Trailers (Optional, disabled by default to save drive space)
- **Max Parallel Uploads:** Set to `4` (default) or `8` for high-bandwidth connections.

Click **Save** to persist settings.

### 4.4 First Full Library Export
1. In Playnite's top bar or main menu, navigate to:
   **Extensions -> Mobile Delta Sync Exporter -> Sync Full Library Now**
2. A progress notification will appear in Playnite:
   - Aggregating game metadata and calculating deterministic SHA-256 hashes.
   - Extracting installed addons (`SuccessStory`, `HowLongToBeat`, `GameActivity`, `CheckDlc`, `SystemChecker`, `SteamReviewsViewer`, `SteamScreenshots`, etc.).
   - Uploading `games/{game_id}.json` payloads.
   - Uploading content-addressable covers (`media/covers/{sha256}.webp`).
   - Atomically writing `manifest.json` and `sync_index.json`.
3. Confirm completion in Playnite notifications: **"Delta Sync Complete: X games uploaded, 0 errors."**

---

## 5. Flutter Mobile Companion Deployment

The companion app is built using Flutter 3.38+ with Dart 3.10+ and supports Android (API 24+) as well as Windows desktop testing.

### 5.1 Environment Prerequisites
Ensure your build environment has:
- [Flutter SDK 3.38+](https://docs.flutter.dev/get-started/install) (`flutter --version`)
- Android Studio / Android SDK with Build-Tools 34.0.0+
- JDK 17 (recommended for Gradle 8+)

Verify your tooling:
```bash
flutter doctor
```

### 5.2 Building Release APK & App Bundle
Open a terminal in the mobile companion directory:

```bash
cd C:\Users\adith\Documents\Code\Playnite_Addon\playnite-mobile-companion

# Fetch and verify dependencies
flutter pub get

# Run static analysis to verify clean codebase
flutter analyze

# Execute all automated unit and integration tests
flutter test

# Build optimized release APK
flutter build apk --release

# (Optional) Build Google Play App Bundle for Play Console publishing
flutter build appbundle --release
```

The release APK is produced at:
`playnite-mobile-companion/build/app/outputs/flutter-apk/app-release.apk`

### 5.3 Sideloading via ADB or Direct Transfer

#### Option A: ADB Sideload (Fastest for Developers)
1. Connect your Android device via USB and enable **USB Debugging** in Developer Options.
2. Confirm device connection:
   ```bash
   adb devices
   ```
3. Install the release APK:
   ```bash
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```

#### Option B: Direct File Transfer
1. Copy `app-release.apk` to your phone via USB cable, Google Drive, or local storage.
2. On your device, open your File Manager, tap `app-release.apk`, and tap **Install**.
   *(If prompted, allow "Install Unknown Apps" for your file manager)*.

### 5.4 Mobile Client Configuration
1. Launch **Playnite Companion** on your phone.
2. On first launch, the app initializes the local SQLite database (`playnite_companion.db`) and opens to the Library screen.
3. Tap the **Sync** icon in the top app bar.
4. If using Google Drive:
   - Enter your OAuth Bearer Token or authenticate via Google Sign-In.
   - Specify folder name: `PlayniteSync`.
5. Tap **Start Delta Sync**.

---

## 6. End-to-End Verification Procedure

Follow this 5-step checklist to confirm full system integrity.

### Step 1: Baseline Full Export Verification
- Open Google Drive in your web browser (or inspect your local staging folder).
- Verify the following hierarchy exists:
  ```text
  PlayniteSync/
  |-- manifest.json
  |-- sync_index.json
  |-- games/
  |     |-- {guid-1}.json
  |     |-- {guid-2}.json
  +-- media/
        |-- covers/
        |     +-- {sha256}.webp
        +-- backgrounds/
  ```
- Open `sync_index.json` in a text editor. Confirm `total_games` matches your Playnite library count, and `entries` contains a mapping for each game.

### Step 2: Mobile Ingestion & SQLite Normalization
- In the mobile companion app, tap **Sync** -> **Start Delta Sync**.
- Observe the synchronized progress modal:
  1. `Phase: Fetching remote sync index...`
  2. `Phase: Diffing library state...`
  3. `Phase: Pulling delta: N payloads...`
  4. `Phase: Committing transaction to local database...`
  5. `Phase: Delta sync successfully completed.`
- Confirm the Library tab displays games in grid/list views with cover art, playtime badges, and source tags.
- Tap a game to open **Game Detail Screen**:
  - Verify **Achievements** card renders unlocked/locked counts and trophy icons.
  - Verify **HowLongToBeat** card displays Main Story, Extra, and Completionist hours.
  - Verify **Play Activity** shows historical sessions and timeline chart.
  - Verify **Microtrailer** plays smoothly when tapped.
- In the search bar, type a game name, developer name (e.g. `CD PROJEKT`), or genre. Confirm FTS5 returns matching results instantaneously (<16ms).

### Step 3: Fast-Path Game Exit Verification
1. On your PC, launch any game from Playnite.
2. Play for 2 minutes, then exit the game.
3. Observe Playnite:
   - Playnite records updated playtime and last played timestamp.
   - The exporter plugin immediately executes targeted `SyncSingleGameAsync`.
   - Inspection shows **only** `games/{target_game_id}.json` and `sync_index.json` were uploaded. All other games in `games/` remain completely untouched.

### Step 4: Mobile Delta Pull Efficiency
1. Open the mobile companion app and tap **Sync**.
2. Observe the report:
   - **Downloaded:** Exactly `1` payload.
   - **Transferred:** Only ~3 KB.
   - **Unchanged Games Downloaded:** `0`.
   - **Duration:** <250 ms.
3. Open the played game in mobile companion: verify playtime and recent activity reflect the session just concluded on PC.

### Step 5: Orphan Pruning on Game Deletion
1. In Playnite desktop, select a game and delete/remove it from your library.
2. Wait for auto-sync or trigger incremental sync.
3. In storage, verify `games/{deleted_game_id}.json` has been physically deleted, and `sync_index.json` removes its entry.
4. On mobile, tap **Sync**:
   - `PullDiff` identifies the deleted game.
   - Atomic SQLite transaction cascade-deletes the game from `games`, `games_fts`, `achievements`, `play_sessions`, `hltb_data`, and `dlc_items`.
   - Verify the game is gone from the mobile library screen with zero UI errors.

---

## 7. Troubleshooting & Diagnostics

### Google OAuth 401 / "Error 401: invalid_client"
- **Symptom:** During OAuth login, Google displays `Error 401: invalid_client` with `flowName=GeneralOAuthFlow`.
- **Cause:** Client ID and/or Client Secret are missing, mistyped, or an invalid OAuth Client Type was chosen in Google Cloud Console.
- **Solution:**
  1. Open [Google Cloud Console Credentials](https://console.cloud.google.com/apis/credentials).
  2. Ensure your OAuth 2.0 Client ID was created with **Application type: Desktop app** (not Web Application or Android).
  3. Copy the Client ID and Client Secret directly into Playnite -> **Add-ons -> Extension Settings -> Mobile Delta Sync Exporter**.
  4. Ensure Google Drive API is enabled in your GCP project.
  5. *Alternative:* If you have **Google Drive for Desktop** installed, simply switch your Storage Destination to **Google Drive Desktop / Local Sync** and point it to your `G:\My Drive\PlayniteSync` folder! It syncs automatically in the background with zero Google Cloud API keys or setup!

### Google OAuth 403 / "Access Blocked: Test Users" Error
- **Symptom:** During browser login, Google displays `Error 403: access_denied` with the message *"Playnite Mobile Sync has not completed the Google verification process. The app is currently being tested..."*
- **Solution:** Because your GCP project is in "Testing" mode, Google blocks accounts not explicitly whitelisted.
  1. Open [Google Cloud Console -> OAuth consent screen](https://console.cloud.google.com/apis/credentials/consent).
  2. Scroll down to **Test users**.
  3. Click **+ Add Users** and enter the exact Gmail address you are attempting to log in with.
  4. Click **Save** and retry the authentication flow in Playnite.

### Playnite Plugin Fails to Load / SDK Assembly Mismatch
- **Symptom:** Playnite starts, but Mobile Delta Sync Exporter is marked with an exclamation point in Add-ons, or does not appear in the menu.
- **Cause:** Missing dependency DLLs or SDK version mismatch.
- **Solution:**
  1. Check Playnite log file at `%AppData%\Playnite\playnite.log`.
  2. Verify that `Google.Apis.dll`, `Newtonsoft.Json.dll`, and `Polly.dll` exist in the extension folder alongside `PlayniteExporterPlugin.dll`.
  3. Ensure your desktop is running .NET Framework 4.6.2 or higher.

### CAS Media Hash Invalidation & Network Jitter
- **Symptom:** Mobile app shows placeholder covers for games whose artwork was updated on PC.
- **Cause:** Content-Addressable Storage (CAS) hashes identify images by their SHA-256 digest. If cover replacement occurs while mobile cached images are present:
- **Solution:**
  1. `MediaUrlResolver` generates URLs using the new `driveFileId`. `CachedNetworkImage` automatically caches against the new file ID.
  2. If images fail to refresh due to aggressive OS HTTP caching, open Companion App Settings -> **Clear Media Cache**.

### Android Background Battery Optimization (Doze Mode)
- **Symptom:** If background sync notifications are delayed or paused when the device is locked.
- **Solution:** Android Doze mode restricts network access for background applications.
  1. On your Android phone, go to **Settings -> Apps -> Playnite Companion -> Battery**.
  2. Select **Unrestricted** (or disable "Battery Optimization").
  3. Allow **Background data** under Mobile Data settings.

### Corrupt SQLite Cache Recovery
- **Symptom:** Mobile app encounters database locks or disk I/O errors after an unexpected phone shutdown.
- **Solution:** The companion app features atomic rollback and safe reconstruction:
  1. Open Companion App -> **Settings**.
  2. Tap **Reset Database**. This triggers `AppDatabase.instance.reset()`, purging local SQLite tables.
  3. Tap **Sync**. The app will perform a fresh pull from `sync_index.json`, completely reconstructing your normalized library with 100% fidelity.

---

*Playnite Mobile Delta Sync — Released under the MIT License.*
