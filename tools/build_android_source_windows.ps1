[CmdletBinding()]
param(
    [string]$AndroidSdkRoot = "$env:LOCALAPPDATA\Android\Sdk",
    [string]$GodotExe = "$env:USERPROFILE\Downloads\Godot_v4.6.1-stable_win64.exe",
    [string]$DeviceSerial = "",
    [int]$DeviceTestTimeoutSeconds = 45,
    [switch]$SkipOrtBuild
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$OrtCommit = "5630b081cd25e4eccc7516a652ff956e51676794"
$OrtTag = "v1.22.2"
$OrtSource = Join-Path $RepoRoot ".ort-src\onnxruntime"
$OrtBuild = Join-Path $RepoRoot ".ort-build-android"
$OrtStage = Join-Path $RepoRoot ".ort-source-install-android"
$NdkRoot = Join-Path $AndroidSdkRoot "ndk\28.1.13356709"
$JavaHome = "C:\Program Files\Eclipse Adoptium\jdk-17.0.13.11-hotspot"
$Adb = Join-Path $AndroidSdkRoot "platform-tools\adb.exe"
$Apk = Join-Path $RepoRoot "build\android\onnx-loader-smoke.apk"

# Windows Explorer commonly extracts the Godot zip into a directory whose
# name itself ends in .exe. Resolve the real executable inside that directory.
if (Test-Path $GodotExe -PathType Container) {
    $godotContainer = $GodotExe
    $godotLeaf = Split-Path $godotContainer -Leaf
    $consoleLeaf = "$([IO.Path]::GetFileNameWithoutExtension($godotLeaf))_console.exe"
    $consoleExe = Join-Path $godotContainer $consoleLeaf
    $GodotExe = if (Test-Path $consoleExe) {
        $consoleExe
    } else {
        Join-Path $godotContainer $godotLeaf
    }
}

foreach ($required in @($AndroidSdkRoot, $NdkRoot, $JavaHome, $GodotExe, $Adb)) {
    if (-not (Test-Path $required)) { throw "Required path is missing: $required" }
}
$env:ANDROID_HOME = $AndroidSdkRoot
$env:ANDROID_SDK_ROOT = $AndroidSdkRoot
$env:ANDROID_NDK_HOME = $NdkRoot
$env:JAVA_HOME = $JavaHome
$env:PATH = "$JavaHome\bin;$AndroidSdkRoot\platform-tools;$env:PATH"

if (-not (Test-Path (Join-Path $OrtSource ".git"))) {
    New-Item -ItemType Directory -Force (Split-Path $OrtSource -Parent) | Out-Null
    & git clone --branch $OrtTag --depth 1 --recurse-submodules --shallow-submodules `
        https://github.com/microsoft/onnxruntime.git $OrtSource
    if ($LASTEXITCODE -ne 0) { throw "ONNX Runtime clone failed: $LASTEXITCODE" }
}
$actualCommit = (& git -C $OrtSource rev-parse HEAD).Trim()
if ($actualCommit -ne $OrtCommit) {
    throw "ONNX Runtime checkout mismatch: expected $OrtCommit, got $actualCommit"
}
& git -C $OrtSource submodule update --init --recursive --depth 1
if ($LASTEXITCODE -ne 0) { throw "ONNX Runtime submodule update failed: $LASTEXITCODE" }

if (-not $SkipOrtBuild) {
    & (Join-Path $OrtSource "build.bat") `
        --config Release `
        --build_dir $OrtBuild `
        --parallel `
        --build_shared_lib `
        --skip_tests `
        --compile_no_warning_as_error `
        --cmake_generator Ninja `
        --android `
        --android_sdk_path $AndroidSdkRoot `
        --android_ndk_path $NdkRoot `
        --android_abi arm64-v8a `
        --android_api 29 `
        --cmake_extra_defines onnxruntime_BUILD_UNIT_TESTS=OFF
    if ($LASTEXITCODE -ne 0) { throw "ONNX Runtime Android build failed: $LASTEXITCODE" }
}

$runtime = Get-ChildItem $OrtBuild -Filter "libonnxruntime.so" -File -Recurse |
    Where-Object { $_.FullName -match "Release" } |
    Sort-Object FullName |
    Select-Object -First 1
if (-not $runtime) { throw "libonnxruntime.so was not found under $OrtBuild" }
New-Item -ItemType Directory -Force (Join-Path $OrtStage "include") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $OrtStage "lib") | Out-Null
Copy-Item (Join-Path $OrtSource "include\onnxruntime\core\session\*") `
    (Join-Path $OrtStage "include") -Force
Copy-Item $runtime.FullName (Join-Path $OrtStage "lib\libonnxruntime.so") -Force
Write-Host "ORT_ANDROID_SOURCE_BUILD_OK commit=$actualCommit library=$($runtime.FullName)"

Push-Location $RepoRoot
try {
    $env:ORT_ROOT = $OrtStage
    $env:ORT_BUNDLE = "1"
    & scons platform=android arch=arm64 target=template_debug `
        -j ([Environment]::ProcessorCount)
    if ($LASTEXITCODE -ne 0) { throw "GDExtension Android build failed: $LASTEXITCODE" }
} finally {
    Pop-Location
}

