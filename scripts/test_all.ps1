<#
.SYNOPSIS
    Runs all unit, integration, version parity, and artifact integrity test suites across both the Playnite Desktop Exporter plugin and Flutter Mobile Companion.

.DESCRIPTION
    Aggregates test execution across:
    1. Version Parity & Metadata Guardrails (extension.yaml, pubspec.yaml, installer.yaml)
    2. Distribution Artifact Integrity (if dist/MobileDeltaSyncExporter.pext exists)
    3. C# Exporter Plugin Tests (dotnet test)
    4. Flutter Mobile Companion Tests (flutter test)

    Exits with code 0 if all test suites pass, or code 1 if any test suite fails.
    Handles path locations relative to repo root regardless of where the script is invoked from.

.PARAMETER Configuration
    Build configuration for dotnet test (defaults to "Release").

.EXAMPLE
    .\scripts\test_all.ps1
    .\scripts\test_all.ps1 -Configuration Debug
#>

[CmdletBinding()]
param(
    [string]$Configuration = "Release"
)

Add-Type -AssemblyName System.IO.Compression.FileSystem

# Determine repo root directory relative to this script's location
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot = Split-Path -Parent $ScriptDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Running Unified Workspace Test Suites & Guardrails" -ForegroundColor Cyan
Write-Host " Repository Root: $RepoRoot" -ForegroundColor DarkGray
Write-Host " Configuration:   $Configuration" -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$GuardrailSuccess = $false
$DotnetSuccess = $false
$FlutterSuccess = $false

# 1. Version Parity & Metadata Guardrails
Write-Host "[1/3] Verifying Version Parity & Metadata Guardrails..." -ForegroundColor Yellow

$extensionYamlPath = Join-Path $RepoRoot "playnite-exporter-plugin\extension.yaml"
$pubspecPath = Join-Path $RepoRoot "playnite-mobile-companion\pubspec.yaml"
$installerYamlPath = Join-Path $RepoRoot "installer.yaml"

try {
    $extensionVerMatch = Select-String -Path $extensionYamlPath -Pattern '(?m)^Version:\s*([0-9\.]+)'
    if (-not $extensionVerMatch) {
        throw "Could not extract Version from $extensionYamlPath"
    }
    $extVer = $extensionVerMatch.Matches[0].Groups[1].Value.Trim()

    $pubspecVerMatch = Select-String -Path $pubspecPath -Pattern '(?m)^version:\s*([0-9\.]+)'
    if (-not $pubspecVerMatch) {
        throw "Could not extract version from $pubspecPath"
    }
    $pubVer = $pubspecVerMatch.Matches[0].Groups[1].Value.Trim()

    $installerContent = Get-Content -Path $installerYamlPath -Raw
    $installerHasVer = $installerContent -match "(?m)^\s*-\s*Version:\s*$([regex]::Escape($extVer))\b"

    Write-Host "      Addon (extension.yaml):  $extVer" -ForegroundColor DarkGray
    Write-Host "      Mobile (pubspec.yaml):   $pubVer" -ForegroundColor DarkGray
    Write-Host "      Changelog entry present: $installerHasVer" -ForegroundColor DarkGray

    if ($extVer -ne $pubVer) {
        throw "Version mismatch between extension.yaml ($extVer) and pubspec.yaml ($pubVer)"
    }

    if (-not $installerHasVer) {
        throw "installer.yaml missing entry for active version $extVer"
    }

    # Artifact integrity check if dist/MobileDeltaSyncExporter.pext exists
    $pextPath = Join-Path $RepoRoot "dist\MobileDeltaSyncExporter.pext"
    if (Test-Path $pextPath) {
        Write-Host "      Checking dist\MobileDeltaSyncExporter.pext integrity..." -ForegroundColor DarkGray
        $archive = [System.IO.Compression.ZipFile]::OpenRead($pextPath)
        $entryNames = $archive.Entries | ForEach-Object { $_.FullName }
        $archive.Dispose()

        $requiredDlls = @("PlayniteExporterPlugin.dll", "Newtonsoft.Json.dll", "Polly.dll", "System.ValueTuple.dll")
        foreach ($dll in $requiredDlls) {
            if ($entryNames -notcontains $dll) {
                throw "Packaged .pext missing required assembly: $dll"
            }
        }
        Write-Host "      Packaged .pext has all required dependency assemblies." -ForegroundColor DarkGray
    }

    $GuardrailSuccess = $true
    Write-Host ">> Version parity and metadata guardrails PASSED." -ForegroundColor Green
}
catch {
    $GuardrailSuccess = $false
    Write-Host ">> Guardrail FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# 2. C# Plugin Tests
$CsharpProjPath = Join-Path $RepoRoot "playnite-exporter-plugin.Tests\PlayniteExporterPlugin.Tests.csproj"

Write-Host "[2/3] Running Playnite Desktop Exporter tests (C#)..." -ForegroundColor Yellow
Write-Host "      Project: $CsharpProjPath" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-Path $CsharpProjPath)) {
    Write-Host "ERROR: C# test project not found at: $CsharpProjPath" -ForegroundColor Red
    $DotnetSuccess = $false
} else {
    dotnet test $CsharpProjPath -c $Configuration --nologo
    if ($LASTEXITCODE -eq 0) {
        $DotnetSuccess = $true
        Write-Host ">> Playnite Desktop Exporter tests PASSED." -ForegroundColor Green
    } else {
        $DotnetSuccess = $false
        Write-Host ">> Playnite Desktop Exporter tests FAILED (exit code: $LASTEXITCODE)." -ForegroundColor Red
    }
}

