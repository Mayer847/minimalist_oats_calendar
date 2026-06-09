# Minimalist OATS Calendar

A small Flutter Web weekly schedule app inspired by a handwritten OATS weekly report sheet.

## Features

- Weekly grid: configurable start day, 7 days shown.
- Auto week range at the top: `DD.MM.YY ~ DD.MM.YY`.
- Previous / next week navigation.
- Editable `TEAM` and `NAME` fields.
- Time rows from `6` to `24`.
- Three default late-night rows: `25`, `26`, `27`.
- `+ Add late row` and `Remove late row` buttons.
- 24h / 12h toggle.
- Editable schedule cells.
- Preset and custom RGB ink colors.
- Daily review:
  - Done = green.
  - Missed = grey.
  - Not sure = yellow.
- Default review time is 10:00 PM, configurable by user.
- Auto-review opens when the app is open and the review time passes.
- Data is stored locally in the browser using `shared_preferences`.

## Run locally

```bash
flutter pub get
flutter run -d chrome
```

## Build for web

```bash
flutter build web
```

Upload `build/web` to Firebase Hosting, Netlify, Vercel, GitHub Pages, or any static web host.

## Reminder roadmap

Actual background notifications are intentionally not implemented in this MVP. Later options:

1. Flutter mobile notifications with `flutter_local_notifications`.
2. Browser push notifications with service workers.
3. Firebase Cloud Messaging for cross-device reminders.
