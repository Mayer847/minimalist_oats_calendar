# Minimalist OATS Calendar

Live app:

https://mayer847.github.io/minimalist_oats_calendar/

## v5 Updates

- Items that continue past 06:00 overflow visually into the next day column.
- Added Undo and Redo.
- Added manual **Sync now** plus automatic debounce sync after edits.
- First launch asks the user to connect Google Drive or use local-only mode.
- Top control bar is horizontally scrollable on small screens.
- Increased row/header height and font line-height to reduce trimmed handwritten text.
- Schedule still supports local JSON export/import and PNG export.

## Google Drive Sync

Each user signs in with Google and the app stores the backup in that user's own Google Drive `appDataFolder`.

GitHub Actions variable required:

```text
GOOGLE_CLIENT_ID=xxxxx.apps.googleusercontent.com
```

Google Cloud OAuth Web app authorized JavaScript origin:

```text
https://mayer847.github.io
```

Local test origin if needed:

```text
http://localhost:8800
```

## Local run

```bash
flutter pub get
flutter run -d chrome --web-port 8800 --dart-define=GOOGLE_CLIENT_ID=xxxxx.apps.googleusercontent.com
```

## Release

PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\release.ps1 "Add v5 schedule updates" v0.3.0
```

Git Bash:

```bash
chmod +x scripts/release.sh
./scripts/release.sh "Add v5 schedule updates" v0.3.0
```
