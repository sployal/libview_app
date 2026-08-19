# Generates android/app/google-services.json and lib/firebase_options.dart
# for the edupal-app-8ccb1 Firebase project.
#
# Prerequisites:
#   1. Firebase CLI: npm install -g firebase-tools
#   2. Log in once: firebase login
#
# Run from the project root:
#   .\setup_firebase.ps1

$ErrorActionPreference = "Stop"

Write-Host "Activating FlutterFire CLI..."
dart pub global activate flutterfire_cli

$flutterfire = Join-Path $env:LOCALAPPDATA "Pub\Cache\bin\flutterfire.bat"
if (-not (Test-Path $flutterfire)) {
    throw "flutterfire not found at $flutterfire"
}

Write-Host "Configuring Firebase for Android..."
& $flutterfire configure `
    --project=edupal-app-8ccb1 `
    --platforms=android `
    --android-package-name=com.example.libview `
    --yes

Write-Host "Done. Run: flutter pub get && flutter run"
