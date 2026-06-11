# Runs Flutter Web using web-server on port 8800 with the OATS Google Client ID.
# Usage from project root:
#   powershell -ExecutionPolicy Bypass -File .\scripts\run_web_server.ps1

$ErrorActionPreference = "Stop"

flutter pub get
flutter run -d web-server --web-port 8800 --dart-define=GOOGLE_CLIENT_ID=462452343506-csg26cgk1uvr2m4qf4p80l9kair8jf48.apps.googleusercontent.com
