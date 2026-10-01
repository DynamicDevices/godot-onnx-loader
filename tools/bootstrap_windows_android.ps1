[CmdletBinding()]
param(
    [string]$AndroidSdkRoot = "$env:LOCALAPPDATA\Android\Sdk",
    [switch]$SkipVisualStudio,
    [switch]$SkipGodotTemplates,
    [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$CommandLineToolsRevision = "15859902"
$CommandLineToolsSha256 = "90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a"
$NdkVersion = "28.1.13356709"
$AndroidPackages = @(
    "platform-tools",
    "build-tools;35.0.1",
    "platforms;android-35",
    "cmake;3.10.2.4988404",
    "ndk;$NdkVersion"
)

function Test-Command([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Set-UserEnvironment([string]$Name, [string]$Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "env:$Name" -Value $Value
}

function Add-UserPath([string]$PathEntry) {
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $items = @($current -split ";" | Where-Object { $_ })
    if ($items -notcontains $PathEntry) {
        [Environment]::SetEnvironmentVariable("Path", (($items + $PathEntry) -join ";"), "User")
    }
    if (($env:Path -split ";") -notcontains $PathEntry) {
        $env:Path = "$env:Path;$PathEntry"
    }
}

function Find-VsWhere {
    $candidate = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Find-Jdk17 {
    $roots = @(
        "C:\Program Files\Eclipse Adoptium",
        "C:\Program Files\Microsoft",
        "C:\Program Files\Java"
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $java = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "(jdk-?17|17.*jdk)" } |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($java -and (Test-Path (Join-Path $java.FullName "bin\java.exe"))) {
            return $java.FullName
        }
    }
    return $null
}

function Show-Verification {
    $vswhere = Find-VsWhere
    $vsInstall = if ($vswhere) {
        & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    } else { $null }
    $sdkManager = Join-Path $AndroidSdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
    $adb = Join-Path $AndroidSdkRoot "platform-tools\adb.exe"
    $ndk = Join-Path $AndroidSdkRoot "ndk\$NdkVersion"
    $templateRoot = Join-Path $env:APPDATA "Godot\export_templates"
    $templates = Get-ChildItem $templateRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^4\.6(\.\d+)?\.stable$' } |
        Where-Object { Test-Path (Join-Path $_.FullName "android_debug.apk") } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    $jdk = Find-Jdk17

    Write-Host "Visual Studio C++ tools: $([bool]$vsInstall) $vsInstall"
    Write-Host "JDK 17:                 $([bool]$jdk) $jdk"
    Write-Host "Android sdkmanager:     $(Test-Path $sdkManager) $sdkManager"
    Write-Host "Android adb:            $(Test-Path $adb) $adb"
    Write-Host "Android NDK r28b:       $(Test-Path $ndk) $ndk"
    Write-Host "Godot 4.6 templates:    $([bool]$templates) $($templates.FullName)"

    if (-not $vsInstall -or -not $jdk -or -not (Test-Path $sdkManager) -or
        -not (Test-Path $adb) -or -not (Test-Path $ndk) -or
        (-not $SkipGodotTemplates -and -not $templates)) {
        throw "One or more required components are missing."
    }
}

if ($VerifyOnly) {
    Show-Verification
    exit 0
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an Administrator PowerShell terminal."
}

if (-not $SkipVisualStudio) {
    $vswhere = Find-VsWhere
    $vsInstall = if ($vswhere) {
        & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    } else { $null }
    if (-not $vsInstall) {
        if (-not (Test-Command "winget.exe")) { throw "winget.exe is required to install Visual Studio Build Tools." }
        & winget.exe install --exact --id Microsoft.VisualStudio.2022.BuildTools `
            --accept-source-agreements --accept-package-agreements `
            --override "--passive --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
        if ($LASTEXITCODE -ne 0) { throw "Visual Studio Build Tools installation failed: $LASTEXITCODE" }
    }
}

$jdk = Find-Jdk17
if (-not $jdk) { throw "JDK 17 was not found. Install an x64 JDK 17 and rerun." }
Set-UserEnvironment "JAVA_HOME" $jdk

$sdkManager = Join-Path $AndroidSdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkManager)) {
    $download = Join-Path $env:TEMP "android-commandlinetools-$CommandLineToolsRevision.zip"
    $extract = Join-Path $env:TEMP "android-commandlinetools-$CommandLineToolsRevision"
    Invoke-WebRequest "https://dl.google.com/android/repository/commandlinetools-win-${CommandLineToolsRevision}_latest.zip" -OutFile $download
    $actual = (Get-FileHash $download -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $CommandLineToolsSha256) {
        throw "Android command-line tools checksum mismatch: $actual"
    }
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive $download -DestinationPath $extract
    $latest = Join-Path $AndroidSdkRoot "cmdline-tools\latest"
    New-Item -ItemType Directory -Force $latest | Out-Null
    Copy-Item (Join-Path $extract "cmdline-tools\*") $latest -Recurse -Force
    $sdkManager = Join-Path $latest "bin\sdkmanager.bat"
}

Set-UserEnvironment "ANDROID_HOME" $AndroidSdkRoot
Set-UserEnvironment "ANDROID_SDK_ROOT" $AndroidSdkRoot
Set-UserEnvironment "ANDROID_NDK_HOME" (Join-Path $AndroidSdkRoot "ndk\$NdkVersion")
Add-UserPath (Join-Path $AndroidSdkRoot "platform-tools")
Add-UserPath (Join-Path $AndroidSdkRoot "cmdline-tools\latest\bin")

Write-Host "Review and accept the Android SDK licences when prompted."
& $sdkManager --sdk_root=$AndroidSdkRoot --licenses
if ($LASTEXITCODE -ne 0) { throw "Android licence acceptance failed: $LASTEXITCODE" }
& $sdkManager --sdk_root=$AndroidSdkRoot @AndroidPackages
if ($LASTEXITCODE -ne 0) { throw "Android SDK package installation failed: $LASTEXITCODE" }

if (-not $SkipGodotTemplates) {
    $templateUrl = "https://github.com/godotengine/godot/releases/download/4.6-stable/Godot_v4.6-stable_export_templates.tpz"
    $sumsUrl = "https://github.com/godotengine/godot/releases/download/4.6-stable/SHA512-SUMS.txt"
    $archive = Join-Path $env:TEMP "Godot_v4.6-stable_export_templates.zip"
    $sums = (Invoke-WebRequest $sumsUrl).Content
    $match = [regex]::Match($sums, "(?im)^([0-9a-f]{128})\s+Godot_v4\.6-stable_export_templates\.tpz$")
    if (-not $match.Success) { throw "Could not resolve the official Godot template checksum." }
    Invoke-WebRequest $templateUrl -OutFile $archive
    $actual = (Get-FileHash $archive -Algorithm SHA512).Hash.ToLowerInvariant()
    if ($actual -ne $match.Groups[1].Value.ToLowerInvariant()) {
        throw "Godot export-template checksum mismatch: $actual"
    }
    $extract = Join-Path $env:TEMP "godot-4.6-export-templates"
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive $archive -DestinationPath $extract
    $source = Join-Path $extract "templates"
    $destination = Join-Path $env:APPDATA "Godot\export_templates\4.6.stable"
    New-Item -ItemType Directory -Force $destination | Out-Null
    Copy-Item (Join-Path $source "*") $destination -Recurse -Force
}

Show-Verification
Write-Host "WINDOWS_ANDROID_BOOTSTRAP_OK"
Write-Host "Restart terminals and Godot so the new user environment variables are visible."
