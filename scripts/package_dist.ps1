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

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Playnite Mobile Companion & Exporter Packaging" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Version Parity Guardrail Check
$extensionYamlPath = Join-Path $repoRoot "playnite-exporter-plugin\extension.yaml"
$pubspecPath = Join-Path $repoRoot "playnite-mobile-companion\pubspec.yaml"
$installerYamlPath = Join-Path $repoRoot "installer.yaml"

$extensionVerMatch = Select-String -Path $extensionYamlPath -Pattern '(?m)^Version:\s*([0-9\.]+)'
if (-not $extensionVerMatch) {
    throw "Unable to extract Version from $extensionYamlPath"
}
$extensionVer = $extensionVerMatch.Matches[0].Groups[1].Value.Trim()

$pubspecVerMatch = Select-String -Path $pubspecPath -Pattern '(?m)^version:\s*([0-9\.]+)'
if (-not $pubspecVerMatch) {
    throw "Unable to extract version from $pubspecPath"
}
$pubspecVer = $pubspecVerMatch.Matches[0].Groups[1].Value.Trim()

$installerContent = Get-Content -Path $installerYamlPath -Raw
$installerHasVer = $installerContent -match "(?m)^\s*-\s*Version:\s*$([regex]::Escape($extensionVer))\b"

Write-Host "Detected Addon Version:     $extensionVer"
Write-Host "Detected Mobile Version:    $pubspecVer"
Write-Host "Installer Changelog Matched: $installerHasVer"

if ($extensionVer -ne $pubspecVer) {
    throw "Version Parity Guardrail Failed: extension.yaml ($extensionVer) != pubspec.yaml ($pubspecVer)!"
}

if (-not $installerHasVer) {
    throw "Version Parity Guardrail Failed: installer.yaml does not contain an entry for Version $extensionVer!"
}
Write-Host ">> Version parity check PASSED." -ForegroundColor Green

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

        # Check if Playnite is running before attempting hot-update
        $playniteProc = Get-Process -Name "Playnite.DesktopApp" -ErrorAction SilentlyContinue
        if ($playniteProc) {
            Write-Warning "Playnite is currently running (PID: $($playniteProc.Id)) and holding locks on addon assemblies."
            Write-Warning "To update installed extension in-place, please close Playnite."
        }

        # Hot-update local Playnite installation if present
        $installedAddonDir = "$env:AppData\Playnite\Extensions\MobileDeltaSyncExporter_d3b07384-d113-4c90-951b-10f88a91a92a"
        if (Test-Path $installedAddonDir) {
            Write-Host "Attempting hot-update of installed Playnite extension at $installedAddonDir..."
            try {
                Copy-Item (Join-Path $stagingDir "*") -Destination $installedAddonDir -Recurse -Force -ErrorAction Stop
                Write-Host "Hot-update succeeded!" -ForegroundColor Green
            } catch {
                Write-Warning "Could not hot-update installed extension files ($($_.Exception.Message)). Addon files will update upon Playnite restart or manual .pext install."
            }
        }

        # Verify key dependencies inside the archive
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
