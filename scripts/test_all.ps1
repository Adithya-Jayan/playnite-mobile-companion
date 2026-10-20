<#
.SYNOPSIS
    Runs all unit and integration test suites across both the Playnite Desktop Exporter plugin and Flutter Mobile Companion.

.DESCRIPTION
    Aggregates test execution across:
    1. C# Exporter Plugin Tests (dotnet test)
    2. Flutter Mobile Companion Tests (flutter test)

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

# Determine repo root directory relative to this script's location
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot = Split-Path -Parent $ScriptDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Running Unified Workspace Test Suites" -ForegroundColor Cyan
Write-Host " Repository Root: $RepoRoot" -ForegroundColor DarkGray
Write-Host " Configuration:   $Configuration" -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$DotnetSuccess = $false
$FlutterSuccess = $false

# 1. C# Plugin Tests
$CsharpProjPath = Join-Path $RepoRoot "playnite-exporter-plugin.Tests\PlayniteExporterPlugin.Tests.csproj"

Write-Host "[1/2] Running Playnite Desktop Exporter tests (C#)..." -ForegroundColor Yellow
Write-Host "      Project: $CsharpProjPath" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-Path $CsharpProjPath)) {
    Write-Host "ERROR: C# test project not found at: $CsharpProjPath" -ForegroundColor Red
    $DotnetSuccess = $false
} else {
    dotnet test $CsharpProjPath -c $Configuration
    if ($LASTEXITCODE -eq 0) {
        $DotnetSuccess = $true
        Write-Host ">> Playnite Desktop Exporter tests PASSED." -ForegroundColor Green
    } else {
        $DotnetSuccess = $false
        Write-Host ">> Playnite Desktop Exporter tests FAILED (exit code: $LASTEXITCODE)." -ForegroundColor Red
    }
}

Write-Host ""

# 2. Flutter Mobile Companion Tests
$FlutterDir = Join-Path $RepoRoot "playnite-mobile-companion"

Write-Host "[2/2] Running Playnite Mobile Companion tests (Flutter)..." -ForegroundColor Yellow
Write-Host "      Directory: $FlutterDir" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-Path $FlutterDir)) {
    Write-Host "ERROR: Flutter directory not found at: $FlutterDir" -ForegroundColor Red
    $FlutterSuccess = $false
} else {
    Push-Location $FlutterDir
    try {
        flutter test
        if ($LASTEXITCODE -eq 0) {
            $FlutterSuccess = $true
            Write-Host ">> Playnite Mobile Companion tests PASSED." -ForegroundColor Green
        } else {
            $FlutterSuccess = $false
            Write-Host ">> Playnite Mobile Companion tests FAILED (exit code: $LASTEXITCODE)." -ForegroundColor Red
        }
    } finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Unified Test Execution Summary" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if ($DotnetSuccess) {
    Write-Host "  C# Exporter Plugin:       [ PASS ]" -ForegroundColor Green
} else {
    Write-Host "  C# Exporter Plugin:       [ FAIL ]" -ForegroundColor Red
}

if ($FlutterSuccess) {
    Write-Host "  Flutter Mobile Companion: [ PASS ]" -ForegroundColor Green
} else {
    Write-Host "  Flutter Mobile Companion: [ FAIL ]" -ForegroundColor Red
}

Write-Host "==========================================================" -ForegroundColor Cyan

if ($DotnetSuccess -and $FlutterSuccess) {
    Write-Host "All test suites passed successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "One or more test suites failed." -ForegroundColor Red
    exit 1
}
