[CmdletBinding()]
param(
    [switch]$SkipPext,
    [switch]$SkipApk
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$distDir = Join-Path $repoRoot "dist"
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

Write-Host "=== Playnite Mobile Companion Packaging ===" -ForegroundColor Cyan

# 1. Version Parity Check
$extensionYamlPath = Join-Path $repoRoot "playnite-exporter-plugin\extension.yaml"
$pubspecPath = Join-Path $repoRoot "playnite-mobile-companion\pubspec.yaml"
$installerYamlPath = Join-Path $repoRoot "installer.yaml"

$extensionVer = (Select-String -Path $extensionYamlPath -Pattern '^Version:\s*([0-9\.]+)').Matches.Groups[1].Value
$pubspecVer = (Select-String -Path $pubspecPath -Pattern '^version:\s*([0-9\.]+)').Matches.Groups[1].Value

Write-Host "Detected Addon Version:  $extensionVer"
Write-Host "Detected Mobile Version: $pubspecVer"

if ($extensionVer -ne $pubspecVer) {
    Write-Warning "Version mismatch between extension.yaml ($extensionVer) and pubspec.yaml ($pubspecVer)!"
}

# 2. Build & Package .pext
if (-not $SkipPext) {
    Write-Host "`n--- Building C# Exporter Plugin (Release) ---" -ForegroundColor Yellow
    $csprojPath = Join-Path $repoRoot "playnite-exporter-plugin\PlayniteExporterPlugin.csproj"
    dotnet build $csprojPath -c Release --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build C# plugin."
    }

    $binDir = Join-Path $repoRoot "playnite-exporter-plugin\bin\Release\net462"
    $pextTarget = Join-Path $distDir "MobileDeltaSyncExporter.pext"
    $stagingDir = Join-Path $env:TEMP "pext_staging_$(Get-Random)"

    try {
        if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
        Copy-Item (Join-Path $binDir "*") -Destination $stagingDir -Recurse -Force

        # Remove existing target pext
        if (Test-Path $pextTarget) { Remove-Item $pextTarget -Force }

        Write-Host "Packaging .pext with all dependencies..."
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $pextTarget)

        # Hot-update local Playnite installation if present
        $installedAddonDir = "$env:AppData\Playnite\Extensions\MobileDeltaSyncExporter_d3b07384-d113-4c90-951b-10f88a91a92a"
        if (Test-Path $installedAddonDir) {
            Write-Host "Hot-updating installed Playnite extension at $installedAddonDir..."
            try {
                Copy-Item (Join-Path $stagingDir "*") -Destination $installedAddonDir -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Warning "Playnite is currently running and locking addon DLLs ($($_.Exception.Message)). Addon files will update upon Playnite restart or manual .pext install."
            }
        }

        # Verify key dependencies
        $archive = [System.IO.Compression.ZipFile]::OpenRead($pextTarget)
        $entryNames = $archive.Entries | ForEach-Object { $_.FullName }
        $archive.Dispose()

        $requiredDlls = @("PlayniteExporterPlugin.dll", "Newtonsoft.Json.dll", "Polly.dll", "System.ValueTuple.dll")
        foreach ($dll in $requiredDlls) {
            if ($entryNames -notcontains $dll) {
                throw "CRITICAL: $dll is missing from packaged .pext!"
            }
        }
        Write-Host "PEXT packaged successfully: $pextTarget ($( [math]::Round((Get-Item $pextTarget).Length / 1MB, 2) ) MB)" -ForegroundColor Green
    }
    finally {
        if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# 3. Build & Package Flutter APK
if (-not $SkipApk) {
    Write-Host "`n--- Building Flutter Companion APK (Release) ---" -ForegroundColor Yellow
    $flutterDir = Join-Path $repoRoot "playnite-mobile-companion"
    Push-Location $flutterDir
    try {
        flutter build apk --release
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter APK build failed."
        }
        $builtApk = Join-Path $flutterDir "build\app\outputs\flutter-apk\app-release.apk"
        $targetApk = Join-Path $distDir "playnite-mobile-companion.apk"
        Copy-Item $builtApk -Destination $targetApk -Force
        Write-Host "APK packaged successfully: $targetApk ($( [math]::Round((Get-Item $targetApk).Length / 1MB, 2) ) MB)" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

Write-Host "`nPackaging completed successfully!" -ForegroundColor Green
