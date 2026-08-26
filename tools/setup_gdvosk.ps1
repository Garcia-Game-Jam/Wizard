# Installs gdvosk GDExtension and a small English Vosk model for Wizard.
# Run from repo root: powershell -ExecutionPolicy Bypass -File tools/setup_gdvosk.ps1
# Downloads ~500 MB on first run; later runs reuse .cache/voice-setup/ and skip re-download.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$VersionsFile = Join-Path $Root "tools\versions.env"
Get-Content -Path $VersionsFile | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
    $parts = $_ -split '=', 2
    Set-Variable -Name $parts[0].Trim() -Value $parts[1].Trim() -Scope Script
}

$Cache = Join-Path $Root ".cache\voice-setup"
$AddonsDir = Join-Path $Root "addons\gdvosk"
$ModelDir = Join-Path $Root "models\vosk"

$GdvoskUrl = "https://github.com/Nihlus/gdvosk/releases/download/$GDVOSK_RELEASE_TAG/$GDVOSK_ZIP"
$ModelUrl = "https://alphacephei.com/vosk/models/$VOSK_MODEL_ZIP"
$DownloadsZip = Join-Path $env:USERPROFILE "Downloads\$GDVOSK_ZIP"

New-Item -ItemType Directory -Force -Path $Cache | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $AddonsDir) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $ModelDir) | Out-Null

function Get-FileIfMissing($Url, $Dest) {
    if (Test-Path $Dest) {
        Write-Host "Using cached $(Split-Path -Leaf $Dest)"
        return
    }
    Write-Host "Downloading $Url ..."
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
}

$GdvoskZip = Join-Path $Cache $GDVOSK_ZIP
$ModelZip = Join-Path $Cache $VOSK_MODEL_ZIP

if (Test-Path $DownloadsZip) {
    Write-Host "Using gdvosk zip from Downloads"
    Copy-Item -Path $DownloadsZip -Destination $GdvoskZip -Force
} else {
    Get-FileIfMissing $GdvoskUrl $GdvoskZip
}
Get-FileIfMissing $ModelUrl $ModelZip

if (-not (Test-Path (Join-Path $AddonsDir "gdvosk.gdextension"))) {
    Write-Host "Extracting gdvosk to addons/ ..."
    $TempExtract = Join-Path $Cache "gdvosk-extract"
    if (Test-Path $TempExtract) { Remove-Item -Recurse -Force $TempExtract }
    Expand-Archive -Path $GdvoskZip -DestinationPath $TempExtract -Force

    # Release zip may contain addons/gdvosk/ or a top-level gdvosk/ folder.
    $Candidates = @(
        (Join-Path $TempExtract "addons\gdvosk"),
        (Join-Path $TempExtract "gdvosk"),
        $TempExtract
    )
    $Source = $Candidates | Where-Object { Test-Path (Join-Path $_ "gdvosk.gdextension") } | Select-Object -First 1
    if (-not $Source) {
        throw "Could not find gdvosk.gdextension inside the release zip."
    }
    if (Test-Path $AddonsDir) { Remove-Item -Recurse -Force $AddonsDir }
    Copy-Item -Path $Source -Destination $AddonsDir -Recurse -Force
    Write-Host "gdvosk installed to $AddonsDir"
} else {
    Write-Host "gdvosk already installed at $AddonsDir"
}

$WindowsLib = Join-Path $AddonsDir "lib\windows\x86_64\libgdvosk-d.dll"
if (-not (Test-Path $WindowsLib)) {
    throw "gdvosk native libraries are missing at $WindowsLib. Re-run this script after deleting addons\gdvosk."
}

function Ensure-GdvoskEditorLibraries {
    param([string]$GdExtensionPath)
    if (-not (Test-Path $GdExtensionPath)) { return }
    $content = Get-Content -Path $GdExtensionPath -Raw
    if ($content -match "windows\.editor\.x86_64") {
        Write-Host "gdvosk.gdextension already has editor library entries"
        return
    }
    Write-Host "Patching gdvosk.gdextension for Godot editor (windows.editor / linux.editor / macos.editor) ..."
    $content = $content -replace '(macos\.debug = "res://addons/gdvosk/lib/macos/universal/libgdvosk-d\.dylib")', "`$1`r`nmacos.editor = `"res://addons/gdvosk/lib/macos/universal/libgdvosk-d.dylib`""
    $content = $content -replace '(windows\.debug\.x86_32 = "res://addons/gdvosk/lib/windows/x86_32/libgdvosk-d\.dll")', "`$1`r`nwindows.editor.x86_32 = `"res://addons/gdvosk/lib/windows/x86_32/libgdvosk-d.dll`""
    $content = $content -replace '(windows\.debug\.x86_64 = "res://addons/gdvosk/lib/windows/x86_64/libgdvosk-d\.dll")', "`$1`r`nwindows.editor.x86_64 = `"res://addons/gdvosk/lib/windows/x86_64/libgdvosk-d.dll`""
    $content = $content -replace '(linux\.debug\.x86_64 = "res://addons/gdvosk/lib/linux/x86_64/libgdvosk-d\.so")', "`$1`r`nlinux.editor.x86_64 = `"res://addons/gdvosk/lib/linux/x86_64/libgdvosk-d.so`""
    Set-Content -Path $GdExtensionPath -Value $content -NoNewline
}

Ensure-GdvoskEditorLibraries (Join-Path $AddonsDir "gdvosk.gdextension")

if (-not (Test-Path (Join-Path $ModelDir "am"))) {
    Write-Host "Extracting Vosk model to models/vosk/ ..."
    $TempModel = Join-Path $Cache "model-extract"
    if (Test-Path $TempModel) { Remove-Item -Recurse -Force $TempModel }
    Expand-Archive -Path $ModelZip -DestinationPath $TempModel -Force

    $Inner = Get-ChildItem -Path $TempModel -Directory | Select-Object -First 1
    if (-not $Inner) { throw "Vosk model zip was empty." }
    if (Test-Path $ModelDir) { Remove-Item -Recurse -Force $ModelDir }
    Copy-Item -Path $Inner.FullName -Destination $ModelDir -Recurse -Force
    Write-Host "Vosk model installed to $ModelDir"
} else {
    Write-Host "Vosk model already installed at $ModelDir"
}

Write-Host ""
Write-Host "Done. Fully quit Godot (all windows), reopen the project, then verify with:"
Write-Host "  powershell -ExecutionPolicy Bypass -File tools/verify_gdvosk.ps1"
Write-Host "You should see: VoskRecognizer available: true"