$extension = Join-Path $RepoRoot "addons\onnx_loader\bin\libonnx_loader.android.template_debug.arm64.so"
if (-not (Test-Path $extension)) { throw "Expected GDExtension was not produced: $extension" }

# The Windows editor must be able to load the class while it scans the export
# project. Build an editor-only helper from the same extension sources. It does
# not load ORT until load_model(), so no host onnxruntime.dll is required.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere.exe was not found" }
$vsInstall = (& $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath).Trim()
$vsDevCmd = Join-Path $vsInstall "Common7\Tools\VsDevCmd.bat"
if (-not (Test-Path $vsDevCmd)) { throw "VsDevCmd.bat was not found: $vsDevCmd" }
$helperCmd = Join-Path $RepoRoot "build\android\build-editor-helper.cmd"
New-Item -ItemType Directory -Force (Split-Path $helperCmd -Parent) | Out-Null
[IO.File]::WriteAllLines($helperCmd, @(
    "@call `"$vsDevCmd`" -arch=x64 -host_arch=x64",
    "@if errorlevel 1 exit /b %errorlevel%",
    "@scons platform=windows arch=x86_64 target=template_debug -j $([Environment]::ProcessorCount)"
), [Text.ASCIIEncoding]::new())
$env:ORT_BUNDLE = "0"
Push-Location $RepoRoot
try {
    & cmd.exe /d /c $helperCmd
    if ($LASTEXITCODE -ne 0) { throw "Windows editor-helper build failed: $LASTEXITCODE" }
} finally {
    Pop-Location
    $env:ORT_BUNDLE = "1"
}
$editorHelper = Join-Path $RepoRoot "addons\onnx_loader\bin\libonnx_loader.windows.template_debug.x86_64.dll"
if (-not (Test-Path $editorHelper)) { throw "Editor helper was not produced: $editorHelper" }

$demoAddon = Join-Path $RepoRoot "demo\addons\onnx_loader"
# Git for Windows may materialize this repository symlink as a one-line file
# when Developer Mode/symlink privileges are unavailable. Replace that local
# checkout representation with the directory the Android exporter needs.
if (Test-Path $demoAddon -PathType Leaf) { Remove-Item $demoAddon -Force }
New-Item -ItemType Directory -Force $demoAddon | Out-Null
Copy-Item (Join-Path $RepoRoot "tools\onnx_loader_android_export.gdextension") `
    (Join-Path $demoAddon "onnx_loader.gdextension") -Force
$demoBin = Join-Path $demoAddon "bin"
New-Item -ItemType Directory -Force $demoBin | Out-Null
Copy-Item (Join-Path $RepoRoot "addons\onnx_loader\bin\*") $demoBin -Recurse -Force
$modelDir = Join-Path $RepoRoot "demo\models"
New-Item -ItemType Directory -Force $modelDir | Out-Null
Copy-Item (Join-Path $RepoRoot "fixtures\ci-smoke\model.onnx") `
    (Join-Path $modelDir "ci_model.onnx") -Force

# Force a clean extension rescan. This is generated editor state and may still
# reference manifests that were removed or replaced during an earlier run.
$godotCache = Join-Path $RepoRoot "demo\.godot"
if (Test-Path $godotCache) { Remove-Item $godotCache -Recurse -Force }

$projectFile = Join-Path $RepoRoot "demo\project.godot"
$projectText = Get-Content $projectFile -Raw
$projectText = $projectText.Replace('run/main_scene="res://matrix_demo.tscn"', 'run/main_scene="res://android_smoke.tscn"')
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($projectFile, $projectText.TrimStart([char]0xFEFF), $utf8NoBom)

# Godot persists Android tool locations independently of ANDROID_HOME. Keep
# its editor setting aligned with the SDK this script just validated.
$editorSettings = Join-Path $env:APPDATA "Godot\editor_settings-4.6.tres"
if (Test-Path $editorSettings) {
    $settingsText = Get-Content $editorSettings -Raw
    $godotSdkPath = $AndroidSdkRoot.Replace("\", "/")
    $settingsText = $settingsText -replace `
        'export/android/android_sdk_path = "[^"]*"', `
        "export/android/android_sdk_path = `"$godotSdkPath`""
    [IO.File]::WriteAllText(
        $editorSettings,
        $settingsText.TrimStart([char]0xFEFF),
        $utf8NoBom
    )
}
New-Item -ItemType Directory -Force (Split-Path $Apk -Parent) | Out-Null
& $GodotExe --headless --path (Join-Path $RepoRoot "demo") `
    --export-debug "Android Smoke" $Apk
$godotExportExit = $LASTEXITCODE
if (-not (Test-Path $Apk)) {
    throw "Godot Android export failed ($godotExportExit); APK was not produced: $Apk"
}
if ($godotExportExit -ne 0) {
    Write-Warning "Godot exited $godotExportExit after producing the APK; continuing with device validation."
}
Write-Host "GODOT_ANDROID_EXPORT_OK apk=$Apk bytes=$((Get-Item $Apk).Length)"

$adbArgs = @()
if ($DeviceSerial) { $adbArgs += @("-s", $DeviceSerial) }
& $Adb @adbArgs install -r $Apk
if ($LASTEXITCODE -ne 0) { throw "APK installation failed: $LASTEXITCODE" }
& $Adb @adbArgs shell input keyevent KEYCODE_WAKEUP
& $Adb @adbArgs shell wm dismiss-keyguard
& $Adb @adbArgs shell input keyevent 82
Start-Sleep -Seconds 1
& $Adb @adbArgs logcat -c
& $Adb @adbArgs shell am force-stop org.dynamicdevices.onnxloadersmoke
& $Adb @adbArgs shell am start -W -n `
    "org.dynamicdevices.onnxloadersmoke/com.godot.game.GodotAppLauncher"
if ($LASTEXITCODE -ne 0) { throw "APK launch failed: $LASTEXITCODE" }
Write-Host "ANDROID_ONNX_SMOKE_LAUNCHED serial=$DeviceSerial"

$deadline = (Get-Date).AddSeconds($DeviceTestTimeoutSeconds)
$markerLines = @()
do {
    Start-Sleep -Milliseconds 750
    $deviceLog = & $Adb @adbArgs logcat -d -v threadtime
    $markerLines = @($deviceLog | Select-String -Pattern `
        'ANDROID_ONNX_|FATAL EXCEPTION|Fatal signal|Process: org.dynamicdevices.onnxloadersmoke' |
        ForEach-Object { $_.Line })
    $terminalLines = @($markerLines -match `
        'ANDROID_ONNX_TEARDOWN_OK|ANDROID_ONNX_SMOKE_FAILED|FATAL EXCEPTION|Fatal signal')
} while ($terminalLines.Count -eq 0 -and (Get-Date) -lt $deadline)

Write-Host "--- ANDROID SMOKE MARKERS ---"
$markerLines | ForEach-Object { Write-Host $_ }
$successLines = @($markerLines -match 'ANDROID_ONNX_SMOKE_OK')
$teardownLines = @($markerLines -match 'ANDROID_ONNX_TEARDOWN_OK')
$failureLines = @($markerLines -match `
    'ANDROID_ONNX_SMOKE_FAILED|FATAL EXCEPTION|Fatal signal')
if ($successLines.Count -eq 0 -or $teardownLines.Count -eq 0 -or $failureLines.Count -gt 0) {
    Write-Host "--- ANDROID CRASH BUFFER ---"
    & $Adb @adbArgs logcat -b crash -d -v threadtime
    Write-Host "--- ANDROID HISTORICAL EXIT INFO ---"
    & $Adb @adbArgs shell dumpsys activity exit-info org.dynamicdevices.onnxloadersmoke
    throw "Android ONNX smoke did not complete successfully within $DeviceTestTimeoutSeconds seconds"
}
Write-Host "ANDROID_ONNX_DEVICE_VALIDATION_OK serial=$DeviceSerial"
