# Verifies gdvosk is installed and gdvosk.gdextension has editor library entries.
# Run from repo root: powershell -ExecutionPolicy Bypass -File tools/verify_gdvosk.ps1
#
# Note: Godot --script mode does not register gdvosk (VoskRecognizer stays false).
# After this passes, fully quit Godot, reopen the project, and test a spell in Play.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$AddonsDir = Join-Path $Root "addons\gdvosk"
$GdExtension = Join-Path $AddonsDir "gdvosk.gdextension"
$GdExtensionDisabled = Join-Path $AddonsDir "gdvosk.gdextension.disabled"
$WindowsLib = Join-Path $AddonsDir "lib\windows\x86_64\libgdvosk-d.dll"
$ModelDir = Join-Path $Root "models\vosk"

$RequiredEditorKeys = @(
    "windows.editor.x86_64",
    "windows.editor.x86_32",
    "linux.editor.x86_64",
    "macos.editor"
)

if (Test-Path $GdExtensionDisabled) {
    if (-not (Test-Path $GdExtension)) {
        Write-Host "Restoring disabled gdvosk.gdextension ..."
        Move-Item -Path $GdExtensionDisabled -Destination $GdExtension
    }
}

if (-not (Test-Path $GdExtension)) {
    Write-Error "gdvosk not installed. Run make setup-voice first."
}

if (-not (Test-Path $WindowsLib)) {
    Write-Error "gdvosk native library missing at $WindowsLib. Re-run make setup-voice."
}

$manifest = Get-Content $GdExtension -Raw
foreach ($key in $RequiredEditorKeys) {
    if ($manifest -notmatch [regex]::Escape("$key =")) {
        Write-Error "gdvosk.gdextension is missing '$key'. Run make setup-voice."
    }
}

$modelFound = $false
if (Test-Path $ModelDir) {
    $modelFound = @(Get-ChildItem -Path $ModelDir -Directory -ErrorAction SilentlyContinue).Count -gt 0
}
if (-not $modelFound) {
    Write-Error "Vosk model not found under $ModelDir. Run make setup-voice."
}

Write-Host "gdvosk verify passed:"
Write-Host "  - gdvosk.gdextension present with editor library entries"
Write-Host "  - native library: $WindowsLib"
Write-Host "  - speech model under: $ModelDir"
Write-Host ""
Write-Host "Fully quit Godot, reopen the project, then press Play to confirm spells recognize speech."
