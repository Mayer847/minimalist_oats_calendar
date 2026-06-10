# Minimalist OATS Calendar

Live app:

https://mayer847.github.io/minimalist_oats_calendar/

## Google Drive Sync

Each user signs in with Google and the app stores the backup in that user's own Google Drive `appDataFolder`.

The app owner creates one public web OAuth Client ID. Users do **not** create their own Client ID.

## Google setup

GitHub repo → Settings → Secrets and variables → Actions → Variables:

```text
GOOGLE_CLIENT_ID=xxxxx.apps.googleusercontent.com
```

Google Cloud OAuth Web app authorized JavaScript origin:

```text
https://mayer847.github.io
```

## Local run

```bash
flutter pub get
flutter run -d chrome --dart-define=GOOGLE_CLIENT_ID=xxxxx.apps.googleusercontent.com
```

## Release

PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\release.ps1 "Fix Google Drive sync UI" v0.2.2
```

Git Bash:

```bash
chmod +x scripts/release.sh
./scripts/release.sh "Fix Google Drive sync UI" v0.2.2
```
