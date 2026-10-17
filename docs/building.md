# Building from Source: Desktop Extension (`.pext`) & Mobile App (`.apk`)

This guide provides step-by-step instructions for compiling both components from source code.

---

## Table of Contents
1. [Prerequisites & Development Environment](#1-prerequisites--development-environment)
2. [Building the Playnite Desktop Extension (`.pext`)](#2-building-the-playnite-desktop-extension-pext)
   - [Run Unit & Integration Tests](#run-unit--integration-tests)
   - [Compile the Release Build](#compile-the-release-build)
   - [Package the Ready-to-Install `.pext` File](#package-the-ready-to-install-pext-file)
3. [Building the Flutter Mobile Companion (`.apk`)](#3-building-the-flutter-mobile-companion-apk)
   - [Install Dependencies & Run Code Generator](#install-dependencies--run-code-generator)
   - [Run Automated Flutter Tests](#run-automated-flutter-tests)
   - [Build the Release APK](#build-the-release-apk)
4. [One-Click Automated Build Script](#4-one-click-automated-build-script)

---

## 1. Prerequisites & Development Environment

Before building, ensure the following software is installed on your machine:

### For the Playnite Desktop Addon
| Tool | Minimum Version | Notes |
| :--- | :--- | :--- |
| **Windows OS** | Windows 10 / 11 (x64) | Playnite is a native Windows WPF desktop application. |
| **.NET SDK** | .NET 6.0, 7.0, or 8.0+ | Download from [dot.net](https://dotnet.microsoft.com/download). |
| **.NET Framework 4.6.2 Targeting Pack** | 4.6.2 Dev Pack | Required by Playnite's plugin architecture. Installed via Visual Studio Installer (check *.NET Framework 4.6.2 targeting pack*) or directly via [Microsoft .NET 4.6.2 Developer Pack](https://dotnet.microsoft.com/download/dotnet-framework/net462). |
| **PowerShell** | 5.1+ or PowerShell 7+ | Used for archive compression. |

### For the Flutter Mobile Companion
| Tool | Minimum Version | Notes |
| :--- | :--- | :--- |
| **Flutter SDK** | 3.22+ (Dart 3.4+) | Install from [flutter.dev](https://docs.flutter.dev/get-started/install). Ensure `flutter` is added to your system `PATH`. |
| **Java Development Kit** | JDK 17 (Eclipse Temurin or OpenJDK) | Required for Gradle on Android API 34. |
| **Android SDK & Build-Tools** | SDK Platform 34, Build-Tools 34.0.0 | Install via Android Studio SDK Manager or command-line tools. |

To verify your environment, open PowerShell and run:
```powershell
dotnet --version
flutter doctor
```

---

## 2. Building the Playnite Desktop Extension (`.pext`)

All commands in this section should be executed from the **repository root directory**:
```powershell
cd C:\Users\adith\Documents\Code\Playnite_Addon
```

### Run Unit & Integration Tests
Run the automated test suite to ensure all 30 delta-sync, deterministic hashing, and serialization tests pass:
```powershell
dotnet test playnite-exporter-plugin.Tests\PlayniteExporterPlugin.Tests.csproj
```
*Expected output:* `Passed! - Failed: 0, Passed: 30, Skipped: 0`

### Compile the Release Build
Compile the C# extension targeting .NET Framework 4.6.2 in Release mode:
```powershell
dotnet build -c Release playnite-exporter-plugin\PlayniteExporterPlugin.csproj
```
*Output binaries are placed in:*
`playnite-exporter-plugin\bin\Release\net462\`

### Package the Ready-to-Install `.pext` File
Playnite extensions (`.pext`) are standard zip archives with a flat root structure containing `extension.yaml`, `icon.png`, and the compiled assemblies.

Run the following PowerShell command from the repository root:
```powershell
# Create dist directory if it does not exist
if (!(Test-Path 'dist')) { New-Item -ItemType Directory -Path 'dist' }

# Remove old artifact if present
if (Test-Path 'dist\MobileDeltaSyncExporter.pext') { Remove-Item 'dist\MobileDeltaSyncExporter.pext' -Force }
if (Test-Path 'dist\MobileDeltaSyncExporter.zip') { Remove-Item 'dist\MobileDeltaSyncExporter.zip' -Force }

# Compress output files directly into the root of the archive
Compress-Archive -Path 'playnite-exporter-plugin\bin\Release\net462\*' -DestinationPath 'dist\MobileDeltaSyncExporter.zip' -Force
Rename-Item -Path 'dist\MobileDeltaSyncExporter.zip' -NewName 'MobileDeltaSyncExporter.pext' -Force
```

*Final Artifact:* `dist\MobileDeltaSyncExporter.pext`

---

## 3. Building the Flutter Mobile Companion (`.apk`)

All commands in this section should be executed from the **`playnite-mobile-companion`** directory:
```powershell
cd C:\Users\adith\Documents\Code\Playnite_Addon\playnite-mobile-companion
```

### Install Dependencies & Run Code Generator
Fetch pub packages and run the Drift/build_runner code generation:
```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Run Automated Flutter Tests
Verify SQLite normalization, delta-pull network efficiency, and UI safety:
```powershell
flutter test
```
*Expected output:* `All tests passed!`

### Build the Release APK
Build the release Android package:
```powershell
flutter build apk --release
```
*Built output:* `build\app\outputs\flutter-apk\app-release.apk`

Copy the built APK to the top-level `dist/` directory:
```powershell
Copy-Item build\app\outputs\flutter-apk\app-release.apk ..\dist\playnite-mobile-companion.apk -Force
```

*Final Artifact:* `dist\playnite-mobile-companion.apk`

---

## 4. One-Click Automated Build Script

To build and package **both** the Playnite desktop extension and the Android mobile app in a single command, run the following PowerShell snippet from the repository root:

```powershell
Write-Host "=== 1/4 Testing Desktop Plugin ===" -ForegroundColor Cyan
dotnet test playnite-exporter-plugin.Tests\PlayniteExporterPlugin.Tests.csproj
if ($LASTEXITCODE -ne 0) { throw "Desktop tests failed!" }

Write-Host "=== 2/4 Compiling Desktop Plugin (Release) ===" -ForegroundColor Cyan
dotnet build -c Release playnite-exporter-plugin\PlayniteExporterPlugin.csproj
if ($LASTEXITCODE -ne 0) { throw "Desktop build failed!" }

Write-Host "=== Packaging .pext Archive ===" -ForegroundColor Cyan
if (!(Test-Path 'dist')) { New-Item -ItemType Directory -Path 'dist' }
if (Test-Path 'dist\MobileDeltaSyncExporter.pext') { Remove-Item 'dist\MobileDeltaSyncExporter.pext' -Force }
Compress-Archive -Path 'playnite-exporter-plugin\bin\Release\net462\*' -DestinationPath 'dist\temp.zip' -Force
Rename-Item -Path 'dist\temp.zip' -NewName 'MobileDeltaSyncExporter.pext' -Force

Write-Host "=== 3/4 Testing Flutter Companion ===" -ForegroundColor Cyan
Push-Location playnite-mobile-companion
flutter pub get
flutter test
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Mobile tests failed!" }

Write-Host "=== 4/4 Compiling Android Release APK ===" -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Mobile APK build failed!" }
Copy-Item build\app\outputs\flutter-apk\app-release.apk ..\dist\playnite-mobile-companion.apk -Force
Pop-Location

Write-Host "Build complete! Artifacts created in dist/:" -ForegroundColor Green
Get-ChildItem dist
```
