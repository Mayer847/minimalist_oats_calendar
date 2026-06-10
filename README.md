# Minimalist OATS Calendar

Live app:

https://mayer847.github.io/minimalist_oats_calendar/

A minimalist Flutter Web weekly schedule app inspired by the handwritten OATS weekly report sheet.

## Public Google Drive Sync

This app can optionally sync each user's schedule to **their own Google Drive** using the hidden Drive `appDataFolder`.

Important:

- The Google Client ID identifies this app/project.
- Every user uses the same Client ID.
- The user's backup is stored inside **their Google Drive appDataFolder**, not inside your personal Google Drive.
- The Client ID is not a secret. It will be visible in the deployed web app bundle.
- No Firebase or paid backend is required.
- True background sync while the app is closed is not available without a backend. Auto-sync works while the app is open.

## Required Google Cloud Setup

1. Go to Google Cloud Console.
2. Create/select a project.
3. Enable **Google Drive API**.
4. Configure **OAuth consent screen**:
   - User type: External.
   - Publishing status: Production when ready for public use.
   - App domain: `https://mayer847.github.io`
   - Authorized domain: `github.io`
   - Add a privacy policy URL if Google requires it for publishing.
5. Create OAuth Client ID:
   - Application type: Web application.
   - Authorized JavaScript origins:

```text
https://mayer847.github.io
```

6. Copy the generated Client ID.
7. In GitHub repo:
   - Settings → Secrets and variables → Actions → Variables
   - Add variable:

```text
GOOGLE_CLIENT_ID=xxxxx.apps.googleusercontent.com
```

## Local Run

```bash
flutter pub get
flutter run -d chrome --dart-define=GOOGLE_CLIENT_ID=PASTE_YOUR_GOOGLE_CLIENT_ID_HERE
```

## GitHub Pages Deploy

This repo includes:

```text
.github/workflows/deploy.yml
```

The workflow builds with:

```bash
--dart-define=GOOGLE_CLIENT_ID=${{ vars.GOOGLE_CLIENT_ID }}
```

Push to `main`, then GitHub Actions will deploy.

## Release Script

Bash/Git Bash:

```bash
chmod +x scripts/release.sh
./scripts/release.sh "Add Google Drive sync" v0.2.0
```

PowerShell:

```powershell
.\scripts\release.ps1 "Add Google Drive sync" v0.2.0
```

Auto bump:

```bash
./scripts/release.sh "Small fix" patch
./scripts/release.sh "New feature" minor
```

## Backup Options

- Local browser storage.
- Manual JSON export/import.
- Google Drive appDataFolder cloud sync.
- Download visible schedule as PNG.
