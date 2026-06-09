# Minimalist OATS Calendar

A minimalist Flutter Web weekly schedule app inspired by the handwritten OATS weekly report sheet.

## Live App

Open the app here:

https://mayer847.github.io/minimalist_oats_calendar/

## Features

- Local-first storage using browser local storage.
- Export/import full backup as JSON anytime.
- Download the visible schedule as PNG.
- GitHub Pages deployment workflow included.
- Start day selector in the top bar next to the 24h/12h control.
- Undo button for edits, imports, row changes, review changes, and drag/drop.
- Overlap handling: later items are pushed down automatically.
- Review any day from the `Review Day` button or by tapping a day header.
- Review screen has visible `Done`, `Missed`, and `Not sure` buttons directly.
- 30-minute slots with duration-based item blocks.
- Dashed row guides instead of full horizontal row borders.
- Long-press and drag:
  - Same day = move vertically.
  - Different day = copy horizontally.

## Run Locally

```bash
flutter pub get
flutter run -d chrome
```

## Build for Web

```bash
flutter build web --release --base-href /minimalist_oats_calendar/
```

## Deploy to GitHub Pages

This project includes a GitHub Actions workflow at:

```text
.github/workflows/deploy.yml
```

To deploy:

1. Push changes to the `main` branch.
2. Go to GitHub repo settings.
3. Open **Pages**.
4. Set **Source** to **GitHub Actions**.
5. Wait for the workflow to finish.
6. Open:

```text
https://mayer847.github.io/minimalist_oats_calendar/
```

## Backup and Restore

Use the export/import menu inside the app:

- **Export backup JSON**: saves all local schedule data to a `.json` file.
- **Import backup JSON**: restores schedule data from a previous backup.
- **Download schedule PNG**: exports the visible schedule as an image.

## Notes

- Data is stored locally in the browser, so use **Export backup JSON** regularly if you want to preserve or move your data between browsers/devices.
- The app is static and can be hosted on GitHub Pages.
- Background reminders are planned for a later version.
