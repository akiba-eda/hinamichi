#!/usr/bin/env bash
# One-time project setup on your Mac (run inside app/):
#   bash tool/setup.sh
# Generates android/ and ios/ (kept out of the repo until first run), applies the permission patches,
# then prints the remaining manual steps (flutterfire configure).
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ] || [ ! -d ios ]; then
  flutter create . --org jp.hinamichi --project-name hinamichi --platforms android,ios
fi
flutter pub get
python3 tool/patch_platforms.py
dart run flutter_launcher_icons || true

cat <<'MSG'

Next:
  1) firebase login && dart pub global activate flutterfire_cli
  2) flutterfire configure --project=<your-firebase-project-id>   # writes lib/firebase_options.dart + google-services.json / GoogleService-Info.plist
  3) flutter run -d <android-device> --dart-define=API_BASE=https://<your>.vercel.app
     (LAN dev server: --dart-define=API_BASE=http://<mac-ip>:3000)
MSG
