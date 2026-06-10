# Google Drive Sync Integration Notes

This upgrade pack adds browser-only Google Drive `appDataFolder` sync.

## Files to copy

Copy these into your Flutter app:

```text
lib/services/google_drive_sync_service.dart
web/google_drive_sync.js
web/index.html
.github/workflows/deploy.yml
scripts/release.sh
scripts/release.ps1
README.md
.gitignore
```

If you already customized `web/index.html`, only add these scripts before `flutter_bootstrap.js`:

```html
<script src="https://accounts.google.com/gsi/client" async defer></script>
<script src="https://apis.google.com/js/api.js" async defer></script>
<script src="google_drive_sync.js" defer></script>
```

## Main app hooks

In `main.dart`, import:

```dart
import 'services/google_drive_sync_service.dart';
```

Add fields in your state class:

```dart
final GoogleDriveSyncService driveSync = GoogleDriveSyncService();
final SyncDebouncer cloudSyncDebouncer = SyncDebouncer(const Duration(seconds: 8));
String cloudSyncStatus = 'Cloud sync not connected';
bool cloudSyncEnabled = false;
```

In `initState`, after local data loads:

```dart
_initCloudSync();
```

Add methods:

```dart
Future<void> _initCloudSync() async {
  if (!driveSync.isConfigured) {
    setState(() => cloudSyncStatus = 'Missing GOOGLE_CLIENT_ID');
    return;
  }
  try {
    await driveSync.initialize();
    setState(() => cloudSyncStatus = 'Google Drive ready');
  } catch (e) {
    setState(() => cloudSyncStatus = 'Drive init failed: $e');
  }
}

Future<void> _connectGoogleDrive() async {
  try {
    await driveSync.initialize();
    await driveSync.connect();
    final cloudBackup = await driveSync.loadBackup();
    if (cloudBackup != null) {
      // TODO: show dialog: Restore cloud / Keep local.
      // To restore, parse cloudBackup['entries'] and cloudBackup['settings'] using your existing import logic.
    } else {
      await driveSync.saveBackup(_backupJson());
    }
    setState(() {
      cloudSyncEnabled = true;
      cloudSyncStatus = 'Synced';
    });
  } catch (e) {
    setState(() => cloudSyncStatus = 'Sync error: $e');
  }
}

void _scheduleCloudSync() {
  if (!cloudSyncEnabled) return;
  cloudSyncDebouncer.run(() async {
    try {
      await driveSync.saveBackup(_backupJson());
      if (mounted) setState(() => cloudSyncStatus = 'Synced');
    } catch (e) {
      if (mounted) setState(() => cloudSyncStatus = 'Sync failed: $e');
    }
  });
}
```

After every successful local `_saveData()`, call:

```dart
_scheduleCloudSync();
```

Add app bar button:

```dart
TextButton.icon(
  onPressed: _connectGoogleDrive,
  icon: const Icon(Icons.cloud_sync_outlined),
  label: Text(cloudSyncEnabled ? cloudSyncStatus : 'Connect Drive'),
),
```

## Build locally

```bash
flutter run -d chrome --dart-define=GOOGLE_CLIENT_ID=PASTE_YOUR_GOOGLE_CLIENT_ID_HERE
```

## Build for GitHub Pages

```bash
flutter build web --release \
  --base-href /minimalist_oats_calendar/ \
  --dart-define=GOOGLE_CLIENT_ID=PASTE_YOUR_GOOGLE_CLIENT_ID_HERE
```