Write-Host ""

# 3. Flutter Mobile Companion Tests
$FlutterDir = Join-Path $RepoRoot "playnite-mobile-companion"

Write-Host "[3/3] Running Playnite Mobile Companion tests (Flutter)..." -ForegroundColor Yellow
Write-Host "      Directory: $FlutterDir" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-Path $FlutterDir)) {
    Write-Host "ERROR: Flutter directory not found at: $FlutterDir" -ForegroundColor Red
    $FlutterSuccess = $false
} else {
    Push-Location $FlutterDir
    try {
        Write-Host "Running flutter analyze..." -ForegroundColor DarkGray
        flutter analyze
        if ($LASTEXITCODE -ne 0) {
            $FlutterSuccess = $false
            Write-Host ">> Playnite Mobile Companion analysis FAILED (exit code: $LASTEXITCODE)." -ForegroundColor Red
        } else {
            Write-Host ">> Playnite Mobile Companion analysis PASSED." -ForegroundColor Green
            Write-Host ""
            Write-Host "Running flutter test..." -ForegroundColor DarkGray
            flutter test
            if ($LASTEXITCODE -eq 0) {
                $FlutterSuccess = $true
                Write-Host ">> Playnite Mobile Companion tests PASSED." -ForegroundColor Green
            } else {
                $FlutterSuccess = $false
                Write-Host ">> Playnite Mobile Companion tests FAILED (exit code: $LASTEXITCODE)." -ForegroundColor Red
            }
        }
    } finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Unified Test Execution Summary" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if ($GuardrailSuccess) {
    Write-Host "  Version & Artifact Guardrails: [ PASS ]" -ForegroundColor Green
} else {
    Write-Host "  Version & Artifact Guardrails: [ FAIL ]" -ForegroundColor Red
}

if ($DotnetSuccess) {
    Write-Host "  C# Exporter Plugin Tests:      [ PASS ]" -ForegroundColor Green
} else {
    Write-Host "  C# Exporter Plugin Tests:      [ FAIL ]" -ForegroundColor Red
}

if ($FlutterSuccess) {
    Write-Host "  Flutter Mobile Companion Tests:[ PASS ]" -ForegroundColor Green
} else {
    Write-Host "  Flutter Mobile Companion Tests:[ FAIL ]" -ForegroundColor Red
}

Write-Host "==========================================================" -ForegroundColor Cyan

if ($GuardrailSuccess -and $DotnetSuccess -and $FlutterSuccess) {
    Write-Host "All test suites and guardrails passed successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "One or more test suites or guardrails failed." -ForegroundColor Red
    exit 1
}
